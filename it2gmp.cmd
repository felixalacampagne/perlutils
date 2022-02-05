set USBDRV=%1
if "%USBDRV%" == "" set USBDRV=K
set PLAYLIST=N:\Music\playlists\music.xml

if "%UTLDIR%" == "" set UTLDIR=C:\Development\utils
set FFMPEG=%UTLDIR%\ffmpeg\ffmpeg
set USBDIR=%USBDRV%\Music

call :setts
set log=%PLAYLIST%_it2usb_%ts%.log
date /T >"%log%"

rem debug cmd line
rem perl it2gmp.pl "N:\Music\playlists\music.xml" "k:\Music"
perl "%UTLDIR%\it2gmp.pl" "%PLAYLIST%" "%USBDIR%">"%log%" 2>&1

goto :EOF

:setts
for /F "tokens=1,2,3 delims=/" %%i in ('date /t') do call :setdate %%i %%j %%k
for /F "tokens=1,2 delims=:" %%i in ('time /t') do call :settime %%i %%j
set ts=%YEAR%%MONTH%%DAY%%HOUR%%MINUTE%
rem set ts=%YEAR%%MONTH%%DAY%
goto :EOF

:settime
set HOUR=%1
set MINUTE=%2
goto :EOF

:setdate
set DAY=%1
set MONTH=%2
set YEAR=%3
goto :EOF