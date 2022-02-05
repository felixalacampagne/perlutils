rem Uses multiprocess version to create 30GB of .mp3
rem files from the default playlist on V: drive 
rem for later transfer to a USB drive, etc.

set USBDRV=K:

set PLDIR=%~dp1
if "%UTLDIR%" == "" set UTLDIR=C:\Development\utils
set FFMPEG=%UTLDIR%\ffmpeg\ffmpeg
set USBDIR=%USBDRV%\Music
mkdir "%USBDIR%" 2>nul

call :setts
set log=%PLDIR%\it2gmpA_%ts%.log
date /T >"%log%"

rem debug cmd line
perl "%UTLDIR%\it2gmpA.pl" -p %1 -m "%USBDIR%" -s 20GB -j 4 >"%log%" 2>&1

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