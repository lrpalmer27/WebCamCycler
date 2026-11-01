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
let stagedLoadAttempted = false;
let stagedPromise = null;
let preloadGeneration = 0;
let failedAutomaticCameraIndex = null;
let failedAutomaticNextIndex = null;
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
                if (slot.finishPending) {
                    slot.finishPending(false);
                }
            }
        });
        slot.video.addEventListener("waiting", () => {
            if (slot === activeSlot && !playbackTimeout) {
                playbackTimeout = window.setTimeout(() => {
                    scheduleNextCamera("Stream stalled; trying another camera...");
                }, PLAYBACK_TIMEOUT_MS);
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
    if (shuffleInProgress || !activeCamera) {
        return;
    }

    shuffleInProgress = true;
    window.clearTimeout(retryTimeout);
    clearPlaybackTimeout();
    preloadGeneration += 1;
    stagedPromise = null;
    clearSlot(stagingSlot);

    try {
        let targetIndex = direction === "next"
            ? activeCamera.NextCameraIndex
            : activeCamera.PreviousCameraIndex;
        if (
            direction === "next" &&
            targetIndex === failedAutomaticCameraIndex
        ) {
            targetIndex = failedAutomaticNextIndex;
        }

        const data = await fetchJSON(`/camera/${targetIndex}/`);
        failedAutomaticCameraIndex = null;
        failedAutomaticNextIndex = null;
        activeCamera = data;
        updateCameraLabels(data);

        const started = await prepareSlot(activeSlot, data, false, false);
        if (!started) {
            showStatus("Camera could not be started.");
        }
    } catch (error) {
        console.error("Unable to select camera:", error);
        showStatus("Unable to select camera; try again.");
    } finally {
        shuffleInProgress = false;
        preloadNextCamera();
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
        if (direction === "previous") {
            preloadGeneration += 1;
            stagedPromise = null;
            clearSlot(stagingSlot);
            const previousCamera = await fetchJSON(
                `/camera/${activeCamera.PreviousCameraIndex}/`
            );
            const ready = await prepareSlot(stagingSlot, previousCamera, true);
            if (!ready) {
                throw new Error(
                    `Camera did not become ready: ${previousCamera.webcamLocationDesc}`
                );
            }
            promoteStagedCamera(previousCamera);
            return;
        }

        if (stagedPromise) {
            await stagedPromise;
        }

        let targetIndex = activeCamera.NextCameraIndex;
        let firstFailedCamera = null;
        for (let attempt = 0; attempt < activeCamera.CameraCount; attempt += 1) {
            let candidate = null;
            let ready = false;
            if (failedAutomaticCameraIndex === targetIndex) {
                candidate = {
                    CameraIndex: failedAutomaticCameraIndex,
                    NextCameraIndex: failedAutomaticNextIndex,
                    webcamLocationDesc: "previously unavailable camera",
                };
            } else if (stagedCamera?.CameraIndex === targetIndex) {
                candidate = stagedCamera;
                ready = stagedReady;
                if (!ready && !stagedLoadAttempted) {
                    ready = await prepareSlot(stagingSlot, candidate, true);
                }
            } else {
                candidate = await fetchJSON(`/camera/${targetIndex}/`);
                ready = await prepareSlot(stagingSlot, candidate, true);
            }

            if (ready) {
                failedAutomaticCameraIndex = null;
                failedAutomaticNextIndex = null;
                promoteStagedCamera(candidate);
                return;
            }

            if (!firstFailedCamera) {
                firstFailedCamera = candidate;
            }
            console.warn(
                `Camera was not ready within ${PRELOAD_TIMEOUT_MS}ms; skipping:`,
                candidate.webcamLocationDesc
            );
            targetIndex = candidate.NextCameraIndex;
            clearSlot(stagingSlot);
        }

        if (firstFailedCamera) {
            failedAutomaticCameraIndex = firstFailedCamera.CameraIndex;
            failedAutomaticNextIndex = firstFailedCamera.NextCameraIndex;
        }
        showStatus("No other streams are ready; retrying shortly...");
        window.clearTimeout(retryTimeout);
        retryTimeout = window.setTimeout(ShuffleVideoSource, RETRY_INTERVAL_MS);
    } catch (error) {
        console.error("Unable to find a ready camera:", error);
        clearSlot(stagingSlot);
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

async function prepareSlot(slot, data, isStaging, waitForReady = true) {
    clearSlot(slot);
    if (isStaging) {
        stagedLoadAttempted = true;
    }
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
        if (slot.finishPending === finish) {
            slot.finishPending = null;
        }
        resolveReady(ready);
    };
    slot.finishPending = finish;
    timeout = window.setTimeout(() => finish(false), PRELOAD_TIMEOUT_MS);
    const ready = () => {
        if (slot.loadId !== loadId) {
            return;
        }
        window.clearTimeout(timeout);
        finish(true);
    };

    if (data.VidSource === "m3u8") {
        slot.video.hidden = false;
        slot.video.addEventListener("playing", () => {
            if (slot.loadId === loadId) {
                ready();
            }
        }, { once: true });

        if (window.Hls && Hls.isSupported()) {
            slot.hls = new Hls({
                maxBufferLength: isStaging ? 2 : 4,
                maxMaxBufferLength: isStaging ? 3 : 6,
            });
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
        slot.iframe.addEventListener("load", () => {
            ready();
        }, { once: true });
        slot.iframe.addEventListener("error", () => {
            if (slot.loadId !== loadId) {
                return;
            }
            if (slot === activeSlot && activeCamera) {
                scheduleNextCamera(
                    "Camera page failed to load; trying another camera..."
                );
            }
            finish(false);
        }, { once: true });
        slot.iframe.src = data.ShuffledURL;
    }

    if (isStaging) {
        stagedCamera = data;
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
        stagedLoadAttempted = false;
    }
}

function preloadNextCamera() {
    if (!activeCamera || shuffleInProgress || stagedPromise) {
        return;
    }
    const nextIndex = activeCamera.NextCameraIndex;
    const generation = ++preloadGeneration;
    stagedPromise = (async () => {
        try {
            const data = await fetchJSON(`/camera/${nextIndex}/`);
            const expectedIndex = activeCamera && activeCamera.NextCameraIndex;
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
            if (generation !== preloadGeneration) {
                return false;
            }
            stagedReady = ready;
            if (!ready) {
                failedAutomaticCameraIndex = data.CameraIndex;
                failedAutomaticNextIndex = data.NextCameraIndex;
                clearSlot(stagingSlot);
            }
            return ready;
        } catch (error) {
            console.warn("Unable to preload next camera:", error);
            if (generation === preloadGeneration) {
                stagedReady = false;
                if (stagedCamera) {
                    failedAutomaticCameraIndex = stagedCamera.CameraIndex;
                    failedAutomaticNextIndex = stagedCamera.NextCameraIndex;
                }
                clearSlot(stagingSlot);
            }
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
