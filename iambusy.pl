#!/usr/bin/perl
# 10-07-2015 Tweaked output
# 08-07-2015 Added the total sleep time option so an external script is not required to keep calling
#            iambusy in order to keep the machine awake. 

# Usage: iambusy -s <mins> -t <mins> -i 
#           -s period to sleep (minutes) after ES_SYSTEM_REQUIRED
#           -t total period (minutes) over which to issue the ES_SYSTEM_REQUIREDs
#           -i don't issue the ES_SYSTEM_REQUIREDs (don't remember why I wanted this)
# To keep the machine awake the ES_SYSTEM_REQUIREDs must be issued within the sleep timeout
# of the current power saving profile, ie.
# to keep machine awake for 3 hours, when the sleep time is 10mins use a command like
#  iambusy -s 5 -t 180

use strict;
use Win32::API;
use Getopt::Long;
use Time::Seconds;
Getopt::Long::Configure("pass_through", "bundling_override");
       


my $sleep=-1;
my $idle=0;
my $totsleep=-1;

# Params in minutes
GetOptions('sleep|s=i' => \$sleep,
           'idle|i' => \$idle,
           'total|t=i' => \$totsleep);

# Convert to seconds
$totsleep *= 60;
$sleep *= 60;
my $ts;
my $startsecs = time();

if($totsleep>0)
{
   # If a total sleep is specified make sure the "poll" interval
   # is sensible
   if($sleep < 1)
   {
      $sleep = $totsleep / 10;
      # Probably a better way to do this...
      if($sleep < 1)
      {
         $sleep = 1;
      }
   }

   $ts = time2date($startsecs + $totsleep);
   print "Preventing computer sleep until $ts";
}
elsif($sleep > 0)
{
   $ts = time2date($startsecs + $sleep);
   print "Sleeping until $ts";
}

my $elapsed=0;
$|=1;
my $remain;
do
{
   if($idle == 0)
   {
      wakeywakey();
   }

   if($sleep > 0)
   {
      sleep $sleep;
   }

   $elapsed = (time() - $startsecs);
   
   if($elapsed<$totsleep)
   {
      $remain = secs2dhms($totsleep - $elapsed);
      print "\nRemaining busy time: " . $remain;
   }
}until($elapsed>$totsleep);

$ts = time2date(time());
print "\nDone at $ts\n";
exit(0);
# Can't seem to find a standard Perl way to output a time in a readable format
sub time2date
{
my ($epochsecs) = @_;
my @dateparts = localtime($epochsecs);
my @nowparts = localtime(time());
my $ts;
   if(($dateparts[3]==$nowparts[3]) &&
      ($dateparts[4]==$nowparts[4]) &&
      ($dateparts[5]==$nowparts[5]))
   {
      # If the time is today then don't print the date part
      $ts = sprintf("%02d:%02d", $dateparts[2], $dateparts[1]);     
   }
   else
   {
      $ts = sprintf("%02d:%02d %02d-%02d-%04d", $dateparts[2], $dateparts[1],
                                             $dateparts[3], $dateparts[4]+1, 
                                             $dateparts[5]+1900);     
   }
   return $ts;
}

# Alas! No standard Perl way to print a number seconds in H:M:S format
sub secs2dhms
{
my ($sec) = @_;
my $days;
my $hours;
my $mins;
my $retval;
my $fmt;
$days = int($sec/(24*60*60));
$hours = ($sec/(60*60))%24;
$mins = ($sec/60)%60;
$sec = $sec%60;

   $fmt = "%02dh%02dm%02ds";
   if($days != 0)
   {
      $retval = sprintf("%dd ". $fmt, $days, $hours, $mins, $sec);
   }
   elsif($hours != 0)
   {
      $retval = sprintf($fmt, $hours, $mins, $sec);
   }
   elsif($sec == 0)
   {
      $retval = sprintf("%02dm", $mins);
   }
   else
   {
      $retval = sprintf("%02dm%02ds", $mins, $sec);
   }
   
   return $retval;

}
sub wakeywakey
{
   # Want to use EXECUTION_STATE WINAPI SetThreadExecutionState(_In_  EXECUTION_STATE esFlags);
   my $ES_SYSTEM_REQUIRED = 1;
   my $ES_DISPLAY_REQUIRED = 2;
   my $ES_USER_PRESENT = 4;
   my $ES_CONTINUOUS = 0x80000000;
   
   # Unfortunately this does not work with the Perl available at "some sites" - I guess I am using
   # a version which is too uptodate
   #my $SetThreadExecutionState = Win32::API::More->new('kernel32', 'SetThreadExecutionState', 'N', 'N');
   
   # So this version of the command doesn't give an error with AS Perl 5.14. I have no idea whether
   # it works (the other form does stop sleep from occurring) - that needs to be tested in a sleep prone
   # environment :-)
   my $SetThreadExecutionState = new Win32::API('kernel32', 'SetThreadExecutionState', 'N', 'N');
   if (defined $SetThreadExecutionState) 
   {
      # This should just reset the idle timer back to zero
      #print "Calling SetThreadExecutionState with 'System Required'\n";
      my $rc = $SetThreadExecutionState->Call($ES_SYSTEM_REQUIRED);
      #print "'System Required' sent... ";
   }
   else
   {
      print "ERROR: SetThreadExecutionState did NOT load!!  ";
   }
}   
