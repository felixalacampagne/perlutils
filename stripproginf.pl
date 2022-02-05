use 5.010;  # Available since 2007, so should be safe to use this!!
use strict;
use IO::Handle;
#use Data::Dumper;
use Digest::MD5;
use File::Spec;
use File::Basename;
use File::Temp qw/ tempfile tempdir /;
use File::Copy;
use Date::Calc qw(Today_and_Now Delta_DHMS);
use Cwd;
use Encode;
use Getopt::Std;
use Win32::API;


my $startdir = "";

if( @ARGV > 0)
{
   $startdir = $ARGV[0];
}

if($startdir eq "")   # ie. nothing specified on command line
{
	$startdir = File::Spec->curdir();
	$startdir = File::Spec->rel2abs(File::Spec->curdir());
}
else
{
	$startdir = File::Spec->rel2abs($startdir);
}

if( -d $startdir )
{
   processDir($startdir);
}

############## End of prog
sub processDir
{
my ($curdir) = @_;
my @subdirs;
my @md5files;
my @files;
my $dh;
my $fullfile;

my $pat=/^\d{8} \d{4} \- .*? \- (.*$)(\..*)$/;
   # Open the directory and read everything (sub-dirs and files) except the "." and ".."
   # Note that the names will not have path information on them
   print "Processing $curdir\n";
   unless (opendir $dh, $curdir)
   {
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
         # Ignore directories
      }
      elsif( $file =~ m/^\d{8} \d{4} \- .*? \- (.*)(\..*)$/ ) 
      {
         my $newname = $1;
         my $ext = $2;
         print "Found a file to rename: $file: name=" . $newname . ", ext= " . $ext . "\n";
         if($newname =~ m/^(.*)\.\[\d\]$/)
         {
            $newname = $1;
            print "Removing smartcut version number: $newname\n";
         }
         $newname =~ s/\s{2,}/ /g;
         $newname = $newname . $ext;
         print "Rename $file to $newname\n";
         move($file, $newname);
      }
   }
}