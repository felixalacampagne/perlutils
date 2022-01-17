use strict;
use warnings;
use Win32::Clipboard;

use Getopt::Std;


###############################################################
###############################################################
####                    #######################################
#### Main program       #######################################
####                    #######################################
###############################################################
###############################################################
# Wanted to do this with JScript, since it is native, but the 
# only way to get at the clipboard that I came across is to
# use IE and it's DOM!
my $clip;
my $cliptxt;
my $cliptxtorig;
$clip = Win32::Clipboard();

$cliptxtorig = $clip->Get();
$cliptxt = $cliptxtorig;

print "$cliptxt";