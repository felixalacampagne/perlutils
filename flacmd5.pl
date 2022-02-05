#!/usr/bin/perl
# Use ffmepg to calculate the MD5 of the audio in FLAC files.
# Performs the calculation for all .flac or .m4a files in the sub-directories of the current or specified directory
# 26 Oct 2018 Defaults to checking. Creates .md5 if it does not exist.
# 19 Aug 2018 Can handle ALAC .m4a files
# 27 Jul 2018 Adapted from foldermd5
# 25 Apr 2015 Uses SetThreadExecutionState to prevent OS from going to sleep while processing directories
use 5.010;  # Available since 2007, so should be safe to use this!!
use strict;
use IO::Handle;
#use Data::Dumper;
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

my $FFMPEG=$ENV{FFMPEG} . "";
my $MD5CNTNAME = "folderaudio.md5";
if($FFMPEG eq "")
{
   print "FFMPEG environment variable must be set to point to the ffmpeg executable";
   exit(1);
}


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
my $logfh;
my $logfilename;
my %opts;
my @starttime = Today_and_Now();
my @endtime;
my $mode = 1;  # Quick and dirty calc/check mode 0 - calc, 1 = check
getopts('cgvlpr?', \%opts);

if( $opts{"?"} == 1 )
{
   HELP_MESSAGE();
}

if( $opts{"c"} == 1)
{
   $mode = 1;
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
}

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
   	if($filename =~ m/^$MD5CNTNAME$/i) # This should work according to my tests
   	{
   	   # remove the filename - the check is automatic if there is a folder.md5 present
   	   $startdir = $directories;

         # In this case it is handy to have logging and pauseonexit enabled
   	   LogToFile(1);
   	   PauseOnExit(1);
   	}
   }

   # NB. flacmd5 log file is created in the CURRENT directory. This is because it is usually
   # run from the command line with a folder spec, eg.
   # N:\alac> flacmd5 -c -l "01 pop-rock"
   if ( LogToFile() == 1 )
   {
      my @now = localtime();
      my $ts = sprintf("%04d%02d%02d%02d%02d",
                           $now[5]+1900, $now[4]+1, $now[3],
                           $now[2],      $now[1]);
      my $logname = "";
      my $key = "";
      # my $path = "";
      if( -d $startdir )
      {
         $key = filename2key($startdir);
      }
      else
      {
         my ($filename,$directories,$dummy) = fileparse( $startdir );
         $key = filename2key($filename);
      }
      $logname = "flacmd5_" . $ts . "_" . $key . ".log";
      $logfilename = File::Spec->catdir(File::Spec->curdir(), $logname);

      if(!open ($logfh, '>>', $logfilename))
      {
         $LOG->warn("Failed to open log file $logfilename: $!\n");
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
         $LOG->info("Logging output to " . $logfilename . "\n");
         # Extra attempt to get the output visible in UltraEdit during the processing
         $logfh->autoflush(1);
         # select new filehandle
         $LOG->logfile($logfh);
         # select $logfh;
      }
      $|=1;
   }


   # This bit of perl black magic is supposed to make stdout flush
   # each line even when redirected to a file, but it doesn't seem to work inside
   # the logtofile if block and it doesn't seem to work here either when logfh is selected.
   # At least the output is actually going into the file though.
   $|=1;


   my $tab="  ";
   if( -d $startdir )
   {
      $LOG->info("Processing directory: %s\n", $startdir);
      $LOG->info("Started at:           %s\n", ymdhmsString(@starttime));
      processDir($startdir);
   }
   elsif( isFileForMD5($startdir) )
   {
      $LOG->info("MD5 update: %s\n", $startdir);
      $LOG->info("Started at: %s\n", ymdhmsString(@starttime));
      updateFileMD5($startdir);
   }
   else
   {
      $LOG->info("Processing of $startdir not supported");
   }


   @endtime = Today_and_Now();
   my @elapsed = Delta_DHMS(@starttime, @endtime); # ($days,$hours,$minutes,$seconds)

   $LOG->info("${tab}Finished at:                %s\n", ymdhmsString(@endtime));
   $LOG->info("${tab}Elapsed:                    %02d:%02d:%02d\n", $elapsed[1],$elapsed[2],$elapsed[3]);
   $LOG->info("${tab}Total directories:          " . getTotdirs() . "\n");
   $LOG->info("${tab}Directories requiring MD5s: " . getTotmd5dirs() . "\n");
   $LOG->info("${tab}Folder MD5s calculated:     " . getTotcalcmd5() . "\n");
   if($mode == 1)
   {
      $LOG->info("${tab}Folder MD5s checked:        " . getTotchkmd5() . "\n");
      $LOG->info("${tab}Failed folder MD5s:         " . getTotfailmd5dir() . "\n");
      $LOG->info("${tab}Failed file MD5s:           " . getTotfailmd5file() . "\n");
   }
   # If $logfh is initialized to a known value the open command complains
   # so 'defined' seems to be the way to check whether the variable was
   # initialized.
   if ( defined $logfh )
   {
      close($logfh);
   }
   #select STDOUT;

   shift(@ARGV); #Removes first element
   $startdir = $ARGV[0];

}while(length $startdir > 0);

# Enable power saving here so machine can go to sleep
# while waiting for input.
setpowersaving(1);


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
my $foldermd5path = File::Spec->catdir($directories, $MD5CNTNAME);

   $LOG->debug("Calculated MD5:  New value: $md5new\n");

   if( -e $foldermd5path)
   {
      $LOG->debug("MD5 file already exists: $foldermd5path\n");
      my @md5s = loadfile2array(File::Spec->catdir($directories, $MD5CNTNAME));
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
               $LOG->debug("File is present in $MD5CNTNAME: Old value: $md5\n");
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

# TRUE if the file is FLAC or
# TRUE if the file is M4A, which for me means it's an ALAC, which is also lossless so the audio MD5 should be also be reproducible
sub isFileForMD5
{
my ($file) = @_;
   if( $file =~ m/.*\.(mp3|m4a|flac)$/i )
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
   print "flacmd5 [-l] [-v] [initial scan directory]...\n";
   print "   -l Log to file. Log file is created in the\n";
   print "      initial scan directory with name md5_yyyymmddhhmm\n";
   print "   -v Verbose output\n";
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

   incTotdirs();
   # Open the directory and read everything (sub-dirs and files) except the "." and ".."
   # Note that the names will not have path information on them
   # print "Processing $curdir\n";
   unless (opendir $dh, $curdir)
   {
      $LOG->warn("FAILED: Could not open $curdir: " . $!);
      incTotfailmd5dir();
      return;
   }

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
      elsif( $file =~ m/^$MD5CNTNAME$/i ) # This works in my test program!!
      {
         $hasmd5 = 1;
      }
      elsif( isFileForMD5($file)) # $file =~ m/.*\.(mp3|m4a|m4v|mp4|flac)$/i )
      {
         # Build the list of files to be md5'd
         push(@md5files, $file);
      }
   }


   if(@md5files > 0)
   {
      # if the md5 file does not exist then do a calculation regardless of mode setting
      if(($mode == 0) || ($hasmd5 != 1))
      {
         my $foldermd5 = File::Spec->catdir($curdir, $MD5CNTNAME);
         if( open(FILE, ">>", $foldermd5) )
         {
            close(FILE);
            incTotmd5dirs();
            incTotcalcmd5();

            $LOG->info("procDir: CALCMD5  : $curdir\n");
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
      elsif($mode == 1)
      {
         my @fails;
         incTotmd5dirs();
         incTotchkmd5();
         @fails = checkmd5($curdir, $MD5CNTNAME);
         if(@fails > 0)
         {
            incTotfailmd5dir();
            incTotfailmd5file(scalar @fails);
            #my $failfiles = join("\n", @fails);
            #binmode select, ":encoding(UTF-8)";
            ## NB Non-ascii characters do not print correctly, even using the same encoding
            ## as is used for accessing the files - fking Perl
            #$LOG->warn("Mismatches:\n" . $failfiles . "\nFAIL    : $curdir\n");

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
my @fails;
# print STDOUT "chckmd5: Checking content of $md5sumfile\n";
my $sumpath = File::Spec->catdir($chkdir, $md5sumfile);
   if( ! -e $sumpath )
   {
      push(@fails, "MISSING: No " . $md5sumfile . " to check: " . $sumpath);
      $LOG->info( "chckmd5:   MISSING  : $md5sumfile not found in $chkdir\n");
      return @fails;
   }

my @md5s = loadfile2array($sumpath);
my $hash;
my $name;
my $calchash;
my $fullfile;
   $LOG->info("chckmd5: CHECKING: $chkdir\n");
   foreach my $md5 (@md5s)
   {
      # ae907fd31ff602bbb33bc716c072f0f5 *01 One Of These Nights.mp3
      # Split line into hash
      if ( $md5 =~ m/^([a-z0-9]*) \*(.*)$/ )
      {
         $hash = $1;
         $name = $2;

         $fullfile = File::Spec->catdir($chkdir, $name);

         # Need to check that file exists
         # Same shirt, different function! Special characters fork up the ffmpeg command, presumably
         # because UTF-8 is being passed instead of the OS default encoding. This only seems to affect
         # the checking, I guess because the md5 file contains UTF-8 and the UTF-8 is passed to
         # the command line. This implies that the filenames passed during the original calculation
         # are passed using the OS encoding, maybe because they names come from reading the directory?
         # Hopefully the same trick as used for other OS filename requests will work.
         my $fsname = getFSname($fullfile);
         if( -e $fsname)
         {

            $calchash = md5sum($fsname);
            if( $hash ne $calchash )
            {
               push(@fails, "MISMATCH: " . $name);
               $LOG->info("chckmd5: MISMATCH: $name\n");
               $LOG->debug("new:$calchash prev:$hash\n");
            }
            else
            {
               $LOG->info( "chckmd5: MATCH   : $name\n");
            }
         }
         else
         {
            push(@fails, "MISSING: " . $name);
            $LOG->info( "chckmd5: MISSING : $name not found\n");
         }
      }
      else
      {
         $LOG->info("chckmd5: INVALID  : Non-md5sum line found: '$md5'\n");
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
      $LOG->debug( "MD5: $md5 File: $file\n");
   }
   return $md5sum;
}


sub md5sum
{
my $file = shift;

my $digest = "";
my $fh;
my $ffres;
   eval
   {
      # This is the ffmpeg command to output the audio MD5 to stdout.
      # Just need a way to grab the output to a file and extract only the MD5 part
      # ffmpeg -i "$file" -f framemd5 -
      # MD5=a34bfd9245ad6d69eddcb92035219044
      # The blog post used s slightly different command line;
      # ffmpeg -i "$file" -map 0:a -f md5 -
      # It's not at all obvious from the docs but it seems that the framemd5 will calculate an MD5 for each and every
      # frame, not for the entire content. I guess this is why the more complicated command is suggested by the blog
      # the "-f hash" doc says calculates a hash of all the input audio frames so maybe something like this will work
      # ffmpeg -i "$file" -f hash md5 - - 2>nul
      # qx is apparently the same a "backtic" but easier to read.
      # both are supposed to only capture stdout

      # This works fine for updating the lyrics with my FLACtagger and with mp3tag.
      # Unfortunately deleting the album art using mp3tag results in a different MD5 from
      # ffmpeg with this command HOWEVER foobar2k Bitcompare reports that the audio is unchanged.
      # I think this might be because mp3tag does not remove the image from the file buts
      # zeros it out. I guess that it must assign it a dummy packet type which is included in
      # the output by ffmpeg even though it isn't part of the audio. Maybe this is why
      # the blog post mentions the -map 0:a
      #$ffres = qx ($FFMPEG -i "$file" -f hash -hash md5 -v 0 -);
      # Adding the map does produce the same MD5 for the original file and the updated file
      # after removing the albumart. I have the impression that the albumart was being included
      # in the md5 because it is treated as a video stream. Have to assume the audio stream is
      # always stream 0, I guess.... typical forking Unix shit '-map 0:a' means take the audio
      # stream as the first stream and ignore the rest.
      
      # It may be possible to md5 just the mp3 audio data, ie. ignore the tag info and do not convert
      # the mp3 data to pcm, using the following ffmpeg command;
      # ffmpeg -i "$file" -map 0:a -c:a copy -v 0 -f hash -hash md5 -
      # or a more simplified form might be
      # ffmpeg -i "$file" -c:a copy -vn -f md5 -
      # unfortunately this does not produce the same md5 as the mp3tag command _md5audio.
      # So for now I'm sticking with the same command as used for flac and alsc. This might actually
      # be better since apparently there are some mp3 headers, which are not tags, which may or may not 
      # be changed, or may or may not be included in an mp3audio digest but in theory would not affect the
      # raw pcm audio output...
      $ffres = qx ($FFMPEG -i "$file" -map 0:a -f hash -hash md5 -v 0 -);
      #print "ffmpeg returned the following:\n" . $ffres;
      if($ffres =~ m/MD5=([a-f0-9]{32,32})/)
      {
         $digest = $1;
         #print "MD5: $digest File: $file\n";
      }
      else
      {
         print "No MD5 detected: $file\n";
      }
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
my @contents = "";
my $line = "";

   {
      # temporarily undefs the record separator
      # local(*INPUT, $/);

      if(open (INPUT, $path))
      {
         binmode INPUT, ":encoding(utf-8)";
         @contents = <INPUT>;
         close(INPUT);
      }
      else
      {
         $LOG->warn("FAILED: Could not open $path: $!");
      }
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


