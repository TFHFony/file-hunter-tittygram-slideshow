@echo off
cd /d "%~dp0"
python tools\makeadf.py
if errorlevel 1 (
    echo BUILD FAILED
    exit /b 1
)
echo Build OK: out\slideshow.adf
