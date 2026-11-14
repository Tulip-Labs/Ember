@echo off
setlocal
title Ember 3.0 - Install
echo ============================================
echo   Ember 3.0 - one-time permanent install
echo ============================================
echo.
echo This will:
echo   1. Stop and remove the Ember currently installed
echo   2. Install Ember 3.0 in its place
echo   3. Set Ember 3.0 as your permanent Windows shell
echo      (your hidden apps and theme are kept)
echo.

set "SRC=%~dp0Ember.exe"
set "DEST=%LOCALAPPDATA%\Ember"

if not exist "%SRC%" (
  echo ERROR: Ember.exe was not found next to this file.
  echo Keep INSTALAR.bat and Ember.exe together in the same folder.
  pause
  exit /b 1
)

echo Stopping the old Ember if it is running...
taskkill /IM Ember.exe /F >nul 2>&1
timeout /t 1 /nobreak >nul

echo Removing the old installed copy...
rmdir /S /Q "%DEST%" >nul 2>&1

echo Installing Ember 3.0...
mkdir "%DEST%" >nul 2>&1
copy /Y "%SRC%" "%DEST%\Ember.exe" >nul
if not exist "%DEST%\Ember.exe" (
  echo ERROR: the copy failed. Ember was NOT installed.
  pause
  exit /b 1
)

echo Setting Ember 3.0 as your Windows shell...
reg add "HKCU\Software\Microsoft\Windows NT\CurrentVersion\Winlogon" /v Shell /t REG_SZ /d "%DEST%\Ember.exe" /F >nul
if errorlevel 1 (
  echo ERROR: could not set the shell. Ember was NOT made permanent.
  pause
  exit /b 1
)

echo.
echo Verifying...
reg query "HKCU\Software\Microsoft\Windows NT\CurrentVersion\Winlogon" /v Shell
echo.
echo Done. Ember 3.0 is now your permanent shell.
echo (Safety nets: if Ember fails to start 3 times in a row it restores
echo  Explorer by itself, and RESTAURAR-EXPLORER.bat undoes this install.)
echo.
choice /C YN /M "Restart now so the new shell takes over"
if errorlevel 2 goto :eof
shutdown /r /t 0
