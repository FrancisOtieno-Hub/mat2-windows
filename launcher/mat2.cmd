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
"%HERE%bin\gdk-pixbuf-query-loaders.exe" > "%GDK_PIXBUF_MODULE_FILE%" 2>nul
"%HERE%bin\python.exe" "%HERE%app\mat2.py" %*
exit /b %errorlevel%
