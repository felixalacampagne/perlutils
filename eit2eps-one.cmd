@echo off
set SCRIPTDIR=N:\Documents\git\ScriptGit\iTunesUtilities
set NASMP4DIR=N:\Videos\mp4
set ARTCMD=java -jar "%SCRIPTDIR%\LogoMaker.jar" -i "%NASMP4DIR%\background.png" -b 160 -l 40 -r 110 -t "#PROGNAME#" -o "#PROGDIR#\folder.jpg"
perl "%SCRIPTDIR%\eit2eps.pl" -d "%NASMP4DIR%" %*
pause