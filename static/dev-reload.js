const DEV_RELOAD_INTERVAL_MS = 1000;

async function checkForDevelopmentChanges() {
    try {
        const response = await fetch("/dev/revision/", { cache: "no-store" });
        if (!response.ok) {
            throw new Error(`/dev/revision/ returned HTTP ${response.status}`);
        }

        const data = await response.json();
        const revision = JSON.stringify(data.revision);
        if (window.webcamCyclerRevision === undefined) {
            window.webcamCyclerRevision = revision;
        } else if (window.webcamCyclerRevision !== revision) {
            window.location.reload();
        }
    } catch (error) {
        console.warn("Development change check failed; it will retry:", error);
    }
}

document.addEventListener("DOMContentLoaded", () => {
    checkForDevelopmentChanges();
    window.setInterval(checkForDevelopmentChanges, DEV_RELOAD_INTERVAL_MS);
});
