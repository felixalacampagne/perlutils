@echo off
set SCUDIR=C:\Program Files\SmallCat Utilities
set PERLDIR=C:\PERL\BIN
set ITLIB=D:\Music\iTunes\iTunes Music Library.xml
set DESTDIR=N:\Recordings_iT

PATH=%SCUDIR%;%PERLDIR%;%PATH%
set logfile=%USERPROFILE%\desktop\poddirtfrit.log
echo Logging to "%logfile%"
call :dologged >>"%logfile%" 2>&1
goto :EOF


:dologged
rem Get the directory to copy to.
echo PODDIRTFRIT START: %DATE% %TIME%:

call :CHKDEST "%DESTDIR%"

perl "%SCUDIR%\podfromit.pl" -i "%ITLIB%" -d "%DESTDIR%"
echo PODDIRTFR END: %DATE% %TIME%
goto :EOF

:CHKDEST
rem Try to ensure the network drive is alive
dir /O:N "%DESTDIR%"
goto :EOF