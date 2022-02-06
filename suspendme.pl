#!/usr/bin/perl
# 30-04-2018 Raises a custom Windows event shortly before forcing sleep. This allows a
#            Task with elevated privileges to be executed by triggering on the event. The primary
#            use of this is to remove the "wake to run" flag from the Microsoft tasks which are
#            probably the cause of the Internet radio turning on in the middle of the night. The
#            windows "going to sleep" event does not work in a trigger - apparently because it is 
#            only logged when the computer wake up!
# 30-05-2017 Windows has broken sleep and Task Scheduler wont wake up when "rundll32.exe powrprof.dll,SetSuspendState 0,0,0"
#            is used to send the machine to sleep (this is probably because rundll32 does not pass the parameters to the function
#            as one would expect from the command line, according to Google, resulting in the SetSuspendState being called with the
#            'no wake timers' flag set to true). This is therefore my attempt to workaround this by using Perl to send the machine
#            to sleep so it can be woken up by Task Scheduler to run my tasks...

# Usage: suspendme -s <mins>
#           -s period to wait (minutes) before 'suspending' 

use strict;
use Win32::API;
use Win32::EventLog;
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
   print "suspendme: System will be suspended at $ts";
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
# This only gets printed AFTER the resume from sleep
# BUT might be useful in case the sleep is not working...
print "suspendme: Done at $ts\n";
exit(0);


sub writeeventlog {
my ($id, $msg) = @_;
   
   my $eventLog = Win32::EventLog->new('Application');

   my %eventRecord = (
           #'Computer' => undef,
           'Source' => 'SmallCatUtilities',
           'EventType' => EVENTLOG_INFORMATION_TYPE,
           'Category' => 0, #NULL,
           'EventID' => $id,
           'Strings' => $msg,
           'Data' => 'Data: This does not appear in the event log',
           );

   $eventLog->Report(\%eventRecord);
   $eventLog->Close();
}
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
my $ts;
   # Unfortunately this does not work with the Perl available at "some sites" - I guess I am using
   # a version which is too uptodate
   #my $SetThreadExecutionState = Win32::API::More->new('kernel32', 'SetThreadExecutionState', 'N', 'N');
   
   # This version of the command doesn't give an error with AS Perl 5.14.
   my $SetSuspendState = new Win32::API('PowrProf', 'SetSuspendState', 'III', 'I');
   if (defined $SetSuspendState) 
   {
      # The event can be used to execute a pre-sleep action requiring elevated permissions
      # without the UAC popup by configuring a Task to trigger on the event.
      writeeventlog(1961, "suspendme: System sleep notification.");
      
      # Give the event handler time to perform its actions
      sleep 10;
      $ts = time2date(time());
      print "suspendme: Sending system to sleep at $ts\n";
      my $rc = $SetSuspendState->Call($BOOLEAN_Hibernate, $BOOLEAN_ForceCritical, $BOOLEAN_DisableWakeEvent);
   }
   else
   {
      print "ERROR: suspendme: SetSuspendState did NOT load!!  \n";
   }
}   
