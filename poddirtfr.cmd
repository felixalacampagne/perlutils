@echo off
rem TODO set path to point to perl
set SCUDIR=C:\Program Files\SmallCat Utilities
set PERLDIR=C:\PERL\BIN
PATH=%SCUDIR%;%PERLDIR%;%PATH%
rem Get the directory to copy to.
set DESTDIR=N:\Recordings
set SRCDIR=D:\Documents\Recordings
set DONEDIR=D:\Documents\Recordings
echo PODDIRTFR START: %DATE% %TIME%: Download "%1"

call :CHKDEST "%DESTDIR%"


pushd "%SRCDIR%"

for /R Juice %%i in (*.mp3) do call :ONEFILE "%%~i"
popd
echo PODDIRTFR END: %DATE% %TIME%
goto :EOF


:ONEFILE
perl "%SCUDIR%\podtag.pl" "%~1" "%DESTDIR%" "%DONEDIR%

rem Might still want to set the gain but don't know the name of the output file
rem "%SCUDIR%\mp3gain" /g %GAIN% /z /c /p /q "%destfile%"
goto :EOF

:CHKDEST
rem Try to ensure the network drive is alive
dir /O:N "%DESTDIR%"
goto :EOF