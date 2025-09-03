from flask import Flask, render_template, request
from datetime import timedelta, datetime, timezone
import pytz
from pytz import timezone as ptztz
import pandas as pd
import random
import math

app = Flask(__name__)

@app.route("/")
def hello_world():
    return "<p>Hello, World!</p>"

@app.route("/user/<username>")
def profile(username):
    return f'Hello, {username}'

@app.route("/<location>")
def renderHTML(location):
    return render_template('overlay.html',Location={location})



if __name__ == "__main__":  
    debugging = 0
    # print(pytz.all_timezones)

    LocalTZ = ptztz('America/Los_Angeles')
    LOCALTIME=datetime.now(tz=LocalTZ)
    
    # read csv
    df = pd.read_csv('./WebcamURLs.csv')
        
    # Hide this function in a local time of day checker function ---------------------------------- 
    RandomNo=random.randint(0,df.shape[0]-1) #random integer between 0 and number of rows of dataframe   
    LOCATION = df['DESCRIPTION'].iloc[RandomNo]
    URL= df['URL'].iloc[RandomNo]
    WEBCAM_TZ = df['PYTZ TIMEZONE'].iloc[RandomNo]
    WebCamTimeZone = datetime.now(tz=ptztz(WEBCAM_TZ))
    
    if debugging: 
        print(LOCALTIME)
        print(df)
        print(df.iloc[[RandomNo]])
        print('Webcam timezone: ', WebCamTimeZone)
    
    
    
        
        
    
    
    
    