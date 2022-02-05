@echo off
if "%UTLDIR%" == "" set UTLDIR=C:\Development\utils
set FFMPEG=%UTLDIR%\ffmpeg\ffmpeg
perl "%UTLDIR%\flacmd5.pl" %*
