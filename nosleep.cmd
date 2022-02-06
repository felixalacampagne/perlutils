@echo off
rem Sleep prevention command
if "%UTLDIR%" == "" set UTLDIR=C:\Development\utils
set busycmd=perl "%UTLDIR%\iambusy.pl"
set interval=5
set nosleepmins=60
if NOT "%1"=="" set nosleepmins=%1



echo %DATE% %TIME% Pretending to be busy
%busycmd% -s %interval% -t %nosleepmins%


:END
