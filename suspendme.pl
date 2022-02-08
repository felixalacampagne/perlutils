#!/usr/bin/perl

# Usage: suspendme.pl -s <mins>
#           -s period to wait (minutes) before 'suspending' 

use strict;
use FindBin;           # This should find the location of this script
use lib $FindBin::Bin . '/lib'; # This indicates to look for modules in the script location
use FALC::SCUWin;
use Getopt::Long;

Getopt::Long::Configure("pass_through", "bundling_override");
       
my $sleep=-1;

# Params in minutes
GetOptions('sleep|s=i' => \$sleep);

suspendme($sleep);
exit 0;