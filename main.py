from flask import Flask, render_template, request, jsonify
from datetime import timedelta, datetime, timezone
import pytz
from pytz import timezone as ptztz
import pandas as pd
import random
import math

app = Flask(__name__)

# app.config['expiration_time'] = 

@app.route("/<location>")
def renderHTML(location):
    readData() #initialize by reading the csv to fill in the df var
    Shuffle_webcam_locations() #initialize with a starting shuffle
    return render_template('overlay.html',Location=app.config['webcamLocationDesc'])

def get_webcam_timezone_time():
    WEBCAM_TZ = app.config['df']['PYTZ TIMEZONE'].iloc[app.config['RandomNo']]
    WebCamTimeZone_time = datetime.now(tz=ptztz(WEBCAM_TZ))
    return jsonify({'Webcam_local_time': WebCamTimeZone_time})

def Shuffle_webcam_locations():
    # get new random number
    app.config['RandomNo']= random.randint(0,app.config['df'].shape[0]-1)
    # update URL
    app.config['URL']= app.config['df']['URL'].iloc[app.config['RandomNo']]
    # Update locaton description
    app.config['webcamLocationDesc']=app.config['df']['DESCRIPTION'].iloc[app.config['RandomNo']]
    # call to update webcam local timezone variable
    get_webcam_timezone_time()
    return 

def readData(): 
    app.config['df']= pd.read_csv('./WebcamURLs.csv')

if __name__ == "__main__":   
    debugging = 1
    app.run(debug=debugging, port=5000)
    # print(pytz.all_timezones)

    LocalTZ = ptztz('America/Los_Angeles')
    LOCALTIME=datetime.now(tz=LocalTZ)
    
    # # read csv
    # app.config['df']= pd.read_csv('./WebcamURLs.csv')
        
    # # make random number between 0-max size of df.
    # Shuffle_webcam_locations()
    # get_webcam_locaton()
    
    # print('testing')
    # print(app.config['webcamLocationDesc'])
    
    # #get URL of the location we are going to pull data for
    

    
    
    
    
        
        
    
    
    
    