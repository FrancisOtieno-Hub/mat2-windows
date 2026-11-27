@echo off
setlocal
set "HERE=%~dp0"
set "PYTHONHOME=%HERE%"
set "PYTHONUTF8=1"
set "PATH=%HERE%bin;%PATH%"
"%HERE%bin\python.exe" "%HERE%app\check_office.py" %*
exit /b %errorlevel%
