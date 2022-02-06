if "%UTLDIR%" == "" set UTLDIR=C:\Development\utils
if "%CMDUTLDIR%" == "" set CMDUTLDIR=%UTLDIR%\cmdutils
if "%PERLUTLDIR%" == "" set PERLUTLDIR=%UTLDIR%\perlutils

perl "%PERLUTLDIR%\stripproginf.pl"

rem pause
