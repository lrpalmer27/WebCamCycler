
function autoplay_NTV_streams(){
    fetch("/NTVCAMERA/")
    };

document.addEventListener('DOMContentLoaded',function(){
    ShuffleVideoSource()
});

function UpdateWebcamLocalTime(){
    fetch("/live/")
    .then(response => response.json())
    .then(data => {
        let t = data.Webcam_local_time;
        
        //update time element
        let WebcamLocalTimeElement = document.getElementById("Webcam_local_time_");
        WebcamLocalTimeElement.innerText = {t};
        document.getElementById('Webcam_local_time_').innerText = t;

        //console.log(data);
    })
}

function ShuffleVideoSource(){
    fetch("/shuffle/")
    .then(response => response.json())
    .then(data => {
        let t = data.Webcam_local_time;
        let webcamLocationDesc = data.webcamLocationDesc;
        let new_URL = data.ShuffledURL;
        let NTV = data.NTV;

        //update time element
        let WebcamLocalTimeElement = document.getElementById("Webcam_local_time_");
        WebcamLocalTimeElement.innerText = {t};
        document.getElementById('Webcam_local_time_').innerText = t;

        // update location description element
        let webcamLocationDescElement = document.getElementById("Webcam_location_description");
        webcamLocationDescElement.innerText = {webcamLocationDesc};
        document.getElementById('Webcam_location_description').innerText = webcamLocationDesc;

        // update URL
        let iframeElement = document.getElementById("iFrameElement");
        iframeElement.src = new_URL;

        // call autoclick fcn
        if (NTV) {
            autoplay_NTV_streams()
        }

        console.log(data.webcamLocationDesc, data.ShuffledURL);
    })
}

setInterval(UpdateWebcamLocalTime,1000)
setInterval(ShuffleVideoSource,60000)