@echo off
if "%UTLDIR%" == "" set UTLDIR=C:\Development\utils
if "%PLUTLDIR%" == "" set PLUTLDIR=C:\Development\perlutils
perl "%PLUTLDIR%\suspendme.pl" %*
