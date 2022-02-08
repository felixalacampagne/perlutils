#!/usr/bin/perl

# Usage: iambusy.pl -s <mins> -t <mins> -i 
#           -s period to sleep (minutes) after ES_SYSTEM_REQUIRED
#           -t total period (minutes) over which to issue the ES_SYSTEM_REQUIREDs
#           -i don't issue the ES_SYSTEM_REQUIREDs (don't remember why I wanted this)
# To keep the machine awake the ES_SYSTEM_REQUIREDs must be issued within the sleep timeout
# of the current power saving profile, ie.
# to keep machine awake for 3 hours, when the sleep time is 10mins use a command like
#  iambusy -s 5 -t 180

use strict;

use FindBin;           # This should find the location of this script
use lib $FindBin::Bin . '/lib'; # This indicates to look for modules in the script location
use FALC::SCUWin;
use Getopt::Long;
Getopt::Long::Configure("pass_through", "bundling_override");
       


my $title="No title";

# Params in minutes
GetOptions('title|t=s' => \$title);

settitle($title);

exit 0;

