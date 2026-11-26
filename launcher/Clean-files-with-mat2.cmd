@echo off
if "%~1"=="" (
  echo Drag one or more files onto this file to remove their metadata.
  echo Cleaned copies are saved next to the originals as NAME.cleaned.EXT
  pause
  exit /b 1
)
:loop
if "%~1"=="" goto done
echo Cleaning: %~1
call "%~dp0mat2.cmd" "%~1"
shift
goto loop
:done
echo.
echo Finished. Your original files were not changed.
pause
