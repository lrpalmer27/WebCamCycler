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
# pull location descr based on random No
app.config['webcamLocationDesc']=app.config['df']['DESCRIPTION'].iloc[app.config['RandomNo']]
# URL of location from random No.
app.config['URL']= app.config['df']['URL'].iloc[app.config['RandomNo']]

# global df, RandomNo, webcamLocationDesc, URL
# # read df
# df= pd.read_csv('./WebcamURLs.csv')
# # make random number
# RandomNo= random.randint(0,df.shape[0]-1)
# # pull location descr based on random No
# webcamLocationDesc=df['DESCRIPTION'].iloc[RandomNo]
# # URL of location from random No.
# # URL= df['URL'].iloc[RandomNo]
# app.config['URL']= df['URL'].iloc[RandomNo]

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
    # get new random number
    app.config['RandomNo'] = random.randint(0,app.config['df'].shape[0]-1)
    # update URL
    app.config['URL']= app.config['df']['URL'].iloc[app.config['RandomNo']]
    url_string=str(app.config['URL'])
    # Update locaton description
    app.config['webcamLocationDesc']=app.config['df']['DESCRIPTION'].iloc[app.config['RandomNo']]
    webcamLocationDesc=str(app.config['webcamLocationDesc'])
    #re-render html with new URL
    # renderHTML()
    if debugging: 
        print("Shuffled to new webcam, random No.: ",app.config['RandomNo'])
        print("Location: ",app.config['webcamLocationDesc'])
        print("New URL: ", app.config['URL'])
        print("check str: ", webcamLocationDesc)
    
    return jsonify({'Webcam_local_time':get_webcam_timezone_time(),'webcamLocationDesc':webcamLocationDesc,'ShuffledURL':url_string})
    
@app.route("/live/")
def UpdateTimeLoop():
    return jsonify({'Webcam_local_time': get_webcam_timezone_time()})

@app.route("/shuffle/")
def Shuffle_webcam_locations():
    return SetDataParameters()
  
if __name__ == "__main__":
    debugging = 1
    app.run(debug=debugging, port=5000)
    # print(pytz.all_timezones)

    # LocalTZ = ptztz('America/Los_Angeles')
    # LOCALTIME=datetime.now(tz=LocalTZ)