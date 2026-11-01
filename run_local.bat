@echo off
setlocal
cd /d "%~dp0"

set "PYTHON=%~dp0.venv\Scripts\python.exe"
if not exist "%PYTHON%" set "PYTHON=python"

if "%PYTHON%"=="python" (
    where python >nul 2>nul
    if errorlevel 1 (
        echo Python was not found. Install Python 3 and try again.
        pause
        exit /b 1
    )
)

set "VIEWER_URL=http://127.0.0.1:5050/"
set "HEALTH_URL=http://127.0.0.1:5050/health/"
set "DEV_URL=http://127.0.0.1:5050/dev/revision/"

curl.exe --silent --fail "%HEALTH_URL%" >nul 2>nul
if errorlevel 1 (
    echo Starting Webcam Cycler...
    set "WEBCAM_CYCLER_OPEN_BROWSER=0"
    set "WEBCAM_CYCLER_DEV=1"
    start "Webcam Cycler server" /min "%PYTHON%" "%~dp0main.py"

    for /l %%N in (1,1,30) do (
        timeout /t 1 /nobreak >nul
        curl.exe --silent --fail "%HEALTH_URL%" >nul 2>nul
        if not errorlevel 1 goto server_ready
    )

    echo The server did not start. Check the minimized server window for errors.
    pause
    exit /b 1
) else (
    curl.exe --silent --fail "%DEV_URL%" >nul 2>nul
    if errorlevel 1 (
        echo An older server is running without development reload.
        echo Close its server window once, then run this file again.
        pause
        exit /b 1
    )
    echo Development server is already running.
)

:server_ready
echo Webcam Cycler is running at %VIEWER_URL%
echo Open this address in your browser. Close the minimized "Webcam Cycler server" window to stop it.
