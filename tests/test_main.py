import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

import main


class CameraListTests(unittest.TestCase):
    def test_configured_cameras_are_valid_and_cover_every_source(self):
        cameras = main.load_cameras()

        self.assertGreater(len(cameras), 0)
        self.assertEqual(
            {camera["SOURCE"] for camera in cameras},
            {"Youtube", "NTV", "m3u8", "IPCam", "Earthcam"},
        )
        self.assertTrue(
            all(camera["URL"].startswith("https://") for camera in cameras)
        )
        self.assertTrue(
            all(
                not any(char.isspace() for char in camera["URL"])
                for camera in cameras
            )
        )

    def test_invalid_timezone_is_reported_with_csv_row(self):
        csv_content = (
            "DESCRIPTION,URL,PYTZ TIMEZONE,SOURCE\n"
            "Test camera,https://example.com,Unknown/Zone,m3u8\n"
        )
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "cameras.csv"
            path.write_text(csv_content, encoding="utf-8")

            with self.assertRaisesRegex(ValueError, "row 2.*unknown timezone"):
                main.load_cameras(path)

    def test_unescaped_space_in_url_is_reported_with_csv_row(self):
        csv_content = (
            "DESCRIPTION,URL,PYTZ TIMEZONE,SOURCE\n"
            "Test camera,https://example.com/a b,US/Pacific,m3u8\n"
        )
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "cameras.csv"
            path.write_text(csv_content, encoding="utf-8")

            with self.assertRaisesRegex(ValueError, "row 2.*invalid URL"):
                main.load_cameras(path)


class CameraRoutesTests(unittest.TestCase):
    def setUp(self):
        self.client = main.app.test_client()
        main.app.config["CAMERA_INDEX"] = None
        main.app.config["CAMERA_POSITION"] = None
        main.app.config["DEV_MODE"] = False
        main.app.config["BROWSER_HEARTBEAT_AT"] = None

    def test_health_and_camera_list_report_all_configured_cameras(self):
        health = self.client.get("/health/")
        camera_list = self.client.get("/cameras/")

        self.assertEqual(health.status_code, 200)
        self.assertEqual(health.json["status"], "ok")
        self.assertEqual(
            health.json["camera_count"], len(main.app.config["CAMERAS"])
        )
        self.assertEqual(camera_list.status_code, 200)
        self.assertEqual(
            len(camera_list.json),
            len(main.app.config["CAMERAS"]),
        )
        self.assertEqual(
            {camera["source"] for camera in camera_list.json},
            {"Youtube", "NTV", "m3u8", "IPCam", "Earthcam"},
        )

    def test_browser_heartbeat_is_stale_until_the_viewer_reports(self):
        response = self.client.get("/browser-heartbeat/")

        self.assertEqual(response.status_code, 503)
        self.assertEqual(response.json["status"], "stale")

    def test_browser_heartbeat_expires_when_viewer_stops_reporting(self):
        with patch("main.time.monotonic", return_value=100):
            posted = self.client.post("/browser-heartbeat/")
        with patch("main.time.monotonic", return_value=145):
            status = self.client.get("/browser-heartbeat/")

        self.assertEqual(posted.status_code, 204)
        self.assertEqual(status.status_code, 503)
        self.assertEqual(status.json["status"], "stale")

    def test_browser_heartbeat_is_healthy_when_viewer_reports(self):
        with patch("main.time.monotonic", return_value=100):
            self.client.post("/browser-heartbeat/")
        with patch("main.time.monotonic", return_value=120):
            status = self.client.get("/browser-heartbeat/")

        self.assertEqual(status.status_code, 200)
        self.assertEqual(status.json["status"], "ok")
        self.assertEqual(status.json["age_seconds"], 20)

    def test_shuffle_returns_a_valid_camera_and_time(self):
        response = self.client.get("/shuffle/")
        data = response.json
        order = main.load_camera_order()

        self.assertEqual(response.status_code, 200)
        self.assertEqual(data["CameraIndex"], order[0])
        self.assertIn(
            data["ShuffledURL"],
            {camera["URL"] for camera in main.app.config["CAMERAS"]},
        )
        self.assertIn(
            data["VidSource"],
            {"Youtube", "NTV", "m3u8", "IPCam", "Earthcam"},
        )
        self.assertTrue(data["webcamLocationDesc"])
        self.assertTrue(data["Webcam_local_time"])
        self.assertEqual(data["NextCameraIndex"], order[1])

    def test_health_check_does_not_consume_first_camera_in_random_order(self):
        order = main.load_camera_order()

        self.client.get("/health/")
        first_camera = self.client.get("/shuffle/").json

        self.assertEqual(first_camera["CameraIndex"], order[0])

    def test_shuffle_cycles_through_one_fixed_random_order(self):
        order = main.load_camera_order()

        shuffled = [
            self.client.get("/shuffle/").json["CameraIndex"]
            for _ in range(len(order) + 1)
        ]

        self.assertEqual(shuffled[:-1], order)
        self.assertEqual(shuffled[-1], order[0])

    def test_random_order_contains_each_camera_once(self):
        order = main.load_camera_order()

        self.assertEqual(len(order), len(main.app.config["CAMERAS"]))
        self.assertEqual(set(order), set(range(len(main.app.config["CAMERAS"]))))

    def test_random_order_is_stored_in_a_temp_file(self):
        order_path = Path(main.app.config["CAMERA_ORDER_FILE"])

        self.assertTrue(order_path.is_file())
        self.assertNotIn("CAMERA_ORDER", main.app.config)
        self.assertEqual(len(main.load_camera_order()), len(main.app.config["CAMERAS"]))

    def test_previous_and_next_navigate_cameras_in_randomized_order(self):
        cameras = main.app.config["CAMERAS"]
        order = main.load_camera_order()
        main.app.config["CAMERA_INDEX"] = order[0]
        main.app.config["CAMERA_POSITION"] = 0

        next_camera = self.client.get("/navigate/next/").json
        previous_camera = self.client.get("/navigate/previous/").json

        self.assertEqual(next_camera["CameraIndex"], order[1])
        self.assertEqual(
            next_camera["webcamLocationDesc"], cameras[order[1]]["DESCRIPTION"]
        )
        self.assertEqual(previous_camera["CameraIndex"], order[0])
        self.assertEqual(
            previous_camera["webcamLocationDesc"], cameras[order[0]]["DESCRIPTION"]
        )

    def test_camera_navigation_wraps_at_both_ends(self):
        order = main.load_camera_order()
        main.app.config["CAMERA_INDEX"] = order[-1]
        main.app.config["CAMERA_POSITION"] = len(order) - 1

        next_camera = self.client.get("/navigate/next/").json
        previous_camera = self.client.get("/navigate/previous/").json

        self.assertEqual(next_camera["CameraIndex"], order[0])
        self.assertEqual(
            previous_camera["CameraIndex"], order[-1]
        )

    def test_camera_navigation_uses_the_calling_viewer_index(self):
        order = main.load_camera_order()
        expected_index = order[(order.index(0) + 1) % len(order)]
        main.app.config["CAMERA_INDEX"] = order[-1]
        main.app.config["CAMERA_POSITION"] = len(order) - 1

        response = self.client.get("/navigate/next/?index=0")

        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.json["CameraIndex"], expected_index)

    def test_camera_details_endpoint_returns_requested_camera_without_changing_state(self):
        main.app.config["CAMERA_INDEX"] = 5

        response = self.client.get("/camera/2/")

        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.json["CameraIndex"], 2)
        self.assertEqual(
            response.json["webcamLocationDesc"],
            main.app.config["CAMERAS"][2]["DESCRIPTION"],
        )
        self.assertEqual(main.app.config["CAMERA_INDEX"], 5)

    def test_camera_details_endpoint_rejects_out_of_range_index(self):
        response = self.client.get(
            f"/camera/{len(main.app.config['CAMERAS'])}/"
        )

        self.assertEqual(response.status_code, 404)
        self.assertIn("error", response.json)

    def test_invalid_camera_navigation_direction_is_rejected(self):
        response = self.client.get("/navigate/random/")

        self.assertEqual(response.status_code, 400)
        self.assertIn("error", response.json)

    def test_invalid_camera_navigation_index_is_rejected(self):
        response = self.client.get("/navigate/next/?index=999")

        self.assertEqual(response.status_code, 400)
        self.assertIn("error", response.json)

    def test_viewer_page_includes_playback_elements(self):
        response = self.client.get("/")
        page = response.get_data(as_text=True)

        self.assertEqual(response.status_code, 200)
        self.assertIn('id="VideoElement"', page)
        self.assertIn('id="iFrameElement"', page)
        self.assertIn("camera 'none'", page)
        self.assertIn("microphone 'none'", page)
        self.assertIn('id="Previous_camera"', page)
        self.assertIn('id="Next_camera"', page)
        self.assertIn("hls.js@1.5.17", page)
        cycler_script = Path(main.app.root_path) / "static" / "Cycler.js"
        script = cycler_script.read_text(encoding="utf-8")
        self.assertIn('fetch("/browser-heartbeat/"', script)
        self.assertIn(
            "`/navigate/${direction}/?index=${activeCamera.CameraIndex}`",
            script,
        )

    def test_development_reload_is_available_only_when_enabled(self):
        self.assertEqual(self.client.get("/dev/revision/").status_code, 404)

        main.app.config["DEV_MODE"] = True
        revision = self.client.get("/dev/revision/")
        page = self.client.get("/").get_data(as_text=True)

        self.assertEqual(revision.status_code, 200)
        self.assertGreaterEqual(len(revision.json["revision"]), 5)
        self.assertIn("dev-reload.js", page)

    def test_live_time_uses_current_camera_timezone(self):
        response = self.client.get("/live/")

        self.assertEqual(response.status_code, 200)
        self.assertTrue(response.json["Webcam_local_time"])


if __name__ == "__main__":
    unittest.main()
