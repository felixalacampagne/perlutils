# WARNING: Windows 11 Terminal has broken the 'TITLE' test for running processes. 
# To use MP4P the command prompt windows must be opened by the 'Console Host' as tasklist
# does not report windowtitles of prompts running in a Terminal host unless it is the title
# of the window running the tasklist command.

# 06 May 2025 refactor
# 05 May 2025 added loading of additional config from file located with the lockfile.
# 04 May 2025 use a single call to tasklist with LIST format and scan the output for matching
#             window titles and image name.
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
 
use strict;
use FindBin;           # This should find the location of this script
use lib $FindBin::Bin . "/lib"; # This indicates to look for modules in the lib directory in script location
use File::Path qw( make_path );
use FALC::SCULog;
use FALC::SCUWin;
use Date::Calc qw(Today_and_Now Delta_DHMS);  # Install on strwberry with cpanm Date::Calc
use Fcntl qw !LOCK_EX LOCK_NB!;   # file lock to prevent multiple instances
use JSON;
use Try::Tiny; # for try...catch
use Getopt::Std;
use Term::ReadKey;

my $LOG = FALC::SCULog->new();

my $VERSION = "MonitorProcess4Power v3.2 250511";

my @titles = ("VideoConversionInProgress", 
              "nosleep", 
              "ScheduledShutdownPending", 
              "ProcMon4PowerNoSleep");
              
my @images = ("HandBrakeCLI.exe",
              "HandBrake.exe");
my $MP4PKEEPAWAKE = $ENV{'MP4PKEEPAWAKE'};

my %opts;
   getopts('gd', \%opts);
   if( $opts{"d"} == 1)
   {
      $LOG->level(FALC::SCULog->LOG_DEBUG);
   }
   
   if($MP4PKEEPAWAKE)
   {
      push(@titles, $MP4PKEEPAWAKE);
   }

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
my $cfgdir    = $ENV{'PUBLIC'};
   $cfgdir = $cfgdir . "\\mp4pwr";
   if( ! -d $cfgdir)
   {
      $LOG->debug( "Config directory is: $cfgdir\n");
      make_path $cfgdir or print "IGNORING: Failed to create $cfgdir: $!\n";
   }

my $xtracfgfile = $cfgdir . "\\ProcessMonitor4Power.json";
   if( $opts{"g"} == 1)
   {
      # Generate an example additional custom config file
      genDefaultConfig($xtracfgfile . ".default");
      exit(0);
   }
  
my $lockfh = mustBeSingleton($cfgdir); # Must keep the lock handle otherwise the file is closed and the lock released.
   
   $LOG->info( "Looks like it's just us!\n");

   settitle("ProcessMonitor4Power");

   loadConfig($xtracfgfile);
   $LOG->debug("Window titles: @titles\n");
   $LOG->debug("Image names: @images\n");

my $filters = '/fi "IMAGENAME ne svchost.exe" ';
   $filters = $filters . '/fi "IMAGENAME ne msedgewebview2.exe" ';
   $filters = $filters . '/fi "IMAGENAME ne GoogleDriveFS.exe" ';
my $tasklistcmd = "tasklist /FO LIST /V " . $filters;
   $LOG->info("tasklist cmd:\n$tasklistcmd\n");
 
my $allowed = 0;

   do
   {
      my $tasklist = qx{$tasklistcmd};
      $LOG->debug("tasklist result:\n$tasklist\n");
           
      my $processbusy = "";
      
      $processbusy = scanForLineMatch($tasklist, "Window Title", \@titles);
      
      if( $processbusy eq "")
      {
         $processbusy = scanForLineMatch($tasklist, "Image Name", \@images);
      }
      
      if($processbusy eq "")
      {
         $allowed += 1;
         $LOG->info("Power saving should be ALLOWED ($allowed)\n");
         if($allowed >= 4)
         {
            $allowed = 0;
            $tasklist = qx (tasklist /nh $filters);
            $LOG->info("Running tasks:\n" . $tasklist);
            sleepWarning();
            my $abort = pause4key("Press SPACEBAR to abort sleep...");
            $LOG->info("Key pressed: [$abort]\n");
            if($abort ne " ")
            {
               $LOG->info("Forcing sleep... nightynite\n");
      
               suspendme(1);  # Use -1 for immediate when abort option is added above
               $LOG->info("Finished sleeping\n");
            }
         }
      }
      else
      {
         $LOG->info("Long running process detected: $processbusy\n");
         $LOG->info("Power saving should be PREVENTED\n");
         $allowed = 0;
      }
   
      iambusy(5, -1, 0);
      
   } while(1);

###############################################################
###############################################################
####                    #######################################
#### End Main program   #######################################
####                    #######################################
###############################################################
###############################################################
sub pause4key
{
my $msg = shift;
   $|=1;
   print $msg;
   ReadMode 'cbreak';

   my $key = ReadKey(120);
   ReadMode 'normal';
   print "\n";
   return $key;
}

# This requires that the powershell script 'notify.ps1' is available
# It might be possible to do this entirely from the command line
# to avoid the dependency on this script.
sub sleepWarning
{
my $pwrshelcmd = '"powershell.exe" -noLogo -ExecutionPolicy unrestricted -command ';
my $desc = " 'WARNING: System is about to go to sleep'";
my $title = " 'MonitorProcess4Power'";
my $iconfile = "'C:\\Windows\\System32\\notepad.exe'";
my $notify_ps1= '';

$notify_ps1 = $notify_ps1 . '$description = ' . $desc . ';';
$notify_ps1 = $notify_ps1 . '$title = ' . $title . ';';
$notify_ps1 = $notify_ps1 . 'Add-Type -AssemblyName System.Windows.Forms;';
$notify_ps1 = $notify_ps1 . '$notifyIcon = New-Object System.Windows.Forms.NotifyIcon;';
# %SystemRoot%\System32\SHELL32.dll 7x4 =28
# $Icon = [System.IconExtractor]::Extract($SourceEXEFilePath, $IconIndexNo, $true)
$notify_ps1 = $notify_ps1 . '$notifyIcon.Icon = [System.Drawing.Icon]::ExtractAssociatedIcon(' . $iconfile . ');';
$notify_ps1 = $notify_ps1 . '$notifyIcon.BalloonTipText = $description;';
$notify_ps1 = $notify_ps1 . '$notifyIcon.BalloonTipTitle = $title;';
$notify_ps1 = $notify_ps1 . '$notifyIcon.BalloonTipIcon = [System.Windows.Forms.ToolTipIcon]::Warning;';
$notify_ps1 = $notify_ps1 . '$notifyIcon.Visible = $true;';
$notify_ps1 = $notify_ps1 . '$notifyIcon.ShowBalloonTip(15000);';


$pwrshelcmd = $pwrshelcmd . '"' . $notify_ps1 . '"';
$LOG->debug("pwoershell commend:\n$pwrshelcmd\n");
my $res = qx ($pwrshelcmd );

}

# tasklist    - task list in LIST format to be scanned
# prefix      - label at start of the line containing the pattern to scan for, eg. 'Window Title', 'Image Name'
# patternsref - reference to array of patterns to scan for
#
# returns     - matching process details, empty string if none found
sub scanForLineMatch
{
my ($tasklist, $prefix, $patternsref) = @_;
my @patterns = @$patternsref;
my $processbusy = "";
   
   foreach my $pattern (@patterns) 
   {
      # Must treat the patterns as literals so dot "." and star "*" are not given special meaning 
      my $qpattern = qr/\Q$pattern\E/;
      my $linepattern = qr/$prefix:\s*($qpattern.*)$/m;
      my $runtask;
      if( ($runtask) = ($tasklist =~ m/$linepattern/))
      {
         $LOG->debug("Match for $linepattern: $runtask\n");
         $processbusy = $runtask;
         last;
      }
      else
      {
         $LOG->debug("NO match for $linepattern\n");
      }
   }
   return $processbusy;
}

sub savetext
{
my ($path, $data) = @_;

   unlink "$path";
   if(open(my $output, ">", $path) )
   {
      binmode $output, ":unix:encoding(UTF-8)";
      print $output $data;
      close($output);
   }
   else
   {
      warn "Failed to save file: " . $path . " : " . $! . "\n";
   }
}

sub loadtext 
{
   my ($file) = @_;
   
   my $fulfile = File::Spec->rel2abs($file);
   my $file_content = "";
   if( -f $fulfile )
   {
      open my $fh, '<', $fulfile or die "Can't open file $fulfile: $!";
        
      binmode $fh, ":encoding(utf-8)";   
      
      
      read $fh, $file_content, -s $fh;
   }
   return $file_content
}

sub genDefaultConfig
{
my ($file) = @_;
my %bootstrapconfig = ();
   
   $bootstrapconfig{'WindowTitles'}  = \@titles;
   $bootstrapconfig{'ImageNames'}  = \@images;
   my $json = to_json(\%bootstrapconfig, {utf8 => 1, pretty => 1, canonical => 1});
   
   my $fulfile = File::Spec->rel2abs($file);
      
   savetext($fulfile, $json);     
}

sub mustBeSingleton
{
my ($configdir) = @_;  
my $lockfile = $configdir . "\\ProcessMonitor4Power.lock";
   open my $file, ">", $lockfile or die "Failed to open $lockfile: $!"; 
   if ( ! flock($file, LOCK_EX|LOCK_NB) )
   {
      $LOG->info( "Another instance is already running: exiting\n");
      exit(0);
   } 
   return $file;
}
# Config is json file containing two arrays, eg.
#    {
#       "ImageNames" : [
#          "image.exe"
#       ],
#       "WindowTitles" : [
#          "title"   ]
#    }
sub loadConfig
{
my ($file) = @_;  

   my $json = loadtext($file);
   if( $json ne "")
   {
      try
      {   
      my $mapref = decode_json($json) or return;
      my %config = %{$mapref};
      my @xtras;

         @xtras = @{$config{'WindowTitles'}};
         push(@titles, @xtras);
         
         @xtras = @{$config{'ImageNames'}};
         push(@images, @xtras);
      }
      catch
      {
         $LOG->info("loadConfig failed: $_\n");
      }
   }
}

###############################################################
###############################################################
####                    #######################################
#### End functions      #######################################
####                    #######################################
###############################################################
###############################################################

# The notify.ps1 script

## WARNING! MUST have Notifications enabled: Settings -> System -> Notifications
## WARNING! Notifications can be blocked by do not disturb settings...
#
#$description = $args[0];
#$title = $args[1];
## Add System.Windows.Forms assembly
#Add-Type -AssemblyName System.Windows.Forms
#
## Create a NotifyIcon object
#$notifyIcon = New-Object System.Windows.Forms.NotifyIcon
#
## Set the icon
#$notifyIcon.Icon = [System.Drawing.Icon]::ExtractAssociatedIcon("C:\Windows\System32\notepad.exe")
#
## Set the notification text
#$notifyIcon.BalloonTipText = $description
#
## Set the notification title
#$notifyIcon.BalloonTipTitle = $title
#
## Set the icon type (optional)
#$notifyIcon.BalloonTipIcon = [System.Windows.Forms.ToolTipIcon]::Warning
#
## Set the notification to visible
#$notifyIcon.Visible = $true
#
## Show the notification (duration in milliseconds)
#$notifyIcon.ShowBalloonTip(15000)
__DATA__




