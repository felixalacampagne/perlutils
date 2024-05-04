#!/usr/bin/perl
use strict;
use warnings;
use Data::Dumper;
#use File::Copy;
use File::Spec;
use File::Basename; # for fileparse

# use Win32::FileOp; # cpanm --force Win32::FileOp # doesn't work


# NB. Win32::FileOp did not work
# Found the following at https://www.perlmonks.org/?node_id=11153833 which is apparently
# a fixed version of what is in Win32::FileOp 
# It probably belongs in the SCUWin package
use Win32::API;


sub sendToRecycleBin 
{
my $FO_DELETE          = 0x03;
my $FOF_SILENT         = 0x0004; # don't create progress/report
my $FOF_NOCONFIRMATION = 0x0010; # Don't prompt the user.
my $FOF_ALLOWUNDO      = 0x0040; # recycle bin instead of delete
my $FOF_NOERRORUI      = 0x0400; # don't put up error UI

  # a series of null-terminated pathnames, with a double null at the end
  my $paths = join "\0", @_, "\0";
    
  my $recycle = new Win32::API('shell32', 'SHFileOperation', 'P', 'I');
  my $options = $FOF_ALLOWUNDO | $FOF_NOCONFIRMATION | $FOF_SILENT | $FOF_NOERRORUI;
    
  # for everything except paths and options, pack with Q (rather than L), since we're using 64-bit perl
  # my $opstruct = pack ('LLpLILLL', 0, FO_DELETE, $paths, 0, $options, 0, 0, 0);
  my $opstruct = pack ('QQpQIQQQ', 0, $FO_DELETE, $paths, 0, $options, 0, 0, 0);

  return $recycle->Call($opstruct);
}

# Input: a command line wildcard file pattern specification. The pattern can include directories
# but should only have wildcard specifiers in the filename part, eg.
# *.bak
# tmp\*.bak
# ..\*.bak
# c:\tmp\*.bak
# The file search is NOT recursive, only the directory indicated is searched.
# Note that the pattern is NOT a regex pattern.
sub recycleFiles
{
my $ME="recycleFiles: ";
my ($filepat) = @_;
my $fullpathspec = File::Spec->rel2abs($filepat);
printf("$ME: abs path: %s\n", $fullpathspec);

	my @files = glob($fullpathspec);
  foreach my $file (@files)
  {
  	my $delpath = $file;  # File::Spec->catdir($dir, $file);
  	printf("$ME: recycling file %s\n", $delpath);
  	sendToRecycleBin $delpath;
	}
}



# Take a pathname with a wildcard filename specification.
if( @ARGV < 1)
{
	print "Usage: rcyclf <wildcard file pattern to send to recycle bin>\n";
	exit;
}

my $arg0 = $ARGV[0];
printf "Deleting %s\n", $arg0;
recycleFiles $arg0;
