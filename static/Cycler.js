const SHUFFLE_INTERVAL_MS = 60000;
const RETRY_INTERVAL_MS = 10000;
const PLAYBACK_TIMEOUT_MS = 30000;
const CAMERA_LOAD_TIMEOUT_MS = 12000;
const BROWSER_HEARTBEAT_INTERVAL_MS = 15000;

let playbackTimeout = null;
let retryTimeout = null;
let shuffleInProgress = false;
let activeLoadId = 0;
let activeCamera = null;
let activeSlot;

document.addEventListener("DOMContentLoaded", () => {
    activeSlot = {
        iframe: document.getElementById("iFrameElement"),
        video: document.getElementById("VideoElement"),
        hls: null,
        loadId: 0,
        loadListeners: [],
    };

    activeSlot.video.muted = true;
    activeSlot.video.playsInline = true;
    activeSlot.video.addEventListener("playing", () => {
        clearPlaybackTimeout();
        showStatus("");
    });
    activeSlot.video.addEventListener("error", () => {
        if (activeCamera) {
            scheduleNextCamera("Video failed to load; trying another camera...");
        }
    });
    activeSlot.video.addEventListener("waiting", () => {
        if (!playbackTimeout) {
            playbackTimeout = window.setTimeout(() => {
                scheduleNextCamera("Stream stalled; trying another camera...");
            }, PLAYBACK_TIMEOUT_MS);
        }
    });

    document.getElementById("Previous_camera").addEventListener("click", () => {
        NavigateVideo("previous");
    });
    document.getElementById("Next_camera").addEventListener("click", () => {
        NavigateVideo("next");
    });
    document.addEventListener("keydown", (event) => {
        if (event.key === "ArrowLeft") {
            NavigateVideo("previous");
        } else if (event.key === "ArrowRight") {
            NavigateVideo("next");
        }
    });

    ShuffleVideoSource();
    sendBrowserHeartbeat();
    window.setInterval(sendBrowserHeartbeat, BROWSER_HEARTBEAT_INTERVAL_MS);
    window.setInterval(UpdateWebcamLocalTime, 10000);
    window.setInterval(ShuffleVideoSource, SHUFFLE_INTERVAL_MS);
});

function sendBrowserHeartbeat() {
    fetch("/browser-heartbeat/", { method: "POST", cache: "no-store" })
        .catch((error) => {
            console.error("Unable to send browser heartbeat:", error);
        });
}

function showStatus(message) {
    document.getElementById("Playback_status").innerText = message;
}

function clearPlaybackTimeout() {
    window.clearTimeout(playbackTimeout);
    playbackTimeout = null;
}

function scheduleNextCamera(message) {
    showStatus(message);
    clearPlaybackTimeout();
    window.clearTimeout(retryTimeout);
    retryTimeout = window.setTimeout(ShuffleVideoSource, 3000);
}

async function fetchJSON(url) {
    const response = await fetch(url, { cache: "no-store" });
    if (!response.ok) {
        throw new Error(`${url} returned HTTP ${response.status}`);
    }
    return response.json();
}

async function UpdateWebcamLocalTime() {
    if (!activeCamera) {
        return;
    }
    try {
        const data = await fetchJSON(`/live/?index=${activeCamera.CameraIndex}`);
        document.getElementById("Webcam_local_time_").innerText =
            data.Webcam_local_time;
    } catch (error) {
        console.error("Unable to update camera time:", error);
    }
}

async function ShuffleVideoSource() {
    if (shuffleInProgress) {
        return;
    }
    if (activeCamera) {
        await advanceCamera("next");
        return;
    }

    shuffleInProgress = true;
    try {
        const data = await fetchJSON("/shuffle/");
        activeCamera = data;
        updateCameraLabels(data);
        const ready = await prepareSlot(activeSlot, data, false);
        if (!ready) {
            throw new Error(`Camera did not start: ${data.webcamLocationDesc}`);
        }
    } catch (error) {
        console.error("Unable to start a camera:", error);
        showStatus("Unable to start camera; retrying...");
        window.clearTimeout(retryTimeout);
        retryTimeout = window.setTimeout(ShuffleVideoSource, RETRY_INTERVAL_MS);
    } finally {
        shuffleInProgress = false;
    }
}

async function NavigateVideo(direction) {
    if (direction !== "next" && direction !== "previous") {
        return;
    }
    if (shuffleInProgress || !activeCamera) {
        return;
    }

    shuffleInProgress = true;
    window.clearTimeout(retryTimeout);
    clearPlaybackTimeout();

    try {
        const targetIndex = direction === "next"
            ? activeCamera.NextCameraIndex
            : activeCamera.PreviousCameraIndex;

        const data = await fetchJSON(`/camera/${targetIndex}/`);
        activeCamera = data;
        updateCameraLabels(data);

        const started = await prepareSlot(activeSlot, data, false);
        if (!started) {
            showStatus("Camera could not be started.");
        }
    } catch (error) {
        console.error("Unable to select camera:", error);
        showStatus("Unable to select camera; try again.");
    } finally {
        shuffleInProgress = false;
    }
}

async function advanceCamera(direction) {
    if (shuffleInProgress || !activeCamera) {
        return;
    }
    shuffleInProgress = true;
    window.clearTimeout(retryTimeout);
    clearPlaybackTimeout();

    try {
        let targetIndex = direction === "previous"
            ? activeCamera.PreviousCameraIndex
            : activeCamera.NextCameraIndex;
        const attempts = direction === "previous" ? 1 : activeCamera.CameraCount;
        for (let attempt = 0; attempt < attempts; attempt += 1) {
            const candidate = await fetchJSON(`/camera/${targetIndex}/`);
            activeCamera = candidate;
            updateCameraLabels(candidate);
            const ready = await prepareSlot(activeSlot, candidate);
            if (ready) {
                return;
            }
            console.warn(
                `Camera was not ready within ${CAMERA_LOAD_TIMEOUT_MS}ms; skipping:`,
                candidate.webcamLocationDesc
            );
            targetIndex = candidate.NextCameraIndex;
        }

        showStatus("No other streams are ready; retrying shortly...");
        window.clearTimeout(retryTimeout);
        retryTimeout = window.setTimeout(ShuffleVideoSource, RETRY_INTERVAL_MS);
    } catch (error) {
        console.error("Unable to find a ready camera:", error);
        showStatus("Unable to load another stream; retrying shortly...");
        window.clearTimeout(retryTimeout);
        retryTimeout = window.setTimeout(ShuffleVideoSource, RETRY_INTERVAL_MS);
    } finally {
        shuffleInProgress = false;
    }
}

function updateCameraLabels(data) {
    document.getElementById("Webcam_local_time_").innerText =
        data.Webcam_local_time;
    document.getElementById("Webcam_location_description").innerText =
        data.webcamLocationDesc;
    showStatus("");
}

function iframeIsExplicitlyMuted(url) {
    try {
        return new URL(url, window.location.href).searchParams.get("mute") === "1";
    } catch (error) {
        console.warn("Unable to determine whether iframe audio is muted:", error);
        return false;
    }
}

async function prepareSlot(slot, data, waitForReady = true) {
    clearSlot(slot);
    const loadId = ++activeLoadId;
    slot.loadId = loadId;
    let resolveReady;
    const readyPromise = new Promise((resolve) => {
        resolveReady = resolve;
    });
    let settled = false;
    let readyResult = null;
    let timeout;
    const finish = (ready) => {
        if (settled) {
            return;
        }
        settled = true;
        readyResult = ready;
        window.clearTimeout(timeout);
        clearSlotLoadListeners(slot);
        if (slot.finishPending === finish) {
            slot.finishPending = null;
        }
        resolveReady(ready);
    };
    slot.finishPending = finish;
    timeout = window.setTimeout(() => finish(false), CAMERA_LOAD_TIMEOUT_MS);
    const addLoadListener = (target, eventName, handler) => {
        target.addEventListener(eventName, handler);
        slot.loadListeners.push({ target, eventName, handler });
    };
    const ready = () => {
        if (slot.loadId !== loadId) {
            return;
        }
        window.clearTimeout(timeout);
        finish(true);
    };

    if (data.VidSource === "m3u8") {
        slot.video.hidden = false;
        addLoadListener(slot.video, "playing", () => {
            if (slot.loadId === loadId) {
                ready();
            }
        });

        if (window.Hls && Hls.isSupported()) {
            slot.hls = new Hls({
                maxBufferLength: 2,
                maxMaxBufferLength: 3,
                maxBufferSize: 12 * 1024 * 1024,
            });
            slot.hls.on(Hls.Events.ERROR, (_event, errorData) => {
                if (!errorData.fatal || slot.loadId !== loadId) {
                    return;
                }
                if (errorData.type === Hls.ErrorTypes.NETWORK_ERROR && !slot.retried) {
                    slot.retried = true;
                    slot.hls.startLoad();
                } else if (errorData.type === Hls.ErrorTypes.MEDIA_ERROR && !slot.retried) {
                    slot.retried = true;
                    slot.hls.recoverMediaError();
                } else {
                    if (slot === activeSlot) {
                        scheduleNextCamera(
                            "Stream failed; trying another camera..."
                        );
                    }
                    finish(false);
                }
            });
            slot.hls.on(Hls.Events.MANIFEST_PARSED, () => {
                if (slot.loadId !== loadId) {
                    return;
                }
                slot.video.play().catch((error) => {
                    console.warn("Autoplay was blocked:", error);
                    finish(false);
                });
            });
            slot.hls.loadSource(data.ShuffledURL);
            slot.hls.attachMedia(slot.video);
        } else if (slot.video.canPlayType("application/vnd.apple.mpegurl")) {
            slot.video.src = data.ShuffledURL;
            slot.video.play().catch((error) => {
                console.warn("Autoplay was blocked:", error);
                finish(false);
            });
        } else {
            finish(false);
        }
    } else {
        slot.iframe.hidden = false;
        slot.iframe.allow = iframeIsExplicitlyMuted(data.ShuffledURL)
            ? "camera 'none'; microphone 'none'; autoplay; fullscreen; encrypted-media"
            : "camera 'none'; microphone 'none'; fullscreen; encrypted-media";
        addLoadListener(slot.iframe, "load", () => {
            ready();
        });
        addLoadListener(slot.iframe, "error", () => {
            if (slot.loadId !== loadId) {
                return;
            }
            if (slot === activeSlot && activeCamera) {
                scheduleNextCamera(
                    "Camera page failed to load; trying another camera..."
                );
            }
            finish(false);
        });
        slot.iframe.src = data.ShuffledURL;
    }

    if (!waitForReady) {
        return settled ? readyResult : true;
    }
    const isReady = await readyPromise;
    window.clearTimeout(timeout);
    return isReady;
}

function clearSlot(slot) {
    if (slot.finishPending) {
        slot.finishPending(false);
    }
    clearSlotLoadListeners(slot);
    slot.loadId = ++activeLoadId;
    slot.retried = false;
    if (slot === activeSlot) {
        clearPlaybackTimeout();
    }
    if (slot.hls) {
        slot.hls.destroy();
        slot.hls = null;
    }
    if (slot.video) {
        slot.video.pause();
        slot.video.removeAttribute("src");
        slot.video.load();
        slot.video.hidden = true;
    }
    if (slot.iframe) {
        slot.iframe.hidden = true;
        slot.iframe.src = "about:blank";
    }
}

function clearSlotLoadListeners(slot) {
    for (const { target, eventName, handler } of slot.loadListeners) {
        target.removeEventListener(eventName, handler);
    }
    slot.loadListeners = [];
}

document.addEventListener("DOMContentLoaded", () => {
    window.addEventListener("pagehide", () => {
        clearSlot(activeSlot);
    });
});
