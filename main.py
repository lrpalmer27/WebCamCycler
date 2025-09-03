from flask import Flask, render_template

app = Flask(__name__)

@app.route("/")
def hello_world():
    return "<p>Hello, World!</p>"

@app.route("/user/<username>")
def profile(username):
    return f'Hello, {username}'

@app.route("/test")
def renderHTML():
    return render_template('overlay.html')