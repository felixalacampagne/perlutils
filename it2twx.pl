#!/usr/bin/perl
# perl it2tw.pl <itunes XML format playlist>

# The twonky db is built using the Foobar2000 uPnP Browser.
# 	Configure the fb2k copy command
#     Open File>Preferences>Advanced>Display>Legacy title formatting settings>Copy command
#			Set the format to
#			[%artist%]'|'[%album%]'|'[%date%]'|'[%tracknumber%]'|'[%title%]'|'[%path%]
# 	Using View->uPnp Browser select the twonky nas.
# 	Add all tracks into a new playlist
# 	Select all the tracks in the playlist
# 	Copy them (Ctrl-C)
# 	Paste them into UltraEdit and save them as twonkydb.txt

# Twonky detects the .m3u playlists and the content. The playlists play OK on iOS, DLink Mediacenter and
# Denon.
# Tried to set up something similar for FLAC files using Foobar2000 as media server. Foobar2000 does not
# detect m3u or fpl playlists so creating the playlists using a remote fb2k is no use even though the
# paths should work as they do for the twonky playlists. The fb2k server exposes the playlists it has loaded
# in a toplevel playlists entry. So to use playlists it is necessary to define them on the server and to ensure
# they are loaded before the server is started. The playlists seen by the clients can take a while to update, annoying
# at the "development" stage but probably not too bad when things have settled down. The flac playlists will
# inlcude the mp3 files for which there is no flac equivalent making it similar to
# the iTunes ALAC library... eventually. It's not ideal as Blackey still needs to be running so the iTunes
# library is available anyway. Eventually might add the  FLAC files back into the twonky share and
# then build playlists which combine the FLAC and mp3 files, then no computer is required... eventually.
# Need to see if Mediacenter can play FLACs, I don't think it can.
use strict;
use XML::Simple;
use Data::Dumper;
use Mac::iTunes::Library::XML; # From http://search.cpan.org/~dinomite/Mac-iTunes-Library-1.0/
use Mac::iTunes::Library::Playlist;
use File::Basename;
use File::Spec;
my $itunesxmlpl;
my $twonkydbfile = "\\\\NAS\\public\\Music\\mp3\\99 utils\\twonkydb.txt";  #"N:\\Documents\\twonky\\twonkydb.txt";
#my $itPlaylist = XMLin($itunesxmlpl);

my $gtwonkydb;
my $twonkym3u;
my $m3uname;
my $pathname;

if($ARGV[0] eq "")
{
   print "perl it2tw.pl <iTunes XML Playlist>\n";
   exit(1);
}

$itunesxmlpl = $ARGV[0];
$gtwonkydb = loadfile($twonkydbfile);

my $itLibrary = Mac::iTunes::Library::XML->parse($itunesxmlpl);
#print Dumper($itLibrary);

my @items = $itLibrary->playlists();
my $hits = 0;
my $misses = 0;

# Very strange - playlists() returns something, let's call it an array, the first item
# is just a string which looks like the id of the playlist. The second item appears to be
# the actual playlist. Why the hell doesn't it just return playlist objects????
# It's taken me an hour to figure out how to get to the playlist - so for now I'll
# just assume that it will always be like this!
my $pl = @items[1];
#print "Playlist: " . $pl . "\n";
print "Converting playlist: " . $pl->name() . "\n";
$itunesxmlpl = File::Spec->rel2abs($itunesxmlpl) ;
$pathname = dirname($itunesxmlpl);

$m3uname = File::Spec->catfile($pathname, $pl->name() . "_it2twx.m3u");

# Now to get the track key values
# my $key = "";
$twonkym3u = "";
foreach my $track ($pl->items())
{
   # NB the trailing space are retained by the Mac parser but dropped by the XML::Simple parser
   # Would be better not to have the tailing spaces in the first place, but it's a pain to find them...
   my $key = $track->artist() . "|" . trim($track->album()) . "|" . sprintf("%02d", $track->trackNumber()) . "|";
   my $url = getUrlFromDb($key);
   if( $url eq "" )
   {
      print "WARNING: No match for $key\n";
      $misses++;
   }
   else
   {
      # m3u lists from iTunes/WMP have aextra fields which include the track and artist -
      # this would be handy for checking what is in the playlist...
      # The lists start with "#EXTM3U"
      # the path information line is preceeded by a
      # line like "#EXTINF:204,Across the Lines - Tracy Chapman"
      # Don't know what the number is - will use a dummy - and don't know if
      # the "track - artist" format is mandatory - will try "track - album - artist"
      #
      my $duration = sprintf("%d", $track->totalTime() / 1000);
      $twonkym3u = $twonkym3u . "#EXTINF:" . $duration . "," . $track->name() . " - " . $track->album() . " - " . $track->artist() . "\n";
      $twonkym3u = $twonkym3u . $url . "\n";
      $hits++;
      # print "INFO: " . $key . " (" . $track->name() . "): " . $url . "\n";
   }
}

print "Tracks matched=$hits Unmatched=$misses Total=" . ($hits+$misses) . "\n";

#$m3uname = replace .xml with .m3u
if( $twonkym3u ne "" )
{
   $twonkym3u = "#EXTM3U\n" . $twonkym3u;
   print "Saving converted playlist to $m3uname\n";
   savefile($m3uname, $twonkym3u);
}
else
{
   print "WARNING: Converted playlist is empty: nothing saved\n";
}

exit(0);

sub getUrlFromDb()
{
my ($key) = @_;
# Need a way to quote $key
#my $pat = "^\\Q" . $key . "\\E(.*)|(.*)|(.*\$)";
my $pat = '\Q' . $key . '\E(.*)';
my $Url;
#use re 'debug';

   # It has taken f--ing hours to get this to work! There is just no logic to this
   # shitty language at all. One day it will work one way, the next in a completely different way.

   if( $gtwonkydb =~ m/\Q$key\E(.*)\|(.*)\|(.*$)/m )
   {
      $Url = $3;
   }
   return $Url;
}

sub loadfile
{
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
my ($str) = @_;

$str =~ s/^\s+//;
$str =~ s/\s+$//;
return $str;
}