# 25 Jun 2017 Utility to replace the mp3 files in iTunes with their ALAC equivalent
# if it exists. This preserves the play count of the MP3 file, and any star ratings etc.
# Decided to do this as the only reason for keeping the MP3s was to create compilation CDs
# to play in the car. Since I use my iphone exclusively to play music in the car it makes
# no sense to continue using the MP3s.
# Based on findOwn.pl
use strict;
use Win32::OLE;
use Win32::OLE::Variant;
use File::Basename;
use File::Spec;

my $glog = SCULog->new(); 
$glog->level(SCULog->LOG_DEBUG);

my $alacdir = "\\\\NAS\\public\\Music\\alac\\01 pop-rock";
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
	# Get the iTunes Music list.
	initITunes();
my %alacs;
	# Find the name of the list of songs
my $playlist;	
my $lst = $giTunesOLE->LibrarySource->Playlists; # $giTunesOLE->Sources; # $giTunesOLE->LibrarySource->Playlists;

	$glog->warn("Looking for Songs list in %d playlists\n", $lst->Count);
   for(my $i=1; $i<=$lst->Count; $i++)
   {
      my $itm = $lst->Item($i);
      my $itmname = $itm->Name;
      if($itmname eq "Music")
      {
    		$playlist = $itm;
     		last;
     	}
      $glog->debug("Item %02d: Name: %s\n", $i, $itmname);      
   }
   
	# Build list of ALAC albums, ie. directory names keys on the normalized name
	$glog->info("Loading directories in %s\n", $alacdir);
	%alacs = getKeyedDirs($alacdir);	


	# For Each track
my $tracks = $playlist->Tracks;
my $i;
my $converted = 0;
	$glog->info("Checking %d tracks\n", $tracks->Count);
   for($i=1; $i<=$tracks->Count; $i++)
   {
   	my $currtrack = $tracks->Item($i);
   	my $file = $currtrack->Location;

		# If mp3 file
   	if( ($file =~ m/.*\.(mp3)$/i) && ($file =~ m/.*\\01 dup\\.*/i) )
   	{
   		$glog->info("Looking for an ALAC for %s\n", $file);
			# Build a directory key based on artist, album, year (possibly easier than using the location)
         my $tracknumber = $currtrack->TrackNumber;
			my $key = SCUtils->trim($currtrack->Artist) . " - " . SCUtils->trim($currtrack->Album) . "(" . sprintf("%04d", $currtrack->Year) . ")";
			$key = getDirKey($key);
			$glog->info("ALAC directory key %s\n", $key);
			# Check for ALAC directory
      	my $alac4mp3 = $alacs{$key} // "";
      	if( length $alac4mp3 > 0)
      	{
      		
				# If match found
					# Look for matching track using track number
					my $alacfile = findTrack($alac4mp3, $tracknumber); 

					# If match found
					if( length $alacfile > 0 )
					{					
						# Update location with file name	
						$glog->info("Replacing %s with ALAC file %s\n", $file, $alacfile);
						#rename $file, $file . ".obsolete";
						# Seems the Location can't be changed - F--K! 
						# But why does it work from JS in findMissing
						# Perhaps because the file is missing? Maybe make the mp3  missing before updating?
						#$currtrack = $tracks->Item($i);
						#$glog->info("Previous Location: %s, Post rename and re-read Location %s\n", $file, $currtrack->Location);
						#my $hresult = $currtrack->Location(\$alacfile);
						#$glog->info("Set Location return: %d\n", $hresult);
						# Turns out the reason it didn't work is once again down to Perl weirdness. Too simple
						# to just assign to the property as in JavaScript, VBA etc. Nooooo, must have yet another
						# special combination of punctuation... discovered by wading through the Win32::OLE docs, which,
						# to their credit, contains a useful example. There is also an $Object->SetProperty('Property', $Value) form
						$currtrack->{Location} = $alacfile;
					}
					else
					{
						$glog->warn("ALAC track does not exist for mp3:%s\n", $file);
					}
			}
			else
			{
				$glog->warn("ALAC directory does not exist for file %s\n", $file);
			}
		}
	}
	$glog->info("Done!\n");
   exit(0);

###############################################################
###############################################################
####                    #######################################
#### End Main program   #######################################
####                    #######################################
###############################################################
###############################################################
sub findTrack
{
my ($dir, $trackno) = @_;	
my $track = sprintf("%02d ", $trackno); 
my @files;
my $dh;
my $fullfile;

   opendir $dh, $dir or die "Couldn't open dir '$dir': $!";
   @files = grep { /^\Q$track\E.*$/ } readdir $dh;
   closedir $dh;

   foreach my $file (@files)
   {
      $fullfile = File::Spec->catdir($dir,$file);
      if(! -d $fullfile )
      {
         return $fullfile;
      }
   }
   return "";
}

# Generate list of files in directory keyed by 'normalized' filename
# TODO: 
#  List directories only
#  Remove brakets around the year
#  remove spaces
#  make lowercase
sub getKeyedDirs
{
my ($dir) = @_;
my %dirhash;
my $dirkey;
my $dh;
my @files;
my $fullfile;

   opendir $dh, $dir or die "Couldn't open dir '$dir': $!";
   @files = grep { !/^\.\.?$/ } readdir $dh;
   closedir $dh;

   foreach my $file (@files)
   {
      $fullfile = File::Spec->catdir($dir,$file);
      if( -d $fullfile )
      {
         $dirkey = getDirKey($file);
         $dirhash{$dirkey} = $fullfile;
      }
   }

   return %dirhash;
}

# Converts the year brackets to underscores
sub getDirKey
{
my ($str) = @_;
$str =~ s/[\{\[\(\)\]\}\\\/:\?\*\>\<\$\"\| -]/_/g;
$str =~ s/\&/and/g;

# Only need one underscore at a time.
$str =~ s/__+/_/g;

# Remove quotes
$str =~ s/\'//g;

# Make lower case
return lc $str;
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

