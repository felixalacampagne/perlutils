@echo off
rem Sleep prevention command

set busycmd=perl "C:\Program Files\Utils\iambusy.pl"
set interval=5
set nosleepmins=60
if NOT "%1"=="" set nosleepmins=%1



echo %DATE% %TIME% Pretending to be busy
%busycmd% -s %interval% -t %nosleepmins%


:END
