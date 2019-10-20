@echo off
if "%UTLDIR%" == "" set UTLDIR=C:\Development\utils
perl "%UTLDIR%\perlutils\azlyricgrabber.pl" %*
rem pause
