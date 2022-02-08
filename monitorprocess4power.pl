# TODO: Missing timestamp at start of log messages
# TODO: Output from iambusy is only shown when the command returns, so no idea
#       when it is waiting until
# TODO: Make iambusy and suspendme into some sort of API with paramenters equivalent to the command
#       line arguments.

# 07 Feb 2022 port of MonitorProcess4Power.cmd to perl in anticipation of dos command prompt
#    removal which, it appears, is misinformation - command prompt is not being removed, only
#    access via the context menu and right-click start menu. Nevertheless having 
#    MonitorProcess4Power as a Perl script should make it easier to update
#    Trouble is there are quite a number of dos commands which are relied on...
use strict;
use FindBin;           # This should find the location of this script
use lib $FindBin::Bin . "/lib"; # This indicates to look for modules in the lib directory in script location

use FALC::SCULog;      # This should find the FALC\SCULog.pm file

use Date::Calc qw(Today_and_Now Delta_DHMS);
use Win32::API;
use Win32::Console;


my $CONSOLE=Win32::Console->new;
my $LOG = FALC::SCULog->new();

# Set env.var. defaults
#if "%UTLDIR%" == "" set UTLDIR=C:\Development\utils
#if "%CMDUTLDIR%" == "" set CMDUTLDIR=%UTLDIR%\cmdutils
#if "%JSUTLDIR%" == "" set JSUTLDIR=%UTLDIR%\jsutils
#if "%PLUTLDIR%" == "" set PLUTLDIR=%UTLDIR%\perlutils

my $UTLDIR = $ENV{UTLDIR};
if($UTLDIR eq "")
{
   $UTLDIR="C:\\Development\\utils";
}
my $PLUTLDIR = $ENV{PLUTLDIR};
if($PLUTLDIR eq "")
{
   $PLUTLDIR = $UTLDIR . "\\perlutils";
}

# set external commands: maybe these can be called in a 'native' Perl way?
# NB when perl isn't specfified the command runs but the arguments are not present (forking Perl!)
my $busycmd = "\"$PLUTLDIR\\iambusy.pl\"";        # 'perl "%PLUTLDIR%\iambusy.pl"';
my $sleepcmd= "\"$PLUTLDIR\\suspendme.pl\""; # 'perl "%PLUTLDIR%\suspendme.pl"';
my $MP4P="NOTRUNNING";
my $allowed=0;

my $runtask="";
my $tasklist;


# Is MonitorProcess4Power already running
# NB 10th token relies on the memory usage containing a comma!
#for /F "tokens=10* delims=," %%i in ('tasklist /fi "WINDOWTITLE eq ProcessMonitor4Power" /NH /V /FO CSV') do set MP4P=%%i
#if %MP4P%=="ProcessMonitor4Power" goto :END
$LOG->info( "Checking for alreaady running MonitorProcess4Power\n");

$tasklist = qx (tasklist /fi "WINDOWTITLE eq ProcessMonitor4Power" /NH /V /FO CSV);
$LOG->debug( "LOG->info: Output from tasklist:\n" . $tasklist);

if( ($runtask) = ($tasklist =~ m/(ProcessMonitor4Power)/))
{
   $LOG->info( "$runtask already running: exiting\n");
   exit;
}

settitle("ProcessMonitor4Power");

#:MonitorLoop

my $vdub=0; # "NOTRUNNING";

#rem WARNING: Running a batch file after setting TITLE can result in the batch file name
#rem being appended to the TITLE. Seems that wildcard can be specified though!!
#
#rem Relies on there being 10 columns with the last being the window title. The window title
#rem is only displayed if the /V option is set. Appears that multiple consecutive spaces are
#rem treated as one delimiter. NB If the process is not running then vdub ends up being set
#rem to "criteria." because an unavailable INFO message is displayed containing 10 words. No
#rem way to disable the message and keep the window title column! NB It might be possible to use
#rem the "LIST" format which displays each bit of information on a separate line, ie.
#rem    Image Name:   cmd.exe
#rem    PID:          6232
#rem    Session Name: Console
#rem    Session#:     1
#rem    Mem Usage:    3,404 K
#rem    Status:       Running
#rem    User Name:    Chris-PC\Chris
#rem    CPU Time:     0:00:00
#rem    Window Title: VideoConversionInProgress
#rem This would quite different processing but might be more reliable...

#for /F "tokens=10*" %%i in ('tasklist /fi "WINDOWTITLE eq ScheduledShutdownPending*" /NH /V') do set vdub=%%i
#rem echo vdub = %vdub%
#if "%vdub%"=="ScheduledShutdownPending" goto vidconisrunning
do
{
   $vdub = 0;
   $tasklist = qx (tasklist /fi "WINDOWTITLE eq ScheduledShutdownPending*" /NH /V);
   if( ($runtask) = ($tasklist =~ m/(ScheduledShutdownPending)/))
   {
      $LOG->debug( "$runtask is running: PREVENT sleep\n");
      $vdub = 1;
   }
   if($vdub !=1)
   {
      #for /F "tokens=10*" %%i in ('tasklist /fi "WINDOWTITLE eq VideoConversionInProgress*" /NH /V') do set vdub=%%i
      #rem echo vdub = %vdub%
      #if "%vdub%"=="VideoConversionInProgress" goto vidconisrunning
      #echo No VideoConversionInProgress detected - checking for video conversion processes
      
      $tasklist = qx (tasklist /fi "WINDOWTITLE eq VideoConversionInProgress*" /NH /V);
      if( ($runtask) = ($tasklist =~ m/(VideoConversionInProgress)/))
      {
         $LOG->debug( "$runtask is running: PREVENT sleep\n");
         $vdub = 1;
      }
   }

   if($vdub !=1)
   {
      #for /F "tokens=10*" %%i in ('tasklist /fi "WINDOWTITLE eq nosleep*" /NH /V') do set vdub=%%i
      #rem echo vdub = %vdub%
      #if "%vdub%"=="nosleep" goto vidconisrunning
      #echo No nosleep detected - checking for video conversion processes

      $tasklist = qx (tasklist /fi "WINDOWTITLE eq nosleep*" /NH /V);
      if( ($runtask) = ($tasklist =~ m/(nosleep)/))
      {
         $LOG->debug( "$runtask is running: PREVENT sleep\n");
         $vdub = 1;
      }
   }

   if($vdub !=1)
   {
      #rem Handbrake (for iTunes - uses 100% CPU and still machine goes to sleep!)
      #for /F %%i in ('tasklist /fi "IMAGENAME eq HandBrakeCLI.exe" /NH') do set vdub=%%i
      #if "%vdub%"=="HandBrakeCLI.exe" goto vdubisrunning

      $tasklist = qx (tasklist /fi "IMAGENAME eq HandBrakeCLI.exe" /NH);
      if( ($runtask) = ($tasklist =~ m/(HandBrakeCLI\.exe)/))
      {
         $LOG->debug( "$runtask is running: PREVENT sleep\n");
         $vdub = 1;
      }
   }



   if($vdub !=1)
   {
      #for /F %%i in ('tasklist /fi "IMAGENAME eq HandBrake.exe" /NH') do set vdub=%%i
      #if "%vdub%"=="HandBrake.exe" goto vdubisrunning

      $tasklist = qx (tasklist /fi "IMAGENAME eq HandBrake.exe" /NH);
      if( ($runtask) = ($tasklist =~ m/(HandBrake\.exe)/))
      {
         $LOG->debug( "$runtask is running: PREVENT sleep\n");
         $vdub = 1;
      }
   }

   if($vdub !=1)
   {
      #for /F %%i in ('tasklist /fi "IMAGENAME eq mp4box.exe" /NH') do set vdub=%%i
      #if "%vdub%"=="mp4box.exe" goto vdubisrunning

      $tasklist = qx (tasklist /fi "IMAGENAME eq mp4box.exe" /NH);
      if( ($runtask) = ($tasklist =~ m/(mp4box\.exe)/))
      {
         $LOG->debug( "$runtask is running: PREVENT sleep\n");
         $vdub = 1;
      }
   }


   if($vdub !=1)
   {
      #for /F %%i in ('tasklist /fi "IMAGENAME eq ABCore.exe" /nh') do set vdub=%%i
      #if not "%vdub%"=="INFO:" goto vdubisrunning

      $tasklist = qx (tasklist /fi "IMAGENAME eq ABCore.exe" /nh);
      if( ($runtask) = ($tasklist =~ m/(ABCore\.exe)/))
      {
         $LOG->debug( "$runtask is running: PREVENT sleep\n");
         $vdub = 1;
      }
   }

   # Can't use Perl as indicator that sleep should be prevent 
   # because Perl is requried for this script which should be running all the time
   #if($vdub !=1)
   #{
   #   #for /F %%i in ('tasklist /fi "IMAGENAME eq perl.exe" /NH') do set vdub=%%i
   #   #if "%vdub%"=="perl.exe" goto vdubisrunning
   # 
   #    $tasklist = qx ('tasklist /fi "IMAGENAME eq perl.exe" /NH');
   #    if($tasklist =~ m/mp4box\.exe/)
   #    {
   #       print "perl.exe is running: PREVENT sleep\n";
   #       $vdub = 1;
   #    }
   # }


   if($vdub !=1)
   {
      #for /F %%i in ('tasklist /fi "WINDOWTITLE EQ 01 Cnccpf" /NH') do set vdub=%%i
      #if not "%vdub%"=="INFO:" goto vdubisrunning

      $tasklist = qx (tasklist /fi "WINDOWTITLE EQ 01 Cnccpf" /NH);
      if( ($runtask) = ($tasklist =~ m/(Cnccpf)/))
      {
         $LOG->debug( "$runtask is running: PREVENT sleep\n");
         $vdub = 1;
      }
   }

   if($vdub !=1)
   {
      #for /F %%i in ('tasklist /fi "WINDOWTITLE EQ 00 Prjxncut" /NH') do set vdub=%%i
      #if not "%vdub%"=="INFO:" goto vdubisrunning

      $tasklist = qx (tasklist /fi "WINDOWTITLE EQ 01 Prjxncut" /NH);
      if( ($runtask) = ($tasklist =~ m/(Prjxncut)/))
      {
         $LOG->debug( "$runtask is running: PREVENT sleep\n");
         $vdub = 1;
      }
   }


   if($vdub == 0)
   {
      # set /A allowed+=1
      # echo %DATE% %TIME% Power saving should be ALLOWED (%allowed%)
      
      $allowed += 1;
      $LOG->info("Power saving should be ALLOWED ($allowed)\n");
      if($allowed >= 4)
      {
         $allowed = 0;
         $tasklist = qx (tasklist /nh);
         $LOG->info("Running tasks:\n" . $tasklist);
         $LOG->info("Forcing sleep... nightynite");
         #$tasklist = qx ($sleepcmd);
         system($sleepcmd);
         if($? != 0)
         {
            $LOG->warn("Command failed: $sleepcmd");
         }
         $LOG->info("\nFinished sleeping\n");
      }
   }
   else
   {
      $LOG->info("Long running process detected: $runtask\n");
      $LOG->info("Power saving should be PREVENTED\n");
      $allowed = 0;
   }
   #$tasklist = qx ($busycmd -s 5);
   system(($busycmd, "-s", "5"));
   if($? != 0)
   {
      $LOG->warn("Command failed: $busycmd");
   }   
}while($vdub < 2);


###############################################################
###############################################################
####                    #######################################
#### End Main program   #######################################
####                    #######################################
###############################################################
###############################################################


sub settitle
{
my $title = shift;
$CONSOLE->Title($title);
}




