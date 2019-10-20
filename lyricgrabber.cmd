@echo off
if "%UTLDIR%" == "" set UTLDIR=C:\Development\utils
perl "%UTLDIR%\lyricgrabber.pl" %*
rem pause
