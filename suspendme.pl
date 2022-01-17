#!/usr/bin/perl
# 30-05-2017 Windows has broken sleep and Task Scheduler wont wake up when "rundll32.exe powrprof.dll,SetSuspendState 0,0,0"
#            is used to send the machine to sleep (this is probably because rundll32 does not pass the parameters to the function
#            as one would expect from the command line, according to Google, resulting in the SetSuspendState being called with the
#            'no wake timers' flag set to true). This is therefore my attempt to workaround this by using Perl to send the machine
#            to sleep so it can be woken up by Task Scheduler to run my tasks...

# Usage: suspendme -s <mins>
#           -s period to wait (minutes) before 'suspending' 

use strict;
use Win32::API;
use Getopt::Long;
use Time::Seconds;
Getopt::Long::Configure("pass_through", "bundling_override");
       


my $sleep=-1;
my $idle=0;
my $totsleep=-1;

# Params in minutes
GetOptions('sleep|s=i' => \$sleep);

# Convert to seconds
$totsleep *= 60;
$sleep *= 60;
my $ts;
my $startsecs = time();

if($sleep > 0)
{
   $ts = time2date($startsecs + $sleep);
   print "System will be suspended at $ts";
}

my $elapsed=0;
$|=1;
my $remain;

   if($sleep > 0)
   {
      sleep $sleep;
      print "\n";
   }

   niteynitey();
   
$ts = time2date(time());
print "Done at $ts\n";
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
sub niteynitey
{
   my $BOOLEAN_Hibernate = 0;
   my $BOOLEAN_ForceCritical = 0;
   my $BOOLEAN_DisableWakeEvent = 0;
   # Unfortunately this does not work with the Perl available at "some sites" - I guess I am using
   # a version which is too uptodate
   #my $SetThreadExecutionState = Win32::API::More->new('kernel32', 'SetThreadExecutionState', 'N', 'N');
   
   # So this version of the command doesn't give an error with AS Perl 5.14. I have no idea whether
   # it works (the other form does stop sleep from occurring) - that needs to be tested in a sleep prone
   # environment :-)
   my $SetSuspendState = new Win32::API('PowrProf', 'SetSuspendState', 'III', 'I');
   if (defined $SetSuspendState) 
   {
      # This should just reset the idle timer back to zero
      #print "Calling SetThreadExecutionState with 'System Required'\n";
      my $rc = $SetSuspendState->Call($BOOLEAN_Hibernate, $BOOLEAN_ForceCritical, $BOOLEAN_DisableWakeEvent);
      #print "'System Required' sent... ";
   }
   else
   {
      print "ERROR: SetSuspendState did NOT load!!  ";
   }
}   
