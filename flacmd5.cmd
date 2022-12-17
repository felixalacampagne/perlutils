@echo off
if "%UTLDIR%" == "" set UTLDIR=C:\Development\utils
if "%CMDUTLDIR%" == "" set CMDUTLDIR=%UTLDIR%\cmdutils
if "%PERLUTLDIR%" == "" set PERLUTLDIR=%UTLDIR%\perlutils

set FFMPEG=%UTLDIR%\ffmpeg\bin\ffmpeg
perl "%PERLUTLDIR%\flacmd5.pl" %*
