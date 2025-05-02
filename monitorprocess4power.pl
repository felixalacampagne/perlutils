# WARNING: Windows 11 Terminal has broken the 'TITLE' test for running processes. 
# To use MP4P the command prompt windows must be opened by the 'Console Host' as tasklist
# does not report windowtitles of prompts running in a Terminal host unless it is the title
# of the window running the tasklist command.

# 02 May 2025 Added the custom window title. Not very useful as it requires all
#             starters of MP4P to have the env var set to be sure the instance actually
#             running knows about the same value as the user of the variable. As MP4P can
#             be started directly this means the env.var. must be a system setting which is not
#             terribly useful so I added a new hardcoded no sleep title.
# 30-Mar-2023 So now creating the (already existing) directory in 'C:\Users\Public' now
#             fails (as predicted) for no discerable reason. For now the lock on the
#             file seems to still work ok... until that too fails, of course
# 23-Feb-2023 Tried running for first time on system freshly installed with strawberry Perl
#             and get 'No such file or directory' error for the lock file. Since
#             the command is supposed to create the file the error presumably refers to
#             the path however a cd to 'C:\Users\Public\Documents' works just fine.
#             but trying to echo some text to a file fails. No way on this particular system 
#             to write into Public documents from the command line but creating a new dir and writing
#             to it works fine, so that's what will be done from now on.... until that fails as well.
# 24 Apr 2020 fix iambusy parameter order
# 19 Mar 2022 uses file locking to prevent multiple instances since I came
#    across two instance running recently-it does take a while to retrieve the 
#    initial tasklist so I guess the two within 4 or 5 seconds of each together. File
#    locking, which appears to work for Windows, is much faster
# 07 Feb 2022 port of MonitorProcess4Power.cmd to perl in anticipation of dos command prompt
#    removal which, it appears, is misinformation - command prompt is not being removed, only
#    access via the context menu and right-click start menu. Nevertheless having 
#    MonitorProcess4Power as a Perl script should make it easier to update
 
# A single tasklist call cannot be made to check for all target processes, 
# multiple /FI options are ANDed. Instead the complete process list could be 
# captured and each line of the output matched against a list of titles or image names.
# Would probably make sense to use the LIST output format if changing to this method.
# Probably only necessary to search the whole output for 'Window Title: $title'
# or 'Image Name:   $image' which should be pretty quick.
# That will be for MP4P 3.0!
# 
use strict;
use FindBin;           # This should find the location of this script
use lib $FindBin::Bin . "/lib"; # This indicates to look for modules in the lib directory in script location
use File::Path qw( make_path );
use FALC::SCULog;
use FALC::SCUWin;
use Date::Calc qw(Today_and_Now Delta_DHMS);  # Install on strwberry with cpanm Date::Calc
use Fcntl qw !LOCK_EX LOCK_NB!;   # file lock to prevent multiple instances
my $LOG = FALC::SCULog->new();

my $VERSION = "MonitorProcess4Power v2.1 250502" ;

$LOG->info($VERSION . "\n");
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
$docs = $docs . "\\mp4pwr";
my $lockfile = $docs . "\\ProcessMonitor4Power.lock";
$LOG->debug( "Public directory is: $docs\n");
make_path $docs or print "IGNORING: Failed to create $docs: $!\n";
open my $file, ">", $lockfile or die "Failed to open $lockfile: $!"; 
if ( ! flock($file, LOCK_EX|LOCK_NB) )
{
   $LOG->info( "Another instance is already running: exiting\n");
   exit(0);
}
$LOG->info( "Looks like it's just us!\n");
# $LOG->level(FALC::SCULog->LOG_DEBUG);

settitle("ProcessMonitor4Power");

my $MP4PKEEPAWAKE = $ENV{'MP4PKEEPAWAKE'};
my $MP4P="NOTRUNNING";
my $allowed=0;

my $runtask="";
my $tasklist;

my $vdub=0; # "NOTRUNNING";

   if($MP4PKEEPAWAKE)
   {
      $LOG->debug("Checking for custom TITLE: $MP4PKEEPAWAKE\n");
   }

#rem WARNING: Running a batch file after setting TITLE can result in the batch file name
#rem being appended to the TITLE. Seems that wildcard can be specified though!!
#
# NB It might be possible to use
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
   
   # TODO: Make the titles into an array. The custom value can be simply added to the array if it is present
   if($MP4PKEEPAWAKE)
   {
      if($vdub != 1)
      {
         $tasklist = qx{tasklist /fi "WINDOWTITLE eq $MP4PKEEPAWAKE*" /NH /V};
         $LOG->debug( "Title: $MP4PKEEPAWAKE: Tasklist: $tasklist\n");
         if( ($runtask) = ($tasklist =~ m/($MP4PKEEPAWAKE)/))
         {
            $LOG->debug( "Title:$MP4PKEEPAWAKE: $runtask is running: PREVENT sleep\n");
            $vdub = 1;
         }
      } 
   } 
   
   if($vdub != 1)
   {  
      my $windowtitle = "ProcMon4PowerNoSleep";
      $tasklist = qx (tasklist /fi "WINDOWTITLE eq $windowtitle*" /NH /V);
      $LOG->debug( "Title: $windowtitle: Tasklist: $tasklist\n");
      if( ($runtask) = ($tasklist =~ m/($windowtitle)/))
      {
         $LOG->debug( "$runtask is running: PREVENT sleep\n");
         $vdub = 1;
      }
   }
      
   if($vdub != 1)
   {   
      $tasklist = qx (tasklist /fi "WINDOWTITLE eq ScheduledShutdownPending*" /NH /V);
      if( ($runtask) = ($tasklist =~ m/(ScheduledShutdownPending)/))
      {
         $LOG->debug( "$runtask is running: PREVENT sleep\n");
         $vdub = 1;
      }
   }
    
   if($vdub != 1)
   {
      $tasklist = qx (tasklist /fi "WINDOWTITLE eq VideoConversionInProgress*" /NH /V);
      if( ($runtask) = ($tasklist =~ m/(VideoConversionInProgress)/))
      {
         $LOG->debug( "$runtask is running: PREVENT sleep\n");
         $vdub = 1;
      }
   }

   if($vdub != 1)
   {
      $tasklist = qx (tasklist /fi "WINDOWTITLE eq nosleep*" /NH /V);
      if( ($runtask) = ($tasklist =~ m/(nosleep)/))
      {
         $LOG->debug( "$runtask is running: PREVENT sleep\n");
         $vdub = 1;
      }
   }

   if($vdub != 1)
   {
      $tasklist = qx (tasklist /fi "WINDOWTITLE EQ 01 Cnccpf" /NH);
      if( ($runtask) = ($tasklist =~ m/(Cnccpf)/))
      {
         $LOG->debug( "$runtask is running: PREVENT sleep\n");
         $vdub = 1;
      }
   }

   if($vdub != 1)
   {
      $tasklist = qx (tasklist /fi "WINDOWTITLE EQ 01 Prjxncut" /NH);
      if( ($runtask) = ($tasklist =~ m/(Prjxncut)/))
      {
         $LOG->debug( "$runtask is running: PREVENT sleep\n");
         $vdub = 1;
      }
   }

   if($vdub != 1)
   {
      $tasklist = qx (tasklist /fi "IMAGENAME eq HandBrakeCLI.exe" /NH);
      if( ($runtask) = ($tasklist =~ m/(HandBrakeCLI\.exe)/))
      {
         $LOG->debug( "$runtask is running: PREVENT sleep\n");
         $vdub = 1;
      }
   }

   if($vdub != 1)
   {
      $tasklist = qx (tasklist /fi "IMAGENAME eq HandBrake.exe" /NH);
      if( ($runtask) = ($tasklist =~ m/(HandBrake\.exe)/))
      {
         $LOG->debug( "$runtask is running: PREVENT sleep\n");
         $vdub = 1;
      }
   }

   if($vdub != 1)
   {
      $tasklist = qx (tasklist /fi "IMAGENAME eq mp4box.exe" /NH);
      if( ($runtask) = ($tasklist =~ m/(mp4box\.exe)/))
      {
         $LOG->debug( "$runtask is running: PREVENT sleep\n");
         $vdub = 1;
      }
   }

   if($vdub != 1)
   {
      $tasklist = qx (tasklist /fi "IMAGENAME eq ABCore.exe" /nh);
      if( ($runtask) = ($tasklist =~ m/(ABCore\.exe)/))
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






