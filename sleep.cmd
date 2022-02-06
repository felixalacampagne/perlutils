@echo off
if "%UTLDIR%" == "" set UTLDIR=C:\Development\utils
perl "%UTLDIR%\suspendme.pl" %*
