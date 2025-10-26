from flask import Flask, render_template, request, jsonify
from datetime import timedelta, datetime, timezone 
import pytz
from pytz import timezone as ptztz
import pandas as pd
import random
import webbrowser
import sys 

# basics from: https://github.com/CoffeeKeyboardYouTube/TimerWebAppFlask/blob/main/templates/home.html
#              https://www.youtube.com/watch?v=7FwXKxqfuko

debugging = 0
firstPass = 1

app = Flask(__name__)
app.config['TEMPLATES_AUTO_RELOAD'] = True

# # read df
WebCamList='./WebcamURLs.csv'
if debugging: 
    WebCamList ='./WebcamURLs - PC ONLY.csv'
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

def SetDataParameters(FirstPass=0):
    # # read df
    app.config['df']= pd.read_csv(WebCamList)
    # get new random number
    app.config['RandomNo'] = random.randint(0,app.config['df'].shape[0]-1)
    
    # first pass NTV webcam to make sure autoplay starts as intended.
    if FirstPass: 
        app.config['RandomNo'] = 0
       
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
    
    TimeDataList=get_webcam_timezone_time(1)
    
    return jsonify({'Webcam_local_time':get_webcam_timezone_time(),'webcamLocationDesc':webcamLocationDesc,'ShuffledURL':url_string})
    
@app.route("/live/")
def UpdateTimeLoop():
    return jsonify({'Webcam_local_time': get_webcam_timezone_time()})

@app.route("/shuffle/")
def Shuffle_webcam_locations():
    return SetDataParameters()

@app.route("/contentLoaded/")
def ContentLoaded():
    return SetDataParameters(FirstPass=1)
  
if __name__ == "__main__":
    if debugging: 
        pytz.all_timezones
    
    if sys.platform =='win32':
        webbrowser.open('http://localhost:5050')
    
    app.run(debug=debugging, port=5050)
    
    # TODO: make the PI turn off during working hours (when I am not usually home)
    # LocalTZ = ptztz('America/Los_Angeles')
    # LOCALTIME=datetime.now(tz=LocalTZ)
    
    # TODO: make it so this gets displayed full screen on pi.