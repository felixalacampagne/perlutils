@echo off


set SCUDIR=.
set PERLDIR=C:\Perl64\BIN
set ITLIB=%USERPROFILE%\Music\iTunes\iTunes Music Library.xml
set DESTDIR=N:\Recordings_iT_M

PATH=%SCUDIR%;%PERLDIR%;%PATH%
rem set logfile=%USERPROFILE%\desktop\poddirtfrit.log
rem echo Logging to "%logfile%"
rem call :dologged >>"%logfile%" 2>&1
call :dologged "%~1"
goto :EOF


:dologged

set o=%~1
perl "%SCUDIR%\podfromit.pl" -f "%o%"
echo PODDIRTFR END: %DATE% %TIME%
goto :EOF

:CHKDEST
rem Try to ensure the network drive is alive
dir /O:N "%DESTDIR%"
goto :EOF