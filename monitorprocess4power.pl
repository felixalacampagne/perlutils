# 07 Feb 2022 port of MonitorProcess4Power.cmd to perl in anticipation of dos command prompt
#    removal which, it appears, is misinformation - command prompt is not being removed, only
#    access via the context menu and right-click start menu. Nevertheless having 
#    MonitorProcess4Power as a Perl script should make it easier to update

# TODO Check whether a single tasklist call can be made to check for all target processes
use strict;
use FindBin;           # This should find the location of this script
use lib $FindBin::Bin . "/lib"; # This indicates to look for modules in the lib directory in script location

use FALC::SCULog;
use FALC::SCUWin;
use Date::Calc qw(Today_and_Now Delta_DHMS);

my $LOG = FALC::SCULog->new();

# These are no longer required with the use of Perl modules
# but they might be needed in the future, somewhere. They should
# probably go into their own module :-)
# Set env.var. defaults
#if "%UTLDIR%" == "" set UTLDIR=C:\Development\utils
#if "%CMDUTLDIR%" == "" set CMDUTLDIR=%UTLDIR%\cmdutils
#if "%JSUTLDIR%" == "" set JSUTLDIR=%UTLDIR%\jsutils
#if "%PLUTLDIR%" == "" set PLUTLDIR=%UTLDIR%\perlutils

#my $UTLDIR = $ENV{UTLDIR};
#if($UTLDIR eq "")
#{
#   $UTLDIR="C:\\Development\\utils";
#}
#my $PLUTLDIR = $ENV{PLUTLDIR};
#if($PLUTLDIR eq "")
#{
#   $PLUTLDIR = $UTLDIR . "\\perlutils";
#}

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
      $tasklist = qx (tasklist /fi "WINDOWTITLE eq VideoConversionInProgress*" /NH /V);
      if( ($runtask) = ($tasklist =~ m/(VideoConversionInProgress)/))
      {
         $LOG->debug( "$runtask is running: PREVENT sleep\n");
         $vdub = 1;
      }
   }

   if($vdub !=1)
   {
      $tasklist = qx (tasklist /fi "WINDOWTITLE eq nosleep*" /NH /V);
      if( ($runtask) = ($tasklist =~ m/(nosleep)/))
      {
         $LOG->debug( "$runtask is running: PREVENT sleep\n");
         $vdub = 1;
      }
   }

   if($vdub !=1)
   {
      $tasklist = qx (tasklist /fi "IMAGENAME eq HandBrakeCLI.exe" /NH);
      if( ($runtask) = ($tasklist =~ m/(HandBrakeCLI\.exe)/))
      {
         $LOG->debug( "$runtask is running: PREVENT sleep\n");
         $vdub = 1;
      }
   }

   if($vdub !=1)
   {
      $tasklist = qx (tasklist /fi "IMAGENAME eq HandBrake.exe" /NH);
      if( ($runtask) = ($tasklist =~ m/(HandBrake\.exe)/))
      {
         $LOG->debug( "$runtask is running: PREVENT sleep\n");
         $vdub = 1;
      }
   }

   if($vdub !=1)
   {
      $tasklist = qx (tasklist /fi "IMAGENAME eq mp4box.exe" /NH);
      if( ($runtask) = ($tasklist =~ m/(mp4box\.exe)/))
      {
         $LOG->debug( "$runtask is running: PREVENT sleep\n");
         $vdub = 1;
      }
   }

   if($vdub !=1)
   {
      $tasklist = qx (tasklist /fi "IMAGENAME eq ABCore.exe" /nh);
      if( ($runtask) = ($tasklist =~ m/(ABCore\.exe)/))
      {
         $LOG->debug( "$runtask is running: PREVENT sleep\n");
         $vdub = 1;
      }
   }

   if($vdub !=1)
   {
      $tasklist = qx (tasklist /fi "WINDOWTITLE EQ 01 Cnccpf" /NH);
      if( ($runtask) = ($tasklist =~ m/(Cnccpf)/))
      {
         $LOG->debug( "$runtask is running: PREVENT sleep\n");
         $vdub = 1;
      }
   }

   if($vdub !=1)
   {
      $tasklist = qx (tasklist /fi "WINDOWTITLE EQ 01 Prjxncut" /NH);
      if( ($runtask) = ($tasklist =~ m/(Prjxncut)/))
      {
         $LOG->debug( "$runtask is running: PREVENT sleep\n");
         $vdub = 1;
      }
   }

   if($vdub == 0)
   {
      $allowed += 1;
      $LOG->info("Power saving should be ALLOWED ($allowed)\n");
      if($allowed >= 4)
      {
         $allowed = 0;
         $tasklist = qx (tasklist /nh);
         $LOG->info("Running tasks:\n" . $tasklist);
         $LOG->info("Forcing sleep... nightynite\n");

         suspendme(-1);
         $LOG->info("Finished sleeping\n");
      }
   }
   else
   {
      $LOG->info("Long running process detected: $runtask\n");
      $LOG->info("Power saving should be PREVENTED\n");
      $allowed = 0;
   }

   iambusy(5, 0, -1);
   
}while($vdub < 2);


###############################################################
###############################################################
####                    #######################################
#### End Main program   #######################################
####                    #######################################
###############################################################
###############################################################







