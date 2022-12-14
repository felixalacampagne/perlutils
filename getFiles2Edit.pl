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
use FindBin;           # This should find the location of this script
use lib $FindBin::Bin . "/lib"; # This indicates to look for modules in the lib directory in script location


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
use FALC::SCULog;

my $LOG = FALC::SCULog->new();

   # For HD H264 recordings (VU+) for SmartCut editing
my @H264regexes;
#   push(@H264regexes, "NPO3 HD - ");
   
   # push(@H264regexes, "Play4 - ");
   push(@H264regexes, "VTM 2 HD - ");
   push(@H264regexes, "BBC .* HD - Doctor Who");
   push(@H264regexes, "BBC .* HD - Killing Eve");

   # push(@H264regexes, "BBC Two HD - ");
   push(@H264regexes, "BBC Three HD - ");
   # push(@H264regexes, "BBC Four HD - ");
   push(@H264regexes, "ITV HD - ");
   push(@H264regexes, "Channel 4 HD - ");
   
   
   # Non-HD H264 channels (VU+) for SmartCut editing
   push(@H264regexes, "Play5 - ");
   push(@H264regexes, "VTM 3 - ");
   push(@H264regexes, "Play6 - ");

   # SD, ie. MPEG, recordings (VU+) for Cuttermaran editing
my @MP2regexes;
   push(@MP2regexes, "BBC Three - ");
   push(@MP2regexes, "ITV(?: *\\+ *1)? - The Bay");
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

   opendir $dh, $dir or die "Couldn't open dir '$dir': $!";
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
   $LOG->info("Count .TS files found in '$origdir': " . @tsfiles . "\n");
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
