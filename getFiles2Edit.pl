#!/usr/bin/perl

# Automatically move files from VUUltimo to local disk (SSD) for editing.
# Should have been a simple thing to do with a DOS batch file but the
# wildcards don't work, *Homeland*.ts return nothing when there are 
# matching files. Could possibly use "FINDSTR" but not without a lot
# of trickery. So perl it is...

# 09 Dec 2016 Move matching .eit files aswell. They are useful for prog info
# especially if I end up watching the .ts files without converting to .m4v
# as is the case with popular series, eg. Game Of Thrones


use strict;
use IO::Handle;
use Data::Dumper;
use File::Spec;
use File::Basename;
use File::Copy;
use File::stat;
use Cwd;
use Encode;
use Getopt::Std;
use Term::ReadKey;

my $LOG = SCULog->new();

   # For HD H264 recordings (VU+) for SmartCut editing
my @H264regexes;
   push(@H264regexes, "NPO3 HD - Homeland");
   push(@H264regexes, "NPO3 HD - Mr_ Robot");
   
   push(@H264regexes, "VIER HD - Lucifer");
   push(@H264regexes, "Q2 HD - ");
   push(@H264regexes, "BBC .* HD - Doctor Who");
   push(@H264regexes, "BBC One HD - The Missing");
   push(@H264regexes, "BBC Two HD - The Fall");
   push(@H264regexes, "BBC Four HD - The Code");
   push(@H264regexes, "ITV HD - ");
   push(@H264regexes, "Channel 4 HD - ");
   
   
   # Non-HD H264 channels (VU+) for SmartCut editing
   push(@H264regexes, "VIJF - Chesapeake Shores");
   push(@H264regexes, "VIJF - The Rookie");
   push(@H264regexes, "VIJF - Grey\\'s Anatomy");
   push(@H264regexes, "CAZ - ");
   #push(@H264regexes, "ZES - The Blacklist");
   push(@H264regexes, "ZES - ");

   # SD, ie. MPEG, recordings (VU+) for Cuttermaran editing
my @MP2regexes;
   push(@MP2regexes, "ITV.* - The Jonathan Ross Show");
   push(@MP2regexes, "Channel 4 - Homeland");
   push(@MP2regexes, "Channel 5 - ");
   push(@MP2regexes, "5STAR(?: *\\+1)? - ");
   push(@MP2regexes, "Channel 4(?: *\\+ *1)? - ");
   push(@MP2regexes, "E4(?: *\\+1)? - ");
   push(@MP2regexes, "ITV2(?: *\\+1)? - The Vampire Diaries");
   push(@MP2regexes, "ITV4 - The Americans");

   # For all recordings (DB7025) for Cuttermaran editing
my @allregex;
   push(@allregex, ".*");
   
my @gRegexes = @H264regexes;
my $srcdir = "";
my $dstdir = "";
my $logtofile = 0;
my $pauseonexit = 0;
my $logfh;
my $logfilename;
my %opts;



getopts('vlpsa', \%opts);

if( $opts{"v"} == 1)
{
   $LOG->level(SCULog->LOG_DEBUG);
}
if( $opts{"l"} == 1)
{
   $logtofile = 1;
}
if( $opts{"p"} == 1)
{
   $pauseonexit = 1;
}

# Should think of a better way to do this, but haven't come up with anything
# which supports having different directories for the SD and HDs unless
# both are specified on the command line. I guess having both the same
# unless specified otherwise might work...
if( $opts{"s"} == 1)
{
   @gRegexes = @MP2regexes;
}
elsif( $opts{"a"} == 1)
{
   @gRegexes = @allregex;
}

$srcdir = $ARGV[0];
shift(@ARGV); #Removes first element
$dstdir = $ARGV[0];

#print "Logging:     " . $logtofile . "\n";
#print "Pauseonexit: " . $pauseonexit . "\n";
#die(0);
if($srcdir eq "")
{
   $srcdir = "X:\\movie";
}

if($dstdir eq "")
{
   $dstdir = "Q:\\video\\h264";
}

$srcdir = File::Spec->rel2abs($srcdir);
$dstdir = File::Spec->rel2abs($dstdir);


if ( $logtofile == 1 )
{
   my @now = localtime();
   my $ts = sprintf("%04d%02d%02d%02d%02d", 
                        $now[5]+1900, $now[4]+1, $now[3],
                        $now[2],      $now[1]);
   my $suffix = filename2key($dstdir);
   $logfilename = File::Spec->catdir($srcdir, "findOwn_" . $ts . "_" . $suffix . ".log");
   $logfilename = File::Spec->rel2abs($logfilename);
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

processDir($srcdir, $dstdir);

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
########### End of main program
sub getTSFiles
{
my ($dir) = @_;
my @tsfiles;
my $dirkey;
my $dh;
my @files;
my $fullfile;

   opendir $dh, $dir or die "Couldn't open dir '$srcdir': $!";
   @files = grep { !/^\.\.?$/ } readdir $dh;
   closedir $dh;

   foreach my $file (@files)
   {
      #if($file =~ m/.*\.(ts|eit)$/i)
      if($file =~ m/.*\.ts$/i)
      {
         $fullfile = File::Spec->catdir($dir,$file);
         if( -f $fullfile )
         {
            push(@tsfiles, $fullfile);
         }
      }
   }
   return @tsfiles;
}


sub getUniqueDestName
{
my ($dir, $file) =  @_;
my $unqname;
my $name = $file;
my $extn = "";
my $cnt=1;
my $ts;

   # If it doesn't exist then just use the original name
   $unqname = File::Spec->catdir($dir,$file);
   if( ! -f $unqname)
   {
      return $unqname;
   }

   if($file =~ m/^(.*)(\..*)$/ )
   {
      $name = $1;
      $extn = $2;   
   }
   
   # Try inserting a version number betzeen 1 and 9 into the file name
   $cnt = 1;
   for($cnt = 1; $cnt < 10; $cnt++)
   {
      $unqname = File::Spec->catdir($dir, $name . "." . $cnt . $extn);
      if( ! -f $unqname)
      {
         return $unqname;
      }
   }
   
   # In desperation use a timestamp, in theory the file can't already exist!!!
   my @now = localtime();
   $ts = sprintf("%04d%02d%02d%02d%02d%02d", 
                        $now[5]+1900, $now[4]+1, $now[3],
                        $now[2],      $now[1],   $now[0]);
   return File::Spec->catdir($dir, $name . "." . $ts . $extn);
}

sub processDir
{
my ($origdir, $destdir) = @_;
my @tsfiles;
my $destpath;
my $tsfilename;
my $dirs;
my $suffix;
my $fullregex;

   # Dedicated function for .ts files so...
   # - Make list of .ts
   # - Check each filename (only filename) against the reg.exp
   #   - Move matching files (using DOS command?) to dest.

   @tsfiles = getTSFiles($origdir);
   foreach my $tsfullfile (@tsfiles)
   {
      ($tsfilename,$dirs,$suffix) = fileparse( $tsfullfile );
      foreach my $regex (@gRegexes)
      {
         $fullregex = ".*?" . $regex . ".*";
         if($tsfilename =~ m/$regex/)
         {
            # As always with Perl cannot simply create a function which returns a boolean value
            # as there is no boolean type and returning 0 and 1 for some ridiculous Perl reason
            # are not always interpreted as false and true in conditions.
            $LOG->info("File '$tsfilename' matches '$regex'\n");
            if(isFileInUse( $tsfullfile) == 0)
            {
               $destpath = getUniqueDestName($destdir, $tsfilename);
               $LOG->info("Moving '$tsfilename' to $destdir.\n");
               move($tsfullfile, $destdir);
               
               # Cannot passively handle .eit when it is found as a separate file as it should only be moved if
               # the related .ts file is moved
               (my $eitfullfile = $tsfullfile) =~ s/\.ts$/.eit/;
               $LOG->info("Checking for '$eitfullfile'.\n");
               if( -f $eitfullfile )
               {
                  my $eitfile;
                  ($eitfile,$dirs,$suffix) = fileparse( $eitfullfile );
                  $destpath = getUniqueDestName($destdir, $eitfile);
                  $LOG->info("Moving '$eitfullfile' to $destpath.\n");
                  move($eitfullfile, $destpath);
               }
               else
               {
                  $LOG->info("No eit file found for  '$tsfullfile'.\n");
               }
            }
            else
            {
               $LOG->info("'$tsfilename' appears to be in use and will not be moved\n");
            }
            
            last; #This means break!
         }
         else
         {
            $LOG->debug("File '$tsfilename' does NOT match '$regex'.\n");
         }
      }
   }
}
sub isFileInUse
{
my ($pathname) = @_;
my $bInUse = 0;
my $size1;
my $size2;
my $stat;

   $LOG->debug("isFileInUse: stat '$pathname'\n");
   if( -f $pathname )
   {
      $stat = stat($pathname);
      $size1 = $stat->size;
      sleep(20);  # Size does not seem to update very frequently
      $stat = stat($pathname);
      $size2 = $stat->size;
   
      if($size1 != $size2)
      {
         $LOG->info("isFileInUse: '$pathname' size changed from $size1 to $size2, assuming file IS in use\n");
         $bInUse = 1;
      }
      else
      {
         $LOG->debug("isFileInUse: '$pathname' size remained constant at $size1, assuming file NOT in use\n");
      }
   }
   else
   {
      $LOG->info("isFileInUse: '$pathname' is NOT a file!!!! Returning true\n");
      $bInUse = 1;
   }
   return $bInUse;
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
         $!=1;
         
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