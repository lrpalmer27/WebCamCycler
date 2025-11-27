from flask import Flask, render_template, request, jsonify
from datetime import timedelta, datetime, timezone 
import pytz
from pytz import timezone as ptztz
import pandas as pd
import random
import webbrowser
import sys 
import subprocess
import time

# basics from: https://github.com/CoffeeKeyboardYouTube/TimerWebAppFlask/blob/main/templates/home.html
#              https://www.youtube.com/watch?v=7FwXKxqfuko

debugging = 0

app = Flask(__name__)
app.config['TEMPLATES_AUTO_RELOAD'] = True

# # read df
WebCamList='./WebcamURLs_All.csv'
if debugging: 
    WebCamList ='./WebcamURLs_All.csv'
app.config['df']= pd.read_csv(WebCamList)
# make random number. Start with an NTV camera so we get into an active play loop.
app.config['RandomNo'] = 0

@app.route("/")
def renderHTML():
    print('rendering HTML')
    return render_template('overlay.html')

def get_webcam_timezone_time(o=None):
    WEBCAM_TZ = app.config['df']['PYTZ TIMEZONE'].iloc[app.config['RandomNo']]
    # WEBCAM_TZ = df['PYTZ TIMEZONE'].iloc[RandomNo]
    WebCamTimeZone_time = datetime.now(tz=ptztz(WEBCAM_TZ))
    # print('time',WebCamTimeZone_time)
    WebCamTimeZone_time_desc = WebCamTimeZone_time.strftime("%m/%d/%Y - %I:%M:%S %p")
    if o != None:
        return [str(WEBCAM_TZ),WebCamTimeZone_time_desc]
    else:
        return WebCamTimeZone_time_desc

def SetDataParameters():
    # # read df
    app.config['df']= pd.read_csv(WebCamList)
    # get new random number
    app.config['RandomNo'] = random.randint(0,app.config['df'].shape[0]-1)
    # update URL
    url_string= str(app.config['df']['URL'].iloc[app.config['RandomNo']])
    # Update locaton description
    webcamLocationDesc=str(app.config['df']['DESCRIPTION'].iloc[app.config['RandomNo']])
    # send source name field to app
    sourceName = app.config['df']['SOURCE'].iloc[app.config['RandomNo']]
        
    if debugging: 
        print("Shuffled to new webcam, random No.: ",app.config['RandomNo'])
        print("Location: ",webcamLocationDesc)
        print("New URL: ", url_string)
        print("check str: ", webcamLocationDesc)
    
    return jsonify({'Webcam_local_time':get_webcam_timezone_time(),'webcamLocationDesc':webcamLocationDesc,'ShuffledURL':url_string, 'VidSource':sourceName})
    
@app.route("/live/")
def UpdateTimeLoop():
    t=get_webcam_timezone_time()
    print("LIVE ",t)
    return jsonify({'Webcam_local_time':t})

@app.route("/shuffle/")
def Shuffle_webcam_locations():
    return SetDataParameters()

@app.route("/NTVCAMERA/")
def clickCenter():
    if sys.platform =='win32':
        return jsonify({'autoclicked':0})   
    
    print("try to click")
    w, h = map(int, subprocess.check_output(["xdotool", "getdisplaygeometry"]).split())
    CENTER_X, CENTER_Y = w // 2, h // 2
    subprocess.call(["xdotool","mousemove", "$CENTER_X", "$CENTER_Y", "click", "1"])
    print("Clicked!")
    
    return jsonify({'autoclicked':1})   
  
if __name__ == "__main__":
    if debugging: 
        pytz.all_timezones
    
    if sys.platform =='win32':
        webbrowser.open('http://localhost:5050')
    
    app.run(debug=debugging, port=5050)
    
    # TODO: make the PI turn off during working hours (when I am not usually home)
    # LocalTZ = ptztz('America/Los_Angeles')
    # LOCALTIME=datetime.now(tz=LocalTZ)