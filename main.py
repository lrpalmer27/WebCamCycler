from flask import Flask, render_template, request, jsonify
from datetime import timedelta, datetime, timezone 
import pytz
from pytz import timezone as ptztz
import pandas as pd
import random
import math

# basics from: https://github.com/CoffeeKeyboardYouTube/TimerWebAppFlask/blob/main/templates/home.html
#              https://www.youtube.com/watch?v=7FwXKxqfuko

app = Flask(__name__)
app.config['TEMPLATES_AUTO_RELOAD'] = True

# # read df
app.config['df']= pd.read_csv('./WebcamURLs.csv')
# make random number
app.config['RandomNo']= random.randint(0,app.config['df'].shape[0]-1)

@app.route("/")
def renderHTML():
    print('rendering HTML')
    return render_template('overlay.html')

def get_webcam_timezone_time():
    WEBCAM_TZ = app.config['df']['PYTZ TIMEZONE'].iloc[app.config['RandomNo']]
    # WEBCAM_TZ = df['PYTZ TIMEZONE'].iloc[RandomNo]
    WebCamTimeZone_time = datetime.now(tz=ptztz(WEBCAM_TZ))
    # print('time',WebCamTimeZone_time)
    WebCamTimeZone_time_desc = WebCamTimeZone_time.strftime("%m/%d/%Y - %H:%M:%S %p")
    return WebCamTimeZone_time_desc

def SetDataParameters():
    # # read df
    app.config['df']= pd.read_csv('./WebcamURLs.csv')
    # get new random number
    app.config['RandomNo'] = random.randint(0,app.config['df'].shape[0]-1)
    # update URL
    url_string= str(app.config['df']['URL'].iloc[app.config['RandomNo']])
    # Update locaton description
    webcamLocationDesc=str(app.config['df']['DESCRIPTION'].iloc[app.config['RandomNo']])
    #re-render html with new URL
    # renderHTML()
    if debugging: 
        print("Shuffled to new webcam, random No.: ",app.config['RandomNo'])
        print("Location: ",webcamLocationDesc)
        print("New URL: ", url_string)
        print("check str: ", webcamLocationDesc)
    
    return jsonify({'Webcam_local_time':get_webcam_timezone_time(),'webcamLocationDesc':webcamLocationDesc,'ShuffledURL':url_string})
    
@app.route("/live/")
def UpdateTimeLoop():
    return jsonify({'Webcam_local_time': get_webcam_timezone_time()})

@app.route("/shuffle/")
def Shuffle_webcam_locations():
    return SetDataParameters()
  
if __name__ == "__main__":
    debugging = 0
    if debugging: 
        pytz.all_timezones
    
    app.run(debug=debugging, port=5000)
    
    # TODO: make the PI turn off during working hours (when I am not usually home)
    # LocalTZ = ptztz('America/Los_Angeles')
    # LOCALTIME=datetime.now(tz=LocalTZ)
    
    # TODO: make it so this gets displayed full screen on pi.