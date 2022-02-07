# 07 Feb 2022 port of MonitorProcess4Power.cmd to perl in anticipation of dos command prompt
#    removal which, it appears, is misinformation - command prompt is not being removed, only
#    access via the context menu and right-click start menu. Nevertheless having 
#    MonitorProcess4Power as a Perl script should make it easier to update
#    Trouble is there are quite a number of dos commands which are relied on...
use Date::Calc qw(Today_and_Now Delta_DHMS);
use Win32::API;
use Win32::Console;


my $CONSOLE=Win32::Console->new;
my $LOG = SCULog->new();

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
my $busycmd = "perl \"$PLUTLDIR\\iambusy.pl\"";        # 'perl "%PLUTLDIR%\iambusy.pl"';
my $sleepcmd= "\"$PLUTLDIR\\suspendme.pl\""; # 'perl "%PLUTLDIR%\suspendme.pl"';
my $MP4P="NOTRUNNING";
my $allowed=0;

my $runtask="";
my $tasklist;


# Is MonitorProcess4Power already running
# NB 10th token relies on the memory usage containing a comma!
#for /F "tokens=10* delims=," %%i in ('tasklist /fi "WINDOWTITLE eq ProcessMonitor4Power" /NH /V /FO CSV') do set MP4P=%%i
#if %MP4P%=="ProcessMonitor4Power" goto :END
$LOG->debug( "LOG->info: Calling tasklist\n");

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
         $tasklist = qx ($sleepcmd);
         $LOG->info("Output from $sleepcmd: $tasklist");
         $LOG->info("\nFinished sleeping\n");
      }
   }
   else
   {
      $LOG->info("Long running process detected: $runtask\n");
      $LOG->info("Power saving should be PREVENTED\n");
      $allowed = 0;
   }
   $tasklist = qx ($busycmd -s 5);
   $LOG->info("Output from $busycmd:\n$tasklist\n");
}while($vdub < 2);


# :vdubisrunning
# echo Long running process detected: %vdub%
# :vidconisrunning
# set allowed=0
# echo %DATE% %TIME% Power saving should be PREVENTED
# %busycmd% -s 5
# goto MonitorLoop
# 
# rem goto Sleep
# rem 
# :Sleep
# if %allowed% GEQ 4 (
# set allowed=0
# rem This to check for processes for which sleep should have been prevented
# tasklist /nh
# echo Forcing sleep... nightynite
# %sleepcmd%
# )
# rem Sleep for 5 minutes
# rem This seems to work with Windows 7
# rem timeout /T 300 /NOBREAK >nul
# %busycmd% -s 5 -idle
# 
# goto MonitorLoop
# 
# :END
# 

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




package SCULog;
{
# 03 Nov 2014 Updated with stacktrace output for errors.
use Devel::StackTrace;

# This seems to work OK in the class. To use the constans to set the level
# the syntax is like '$log->level(SCULog->LOG_DEBUG);'
use constant { LOG_SILENT => -1, LOG_ALWAYS => 10, LOG_FATAL => 20, LOG_ERROR => 30, LOG_WARN=>40 ,LOG_INFO => 50, LOG_DEBUG => 60, LOG_TRACE => 70};

# This does appear to be shared between the instances of the class
# but initializing it at the class level does not work. It is the same for simple
# scalar values initialized here. The init must be done in the constructor (ie. new())
# but it only needs to be done once.
my %LOG_LABELS;
my $logfh = -1;

sub new
{
   # Init the class variables, this only has to be done once
   # but it doesn't work when done at the class level.
   if(!%LOG_LABELS)
   {
      # print "Initialising LOG_LABELS: " . %LOG_LABELS . "\n";
      %LOG_LABELS = ( LOG_ALWAYS, "ALWAYS", LOG_FATAL, "FATAL", LOG_ERROR, "ERROR", LOG_WARN, "WARNING", LOG_INFO, "INFO", LOG_DEBUG, "DEBUG", LOG_TRACE, "TRACE");
   }
   # print "LOG_LABELS initialised to: " . %LOG_LABELS . "\n";
   # The class is supplied as the first parameter
   # Not sure what it is used for!!!
   my $class = shift;
   my $self = {};  # this becomes the "object", in this case an empty anonymous hash
   bless $self;    # this associates the "object" with the class

   $self->level(LOG_INFO);
   $self->logfile(-1);
   $self->{"_LOG_LABELS"} = \%LOG_LABELS;
   return $self;
}

sub logmsg
{
my $self = shift;
my $keyword = shift;
my $fmt = shift;
my $msg = "";
my $level;
my $logfh = $self->logfile;

   no warnings "numeric";

   # Does this work? Can I just use Level()? How do I know if the first parameter is
   # "self" or a level value??
   $level = $self->level;

   my %labels = %{$self->{"_LOG_LABELS"}};

   if(int($keyword) <= $level)
   {
      my $output;
      $msg = sprintf($fmt, @_);
      if(($keyword == LOG_ERROR) || ($keyword == LOG_FATAL))
      {
         # NB. The frame subroutine value refers to the subroutine being called (an SCULog method normally) at line X in package Y.
         # Therefore need frame(X-1)->subroutine to know who is doing the calling.
         my $trace = Devel::StackTrace->new(ignore_class => 'SCULog');
         my $frame;

         # Get the package and line info
         $frame = $trace->next_frame;
         my $calledfunc = $frame->subroutine;  # Method being called at line X
         my $callerline = $frame->line;
         my $callerpackage=$frame->package;

         # Get the function doing the calling at line X
         $frame = $trace->next_frame;
         my $callerfunc = $frame->subroutine;
         $output = sprintf("%-8s: %s(%04d): %s",($LOG_LABELS{$keyword}//$keyword), $callerfunc, $callerline, $msg);
      }
      else
      {
         $output = sprintf("%-8s: %s",($labels{$keyword}//$keyword), $msg);
      }
      $!=1;
      print $output;
      if($logfh != -1)
      {
         print $logfh $output
      }
   }
   return $msg;
}

sub islevel
{
my $self = shift;
my $testlevel = shift;
my $curlevel = $self->level;

   return (int($testlevel) <= $curlevel);
}

sub level
{
my $self = shift;

   if(@_)
   {
      $self->{level} = shift;
   }
   return $self->{level};
}

sub logfile
{
my $self = shift;

   if(@_)
   {
      $self->{logfile} = shift;
   }
   return $self->{logfile};
}


sub always
{
my $self = shift;
   $self->logmsg(LOG_ALWAYS, @_);
}

sub fatal
{
my $self = shift;
   $self->logmsg(LOG_FATAL, @_);
}

sub error
{
my $self = shift;
   $self->logmsg(LOG_ERROR, @_);
}

sub warn
{
my $self = shift;
   $self->logmsg(LOG_WARN, @_);
}

sub info
{
my $self = shift;
   $self->logmsg(LOG_INFO, @_);
}

sub debug
{
my $self = shift;
   $self->logmsg(LOG_DEBUG, @_);
}

sub trace
{
my $self = shift;
   $self->logmsg(LOG_TRACE, @_);
}


} # End package SCULog