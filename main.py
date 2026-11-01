import csv
import logging
import os
import random
import subprocess
import sys
import threading
import webbrowser
from datetime import datetime
from pathlib import Path
from urllib.parse import urlsplit

import pytz
from flask import Flask, jsonify, render_template, request


app = Flask(__name__)
app.config["TEMPLATES_AUTO_RELOAD"] = True
app.config["JSON_SORT_KEYS"] = False

CAMERA_LIST = Path(__file__).resolve().with_name("WebcamURLs_All.csv")
REQUIRED_COLUMNS = ("DESCRIPTION", "URL", "PYTZ TIMEZONE", "SOURCE")
SUPPORTED_SOURCES = {"Youtube", "NTV", "m3u8", "IPCam", "Earthcam"}
logger = logging.getLogger(__name__)
camera_lock = threading.Lock()


def load_cameras(path=CAMERA_LIST):
    """Load and validate the configured camera list once at startup."""
    try:
        with path.open(newline="", encoding="utf-8-sig") as camera_file:
            reader = csv.DictReader(camera_file)
            missing_columns = set(REQUIRED_COLUMNS) - set(reader.fieldnames or ())
            if missing_columns:
                raise ValueError(
                    "Missing CSV columns: " + ", ".join(sorted(missing_columns))
                )

            cameras = []
            for row_number, row in enumerate(reader, start=2):
                camera = {key: (row.get(key) or "").strip() for key in REQUIRED_COLUMNS}
                if not all(camera.values()):
                    raise ValueError(f"CSV row {row_number} has an empty required field")
                try:
                    parsed_url = urlsplit(camera["URL"])
                except ValueError as error:
                    raise ValueError(
                        f"CSV row {row_number} has an invalid URL"
                    ) from error
                if (
                    parsed_url.scheme not in {"http", "https"}
                    or not parsed_url.netloc
                    or any(character.isspace() for character in camera["URL"])
                ):
                    raise ValueError(f"CSV row {row_number} has an invalid URL")
                if camera["SOURCE"] not in SUPPORTED_SOURCES:
                    raise ValueError(
                        f"CSV row {row_number} has unsupported source "
                        f"{camera['SOURCE']!r}"
                    )
                try:
                    pytz.timezone(camera["PYTZ TIMEZONE"])
                except pytz.UnknownTimeZoneError as error:
                    raise ValueError(
                        f"CSV row {row_number} has unknown timezone "
                        f"{camera['PYTZ TIMEZONE']!r}"
                    ) from error
                cameras.append(camera)
    except OSError as error:
        raise RuntimeError(f"Unable to read camera list at {path}: {error}") from error

    if not cameras:
        raise ValueError(f"Camera list at {path} contains no cameras")
    return cameras


app.config["CAMERAS"] = load_cameras()
app.config["CAMERA_INDEX"] = None


def current_camera():
    cameras = app.config["CAMERAS"]
    with camera_lock:
        index = app.config["CAMERA_INDEX"]
        if index is None:
            index = random.randrange(len(cameras))
            app.config["CAMERA_INDEX"] = index
        return index, cameras[index]


def camera_local_time(camera):
    now = datetime.now(tz=pytz.timezone(camera["PYTZ TIMEZONE"]))
    return now.strftime("%m/%d/%Y - %I:%M:%S %p")


@app.route("/")
def render_html():
    return render_template("overlay.html")


@app.route("/health/")
def health():
    index, camera = current_camera()
    return jsonify(
        {
            "status": "ok",
            "camera_count": len(app.config["CAMERAS"]),
            "current_camera": camera["DESCRIPTION"],
            "current_camera_index": index,
        }
    )


@app.route("/cameras/")
def cameras():
    """Return the configured camera names and sources for diagnostics."""
    return jsonify(
        [
            {"description": camera["DESCRIPTION"], "source": camera["SOURCE"]}
            for camera in app.config["CAMERAS"]
        ]
    )


@app.route("/live/")
def update_time_loop():
    camera_index = request.args.get("index")
    if camera_index is None:
        _, camera = current_camera()
    else:
        try:
            index = int(camera_index)
        except ValueError:
            return jsonify({"error": "Camera index must be an integer"}), 400
        cameras = app.config["CAMERAS"]
        if not 0 <= index < len(cameras):
            return jsonify({"error": "Camera index is out of range"}), 400
        camera = cameras[index]
    return jsonify({"Webcam_local_time": camera_local_time(camera)})


@app.route("/shuffle/")
def shuffle_webcam_locations():
    cameras = app.config["CAMERAS"]
    with camera_lock:
        current_index = app.config["CAMERA_INDEX"]
        if current_index is None:
            new_index = random.randrange(len(cameras))
        elif len(cameras) == 1:
            new_index = current_index
        else:
            new_index = random.choice(
                [index for index in range(len(cameras)) if index != current_index]
            )
        app.config["CAMERA_INDEX"] = new_index
        camera = cameras[new_index]

    return jsonify(camera_response(new_index, camera))


def camera_response(index, camera):
    return {
        "Webcam_local_time": camera_local_time(camera),
        "webcamLocationDesc": camera["DESCRIPTION"],
        "ShuffledURL": camera["URL"],
        "VidSource": camera["SOURCE"],
        "CameraIndex": index,
        "CameraCount": len(app.config["CAMERAS"]),
    }


@app.route("/camera/<int:index>/")
def get_camera(index):
    cameras = app.config["CAMERAS"]
    if not 0 <= index < len(cameras):
        return jsonify({"error": "Camera index is out of range"}), 404
    return jsonify(camera_response(index, cameras[index]))


@app.route("/navigate/<direction>/")
def navigate_camera(direction):
    if direction not in {"next", "previous"}:
        return jsonify({"error": "Direction must be 'next' or 'previous'"}), 400

    cameras = app.config["CAMERAS"]
    requested_index = request.args.get("index")
    if requested_index is not None:
        try:
            current_index = int(requested_index)
        except ValueError:
            return jsonify({"error": "Camera index must be an integer"}), 400
        if not 0 <= current_index < len(cameras):
            return jsonify({"error": "Camera index is out of range"}), 400

    with camera_lock:
        if requested_index is None:
            current_index = app.config["CAMERA_INDEX"]
        if current_index is None:
            current_index = random.randrange(len(cameras))
        offset = 1 if direction == "next" else -1
        new_index = (current_index + offset) % len(cameras)
        app.config["CAMERA_INDEX"] = new_index
        camera = cameras[new_index]

    return jsonify(camera_response(new_index, camera))


@app.route("/NTVCAMERA/")
def click_center():
    if sys.platform == "win32":
        return jsonify({"autoclicked": False, "reason": "not_supported"})

    try:
        geometry = subprocess.run(
            ["xdotool", "getdisplaygeometry"],
            check=True,
            capture_output=True,
            text=True,
            timeout=5,
        ).stdout.split()
        width, height = map(int, geometry)
        subprocess.run(
            [
                "xdotool",
                "mousemove",
                str(width // 2),
                str(height // 2),
                "click",
                "1",
            ],
            check=True,
            timeout=5,
        )
    except (OSError, ValueError, subprocess.SubprocessError) as error:
        logger.exception("Unable to activate NTV camera")
        return jsonify({"autoclicked": False, "error": str(error)}), 503

    return jsonify({"autoclicked": True})


@app.errorhandler(500)
def handle_internal_error(error):
    logger.error(
        "Unhandled server error",
        exc_info=(type(error), error, error.__traceback__),
    )
    return jsonify({"error": "Internal server error"}), 500


if __name__ == "__main__":
    if (
        sys.platform == "win32"
        and os.environ.get("WEBCAM_CYCLER_OPEN_BROWSER", "1") != "0"
    ):
        webbrowser.open("http://localhost:5050")
    app.run(host="0.0.0.0", debug=False, port=5050, threaded=True)
