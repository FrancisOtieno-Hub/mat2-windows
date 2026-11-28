@echo off
setlocal
set "HERE=%~dp0"
set "PYTHONHOME=%HERE%"
set "PYTHONPATH=%HERE%app"
set "PYTHONUTF8=1"
set "PATH=%HERE%bin;%HERE%exiftool;%PATH%"
set "GI_TYPELIB_PATH=%HERE%lib\girepository-1.0"
set "GDK_PIXBUF_MODULEDIR=%HERE%lib\gdk-pixbuf-2.0\2.10.0\loaders"
set "GDK_PIXBUF_MODULE_FILE=%TEMP%\mat2-windows-loaders.cache"
set "FONTCONFIG_PATH=%HERE%etc\fonts"
set "FONTCONFIG_FILE=%HERE%etc\fonts\fonts.conf"
set "XDG_DATA_DIRS=%HERE%share"
set "TCL_LIBRARY=%HERE%lib\tcl8.6"
set "TK_LIBRARY=%HERE%lib\tk8.6"
"%HERE%bin\gdk-pixbuf-query-loaders.exe" > "%GDK_PIXBUF_MODULE_FILE%" 2>nul

rem Start-mat2-window.cmd --check : tests that Tcl/Tk loads, shows no window (used by the build)
if /i "%~1"=="--check" goto check

rem Normal start: no console window if pythonw.exe is present.
rem Files dropped on this .cmd are added to the window's list.
rem (No parentheses blocks here: file names such as "report (1).docx" would break them.)
if exist "%HERE%bin\pythonw.exe" goto gui
start "" "%HERE%bin\python.exe" "%HERE%app\mat2_gui.py" %*
exit /b 0

:gui
start "" "%HERE%bin\pythonw.exe" "%HERE%app\mat2_gui.py" %*
exit /b 0

:check
"%HERE%bin\python.exe" "%HERE%app\mat2_gui.py" --check
exit /b %errorlevel%
