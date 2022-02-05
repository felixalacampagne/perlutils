#!/usr/bin/perl
#
use strict;
use warnings;

# Function: logmsg
# Parameters: <log level / keyword>, <printf fmt>, [printf args]
# Change $LOG_LEVEL to adjust the level of messages output
# NB. log keywords are always output unless  $LOG_LEVEL is
# set to LOG_SILENT.
#

use constant { LOG_SILENT => -1, LOG_ALWAYS => 10, LOG_FATAL => 20, LOG_ERROR => 30, LOG_INFO => 40, LOG_DEBUG => 50, LOG_TRACE => 60};
# NB 'use constant' creates subroutines (WTF???) so "x,y" must be used in the map instead of the normal "x=>y".
my %LOG_LABELS = ( LOG_ALWAYS, "ALWAYS", LOG_FATAL, "FATAL", LOG_ERROR, "ERROR", LOG_INFO, "INFO", LOG_DEBUG, "DEBUG", LOG_TRACE, "TRACE");
my $LOG_LEVEL=LOG_ERROR; 
sub logmsg
{
my $keyword = shift;
my $fmt = shift;
my $msg = "";

   no warnings "numeric";
   if(int($keyword) <= $LOG_LEVEL)
   {
      $msg = sprintf($fmt, @_);
      if(($keyword == LOG_ERROR) || ($keyword == LOG_FATAL))
      {
         my @call_details = caller(0);
         my $callerfunc = $call_details[3];
         my $callerline = $call_details[2];
         
         print sprintf("%-8s: %s.%04d: %s",($LOG_LABELS{$keyword}//$keyword), $callerfunc, $callerline, $msg);
      }
      else
      {
         print sprintf("%-8s: %s",($LOG_LABELS{$keyword}//$keyword), $msg);
      }
   }
   return $msg;
}

###############################################################
###############################################################
####                    #######################################
#### tests and examples #######################################
####                    #######################################
###############################################################
###############################################################

logmsg(LOG_ALWAYS, "Simple message no args\n");
logmsg(LOG_FATAL, "Format with one string arg: %s\n", "This is the arg");
logmsg(LOG_ERROR, "Format with one string and one number: %s - %02d\n", "STRING", 7);
logmsg("IGNR", "User keyword and format with one number (%04d), one string (%s) and one number: %2d\n", 4, "STRING", 7);
my $kw = "REPLACE";
logmsg($kw, "Another user keyword and format with one number (%04d), one string (%s) and one number: %2d\n", 4, "STRING", 7);

$LOG_LEVEL=LOG_SILENT;
logmsg("IGNR", "Message should not appear: User keyword and format with one number (%04d), one string (%s) and one number: %2d\n", 4, "STRING", 7);
$LOG_LEVEL=LOG_INFO;
die( logmsg(LOG_FATAL, "Message in a die statement: %s\n", "This is the arg"));
my @keys = keys %LOG_LABELS;
my @values = values %LOG_LABELS;
while (@keys) 
{
   print pop(@keys), '=', pop(@values), "\n";
}