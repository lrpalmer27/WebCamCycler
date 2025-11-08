
document.addEventListener('DOMContentLoaded',function(){
    ShuffleVideoSource()
})

function UpdateWebcamLocalTime(){
    fetch("/live/")
    .then(response => response.json())
    .then(data => {
        let t = data.Webcam_local_time;
        
        //update time element
        let WebcamLocalTimeElement = document.getElementById("Webcam_local_time_");
        WebcamLocalTimeElement.innerText = {t};
        document.getElementById('Webcam_local_time_').innerText = t;

        console.log('LOCALTIME: ',t)
    })
}

function ShuffleVideoSource(){
    fetch("/shuffle/")
    .then(response => response.json())
    .then(data => {
        let t = data.Webcam_local_time;
        let webcamLocationDesc = data.webcamLocationDesc;
        let new_URL = data.ShuffledURL;
        let VideoSource = data.VidSource;
        let iframeElement = document.getElementById("iFrameElement");
        let VideoElement = document.getElementById("VideoElement");

        // hide both video elements to start: 
        iframeElement.hidden = true;
        VideoElement.hidden = true;

        //update time element
        let WebcamLocalTimeElement = document.getElementById("Webcam_local_time_");
        WebcamLocalTimeElement.innerText = {t};
        document.getElementById('Webcam_local_time_').innerText = t;

        // update location description element
        let webcamLocationDescElement = document.getElementById("Webcam_location_description");
        webcamLocationDescElement.innerText = {webcamLocationDesc};
        document.getElementById('Webcam_location_description').innerText = webcamLocationDesc;

        // ------------------------ source dependent video handling below: ------------------------
        if (VideoSource === 'm3u8'){
            // // // this is for handling HLS video files streaming (.m3u8)
            // show video device we dont want
            VideoElement.hidden = false;

            // play video with HLS.js -- this is needed on Rpi
            const hls = new Hls();
            hls.loadSource(new_URL);
            hls.attachMedia(VideoElement);
            hls.on(Hls.Events.MANIFEST_PARSED, () => VideoElement.play());

            // update URL on video device we do want.
            // VideoElement.src = new_URL;

        } else if (VideoSource === 'NTV'){
            // // // this is for handling NTV video streams that require us to click play each time.
            // hide video device we dont want
            iframeElement.hidden = false;
            // update URL on video device we do want.
            iframeElement.src = new_URL;

            //autoplay NTV video streams:
            fetch("/NTVCAMERA/");
            console.log("fetching autoplay");
            
        } else {
            // // // this is for handling generic web based video streams like youtube
            // hide video device we dont want
            iframeElement.hidden = false;
            // update URL on video device we do want.
            iframeElement.src = new_URL;
        };

        console.log(data.ShuffledURL);
    })
}

setInterval(UpdateWebcamLocalTime,1000)
setInterval(ShuffleVideoSource,60000)