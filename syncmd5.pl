#!/usr/bin/perl
# 15 Aug 2023 option to exclude source directories from the sync using a regex pattern. The pattern
#             is applied to the simple directory name not the full path.
# 27 Apr 2019 Update console window title with currently processing directory
# 23 Feb 2019 Try to keep file/dir times of destination same as source
#             Added sleep preventer
# 30 Jun 2018 Log goes to destination as this fits better with how I use it. 
# XX Jun 2018 based on foldermd5
# This is the real test - the change to main was a mistake because I cannot get used
# to not being put in the branch when I create new one... bloody unix tools
use strict;
use IO::Handle;
use Data::Dumper;
use Digest::MD5;
use File::Spec;
use File::Basename;
use File::Copy;
use File::Path qw(make_path remove_tree);
use Cwd;
use Encode;
use Getopt::Std;
use Term::ReadKey;
use Win32::API;
use Win32::Console; 
my $VERSION="syncMD5 v1.4";
print "$VERSION 20230815\n";

my $CONSOLE=Win32::Console->new;
# Must be positioned at the start of the script before the get/inc funcs are used otherwise
# the hash is not initialised even though there is no syntax error for the
# hash itself not being declared.
my %counters;

my $srcdir = "";
my $destdir = "";
my $verbose = 0;
my $logtofile = 0;
my $pauseonexit = 0;
my $logfh;
my $logfilename;
my %opts;

# I think this will be a regex 'list' pattern, eg. "playlists|ringtones|voicememos" which
# might cause a problem with the command line though but hopefully quoting the argument will
# work
my $excldirs = ""; # Directories to exclude.
getopts('x:ckvlp?', \%opts);

if( $opts{"?"} == 1 )
{
   HELP_MESSAGE();
}

if( $opts{"v"} == 1)
{
   $verbose = 1;
}
if( $opts{"l"} == 1)
{
   $logtofile = 1;
}
if( $opts{"p"} == 1)
{
   $pauseonexit = 1;
}

if( $opts{"x"})
{
   $excldirs = $opts{"x"};
}


# The options are removed from argv which leaves just the directory.
# This makes it possible to specify multiple directories on the command line
# which would be handy for specifying mp3, flac and alac in one script.
# Destdir woul dneed to be specified with an option, and all source root dirs would
# need to be sub-dirs of the destdir, log file should go in root destdir... not really
# required in practice since the format type directories are sub-dirs in both 
# source and dest dirs.

$srcdir = $ARGV[0];
shift(@ARGV); #Removes first element
$destdir = $ARGV[0];

#print "Logging:     " . $logtofile . "\n";
#print "Pauseonexit: " . $pauseonexit . "\n";
#die(0);

if($destdir eq "")
{
   $destdir = $srcdir;
	$srcdir = File::Spec->curdir();
}

$srcdir = File::Spec->rel2abs($srcdir);
$destdir = File::Spec->rel2abs($destdir);

   
if ( $logtofile == 1 )
{
   my @now = localtime();
   my $ts = sprintf("%04d%02d%02d%02d%02d", 
                        $now[5]+1900, $now[4]+1, $now[3],
                        $now[2],      $now[1]);
   my $suffix = filename2key($srcdir);
   $logfilename = File::Spec->catdir($destdir, "sync_" . $ts . "_" . $suffix . ".log");
   print 'Redirecting output to ' . $logfilename . "\n";
   open ($logfh, '>', $logfilename);
   # Extra attempt to get the output visible in UltraEdit during the processing
   $logfh->autoflush(1); 
   # select new filehandle
   select $logfh;
   $|=1;
}


# This bit of perl black magic is supposed to make stdout flush 
# each line even when redirected to a file, but it doesn't seem to work inside
# the logtofile if block and it doesn't seem to work here either when logfh is selected.
# At least the output is actually going into the file though.
$|=1;

print "Syncing directory: $srcdir with $destdir\n";
if(length $excldirs > 0) 
{
   print "Excluding directories matching pattern '$excldirs'\n";
}
syncDir($srcdir, $destdir, $excldirs);
settitle("Done!");
print "Total directories:          " . getTotdirs() . "\n";
print "Total files:                " . getTotfiles() . "\n";
print "Ignored files:              " . getIgnoredFiles() . "\n";
print "Skipped files:              " . getSkippedFiles() . "\n";
print "Failed files:               " . getReadFailed() . "\n";
print "Synced files:               " . getSyncedFiles() . "\n";

# If $logfh is initialized to a known value the open command complains
# so 'defined' seems to be the way to check whether the variable was
# initialized.
if ( defined $logfh )
{
   close($logfh);
}
select STDOUT;

if($pauseonexit == 1)
{
   if( $logtofile == 1 )
   {
      printfile($logfilename);
   }

   print "Press a key to exit . . . ";
   ReadMode 'cbreak';
   my $key = ReadKey(0);
   ReadMode 'normal';
}

sub HELP_MESSAGE()
{
   print "syncmd5 [-l] [-v] [-p] [source directory] [destination directory]\n";
   print "   -l Log to file. Log file is created in the\n";
   print "      initial scan directory with name md5_yyyymmddhhmm\n";
   print "   -v Verbose output\n";
   print "   -p Pause on exit. Waits for a key to be pressed before terminating.\n";
   print "If only one directory is specified it is assumed that the\n";
   print "source directory is the current directory and the specified directory\n";
   print "is the destination directory\n";
   exit(0);
}

sub syncDir
{
my ($srcroot, $destroot, $excldirpat) = @_;
my @subdirs;
my @files;
my @dircontent;   
my $dh;
my $fullfile;
my %srcmd5s;
my %destmd5s;
   settitle(basename($srcroot));
   incTotdirs();
   # Open the directory and read everything (sub-dirs and files) except the "." and ".."
   # Note that the names will not have path information on them
   # print "Processing $curdir\n";
   opendir $dh, $srcroot or die "Couldn't open dir '$srcroot': $!";
   @dircontent = grep { !/^\.\.?$/ } readdir $dh;
   closedir $dh;


   
   # Create dest dir if needed
   make_path($destroot);
   

   # print "Found @files in $curdir\n";
   foreach my $file (@dircontent)
   {
      $fullfile = File::Spec->catdir($srcroot,$file);
      if( -d $fullfile )
      {
         # NB. empty pattern matches everything so excludes all!
         if((length $excldirpat == 0) || ($file !~ m/$excldirpat/) )
         {
            # Add to subdir
            push(@subdirs, $file);
         }
         else
         {
            print "Excluding directory: $fullfile\n";
         }
      }
      elsif(! ($file =~ m/.*\.(ini|db|log|bak|dat)$/i) )
      {
         # Safer to make this an Exclude instead of include
         incTotfiles();
         push(@files, $file);
         if( $file =~ m/^folder\.md5$/i )
         {
            my $desthashpath = File::Spec->catdir($destroot,$file);
            %srcmd5s = loadmd52hash(File::Spec->catdir($srcroot,$file));
            if ( -e $desthashpath )
            {
               %destmd5s = loadmd52hash($desthashpath);
            }
         }         
      }
      else
      {
         incTotfiles();
         incIgnoredFiles();
         print "IGNR: " . $file . "\n";
      }
   }
   
   @files = sort @files;
   foreach my $file (@files)
   {
      my $srchash = $srcmd5s{$file};
      my $desthash = $destmd5s{$file};
      syncFile(File::Spec->catdir($srcroot,$file), File::Spec->catdir($destroot,$file), $srchash, $desthash);
   }
   
   my @srtsubdirs = sort @subdirs;
   foreach my $subdir (@srtsubdirs) 
   {
      syncDir(File::Spec->catdir($srcroot,$subdir), File::Spec->catdir($destroot,$subdir), $excldirpat);
   }

   # Try to make the modification time of the dest directory match the time of the source
   # makes it easier to visually spot when directories are out of date.
   # I guess this needs to be done after all updates to the directory to avoid the OS
   # changing the time to now!
   my $dirmtime=(stat($srcroot))[9];
   utime $dirmtime, $dirmtime, $destroot;
}

sub syncFileMd5
{
my ($src, $dest) = @_;
my $srcmd5="";
my $destmd5="";

   $srcmd5 = md5sum($src);
   # Assume src exists, but dest might not
   if( -e $dest)
   {
      $destmd5 = md5sum($dest);
   }
   
   if((length $srcmd5 == 0) || ($srcmd5 ne $destmd5))
   {
      # Copy file
      if (copy($src, $dest) )
      {
         my $fmtime=(stat($src))[9];
         utime $fmtime, $fmtime, $dest;        
         incSyncedFiles();
         $|=1;
         print "SYNC:  " . $src . " to " . $dest . "\n";      
      }
      else
      {
         $|=1;
         print "FAIL: " . $! . ": Copy " . $src . " to " . $dest . "\n";
         incReadFailed();
      }
   }
   else
   {
      incSkippedFiles();
      $|=1;
      print "SKIP:  " . $src . "\n";

   }
   return;
}

sub syncFile
{
my ($src, $dest, $srcmd5, $destmd5) = @_;
my $tmpdest;
my $srcfh;
my $destfh;
my $buffer;
my $bytesread;
my $readmd5;

   
   if( (length $srcmd5 > 0) && ($srcmd5 eq $destmd5))
   {
      incSkippedFiles();
      print "SKIP:  " . $src . "\n";
      return;
   }
   wakeywakey();
   
   # For files not covered by foldermd5 should calc the src and dest md5
   # and only sync file if the md5s do not match. This is mainly to avoid having
   # the directory modified by time being updated everytime a sync is done because
   # the folder.md5 and album art is always copied.
   if( (length $srcmd5 == 0) || (length $destmd5 == 0))
   {
      syncFileMd5($src, $dest);
      return;
   }

   $tmpdest = $dest . ".sync";
   unlink $tmpdest;
   
   open($destfh, ">", getFSname($tmpdest)) or die "Can't create file $tmpdest:" . $! . "\n";
   binmode $destfh;
   open($srcfh, getFSname($src)) or die "Can't open file $src:" . $! . "\n";
   binmode $srcfh;

   my $ctx = Digest::MD5->new;
   do
   {
      $bytesread = sysread $srcfh, $buffer, 1024 * 1024 * 10;
      if($bytesread > 0)
      {
         syswrite $destfh, $buffer, $bytesread;
         $ctx->add($buffer);
      }
   }while($bytesread > 0);
   
   
   close($srcfh);
   close($destfh);
   $readmd5 = $ctx->hexdigest; 
   if( (length $srcmd5 > 0) && ($readmd5 ne $srcmd5))
   {
      incReadFailed();
      print "FAIL: MD5 source read mismatch: " . $src . "\n";
      unlink $tmpdest;
   }
   else
   {
      unlink $dest;
      move($tmpdest, $dest);
      
      my $fmtime=(stat($src))[9];
      utime $fmtime, $fmtime, $dest;        
      
      print "SYNC:  " . $src . " to " . $dest . "\n";
      incSyncedFiles();      
   }
}


sub loadmd52hash
{
my ($md5sumfile) = @_;
# print STDOUT "checkmd5: Checking content of $md5sumfile\n";
my @md5s = loadfile2array($md5sumfile);
my %file2md5;
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
         $file2md5{$name} = $hash;
      }
   }
   return %file2md5;
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
         print "checkmd5: Non-md5sum line found: '$md5'\n";
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
      if(open($fh, getFSname($file)))
      {
         binmode $fh;
         my $ctx = Digest::MD5->new;
         $ctx->addfile($fh);
         $digest = $ctx->hexdigest;
         close($fh);
      }
      else
      {
         print "ERROR: md5sum: Failed to open " . $file . ": " . $! . "\n";
      }
   };
   
   if($@)
   {    
      print $@;
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
      $|=1;
      print "Failed to create MD5 file: " . $path . " : " . $! . "\n";
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
sub printfile
{
# Declare local variables ...
my ($path) = @_;
#print "loadfile2array: loading content of $path\n";
my @contents = "";
my $line = "";

   open my $fh, "<", $path     || die "can't open $path: $!";
   binmode INPUT, ":encoding(utf-8)";
   while( $line = <$fh> )
   {
      print "$line\n";
   }
   close($fh);

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

sub settitle
{
my $title = shift;
$CONSOLE->Title($VERSION. ": " . $title);
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
      #$LOG->debug("'System Required' sent... ");
   }
   else
   {
      #$LOG->error("SetThreadExecutionState did NOT load!!  ");
   }
}

# Statistics tracking stuff - wanted to create a 'class'
# but it has to be in a different file and one reason for
# the perl script is to avoid needing additional files

# Silly little functions to avoid referring to the counters
# directly in the code.
sub incTotdirs { $counters{"dirs"}++; }
sub getTotdirs { return $counters{"dirs"} // 0; }
sub incTotfiles { $counters{"totfiles"}++; }
sub getTotfiles { return $counters{"totfiles"} // 0; }

sub incIgnoredFiles { $counters{"ignfiles"}++; }
sub getIgnoredFiles { return $counters{"ignfiles"} // 0; }
sub incSkippedFiles { $counters{"skipfiles"}++; }
sub getSkippedFiles { return $counters{"skipfiles"} // 0; }
sub incReadFailed { $counters{"readfail"}++; }
sub getReadFailed { return $counters{"readfail"} // 0; }

sub incSyncedFiles { $counters{"syncfiles"}++; }
sub getSyncedFiles { return $counters{"syncfiles"} // 0; }
