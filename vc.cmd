@echo off
if /i "%~1"=="setup" goto setup
if /i "%~1"=="template" goto setup
if /i "%~1"=="update" goto setup
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0vc.ps1" %*
exit /b %errorlevel%
:setup
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0vc_setup.ps1" %*
exit /b %errorlevel%
