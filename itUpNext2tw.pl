# 29 Jan 2015 Converted from it2twdirect to create twonky playlists based
#             on the "now playing" list. This is useful for capturing "Genius" mixes
# 03 Nov 2014 Updated log class with stacktrace output for errors
# 31 Oct 2014 Added class for general utils containing "static" methods and
#             a log class.
# 30 Oct 2014 v2. Uses my first Perl class to provide access to the Twonky db.
# 28 Oct 2014 v1.
use Win32::OLE;
use Win32::OLE::Variant;
use File::Basename;
use File::Spec;

my $log = SCULog->new(); 
$log->level(SCULog->LOG_DEBUG);


# Only way to obtain the content of the "Genius" mixes is to;
#    manually start a mix in iTunes
#    use a script to grab the currently playing track
#    process the track information, 
#        eg. add to iTunes playlist or a twonky playlist
#    move iTunes to the next track
#    wait for the track to start
#    repeat.
#
# Tracks start to repeat after a short while, ie. less than the number of tracks in the db.
# There is no way to determine which genius mix is being played.
# There is no way to trigger playing of a genius mix.

my $twonkydbfile = "\\\\NAS\\public\\Music\\mp3\\99 utils\\twonkydb.txt";  #"N:\\Documents\\twonky\\twonkydb.txt";
my $m3uoutpath = "\\\\NAS\\public\\Music\\mp3\\06 twonkyplaylists";

my $gtwonkydb;
my $giTunesOLE;

my %counters =
   (
      tracks => 0,
      hits => 0,
      misses => 0,
      totalpls => 0,
      convertedpls => 0,
      emptypls => 0
   );
###############################################################
###############################################################
####                    #######################################
#### Main program       #######################################
####                    #######################################
###############################################################
###############################################################

if($ARGV[0] ne "")
{
   $m3uoutpath = $ARGV[0];
}

if($ARGV[1] ne "")
{
   $twonkydbfile = $ARGV[1];
}

initITunes();
#my $lst = $giTunesOLE->Sources; # $giTunesOLE->LibrarySource->Playlists;
#$log->warn("list count: %d\n", $lst->Count);
#   for($i=1; $i<=$lst->Count; $i++)
#   {
#      my $itm = $lst->Item($i);
#      my $itmname = $itm->Name;
#      $log->warn("Item %02d: Name: %s\n", $i, $itmname);      
#
#   }
#exit(0);

my $gTWDB = Twonkydb->new($twonkydbfile);
my $plname = "069 UpNext";
my $m3u;

   $plname .= "_" . SCUtils->getTimeStamp();
   $m3u = genM3UFromCurrent();
  
   if( $m3u ne "" )
   {
      $m3u = "#EXTM3U\n" . $m3u;
      savem3u($m3uoutpath, $plname, $m3u);
   }
   else
   {
      $log->warn("No Twonky URLs found\n");
   }

   exit(0);

###############################################################
###############################################################
####                    #######################################
#### End Main program   #######################################
####                    #######################################
###############################################################
###############################################################

# Generates a Twonky playlist from the "Now Playing" list using the
# iTunes.CurrentTrack and iTunes.NextTrack() features. This is
# handy for capturing the "Genius" mixes and shuffles which can't
# be accessed in another way. 
# List building will stop when 5 consecutive repeated tracks are encounterd
sub genM3UFromCurrent()
{
my $twonkym3u = "";
my $played="";
my $repeats=0;
my $maxrepeats=5;

   do
   {
      $counters{"tracks"}++;
      my $currtrack = $giTunesOLE->CurrentTrack;
      my $trackid = "|" . $currtrack->TrackDatabaseID . "|";
      
      if( index($played, $trackid) != -1)
      {
         $repeats++;
      }
      else
      {
         $repeats = 0;
         $played .= $trackid; # Pipes are doubled, but who cares....

         # save track details in case object get's updated by the NextTrack call
         my $artist = $currtrack->Artist;
         my $album = $currtrack->Album;
         my $trackname = $currtrack->Name;
         my $tracknumber = $currtrack->TrackNumber;
         my $tracktime = $currtrack->Time;
         
         # Start moving to next track while processing the current track
         $giTunesOLE->NextTrack();
         
         $twonkym3u .= genM3UFromTrack($artist, $album, $trackname, $tracknumber, $tracktime);
      }
   }while($repeats < $maxrepeats);
   
   return $twonkym3u;
}

sub genM3UFromTrack()
{
my ($artist, $album, $trackname, $tracknumber, $tracktime) = @_;
my $key = SCUtils->trim($artist) . "|" . SCUtils->trim($album) . "|" . sprintf("%02d", $tracknumber) . "|";
my $url = $gTWDB->url($key);

my $twonkym3u="";
   
   $log->info("Current track '%s'\n", $key);
   
   if( $url eq "" )
   {
      $log->warn("No match for $key\n");
      $counters{"misses"}++;
   }
   else
   {
      $log->trace("Matched $key to $url\n");
      # m3u lists from iTunes/WMP have aextra fields which include the track and artist -
      # this would be handy for checking what is in the playlist...
      # The lists start with "#EXTM3U"
      # the path information line is preceeded by a
      # line like "#EXTINF:204,Across the Lines - Tracy Chapman"
      my $duration = $tracktime; #sprintf("%d", $currtrack->Time / 1000);
      if( $duration =~ m/(\d{1,3}):(\d{1,2})/ )
      {
         $duration = ($1 * 60) + $2;
      }
      $twonkym3u = "#EXTINF:" . $duration . "," . $trackname . " - " . $album . " - " . $artist . "\n";
      $twonkym3u .= $url . "\n";
      $counters{"hits"}++;
   }
   return $twonkym3u;
}



sub initITunes()
{
my $iTunes;

   # this should connect to a running iTunes, but I don't think it works
   $iTunes = Win32::OLE->GetActiveObject('iTunes.Application');
   unless (defined $iTunes) {
      # This should start iTunes if it's not running
      # A second parameter can be defined as a "destructor" which
      # could be used to shutdown iTunes if it was started by this script
      # however an already running iTunes also get's shutdown at the moment
      # so I've taken this option out until I can test it some more.
      # The xtra parameter was something like "$_->quit", not sure about the 
      # magic symbols though.
      # Seems just saying Quit will work. But don't because GetActiveObject
      # always fails
      $iTunes = Win32::OLE->new('iTunes.Application') or die "iTunes not running and cannot be started";
   }
   $giTunesOLE = $iTunes;
}

sub savem3u
{
my ($m3uoutpath, $plname, $m3u) = @_;
my $m3uname = File::Spec->catfile($m3uoutpath, $plname . "_it2twdirect.m3u");
   $log->info("Saving converted playlist to '%s'\n", $m3uname);
   SCUtils->savefile($m3uname, $m3u);
}

sub resetTrackCount
{
   $counters{"hits"} = 0;
   $counters{"misses"} = 0;  
   $counters{"tracks"} = 0;
}


package SCULog;
{
# 03 Nov 2014 Updated with stacktrace output for errors.
use Devel::StackTrace;

# This seems to work OK in the class. To use the constans to set the level
# the syntax is like '$log->level(SCULog->LOG_DEBUG);'
use constant { LOG_SILENT => -1, LOG_ALWAYS => 10, LOG_FATAL => 20, LOG_ERROR => 30, LOG_WARN=>35 ,LOG_INFO => 40, LOG_DEBUG => 50, LOG_TRACE => 60};

# This does appear to be shared between the instances of the class 
# but initializing it at the class level does not work. It is the same for simple 
# scalar values initialized here. The init must be done in the constructor (ie. new())
# but it only needs to be done once.
my %LOG_LABELS;

   
sub new
{
   # Init the class variables, this only has to be done once
   # but it doesn't work when done at the class level.
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
   $self->{"_LOG_LABELS"} = \%LOG_LABELS;
   return $self;   
}

sub logmsg
{
my $self = shift;
my $keyword = shift;
my $fmt = shift;
my $msg = "";
my $level;
   no warnings "numeric";
   
   # Does this work? Can I just use Level()? How do I know if the first parameter is
   # "self" or a level value??
   $level = $self->level;
   
   my %labels = %{$self->{"_LOG_LABELS"}};

   if(int($keyword) <= $level)
   {
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
         print sprintf("%-8s: %s(%04d): %s",($LOG_LABELS{$keyword}//$keyword), $callerfunc, $callerline, $msg);
      }
      else
      {
         $!=1;
         
         print sprintf("%-8s: %s",($labels{$keyword}//$keyword), $msg);
      }
   }
   return $msg;
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


}

package SCUtils;
{
# The "methods" in this "class" should all be "static", ie. no
# need to call a constructor to obtain an instance of the class.
sub loadfile
{
my $class = shift; # We are a static method in a class now
# Declare local variables ...
my ($path) = @_;
my $contents = "";
my $line = "";

   {
     # temporarily undefs the record separator
     
     local(*INPUT, $/);

     open (INPUT, $path)     || die "can't open $path: $!";
      #binmode INPUT,":utf8";
     $contents = <INPUT>;
     close(INPUT);
   }

	return $contents;
}

sub savefile
{
my $class = shift; # We are a static method in a class now   
my ($path, $data) = @_;


      unlink "$path";
   {
   
      if(open(OUTPUT, ">$path"))
      {
         binmode OUTPUT,":encoding(iso-8859-1)";
		 print OUTPUT $data;
       close(OUTPUT);
      }
   }
}

sub trim
{
my $class = shift; # We are a static method in a class now
my ($str) = @_;

$str =~ s/^\s+//;
$str =~ s/\s+$//;
return $str;
}

# returns the current date/time in the form YYYYMMDDHHmm
# TODO Should e an SCUutil
sub getTimeStamp()
{
my $class = shift; # We are a static method in a class
my @now = localtime();
   return sprintf("%04d%02d%02d%02d%02d", $now[5]+1900, $now[4]+1, $now[3], $now[2], $now[1]);
}

} # End package SCUUtils

package Twonkydb;
{
# Dependencies:
#   SCUtils "class"
sub new
{
   # The class is supplied as the first parameter
   # Not sure what it is used for!!!
   my $class = shift;
   my $self = {};  # this becomes the "object", in this case an empty anonymous hash
   bless $self;    # this associates the "object" with the class
   $self->loaddb(shift);
   return $self;
}

sub loaddb
{
   # the first parameter is the object, which was defined in the new method as a hash
   my $self = shift;
   $self->{dbpath} = shift;
   
   # Need to find a way to access the function in the main part of the code..
   $self->{db} = SCUtils->loadfile($self->{dbpath}); #$self->loadfile($self->{dbpath});
}

sub url()
{
my $self = shift;
my ($key) = shift;
# Need a way to quote $key
#my $pat = "^\\Q" . $key . "\\E(.*)|(.*)|(.*\$)";
my $pat = '\Q' . $key . '\E(.*)';
my $Url;
#use re 'debug';

   # It has taken f--ing hours to get this to work! There is just no logic to this
   # shitty language at all. One day it will work one way, the next in a completely different way.

   if( $self->{db} =~ m/\Q$key\E(.*)\|(.*)\|(.*$)/m )
   {
      $Url = $3;
   }
   return $Url;
}

# To try if the key doesn't work, which is the case for tracks
# recently added to the christmas collection. I suspect Twonky only
# supports track numbers up to 255...
# To be implemented when I have time, easier to renumber the tracks for now,
# ie. Christmas morning....
sub url4title()
{
}

} # End package Twonkydb