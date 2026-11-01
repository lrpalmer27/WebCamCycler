const SHUFFLE_INTERVAL_MS = 60000;
const RETRY_INTERVAL_MS = 10000;
const PLAYBACK_TIMEOUT_MS = 30000;
const PRELOAD_TIMEOUT_MS = 12000;

let activeHls = null;
let stagedHls = null;
let playbackTimeout = null;
let retryTimeout = null;
let shuffleInProgress = false;
let activeLoadId = 0;
let activeCamera = null;
let stagedCamera = null;
let stagedReady = false;
let stagedPromise = null;
let preloadGeneration = 0;
let activeSlot;
let stagingSlot;

document.addEventListener("DOMContentLoaded", () => {
    activeSlot = {
        container: document.getElementById("Active_slot"),
        iframe: document.getElementById("iFrameElement"),
        video: document.getElementById("VideoElement"),
        hls: null,
        loadId: 0,
    };
    stagingSlot = {
        container: document.getElementById("Staging_slot"),
        iframe: document.getElementById("Staging_iframe"),
        video: document.getElementById("Staging_video"),
        hls: null,
        loadId: 0,
    };

    for (const slot of [activeSlot, stagingSlot]) {
        slot.video.muted = true;
        slot.video.playsInline = true;
        slot.video.addEventListener("playing", () => {
            if (slot === activeSlot) {
                clearPlaybackTimeout();
                showStatus("");
            }
        });
        slot.video.addEventListener("error", () => {
            if (slot === activeSlot && activeCamera) {
                scheduleNextCamera("Video failed to load; trying another camera...");
            } else if (slot === stagingSlot) {
                stagedReady = false;
            }
        });
        slot.video.addEventListener("waiting", () => {
            if (slot === activeSlot && !playbackTimeout) {
                playbackTimeout = window.setTimeout(() => {
                    scheduleNextCamera("Stream stalled; trying another camera...");
                }, PLAYBACK_TIMEOUT_MS);
            }
        });
        slot.iframe.addEventListener("load", () => {
            if (slot === stagingSlot && stagedCamera) {
                stagedReady = true;
            }
        });
        slot.iframe.addEventListener("error", () => {
            if (slot === activeSlot && activeCamera) {
                scheduleNextCamera("Camera page failed to load; trying another camera...");
            } else if (slot === stagingSlot) {
                stagedReady = false;
            }
        });
    }

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
    window.setInterval(UpdateWebcamLocalTime, 10000);
    window.setInterval(ShuffleVideoSource, SHUFFLE_INTERVAL_MS);
});

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
    preloadNextCamera();
}

async function NavigateVideo(direction) {
    if (direction !== "next" && direction !== "previous") {
        return;
    }
    await advanceCamera(direction);
}

async function advanceCamera(direction) {
    if (shuffleInProgress || !activeCamera) {
        return;
    }
    shuffleInProgress = true;
    window.clearTimeout(retryTimeout);
    clearPlaybackTimeout();

    try {
        const offset = direction === "next" ? 1 : -1;
        const cameraCount = activeCamera.CameraCount;
        const targetIndex = (activeCamera.CameraIndex + offset + cameraCount) % cameraCount;
        let nextData;
        let ready = false;

        if (direction === "next" && stagedPromise) {
            await stagedPromise;
        }
        if (direction === "next" && stagedCamera?.CameraIndex === targetIndex) {
            nextData = stagedCamera;
            ready = stagedReady;
        }
        if (!nextData || !ready) {
            if (direction !== "next") {
                preloadGeneration += 1;
                stagedPromise = null;
                clearSlot(stagingSlot);
            }
            nextData = await fetchJSON(`/camera/${targetIndex}/`);
            ready = await prepareSlot(stagingSlot, nextData, true);
        }
        if (!ready) {
            throw new Error(`Camera did not become ready: ${nextData.webcamLocationDesc}`);
        }

        promoteStagedCamera(nextData);
    } catch (error) {
        console.error("Unable to switch cameras:", error);
        showStatus("Next camera is not ready; keeping the current stream.");
        preloadNextCamera();
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

async function prepareSlot(slot, data, isStaging) {
    clearSlot(slot);
    const loadId = ++activeLoadId;
    slot.loadId = loadId;
    let resolveReady;
    const readyPromise = new Promise((resolve) => {
        resolveReady = resolve;
    });
    let settled = false;
    const finish = (ready) => {
        if (settled || slot.loadId !== loadId) {
            return;
        }
        settled = true;
        resolveReady(ready);
    };
    const timeout = window.setTimeout(() => finish(false), PRELOAD_TIMEOUT_MS);
    const ready = () => {
        window.clearTimeout(timeout);
        finish(true);
    };

    if (data.VidSource === "m3u8") {
        slot.video.hidden = false;
        slot.video.addEventListener("playing", ready, { once: true });

        if (window.Hls && Hls.isSupported()) {
            slot.hls = new Hls({ maxBufferLength: 4, maxMaxBufferLength: 6 });
            if (isStaging) {
                stagedHls = slot.hls;
            } else {
                activeHls = slot.hls;
            }
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
            ? "autoplay; fullscreen; encrypted-media"
            : "fullscreen; encrypted-media";
        if (isStaging) {
            stagedReady = false;
            stagedCamera = data;
        }
        slot.iframe.addEventListener("load", ready, { once: true });
        slot.iframe.src = data.ShuffledURL;
    }

    if (isStaging) {
        stagedCamera = data;
    }
    const isReady = await readyPromise;
    window.clearTimeout(timeout);
    return isReady;
}

function clearSlot(slot) {
    slot.loadId = ++activeLoadId;
    slot.retried = false;
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
        slot.iframe.removeAttribute("src");
    }
    if (slot === activeSlot) {
        activeHls = null;
    } else if (slot === stagingSlot) {
        stagedHls = null;
        stagedCamera = null;
        stagedReady = false;
    }
}

function preloadNextCamera() {
    if (!activeCamera || shuffleInProgress || stagedPromise) {
        return;
    }
    const nextIndex = (activeCamera.CameraIndex + 1) % activeCamera.CameraCount;
    const generation = ++preloadGeneration;
    stagedPromise = (async () => {
        try {
            const data = await fetchJSON(`/camera/${nextIndex}/`);
            const expectedIndex =
                activeCamera && (activeCamera.CameraIndex + 1) % activeCamera.CameraCount;
            if (generation !== preloadGeneration || nextIndex !== expectedIndex) {
                return false;
            }
            stagedCamera = data;
            if (
                data.VidSource !== "m3u8" &&
                !iframeIsExplicitlyMuted(data.ShuffledURL)
            ) {
                stagedReady = false;
                return false;
            }
            const ready = await prepareSlot(stagingSlot, data, true);
            stagedReady = ready;
            if (!ready) {
                showStatus("Preloading next stream failed; it will load when selected.");
            }
            return ready;
        } catch (error) {
            console.warn("Unable to preload next camera:", error);
            stagedReady = false;
            return false;
        } finally {
            if (generation === preloadGeneration) {
                stagedPromise = null;
            }
        }
    })();
}

function promoteStagedCamera(data) {
    preloadGeneration += 1;
    const oldActiveSlot = activeSlot;
    oldActiveSlot.container.classList.remove("is-active");
    oldActiveSlot.container.classList.add("is-staging");
    oldActiveSlot.container.setAttribute("aria-hidden", "true");
    stagingSlot.container.classList.remove("is-staging");
    stagingSlot.container.classList.add("is-active");
    stagingSlot.container.removeAttribute("aria-hidden");

    activeSlot = stagingSlot;
    stagingSlot = oldActiveSlot;
    activeCamera = data;
    stagedCamera = null;
    stagedReady = false;
    stagedPromise = null;
    activeHls = activeSlot.hls;
    stagedHls = null;
    updateCameraLabels(data);
    if (data.VidSource === "NTV") {
        fetchJSON("/NTVCAMERA/").catch((error) => {
            console.warn("Unable to activate NTV camera:", error);
        });
    }

    window.setTimeout(() => {
        clearSlot(stagingSlot);
        preloadNextCamera();
    }, 300);
}

document.addEventListener("DOMContentLoaded", () => {
    window.addEventListener("pagehide", () => {
        clearSlot(activeSlot);
        clearSlot(stagingSlot);
    });
});
