package FALC::SCULog;
# (c) felixalacampagne 2022
use strict;
use warnings;
#use vars qw($VERSION);
our $VERSION;
$VERSION = 1.0;
{
# 03 Nov 2014 Updated with stacktrace output for errors.
use Devel::StackTrace;
use Date::Calc qw(Today_and_Now Delta_DHMS);
# This seems to work OK in the class. To use the constans to set the level
# the syntax is like '$log->level(FALC::SCULog->LOG_DEBUG);'
use constant { LOG_SILENT => -1, LOG_ALWAYS => 10, LOG_FATAL => 20, LOG_ERROR => 30, LOG_WARN=>40 ,LOG_INFO => 50, LOG_DEBUG => 60, LOG_TRACE => 70};

# This does appear to be shared between the instances of the class
# but initializing it at the class level does not work. It is the same for simple
# scalar values initialized here. The init must be done in the constructor (ie. new())
# but it only needs to be done once.
my %LOG_LABELS;
my $logfh = -1;
my $sculogSingleton;
sub new
{
   # Init the class variables, this only has to be done once
   # but it doesn't work when done at the class level.
   if( ! defined $sculogSingleton )
   {
      if(!%LOG_LABELS)
      {
         # print "Initialising LOG_LABELS: " . %LOG_LABELS . "\n";
         %LOG_LABELS = ( LOG_ALWAYS, "ALWAYS", LOG_FATAL, "FATAL", LOG_ERROR, "ERROR", LOG_WARN, "WARNING", LOG_INFO, "INFO", LOG_DEBUG, "DEBUG", LOG_TRACE, "TRACE");
      }
      # print "LOG_LABELS initialised to: " . %LOG_LABELS . "\n";
      # The class is supplied as the first parameter
      # Not sure what it is used for!!!
      my $class = shift;
      my $self = {};  # this becomes the "object", in this case an empty anonymous hash
      bless $self;    # this associates the "object" with the class
   
      $self->level(LOG_INFO);
      $self->logfile(-1);
      $self->{"_LOG_LABELS"} = \%LOG_LABELS;
      $self->logtime(-1);
      
      $sculogSingleton = $self;
   }
   return $sculogSingleton;
}

sub logmsg
{
my $self = shift;
my $keyword = shift;
my $fmt = shift;
my $msg = "";
my $level;
my $logfh = $self->logfile;
my $ts = "";
   no warnings "numeric";

   # Does this work? Can I just use Level()? How do I know if the first parameter is
   # "self" or a level value??
   $level = $self->level;

   my %labels = %{$self->{"_LOG_LABELS"}};

   if(int($keyword) <= $level)
   {
      my $output;
      
      if($self->islogtime)
      {
         $ts = $self->timestamp . " ";
      }
      
      $msg = sprintf($fmt, @_);
      if(($keyword == LOG_ERROR) || ($keyword == LOG_FATAL))
      {
         # NB. The frame subroutine value refers to the subroutine being called (an SCULog method normally) at line X in package Y.
         # Therefore need frame(X-1)->subroutine to know who is doing the calling.
         my $trace = Devel::StackTrace->new(ignore_class => 'SCULog');
         my $frame;

         # Get the package and line info
         $frame = $trace->next_frame;
         my $calledfunc = $frame->subroutine;  # Method being called at line X
         my $callerline = $frame->line;
         my $callerpackage=$frame->package;

         # Get the function doing the calling at line X
         $frame = $trace->next_frame;
         my $callerfunc = $frame->subroutine;
         $output = sprintf("%s%-8s: %s(%04d): %s", $ts, ($LOG_LABELS{$keyword}//$keyword), $callerfunc, $callerline, $msg);
      }
      else
      {
         $output = sprintf("%s%-8s: %s", $ts,($labels{$keyword}//$keyword), $msg);
      }
      $!=1;
      print $output;
      if($logfh != -1)
      {
         print $logfh $output
      }
   }
   return $msg;
}


sub timestamp
{
my $self = shift;
my @starttime;

if(@_ > 0)
{
   @starttime = @_;
}
else
{
   @starttime = Today_and_Now();
}

#my $nowstr = sprintf("%04d.%02d.%02d %02d:%02d:%02d", $starttime[0],$starttime[1],$starttime[2],$starttime[3],$starttime[4],$starttime[5]);
my $nowstr = sprintf("%02d.%02d %02d:%02d:%02d",$starttime[1],$starttime[2],$starttime[3],$starttime[4],$starttime[5]);

return $nowstr;
}

sub islevel
{
my $self = shift;
my $testlevel = shift;
my $curlevel = $self->level;

   return (int($testlevel) <= $curlevel);
}

sub level
{
my $self = shift;

   if(@_)
   {
      $self->{level} = shift;
   }
   return $self->{level};
}

sub logtime
{
my $self = shift;

   if(@_)
   {
      $self->{logtime} = shift;
   }
   return $self->{logtime};
}

sub islogtime
{
my $self = shift;
my $curlevel = $self->logtime;

   return (-1 == $curlevel);
}

sub logfile
{
my $self = shift;

   if(@_)
   {
      $self->{logfile} = shift;
   }
   return $self->{logfile};
}


sub always
{
my $self = shift;
   $self->logmsg(LOG_ALWAYS, @_);
}

sub fatal
{
my $self = shift;
   $self->logmsg(LOG_FATAL, @_);
}

sub error
{
my $self = shift;
   $self->logmsg(LOG_ERROR, @_);
}

sub warn
{
my $self = shift;
   $self->logmsg(LOG_WARN, @_);
}

sub info
{
my $self = shift;
   $self->logmsg(LOG_INFO, @_);
}

sub debug
{
my $self = shift;
   $self->logmsg(LOG_DEBUG, @_);
}

sub trace
{
my $self = shift;
   $self->logmsg(LOG_TRACE, @_);
}


} # End package SCULog

;1 # needed to avoid 'FALC/SCULog.pm did not return a true value'
