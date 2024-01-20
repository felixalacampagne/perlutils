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
use Win32::API;
use Getopt::Long;

Getopt::Long::Configure("pass_through", "bundling_override");


sub SetMouseSpeed
{
my $MouseSpeed = shift;
use constant SPI_SETMOUSESPEED => 113;  # 0x0071
use constant SPI_GETMOUSESPEED => 112;
use constant SPIF_SENDCHANGE => 0x0002;
use constant SPIF_SENDWININICHANGE => 0x0002;
use constant SPIF_UPDATEINIFILE => 0x001;

# BOOL SystemParametersInfo(UINT uiAction, UINT uiParam, PVOID pvParam, UINT fWinIni);
my $SystemParametersInfo = new Win32::API("user32", "SystemParametersInfo", 'IIPI', 'I') || die;
my $SystemParametersInfoW = new Win32::API("user32", "SystemParametersInfo", 'IINI', 'I') || die;
my $result = 0;


   if ( $MouseSpeed != 0) 
   {
      # print "Set mouse speed to $MouseSpeed\n";
      # SPI_GETMOUSESPEED requires a pointer for the 3rd parameter but SPI_SETMOUSESPEED requires
      # a UINT. I couldn't figure out how to send the UINT using the same object as used for SPI_GETMOUSESPEED, ie.
      # using 'P', ie. a pointer, as the third parameter, no matter what sort of pack command was used.
      # Creating a second object which uses 'I' or 'N' as the third param and sending the regular Perl variable
      # actually seems to change the mouse speed setting in 'Settings'.
      $result = $SystemParametersInfoW->Call(SPI_SETMOUSESPEED, 0x00, $MouseSpeed, SPIF_UPDATEINIFILE | SPIF_SENDCHANGE); # || SPIF_SENDWININICHANGE);
   }   

   my $mArray = pack('I1', 0);
   $result = $SystemParametersInfo->Call(SPI_GETMOUSESPEED, 0x00, $mArray, 0x00);
   my ($LS_A) = unpack('I1',$mArray);

   print "Mouse speed is: $LS_A\n";
}

my $mspeed=0;

# Params in minutes
GetOptions('speed|s=i' => \$mspeed);


SetMouseSpeed($mspeed);

exit 0;

