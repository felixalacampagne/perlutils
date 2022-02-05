@echo off
rem Requires the filename format to be;
rem                  PodcastName_ReleaseDate.mp3
rem                  where 
rem                  ReleaseDate - YYYYMMDDHHMM
rem Known podcast names ares;
rem     The Archers Omnibus
rem     Desert Island Discs
rem     From Our Own Correspondent
rem     Kermode and Mayo's Film Review
rem     Boston Calling
rem     Click

set SCUDIR=C:\Development\utils
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
echo perl "%SCUDIR%\podfromit.pl" -i "%ITLIB%" -d "%DESTDIR%" -t "%o%"
perl "%SCUDIR%\podfromit.pl" -i "%ITLIB%" -d "%DESTDIR%" -t "%o%"
echo PODDIRTFR END: %DATE% %TIME%
goto :EOF

:CHKDEST
rem Try to ensure the network drive is alive
dir /O:N "%DESTDIR%"
goto :EOF