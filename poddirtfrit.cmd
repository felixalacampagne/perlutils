@echo off
if "%UTLDIR%" == "" set UTLDIR=C:\Development\utils
if "%CMDUTLDIR%" == "" set CMDUTLDIR=%UTLDIR%\cmdutils
if "%PERLUTLDIR%" == "" set PERLUTLDIR=%UTLDIR%\perlutils

set SCUDIR=C:\Development\utils
set ITLIB=C:\Development\Music\iTunes\iTunes Library.xml
set DESTDIR=N:\Recordings_iT_M

PATH=%SCUDIR%;%PATH%
set logfile=%USERPROFILE%\desktop\logs\poddirtfrit.log
echo Logging to "%logfile%"
call :dologged >>"%logfile%" 2>&1
goto :EOF


:dologged
rem Get the directory to copy to.
echo PODDIRTFRIT START: %DATE% %TIME%:

call :CHKDEST "%DESTDIR%"

perl "%PERLUTLDIR%\podfromit.pl" -i "%ITLIB%" -d "%DESTDIR%" -v
echo PODDIRTFR END: %DATE% %TIME%
goto :EOF

:CHKDEST
rem Try to ensure the network drive is alive
dir /O:N "%DESTDIR%"
goto :EOF