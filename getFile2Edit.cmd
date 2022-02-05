@echo off
rem 27-May-2015 A windows update has f-cked up the automatic sleep. Tried putting a forced sleep
rem in here but that interferes with video conversion which might still be in progress. MonitorProcess4Power
rem is now updated to force sleep after a while. getFile2Edit needs to integrate with the video
rem conversion so it too must use MonitorProcess4Power - this means we need the in progress title

if "%UTLDIR%" == "" set UTLDIR=C:\Development\utils

start "MonitorProcess4Power" /D "%UTLDIR%" /MIN cmd /c "%UTLDIR%\MonitorProcess4Power.cmd"

TITLE VideoConversionInProgress

set hdeditdir=C:\TVVideos\HD
set sdeditdir=E:\TVVideos\SD\Capture
set vuuprecdir=X:\movie
set dbrecdir=Z:\movie
call :doitLogged >>%USERPROFILE%\desktop\logs\getFile2Edit.log 2>&1
goto :EOF

:doitLogged
@echo off
@echo GetFile2Edit START: %DATE% %TIME%:
@rem Usual problem - bloody windows doesn't connect to remote drives after sleep.

ping vuultimo
net use x: \\VUULTIMO\Harddisk
dir "%vuuprecdir%\*.ts"
perl "%UTLDIR%\getFiles2Edit.pl" "%vuuprecdir%" "%hdeditdir%"
perl "%UTLDIR%\getFiles2Edit.pl" -s "%vuuprecdir%" "%sdeditdir%"

ping dm7025
net use z: \\dm7025\harddisk
dir "%dbrecdir%\*.ts"
perl "%UTLDIR%\getFiles2Edit.pl" -a "%dbrecdir%" "%sdeditdir%"
@echo GetFile2Edit END: %DATE% %TIME%:
@goto :EOF

