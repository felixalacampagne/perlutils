@echo off
rem 26-Apr-2019 Title set from perl.
rem 07-Jul-2018 The quotes and delayed expansion are for the "Florence & The Machine" fix (which wouldn't
rem be required if TITLE was set from Perl). 

if "%UTLDIR%" == "" set UTLDIR=C:\Development\utils
if "%PLUTLDIR%" == "" set PLUTLDIR=%UTLDIR%\perlutils

if not %UTLLOGDIR%x==x set TEMP=%UTLLOGDIR%

TITLE fMD5:
perl "%PLUTLDIR%\foldermd5.pl" %*
