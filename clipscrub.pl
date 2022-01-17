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
my $clip;
my $cliptxt;
my $cliptxtorig;
$clip = Win32::Clipboard();

$cliptxtorig = $clip->Get();
$cliptxt = $cliptxtorig;
$cliptxt =~ s/[\/\+ ]//g;

$clip->Set($cliptxt);

print "Orig: $cliptxtorig   Scrubbed: $cliptxt\n";