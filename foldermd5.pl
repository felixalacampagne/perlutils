#!/usr/bin/perl
# 26 Apr 2019 Update the console title with name of directory being processed. Handy when the
#             output is directed to a log file, eg. when run from context menu.
#             Moved rest of history to the end of the file

use 5.010;  # Available since 2007, so should be safe to use this!!
use strict;
use IO::Handle;
use Data::Dumper;
use Digest::MD5;
use File::Spec;
use File::Basename;
use File::Temp qw/ tempfile tempdir /;
use Date::Calc qw(Today_and_Now Delta_DHMS);
use Cwd;
use Encode;
use Getopt::Std;
use Term::ReadKey;
use Win32::API;
use Win32::DriveInfo;  # Not installed by default: ppm install Win32-DriveInfo
use Win32::Console; 
my $CONSOLE=Win32::Console->new;

my $LOG = SCULog->new();

# Must be positioned at the start of the script before the get/inc funcs are used otherwise
# the hash is not initialised even though there is no syntax error for the
# hash itself not being declared.
my %counters =
(
   dirs => 0,
   md5dirs => 0,
   md5files => 0,
   calcmd5 => 0,
   chkmd5 => 0,
   failmd5dir => 0,
   failmd5file => 0
);

my $startdir = "";
my $vollbl = "";
my $logfh;
my $logfilename;
my %opts;
my @starttime = Today_and_Now();
my @endtime;
getopts('ckvlpr?', \%opts);

if( $opts{"?"} == 1 )
{
   HELP_MESSAGE();
}

if( $opts{"c"} == 1)
{
   SkipCalc(1);
}

if( $opts{"k"} == 1)
{
   SkipCheck(1);
}
if( $opts{"v"} == 1)
{
   $LOG->level(SCULog->LOG_DEBUG);
}

if( $opts{"l"} == 1)
{
   LogToFile(1);
}
if( $opts{"p"} == 1)
{
   PauseOnExit(1);
}
if( $opts{"r"} == 1)
{
   ForceRecalc(1);
}


# The options are removed from argv which leaves just the directory.
# This makes it possible to specify multiple directories on the command line
# which would be handy for specifying mp3, flac and alac in one script.
# Need to decide if the log files should go in each directory...
if( @ARGV > 0)
{
   $startdir = $ARGV[0];
   #
}

#print "Startdir:    " . $startdir . "\n";
#print "Skipcalc:    " . $skipcalc . "\n";
#print "Skipcheck:   " . $skipcheck . "\n";
#print "Logging:     " . $logtofile . "\n";
#print "Pauseonexit: " . $pauseonexit . "\n";
#die(0);



do
{
   if($startdir eq "")   # ie. nothing specified on command line
   {
   	$startdir = File::Spec->curdir();
   	$startdir = File::Spec->rel2abs(File::Spec->curdir());
   	
   }
   else
   {
   	$startdir = File::Spec->rel2abs($startdir);
      # It could be that an MD5 file was double-clicked on, in which case the argument
      # is the full path of the md5.   
   	# So test for folder.md5 
   	my ($filename,$directories,$suffix) = fileparse( $startdir );
   	if($filename =~ m/folder\.md5/i)
   	{
   	   # remove the filename - the check is automatic if there is a folder.md5 present
   	   $startdir = $directories;
   	   
         # In this case it is handy to have logging and pauseonexit enabled 
   	   LogToFile(1);
   	   PauseOnExit(1);
   	}
   }   
   
   
   if ( LogToFile() == 1 )
   {
      my @now = localtime();
      my $ts = sprintf("%04d%02d%02d%02d%02d", 
                           $now[5]+1900, $now[4]+1, $now[3],
                           $now[2],      $now[1]);
      my $logname = "";
      my $key = "";
      my $path = "";
      if( -d $startdir )
      {
         $key = filename2key($startdir);
         $path = $startdir;
      }
      else
      {
         my ($filename,$directories,$dummy) = fileparse( $startdir );
         $key = filename2key($filename);
         $path = $directories;
      }
      $logname = "md5_" . $ts . "_" . $key . ".log";
      $logfilename = File::Spec->catdir($path, $logname);         
      
      if(!open ($logfh, '>>', $logfilename))
      {
         $LOG->warn("Failed to open log file $logfilename: $!\n");
         $vollbl = (Win32::DriveInfo::VolumeInfo((File::Spec->splitpath($startdir))[0]))[0];

         $logname = "md5_" . $ts . "_" . $vollbl . ".log";
         $logfilename = File::Spec->catdir(File::Spec->tmpdir(), $logname);
         
         
         
         if(!open ($logfh, '>>', $logfilename))
         {
            $LOG->warn("WARN: Failed to open log file $logfilename: $!\n");
            $LOG->warn("WARN: Logging to screen only\n");
            LogToFile(0);
         }
      }
      if(LogToFile() > 0)
      {
         $LOG->info("Redirecting output to " . $logfilename . "\n");
         # Extra attempt to get the output visible in UltraEdit during the processing
         $logfh->autoflush(1); 
         # select new filehandle
         select $logfh;
         $|=1;
      }
      $|=1;
   }
   
   if ( SkipCheck() == 1 )
   {
      $LOG->info("Skip CHECK is SET\n");
   }
   if ( SkipCalc() == 1 )
   {
      $LOG->info("Skip CALC is SET\n");
   }
   
   # This bit of perl black magic is supposed to make stdout flush 
   # each line even when redirected to a file, but it doesn't seem to work inside
   # the logtofile if block and it doesn't seem to work here either when logfh is selected.
   # At least the output is actually going into the file though.
   $|=1;
   

   my $tab="  ";
   if( -d $startdir )
   {
      if($vollbl eq "")
      {
         $LOG->info("Processing directory: %s\n", $startdir);
      }
      else
      {
         $LOG->info("Processing Disk: %s directory: %s\n", $vollbl, $startdir);
      }
      $LOG->info("${tab}Started at:                 %s\n", ymdhmsString(@starttime));
      processDir($startdir);
   }
   elsif( isFileForMD5($startdir) )
   {
      $LOG->info("MD5 update: %s\n", $startdir);
      $LOG->info("${tab}Started at:                 %s\n", ymdhmsString(@starttime));
      updateFileMD5($startdir);
   }
   else
   {
      $LOG->info("Processing of $startdir not supported");
   }   
   

   @endtime = Today_and_Now();
   my @elapsed = Delta_DHMS(@starttime, @endtime); # ($days,$hours,$minutes,$seconds)
   settitle("Done!");
   $LOG->info("${tab}Finished at:                %s\n", ymdhmsString(@endtime));
   $LOG->info("${tab}Elapsed:                    %02d:%02d:%02d\n", $elapsed[1],$elapsed[2],$elapsed[3]);
   $LOG->info("${tab}Total directories:          " . getTotdirs() . "\n");
   $LOG->info("${tab}Directories requiring MD5s: " . getTotmd5dirs() . "\n");
   $LOG->info("${tab}Folder MD5s calculated:     " . getTotcalcmd5() . "\n");
   $LOG->info("${tab}Folder MD5s checked:        " . getTotchkmd5() . "\n");
   
   my $fnptr = sub{$LOG->info(@_)};
   if(getTotfailmd5dir() > 0)
   {
      # If a dir failed then there must be some files which failed
      $fnptr = sub{$LOG->warn(@_)};
   }
   &$fnptr("${tab}Failed folder MD5s:         " . getTotfailmd5dir() . "\n");
   &$fnptr("${tab}Failed file MD5s:           " . getTotfailmd5file() . "\n");
   
   # If $logfh is initialized to a known value the open command complains
   # so 'defined' seems to be the way to check whether the variable was
   # initialized.
   if ( defined $logfh )
   {
      close($logfh);
   }
   select STDOUT;
   
   shift(@ARGV); #Removes first element
   $startdir = $ARGV[0];   

}while(length $startdir > 0);

# Enable power saving here so machine can go to sleep
# while waiting for input.
setpowersaving(1);

if(PauseOnExit() == 1)
{
   if( LogToFile() == 1 )
   {
      my @log = loadfile2array($logfilename);
      print @log;
   }
   $|=1;  # Try to force a flush to user can see message
   pause4key("Press a key to exit . . . ");
}

########### End of main program
# calculate the MD5
# create the MD5 file line
# if foldermd5 not already present
#    write line to new foldermd5 file
# else
#    load file
#    if entry already present for file
#       replace entry for file
#    else
#       add entry for file
#    resort file based on filename
#    save file
# Done
# Parameter: File to md5 - must be specified as a full path
sub updateFileMD5
{
my ($fullfile) = @_;
my $foldermd5new = "";


my ($filename,$directories,$suffix) = fileparse( $fullfile );
my $md5new = calcmd5($directories, [$filename]);    # NB the [] seems to imply a reference to the anonymous array of 1...
my $foldermd5path = File::Spec->catdir($directories, "folder.md5");

   $LOG->debug("Calculated MD5:  New value: $md5new\n");

   if( -e $foldermd5path)
   {
      $LOG->debug("MD5 file already exists: $foldermd5path\n");
      my @md5s = loadfile2array(File::Spec->catdir($directories, "folder.md5"));
      my $hash;
      my $name;
   
      foreach my $md5 (@md5s)
      {
         # ae907fd31ff602bbb33bc716c072f0f5 *01 One Of These Nights.mp3
         # Split line into hash
         if ( $md5 =~ m/^([a-z0-9]*) \*(.*)$/ )
         {
            $hash = $1;
            $name = $2;
            if($name ne $filename)
            {
               $foldermd5new .= $md5;
            }
            else
            {
               $LOG->debug("File is present in folder.md5: Old value: $md5\n");
               $foldermd5new .= $md5new;
               $md5new = "";
            }
         }
      }
   }
   
   # Will be set if the folder.md5 didn't already exist OR the file wasn't present in it.
   # sort order will be lost if the folder.md5 already exists without the file
   $foldermd5new .= $md5new;
   saveutf8xfile($foldermd5path, $foldermd5new);
   incTotdirs();            
   incTotmd5dirs();
   incTotcalcmd5();
}


sub isFileForMD5
{
my ($file) = @_;
   if( $file =~ m/.*\.(mp3|m4a|m4v|mp4|flac|raw|wav)$/i )
   {
      return (0==0); # No built-in true or false!!!!
   }
   return (0==1);
}
sub ymdhmsString
{
my @starttime;

if(@_ > 0)
{
   @starttime = @_;
}
else
{
   @starttime = Today_and_Now();
}

my $nowstr = sprintf("%04d.%02d.%02d. %02d:%02d:%02d", $starttime[0],$starttime[1],$starttime[2],$starttime[3],$starttime[4],$starttime[5]);

return $nowstr;
}


sub HELP_MESSAGE()
{
   print "foldermd5 [-l] [-v] [-c] [-k] [-p] [initial scan directory]...\n";
   print "   -l Log to file. Log file is created in the\n";
   print "      initial scan directory with name md5_yyyymmddhhmm\n";
   print "   -v Verbose output\n";
   print "   -c Skip calculation: Do not calculate MD5s when the\n";
   print "      folder.md5 file is not present.\n";
   print "   -k Skip checking: Do not check the MD5s when folder.md5 is present.\n";
   print "   -p Pause on exit. Waits for a key to be pressed before terminating.\n";
   print "   -r recalculate MD5s even if a folder.md5 exists.\n";
   print "Multiple initial scan directories can be specified.\n";
   print "If no initial scan directory is specified the current directory is scanned.\n";
   print "All sub-directories below the initial scan directory are also scanned.\n";
   exit(0);
}

sub pause4key
{
my $msg = shift;
   $|=1;
   print $msg;
   ReadMode 'cbreak';

   my $key = ReadKey(120);
   ReadMode 'normal';
}

# Enables/disables the power saving power scheme
# assumes that the scheme to be configured when the
# script is not running is the "Power saver" scheme
# and the scheme for when the script is running is the
# "High performance" scheme. The Power saver should be
# configured with the desired sleep/hibernate settings etc.
# and the High performance should disable sleep/hibernate
# NB. Use 'powercfg -list' to verify the scheme GUIDs
# Param: mode - 1 power saving enabled, 0 power saving disabled
sub orig_setpowersaving
{
my $mode = shift;
my $scheme_ps="a1841308-3541-4fab-bc81-f71556f20b4a";
my $scheme_hp="8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c";
my $scheme=$scheme_ps;
my $pwrcmd;
   if($mode == 0)
   {
      $scheme = $scheme_hp;
   }
   
   $pwrcmd = sprintf("powercfg -SETACTIVE %s", $scheme);
   system($pwrcmd);
   $LOG->debug("Command '%s' return code: %i: %s\n", $pwrcmd, ($? >> 8), $!);
}

sub settitle
{
my $title = shift;
$CONSOLE->Title('fMD5: ' . $title);
}

# Param: mode - 1 idle, power saving enabled, 0 busy, prevent power saving
sub setpowersaving
{
my $mode = shift;
   if($mode == 0)
   {   
      wakeywakey();
   }
}

sub wakeywakey
{
   # Want to use EXECUTION_STATE WINAPI SetThreadExecutionState(_In_  EXECUTION_STATE esFlags);
   my $ES_SYSTEM_REQUIRED = 1;
   my $ES_DISPLAY_REQUIRED = 2;
   my $ES_USER_PRESENT = 4;
   my $ES_CONTINUOUS = 0x80000000;
   
   my $SetThreadExecutionState = Win32::API::More->new('kernel32', 'SetThreadExecutionState', 'N', 'N');
   
   if (defined $SetThreadExecutionState) 
   {
      # This should just reset the idle timer back to zero
      #print "Calling SetThreadExecutionState with 'System Required'\n";
      my $rc = $SetThreadExecutionState->Call($ES_SYSTEM_REQUIRED);
      $LOG->debug("'System Required' sent... ");
   }
   else
   {
      $LOG->error("SetThreadExecutionState did NOT load!!  ");
   }
}

sub processDir
{
my ($curdir) = @_;
my @subdirs;
my @md5files;
my @files;   
my $dh;
my $fullfile;
my $needsmd5 = 0;
my $hasmd5 = 0;
   
   # basename of a full directory path is the name of the directory
   settitle(basename($curdir));
   
   incTotdirs();
   # Open the directory and read everything (sub-dirs and files) except the "." and ".."
   # Note that the names will not have path information on them
   # print "Processing $curdir\n";
   opendir $dh, $curdir or die "Couldn't open dir '$curdir': $!";
   @files = grep { !/^\.\.?$/ } readdir $dh;
   closedir $dh;

   # print "Found @files in $curdir\n";
   foreach my $file (@files)
   {
      $fullfile = File::Spec->catdir($curdir,$file);
      if( -d $fullfile )
      {
         # Add to subdir
         # print "Found directory: $file\n";
         push(@subdirs, $fullfile);
      }
      elsif( $file =~ m/^folder\.md5$/i )
      {
         $hasmd5 = 1;
      }
      elsif( isFileForMD5($file)) # $file =~ m/.*\.(mp3|m4a|m4v|mp4|flac)$/i )
      {
         # Build the list of files to be md5'd
         push(@md5files, $file);
      }
   }


   if(($hasmd5 > 0) && (ForceRecalc()==0))
   {
      incTotmd5dirs();
      incTotchkmd5();
      # print "Checking $curdir\n";
      # Need to chdir into curdir for the md5s to be correct
      #my $popdir = getcwd;
      my @fails;
      # chdir($curdir);
      if(SkipCheck() == 0)
      {
         $LOG->debug("Checking $curdir\n");
         @fails = checkmd5($curdir, "folder.md5");
         # Supposed cause print to flush - but it doesn't work when
         # a filehandle is selected for print output. Doesn't work after
         # or before the output is written
         $|=1;                  
         if(@fails > 0)
         {
            incTotfailmd5dir();
            incTotfailmd5file(scalar @fails);
            my $failfiles = join("\n", @fails);
            binmode select, ":encoding(UTF-8)";
            # NB Non-ascii characters do not print correctly, even using the same encoding
            # as is used for accessing the files - fking Perl
            $LOG->warn("Mismatches:\n" . $failfiles . "\nFAIL    : $curdir\n");
            
         }
         $LOG->debug("OK:   %s\n", $curdir);
      }
   }
   elsif(@md5files > 0)
   {
      if(SkipCalc() == 0)
      {      
         my $foldermd5 = File::Spec->catdir($curdir,"folder.md5");
         if( open(FILE, ">>", $foldermd5) )
         {
            close(FILE);
            incTotmd5dirs();
            incTotcalcmd5();
            $LOG->info("Calculating MD5s: $curdir\n");
            # Not sure if sort can be done into the same variable
            my @srtmd5files = sort @md5files;
   
            my $md5sum = calcmd5($curdir, \@srtmd5files);
            saveutf8xfile($foldermd5, $md5sum);  
         }
         else
         {
            $LOG->warn("Skipping MD5 calculation for " . $curdir . ". Unable to create MD5 file " . $foldermd5 . ": " . $! . "\n");
         }         
      }
   }
   
   my @srtsubdirs = sort @subdirs;
   foreach my $subdir (@srtsubdirs) 
   {
      # Putting it here should mean that simply checking a single directory
      # doesn't mess with the power saving. When checking multiple directories
      # it will ensure the power saving is off before each directory which
      # should be frequent enough while leaving a reasonable delay between each
      # update.
      setpowersaving(0);
      
      $LOG->info("Processing: " . $subdir ."\n");
      processDir($subdir);
   }
}

# Filenames generated by CD rippers etc. can have non-ascii characters.
# These cause a real problem with Perl which seems to read them OK
# but has a problem when trying to use them for file system related
# operations, eg. the "-e file" test and the open command fail when the name contains non-ascii
# chars. 
# The only work around so far is to encode the name as latin-1 before testing or opening the
# file.
sub getFSname
{
my ($perlname) = @_;
   return Encode::encode('iso-8859-1' , $perlname)
   #return $perlname;
}

# Returns: array of failed files with failure reason suffix, ie.
# FAILREASON:filename
sub checkmd5
{
my ($chkdir, $md5sumfile) = @_;
# print STDOUT "checkmd5: Checking content of $md5sumfile\n";
my @md5s = loadfile2array(File::Spec->catdir($chkdir, $md5sumfile));
my @fails;
my $hash;
my $name;
my $calchash;
my $fullfile;
   foreach my $md5 (@md5s)
   {
      # ae907fd31ff602bbb33bc716c072f0f5 *01 One Of These Nights.mp3
      # Split line into hash
      if ( $md5 =~ m/^([a-z0-9]*) \*(.*)$/ )
      {
         $hash = $1;
         $name = $2;
         # print "checkmd5: Hash='$hash' File='$name'\n";
         $fullfile = File::Spec->catdir($chkdir, $name);
         
         # Need to check that file exists
         if( -e getFSname($fullfile)) 
         {
            $calchash = md5sum($fullfile);
            if( $hash ne $calchash )
            {
               push(@fails, "MISMATCH: " . $name);
               #print "checkmd5: MISMATCH calc:$calchash $md5sumfile:$hash $name\n";
            }
         }
         else
         {
            push(@fails, "MISSING: " . $name);
         }
      }
      else
      {
         $LOG->info("checkmd5: Non-md5sum line found: '$md5'\n");
      }
   }
   
   # Not sure what to return at the moment....
   return @fails;
}


sub calcmd5
{
my ($md5dir, $filesref) = @_;
my @files = @$filesref;
my $md5sum;
my $md5;
my $fullfile;

   foreach my $file (@files)
   {
      $fullfile = File::Spec->catdir($md5dir, $file);
      $md5 = md5sum($fullfile);
      # ae907fd31ff602bbb33bc716c072f0f5 *01 One Of These Nights.mp3
      $md5sum .= $md5 . " *" . $file . "\n";
   }
   return $md5sum;
}


sub md5sum
{  
my $file = shift;
my $digest = "";
my $fh;
   eval
   {    
      open($fh, getFSname($file)) or die "Can't find file $file\n";
      binmode $fh;
      my $ctx = Digest::MD5->new;
      $ctx->addfile($fh);
      $digest = $ctx->hexdigest;
      close($fh);
   };
   
   if($@)
   { 
      # What does this mean, again... some sort of error??   
      $LOG->warn($@);
      return "";
   }  
   
   return $digest;
}

sub saveutf8xfile
{
my ($path, $data) = @_;

   unlink "$path";
   
   # Need to have a utf-8 encoded file with unix line endings to be compatible with
   # the output of the cygwin md5sum command.
   # NB. The order of the 'layers' is important
   # putting the utf8 before unix doesn't work and apparently should not have a space 
   # not have a space between them.
   # NBB The Perl docs helpfully do not make any mention of the "unix" layer.
   
   if(open(my $output, ">", $path) )
   {
      binmode $output, ":unix:encoding(UTF-8)";
      print $output $data;
      close($output);
   }
   else
   {
      $LOG->warn("Failed to create MD5 file: " . $path . " : " . $! . "\n");
   }
}

sub loadfile2array
{
# Declare local variables ...
my ($path) = @_;
#print "loadfile2array: loading content of $path\n";
my @contents = "";
my $line = "";

   {
     # temporarily undefs the record separator
     # local(*INPUT, $/);

     open (INPUT, $path)     || die "can't open $path: $!";
     binmode INPUT, ":encoding(utf-8)";
     @contents = <INPUT>;
     close(INPUT);
   }

	return @contents;
}

# Converts characters to underscores for use as
# logfilename suffix.
# NB Some valid filename chars are also 
# converted, eg. space
sub filename2key
{
my ($str) = @_;
#$str = trim($str);
$str =~ s/[\\\/:\?\*\>\<\$\"\| ]/_/g;

# Only need one underscore at a time.
$str =~ s/__+/_/g;
return $str;
}
# Statistics tracking stuff - wanted to create a 'class'
# but it has to be in a different file and one reason for
# the perl script is to avoid needing additional files

# Silly little functions to avoid referring to the counters
# directly in the code.
sub incTotdirs { $counters{"dirs"}++; }
sub getTotdirs { return $counters{"dirs"}; }
sub incTotmd5dirs { $counters{"md5dirs"}++; }
sub getTotmd5dirs { return $counters{"md5dirs"}; }

sub incTotcalcmd5 { $counters{"calcmd5"}++; }
sub getTotcalcmd5 { return $counters{"calcmd5"}; }
sub incTotchkmd5 { $counters{"chkmd5"}++; }
sub getTotchkmd5 { return $counters{"chkmd5"}; }
sub incTotfailmd5dir { $counters{"failmd5dir"}++; }
sub getTotfailmd5dir { return $counters{"failmd5dir"}; }
sub incTotfailmd5file 
{ 
  my ($increment) = @_;
  if(! defined($increment) ) {
   $counters{"failmd5file"}++; 
  } else {
   $counters{"failmd5file"} += $increment; 
  }
}
sub getTotfailmd5file { 
   return $counters{"failmd5file"}; 
}

####### Property functions to avoid using global variables
####### These might be better in a class (aka package)
sub ForceRecalc
{
   state $forceRecalc = 0;
   if(@_ > 0)
   {
      $forceRecalc = $_[0];
   }
   return $forceRecalc;
}

sub SkipCheck
{
state $skipcheck = 0;
   if(@_ > 0)
   {
      $skipcheck = $_[0];
   }
   return $skipcheck;
}

sub SkipCalc
{
state $skipcalc = 0;
   if(@_ > 0)
   {
      $skipcalc = $_[0];
   }
   return $skipcalc;
}

sub LogToFile
{
state $logtofile = 0;
   if(@_ > 0)
   {
      $logtofile = $_[0];
   }
   return $logtofile;
}

sub PauseOnExit
{
state $pauseonexit = 0;
   if(@_ > 0)
   {
      $pauseonexit = $_[0];
   }
   return $pauseonexit;
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
   no warnings "numeric";
   
   # Does this work? Can I just use Level()? How do I know if the first parameter is
   # "self" or a level value??
   $level = $self->level;
   
   my %labels = %{$self->{"_LOG_LABELS"}};

   if(int($keyword) <= $level)
   {
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
         print sprintf("%-8s: %s(%04d): %s",($LOG_LABELS{$keyword}//$keyword), $callerfunc, $callerline, $msg);
      }
      else
      {
         $|=1;
         
         print sprintf("%-8s: %s",($labels{$keyword}//$keyword), $msg);
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

# 30 Jul 2018 Quick hack to get volume name into the log
# 21 Jul 2018 Uses Disk volume name (label) in temporary log filename when log cannot be opened 
#             in the directory being scanned, eg. when a DVD/BD is being scanned.
# 25 Apr 2015 Uses SetThreadExecutionState to prevent OS from going to sleep while processing directories
# 08 Mar 2015 Added single file update of folder.md
#             FIX Looping on multiple directory/filename parameters did not
#                 check for folder.md5 in each parameter or update the logfile name.
# 06 Mar 2015 Enhance output - use warning in summary when there are mismatches
# 04 Mar 2015 Use SCULog class to output messages
# 02 Mar 2015 Added the recalculate option to work with right-click. Converted some global flags to
#             use functions with static variables. This uses the "state" keyword which requires 
#             Perl 5.10 syntax which must be explicitly enabled.
# 27 Jul 2014 Write to log file in temp directory when unable to open it in the directory
#             being checked, eg. checking a DVD.
# 24 Jul 2014 Windows will go to sleep during long running checks so I start MonitorProcessor4Power
#             which suspends power saving while perl is running (haven't got a better way at the moment
#             although might be able to use the WINDOWTITLE filter of powercfg. NB the window title of
#             a console program changes to include the name of the file being executed, the /FI option
#             of tasklist does work with wildcards, at least 
#                 tasklist /FI "WINDOWTITLE eq FOLDERMD5*"
#             finds a console window with title FOLDERMD5 and running a perl script with a displayed
#             title of "FOLDERMD5 - perl test.pl". (So why can't MonitorProccessor4Power tell that there
#             is already an instance of itself running??)).
#             This causes a problem when FOLDERMD5 is run with pauseonexit as the perl remains
#             until I press a key, with the result that the computer doesn't go to sleep even though it
#             could. For now I've put a 5min timeout on the key press (which seems to work OK for Windows7)
#             which means I can see the response if I'm around and otherwise the machine can go to sleep and
#             I just need to remember to check the log. It might be better to have the script do the power
#             saving disabling. It will need to keep checking that the power saving is disabled as multiple
#             occurrences of FOLDERMD5 are run, each of which will be resetting the power saving when they
#             finish. Should maybe add the same thing to syncmd5 (so make it a function:-) ).
# 20 May 2014 Improved argument handling by using getopts and added support for multiple
#             directories on the command line (possible thanks to getopts removing the args
#             it receognises from the arg list. Each directory is handled independantly, including
#             logging - so each dir gets it's own log.
# 19 May 2014 Support for double-click of folder.md5 file. Also handle missing folder.md5
#             on read-only media - try to create file before performing the calculation.
# 11 May 2014 Sort files and dirs to make checking the lists easier (and it looks better)
#             Flush output so progress can be better viewed when logging to file.
#             Added -l parameter to automatically log to a timestamped md5_ log file in the
#             start directory
# 27 Jan 2014 Does not rely on curdir, chdir, etc. 
# (does rely on File::Spec->catdir alot though)
