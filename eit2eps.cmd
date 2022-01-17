@echo off
if "%SCRIPTDIR%" == "" set SCRIPTDIR=N:\Documents\git\ScriptGit\iTunesUtilities
set NASMP4DIR=N:\Videos\mp4
set ARTCMD=java -jar "%SCRIPTDIR%\LogoMaker.jar" -i "%NASMP4DIR%\background.png" -b 160 -l 40 -r 110 -t "#PROGNAME#" -o "#PROGDIR#\folder.jpg"

set file=%1
set dir=%~dp1
echo Processing %dir%
pushd %dir%
for %%i in (*.eit) do call :doit "%%i"
goto :EOF

:doit
perl "%SCRIPTDIR%\eit2eps.pl" -d "%NASMP4DIR%" -n "%NASMP4DIR%\ZZ new 2 check" %*
if exist done\ move %1 done
goto :EOF
