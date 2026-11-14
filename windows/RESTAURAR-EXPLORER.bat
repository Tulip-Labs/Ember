@echo off
title Ember - Restore Explorer
echo Restoring Windows Explorer as your shell...
reg add "HKCU\Software\Microsoft\Windows NT\CurrentVersion\Winlogon" /v Shell /t REG_SZ /d "explorer.exe" /F >nul
if errorlevel 1 (
  echo Something went wrong. Explorer was NOT restored.
  pause
  exit /b 1
)
echo Done. Restart to get the normal Windows desktop back.
pause
