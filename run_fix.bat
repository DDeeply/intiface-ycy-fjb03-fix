@echo off
chcp 65001 >nul
title YCY-FJB-03 Intiface Central Fix
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Fix-YCY-FJB03.ps1"
if %errorlevel% neq 0 (
    echo.
    echo Script exited with error code: %errorlevel%
    pause
)
