# 24 Apr 2020 fixe iambusy parameter order
# 19 Mar 2022 uses file locking to prevent multiple instances since I came
#    across two instance running recently-it does take a while to retrieve the 
#    initial tasklist so I guess the two within 4 or 5 seconds of each together. File
#    locking, which appears to work for Windows, is much faster
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
use Date::Calc qw(Today_and_Now Delta_DHMS);  # Install on strwberry with cpanm Date::Calc
use Fcntl qw !LOCK_EX LOCK_NB!;   # file lock to prevent multiple instances
#use File::HomeDir;

my $LOG = FALC::SCULog->new();
 
$LOG->info( "Checking for alreaady running MonitorProcess4Power\n");
#flock DATA, LOCK_EX|LOCK_NB or die "Another instance is already running-exiting\n";
# Lock on the __DATA_ section (at the end of the file) seems to prevent Perl
# from even running the script. Consequently the log message and the 'die' message
# do not even appear if another instance is already running.
# Can fix this by using a separate lock file but where to put the lock file since it 
# needs to be common to all the 'users' which may run this script. 
# Most likely place is in the Public user directory but how to find the Public directory location??
# File::HomeDir->users_desktop('Public'); sounds promising but is not implemented!!!
# Could use my_home and go up and down to Public with a relative path but that just
# sucks since the public folder could get moved elsewhere.
# Will rely on the PUBLIC env.var instead....

my $docs    = $ENV{'PUBLIC'};
$docs = $docs . "\\Documents\\";
$LOG->debug( "Public directory is: $docs\n");
open my $file, ">", $docs . "ProcessMonitor4Power.lock" or die $!; 
if ( ! flock($file, LOCK_EX|LOCK_NB) )
{
   $LOG->info( "Another instance is already running: exiting\n");
   exit(0);
}
$LOG->info( "Looks like it's just us!\n");
settitle("ProcessMonitor4Power");

my $MP4P="NOTRUNNING";
my $allowed=0;

my $runtask="";
my $tasklist;

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

   iambusy(5, -1, 0);
   
}while($vdub < 2);


###############################################################
###############################################################
####                    #######################################
#### End Main program   #######################################
####                    #######################################
###############################################################
###############################################################
__DATA__






