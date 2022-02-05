SETLOCAL ENABLEDELAYEDEXPANSION
TITLE iTunes to K: %1
call :INIT
call :setts
set log=D:\Music\mp3\it2k_music_%ts%.log
set PERLLIB=%UTLDIR%\cpaperllib
date /T >"%log%"
perl "%UTLDIR%\it2gmp.pl" "D:\Music\mp3\06 playlists\%1.xml" "K:\Music">"%log%" 2>&1

goto :EOF

:setts
for /F "tokens=1,2,3 delims=/" %%i in ('date /t') do call :setdate %%i %%j %%k
for /F "tokens=1,2 delims=:" %%i in ('time /t') do call :settime %%i %%j
rem set ts=%YEAR%%MONTH%%DAY%%HOUR%%MINUTE%
set ts=%YEAR%%MONTH%%DAY%
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

:INIT

if "%UTLDIR%" == "" set UTLDIR=C:\Development\utils
if "%LOGDIR%" == "" (
set LOGDIR=%USERPROFILE%\Desktop\logs
rem echo Creating !LOGDIR!
mkdir !LOGDIR! >nul 2>&1
)   
if "%LOGFILE%" == "" (
set LOGFILE=%LOGDIR%\%PS1CMD%.log
echo Logging to !LOGFILE!
)
goto :EOF