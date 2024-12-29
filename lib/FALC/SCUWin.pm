#!/usr/bin/perl
# 07-07-2024 clean iambusy logging for -ve total wait
# 24-04-2022 extra iambusy debug logging
# 08-02-2022 iambusy and suspendme code moved into a Perl module for easier access from other Perl scripts.
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

package FALC::SCUWin; 
use strict;
use warnings;

#use vars qw(@ISA @EXPORT $VERSION); # Old way of doing it

# This construction is apparently preferred and more robust for recursion,or something
our (@ISA, @EXPORT, $VERSION); # NB This DOES require commas
BEGIN 
{
require Exporter;
$VERSION = 0.9;
@ISA = qw(Exporter);
@EXPORT = qw(suspendme settitle iambusy);  # NB NOT comma separated!!
}

use Win32::API;
use Win32::EventLog;
use Win32::Console;
use Time::Seconds;
use FALC::SCULog;

my $LOG = FALC::SCULog->new();

# suspendme( delayMins )
#
# Suspend the system after a delay of delayMins minutes. delayMins=0 for no delay
sub suspendme # ( delayInMins )
{
my ($sleep) = @_;

# Convert to seconds
$sleep *= 60;
my $ts;
my $startsecs = time();

   if($sleep > 0)
   {
      $ts = time2date($startsecs + $sleep);
      $LOG->info("suspendme: System will be suspended at $ts\n");
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
   $LOG->info("suspendme: Done at $ts\n");
}

# sleepInMins     - delay before issuing busy signal (-1 : no delay)
# totalBusyInMins - totla time to keep system busy (-1: return after issuing busy signal) 
# idleOnly        - 0: issue busy signals, 1: delay only , no busy signals
sub iambusy # ( sleepInMins, totalBusyInMins, idleOnly )
{
my ($sleep, $totsleep, $idle)  = @_;
my $ts;
my $startsecs = time();
   # Convert to seconds
   $totsleep *= 60;
   $sleep *= 60;
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
      $LOG->info("iambusy: Preventing computer sleep until $ts\n");
   }
   elsif($sleep > 0)
   {
      $ts = time2date($startsecs + $sleep);
      $LOG->info( "iambusy: Sleeping until $ts\n");
   }
   
   my $elapsed=0;
   $|=1;
   my $remain;
   do
   {
      if($idle == 0)
      {
         $LOG->debug("iambusy: busy signal\n");
         wakeywakey();
      }
   
      if($sleep > 0)
      {
         $LOG->debug("iambusy:sleep for $sleep\n");
         sleep $sleep;
      }
   
      $elapsed = (time() - $startsecs);
      if($totsleep > 0)
      {
	      $remain = secs2dhms($totsleep - $elapsed);
	      $LOG->info("iambusy: Remaining busy time: " . $remain . "\n");
	      if($elapsed >= $totsleep)
	      {
	         $LOG->debug("iambusy: target time exceeded, no more waiting to do\n");   
	      }
    	}
   }until($elapsed >= $totsleep);
   
   $ts = time2date(time());
   $LOG->info("iambusy: Done at $ts\n");
}

sub settitle
{
my $title = shift;
my $CONSOLE=Win32::Console->new;
   $CONSOLE->Title($title);
}

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
      $LOG->info( "niteynitey: Sending system to sleep at $ts\n");
      my $rc = $SetSuspendState->Call($BOOLEAN_Hibernate, $BOOLEAN_ForceCritical, $BOOLEAN_DisableWakeEvent);
   }
   else
   {
      $LOG->error("niteynitey: SetSuspendState did NOT load!!  \n");
   }
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
;1 # needed to avoid 'FALC/SCUWin.pm did not return a true value'