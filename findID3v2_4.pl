#!/usr/bin/perl
# I mistakenly directed syncmd5 to copy the mp3 files to the flac backup directory.
# Using "dir /s /q *.mp3" removed the files but the partially empty directories
# still remain - there are alot of directories and checking each and then deleting
# it and rescrolling to the next is very time consuming.
# So this silly little script generates the command to delete directories which dont 
# contain any media files. The number in brackets is the number of non-media files - 
# check it to ensure a genuine directory is not being deleted....


use strict;
use IO::Handle;
use Data::Dumper;
use Digest::MD5;
use File::Spec;
use File::Basename;
use Cwd;
use Encode;
use Getopt::Std;
use Term::ReadKey;
use IO::File;
use utf8;
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
my $verbose = 0;
my $logtofile = 0;
my $pauseonexit = 0;
my $logfh;
my $logfilename;
my %opts;

getopts('vlp', \%opts);

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


# The options are removed from argv which leaves just the directory.
# This makes it possible to specify multiple directories on the command line
# which would be handy for specifying mp3, flac and alac in one script.
# Need to decide if the log files should go in each directory...
if( @ARGV > 0)
{
   $startdir = $ARGV[0];
}

if($startdir eq "")
{
	$startdir = File::Spec->curdir();
}
else
{
	
   # It could be that an MD5 file was double-clicked on, in which case the argument
   # is the full path of the md5.   
	# So test for folder.md5 
	my ($filename,$directories,$suffix) = fileparse( $startdir );
	if($filename =~ m/folder\.md5/i)
	{
	   # remove the filename - the check is automatic if there is a folder.md5 present
	   $startdir = $directories;
	   
      # In this case it is handy to have logging and pauseonexit enabled 
	   $logtofile = 1;
	   $pauseonexit = 1;
	}
}

if ( $logtofile == 1 )
{
   my @now = localtime();
   my $ts = sprintf("%04d%02d%02d%02d%02d", 
                        $now[5]+1900, $now[4]+1, $now[3],
                        $now[2],      $now[1]);
   $logfilename = File::Spec->catdir($startdir, "findempty_" . $ts . ".log");
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

do
{
   $startdir = File::Spec->rel2abs($startdir);
   print "Processing directory: $startdir\n";
   processDir($startdir);
   shift @ARGV;
   $startdir = $ARGV[0];
   
} while(length $startdir > 0);

# If $logfh is initialized to a known value the open command complains
# so 'defined' seems to be the way to check whether the variable was
# initialized.
if ( defined $logfh )
{
   close($logfh);
}
select STDOUT;

print "Total directories check:            " . getTotdirs() . "\n"; 
print "Total mp3 files checked:            " . getTotMP3files() . "\n"; 
print "Total mp3 files with unsync tag:    " . getUnyncfile() ."\n";
print "Total directories with unsync tags: " . getTotUnyncdirs() ."\n";
print "Total mp3 files with no tag:        " . getNoTAG() . "\n";

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
######################################################################
######################################################################
#######               ################################################
#######  End of main  ################################################
#######               ################################################
######################################################################
######################################################################

sub checkID3
{
my ($mp3file) = @_;
my $minorver;
my $buf;
my $flags;
my $majorver;
my $rawsize;
my $tagsize;
my $return = "";
my $isunsync = 0;
my $id3 = "";
   # MP3::Tag doesn't indicate whether unsync is applied to the tag so
   # have to do it the "hard" way
   my $fh = new IO::File($mp3file, 'r') or die("open failed on $mp3file : $!\n");
   $fh->binmode;
   my $len;
   
   # Get ID3
   #$len = 3;
   $len = 6;
   $fh->read($buf, $len);
   ($id3, $majorver, $minorver, $flags) = unpack("a3 C C C", $buf);
   

   if($id3 eq "ID3")
   {
      $isunsync = (($flags & 0x80) > 0) ? 1 : 0;
      if($isunsync > 0)
      {
         # printf("INFO   : ID3v2.%02X : unsync=%02x (%s): %s\n", $majorver, $flags, $isunsync, $mp3file);
         $return = $mp3file;
         incUnyncfile();
      }
      
      # The tag size does not include the size of the header (10bytes) but does include
      # any padding bytes, extended header etc.
      # The MP3 audio data starts at offset "$tagsize+10".
      # Could use this for generating an CRC/MD5 of the audio data to verify that it is not
      # corrupted during the de-unsyncing, but I really don't think I care that much about it
      # since the unsynced files appear to be the one I created from FLACs.
      $len = 4;
      $fh->read($buf, $len);
      foreach my $b (unpack("C4", $buf)) 
      {
   	   $tagsize = ($tagsize << 7) + $b;
      }
      #printf("INFO   : TAG size=0x%05X (0x%05X): %s\n", $tagsize, $tagsize+10, $mp3file);
      
      $fh->seek($tagsize,SEEK_CUR);
      $len = 4;
      $fh->read($buf, $len);
      my @b = unpack("C4", $buf);
      if($b[0] != 0xFF)
      {
         if($return ne "")
         {
            $return = $mp3file;
            incUnyncfile();
         }
         #printf("ERROR  : Invalid MP3 frame at 0x%05X (0x%05X): 0x%02X 0x%02X 0x%02X 0x%02X: %s\n", 
         #   $tagsize, $tagsize+10, $b[0], $b[1], $b[2], $b[3], $mp3file);
      }
      #else
      #{
      #   printf("INFO   : Found start of MP3 data 0x%02X 0x%02X 0x%02X 0x%02X: %s\n",          
      #     $b[0], $b[1], $b[2], $b[3], $mp3file);
      #}
   }
   else
   {
      print "WARNING: ID3 tag not found at start of file: " . $mp3file . "\n";
      incNoTAG();
   }
   
   
   
   $fh->close();
   return $return;   
}


sub processDir
{
my ($curdir) = @_;
my @subdirs;
my @matchedfiles;
my @files;
my @checked;
my @sorted;
my $dh;
my $fullfile;


   incTotdirs();
   opendir $dh, $curdir or die "Couldn't open dir '$curdir': $!";
   @files = grep { !/^\.\.?$/ } readdir $dh;
   closedir $dh;

   foreach my $file (@files)
   {
      $fullfile = File::Spec->catdir($curdir,$file);
      if( -d $fullfile )
      {
         push(@subdirs, $fullfile);
      }
      elsif( $file =~ m/.*\.(mp3)$/i )
      {
         push(@matchedfiles, $file);
         incTotMP3files();
      }
   }

   # Process files first, sub-dirs
   @sorted = sort @matchedfiles;
   foreach my $file (@sorted)
   {
      my $id3file = checkID3(File::Spec->catdir($curdir,$file));
      if($id3file ne "")
      {
         push(@checked, $id3file);
      }
   }
   
   if(@checked > 0)
   {
      print "Unsynced: " . $curdir . "\n";
      incTotUnyncdirs()
   }
   
   @sorted = sort @subdirs;
   foreach my $subdir (@sorted) 
   {
      processDir($subdir);
   }
   return;
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

# Statistics tracking stuff - wanted to create a 'class'
# but it has to be in a different file and one reason for
# the perl script is to avoid needing additional files

# Silly little functions to avoid referring to the counters
# directly in the code.
sub incTotdirs { $counters{"dirs"}++; }
sub getTotdirs { return $counters{"dirs"}; }
sub incTotUnyncdirs { $counters{"md5dirs"}++; }
sub getTotUnyncdirs { return $counters{"md5dirs"}; }

sub incTotMP3files { $counters{"calcmd5"}++; }
sub getTotMP3files { return $counters{"calcmd5"}; }
sub incNoTAG { $counters{"chkmd5"}++; }
sub getNoTAG { return $counters{"chkmd5"}; }
sub incTotfailmd5dir { $counters{"failmd5dir"}++; }
sub getTotfailmd5dir { return $counters{"failmd5dir"}; }
sub incUnyncfile 
{ 
  my ($increment) = @_;
  if(! defined($increment) ) {
   $counters{"failmd5file"}++; 
  } else {
   $counters{"failmd5file"} += $increment; 
  }
}
sub getUnyncfile { 
   return $counters{"failmd5file"}; 
}
