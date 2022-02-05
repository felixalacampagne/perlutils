#!/usr/bin/perl
###########################################################
###########################################################
# 
# Dependencies:
# 
# Net-UPnP
# Mac-iTunes-Library
# XML-Parser-Lite:    just copy the lib content to Perl lib
#
# SOAP-Lite: must be installed using the Perl package manager to
#            get the dependencies which are otherwise unavailable,
#            which requires internet access.
#            Failure to use ppm results in the error;
#               Can't locate Class/Inspector.pm in @INC
#            The PPM command is;
#               ppm install SOAP-Lite
#
###########################################################
###########################################################

# 11 Jul 2015 Improve missing media server behaviour.
# 27 Feb 2015 Added handling for mediaservertrees which end in a container of containers instead 
#             of tracks, eg. Album, Artist/Album, Genre.
# 26 Feb 2015 Seems that intermittently a block of random, unsorted, possibly duplicate tracks is returned. 
#             Subsequent blocks are sorted again but the random entries appear to replace the valid entries, ie. the
#             entries which should have appeared in the block do not appear in subsequent blocks. 
#             This results in unmatched playlist entries even though the count is correct.
#             To workaround this behaviour corrupt block detection and reload of corrupt blocks has been added.
#             Corrupt block detection relies on the list being sorted by artist - an out of order artist 
#             indicates a corrupt block. Only artists appearing in the list when they should have been earlier
#             can be detected. A corrupt block is reloaded upto 5 times. There is no guarentee that 
#             reloading a block wont result in the same corrupt block however it appears that in practice 
#             a single re-read is enough to get a valid block. 
#             It appears that a couple of corrupt blocks happen more or less every time the db is read!
# 15 Jul 2014 Occassionally not all tracks in a playlist can be found even though the number of tracks
# found seems correct. So need to log the tracks found so I can figure out at a later date why
# the missing tracks were not found.
use strict;

# More Perl madness. For some reason Perl randomly thinks normal ascii characters are 'wide characters'
# and it emits a message when doing a 'print'. The warning is supposedly only output when trying to
# print characters greater than 255. Trouble is the characters where the warning appears are actually
# normal ascii characters. Apparently the way to avoid this is to use UTF8 for the
# output. This will screw things up, especially since the characters in question are normal Ascii
# characters. This is just to see if it fixes the warning.
no warnings 'utf8';
use Date::Calc qw(Today_and_Now Delta_DHMS);
use Data::Dumper;
use Net::UPnP::ControlPoint;
use Net::UPnP::AV::MediaServer;
use HTML::Entities;
use XML::Simple;
use Getopt::Std;
my $twonkydbpath="N:\\Music\\mp3\\99 utils\\twonkydb.txt";
my $mediaserver="myTwonky Library at nas"; #"nas";
#my @mediaservertree=("Music", "All Tracks"); # "All Tracks" "Album" "Artist/Album"
my @mediaservertree=("Music", "Artist/Album"); # "All Tracks" "Album" "Artist/Album"
my $gDirSvc;
my $dev;
my $mediaServer;
my $musicContent;
my $alltrackContent;
my $mediaserverpath;
my $trackcnt=0;
my %opts;
my $verbose = 0;
my $logtofile = 0;      # Not implemented
my $pauseonexit = 0;    # Not implemented
use constant { LOG_SILENT => -1, LOG_ALWAYS => 10, LOG_FATAL => 20, LOG_ERROR => 30, LOG_INFO => 40, LOG_DEBUG => 50, LOG_TRACE => 60};
# NB 'use constant' creates subroutines (WTF???) so "x,y" must be used in the map instead of the normal "x=>y".
my %LOG_LABELS = ( LOG_ALWAYS, "ALWAYS", LOG_FATAL, "FATAL", LOG_ERROR, "ERROR", LOG_INFO, "INFO", LOG_DEBUG, "DEBUG", LOG_TRACE, "TRACE");
my $LOG_LEVEL=LOG_INFO; 

###############################################################
###############################################################
####                    #######################################
#### Main program       #######################################
####                    #######################################
###############################################################
###############################################################

my $obj = Net::UPnP::ControlPoint->new();
#@dev_list = $obj->search(st =>'upnp:rootdevice', mx => 10);
my @starttime = Today_and_Now();

getopts('vlp?', \%opts);

if( $opts{"?"} == 1 )
{
   HELP_MESSAGE();
}

if( $opts{"v"} == 1)
{
   $LOG_LEVEL=LOG_DEBUG; 
}
if( $opts{"l"} == 1)
{
   $logtofile = 1;
}
if( $opts{"p"} == 1)
{
   $pauseonexit = 1;
}


logmsg(LOG_INFO, "Searching for mediaserver '%s'\n", $mediaserver);
$dev = findDev($obj, $mediaserver);
unless( defined($dev))
{
   die "Failed to find media server $mediaserver\n";
}
$gDirSvc = $dev->getservicebyname('urn:schemas-upnp-org:service:ContentDirectory:1');
unless (defined($gDirSvc)) {
	die "Not a real media server!!!!: $gDirSvc";
}
$mediaServer = Net::UPnP::AV::MediaServer->new();
$mediaServer->setdevice($dev);
$mediaserverpath = $dev->getfriendlyname();

my $branchid=0;
foreach my $leaf (@mediaservertree)
{
   logmsg(LOG_INFO, "Searching for '%s' in '%s'\n", $leaf, $mediaserverpath);
   $musicContent = findTitle($mediaServer, $branchid, $leaf);
   $mediaserverpath = $mediaserverpath . "->" . $musicContent->gettitle();
   $branchid = $musicContent->getid();
}

logmsg(LOG_INFO, "Writing content of '%s' to '%s'\n", $mediaserverpath, $twonkydbpath);

my $dbfh;
unlink "$twonkydbpath";
if( ! open($dbfh, ">$twonkydbpath"))
{
	die "Failed to open $twonkydbpath for output";
}

#$trackcnt=print_content($mediaServer, $musicContent, $dbfh);
$trackcnt=print_containers($mediaServer, $musicContent, $dbfh);

close($dbfh);


my @endtime = Today_and_Now();
my @elapsed = Delta_DHMS(@starttime, @endtime); # ($days,$hours,$minutes,$seconds)
logmsg(LOG_INFO, "Started  %04d.%02d.%02d. %02d:%02d\n", $starttime[0],$starttime[1],$starttime[2],$starttime[3],$starttime[4]);
logmsg(LOG_INFO, "Finished %04d.%02d.%02d. %02d:%02d\n", $endtime[0],$endtime[1],$endtime[2],$endtime[3],$endtime[4]);
logmsg(LOG_INFO, "Elapsed %02d:%02d:%02d\n", $elapsed[1],$elapsed[2],$elapsed[3]);
logmsg(LOG_INFO, "Total tracks found: %d\n", $trackcnt);
   
###############################################################
###############################################################
####                    #######################################
#### End Main program   #######################################
####                    #######################################
###############################################################
###############################################################



sub findDev
{
my ($controlPoint, $devname) = @_;

# urn:schemas-upnp-org:device:MediaServer:1
#my @dev_list = $controlPoint->search();
my @dev_list = $controlPoint->search(st =>'urn:schemas-upnp-org:device:MediaServer:1');
my $devNum= 0;
my $device_type;

    foreach my $dev (@dev_list) 
    {
        $devNum++;
        $device_type = $dev->getdevicetype();
        if  ($device_type ne 'urn:schemas-upnp-org:device:MediaServer:1') {
            logmsg(LOG_INFO, "Found non MediaServer:1 device: %s\n", $device_type);
            logmsg(LOG_INFO, "[%s] : %s\n", $devNum, $dev->getfriendlyname());
            next;
        }
        logmsg(LOG_INFO, "[%s] : %s\n", $devNum, $dev->getfriendlyname());
        
        if($dev->getfriendlyname() eq $devname )
        {
          # print Dumper($dev);
          return $dev;
        }
   }
   logmsg(LOG_ERROR, "Not found: %s\n", $devname);
   return undef;
}
   
    
sub findTitle
{
my ($mediaServer, $id, $title) = @_;
my  @child_content_list = $mediaServer->getcontentlist(ObjectID => $id, 
                                                   Filter => "*",
                                                   RequestedCount => 0,
                                                   StartingIndex => 0 );
  if (@child_content_list <= 0) {
      logmsg(LOG_INFO, "getcontentlist returned empty list\n");
      return;
  }

  foreach my $child_content (@child_content_list) 
  {
      # logmsg(LOG_INFO, "Child: " . $child_content->gettitle() . "\n");
      if( $child_content->gettitle() eq $title )
      {
         return $child_content;
      }
  }
logmsg(LOG_INFO, "getcontentlist did not find title: %s\n", $title);
return;
}

# Version of print_content intended to handle containers of containers.
# Corrupt block check/reread will have unpredicatable results if the 
# container has mixed item and container content.
sub print_containers {
my ($mediaServer, $content, $outfh) = @_;
my $id = $content->getid();
my $title = $content->gettitle();
my $idx;
my @child_content_list;
my $trackcountblock=0;
my $trackcountcontainer=0;


   unless ($content->iscontainer()) 
   {
      logmsg(LOG_DEBUG, "Content '$title' is NOT a container!\n");
      return 0;
   }
   if($title eq "- ALL -")
   {
      logmsg(LOG_DEBUG, "Skipping the  '$title' container!\n");
      return 0;
   }
   
   my $startindex = 0;
   my $prevartist = "";
   my $blocklastartist = "";
   my $corruptblockindicator = 0;
   my $corruptblockindex = 0;
   my $corruptblockrereads = 0;
   my $blockcontent = "";
   
   do
   {
      
      @child_content_list = $mediaServer->getcontentlist(ObjectID => $id, 
                                                      RequestedCount => 200,
                                                      SortCriteria => "+upnp:artist,-dc:date,upnp:album,upnp:originalTrackNumber",
                                                      StartingIndex => $startindex );
      
      if (@child_content_list <= 0) 
      {
         return $trackcountcontainer;
      }
      logmsg(LOG_DEBUG, "Processing content of '$title' from index $startindex\n");
      $idx = 0;
      $prevartist = $blocklastartist;
      $corruptblockindicator = 0;
      $blockcontent = "";
      $trackcountblock=0;
      foreach my $child_content (@child_content_list) 
      {
         if($child_content->iscontainer())
         {
            # If the media server tree ends in a container of containers, eg. Album then
            # need to recurse down until the tracks are found.
            # NB. The corrupt block detection/reread will mess everything up
            # if items and containers are mixed in the same list.
            logmsg(LOG_DEBUG, "Processing child container '%s' at index %d in '%s'\n",
                              $child_content->gettitle(), $startindex + $idx, $title);
            $trackcountcontainer += print_containers($mediaServer,$child_content, $outfh);
            $idx++;
            next;
         }
         
         my ($contentline, $artist) = getItemInfo($child_content);
         $contentline = "" . $contentline . "\n";
         $trackcountblock++;
         logmsg(LOG_DEBUG, "%05d: %s", ($startindex+$idx), $contentline);
                  
         # Only sorting alphabetically on artist
         my $curartist = lc($artist);
         if($curartist lt $prevartist)
         {
            # Corrupt block? 
            # Need to exit loop without changing startindex and without changing
            # the last content line from the previous block
            $corruptblockindicator = 1;

            # Limit number of times the same block is reread
            if($startindex == $corruptblockindex)
            {
               $corruptblockrereads++;
            }
            else
            {
               $corruptblockrereads = 1;
               $corruptblockindex = $startindex;
            }            
            logmsg(LOG_ERROR, "Out of order entry detected [$corruptblockrereads]: previous=$prevartist current=$curartist\n");            
            if($corruptblockrereads > 5)
            {
               logmsg(LOG_ERROR, "Too many rereads for block starting $startindex [$corruptblockrereads], skipping\n");
               $corruptblockindicator = 0;
            }
            last;
         }

         $blockcontent .= $contentline;
         $idx++;         
         $prevartist = $curartist;
      }

      if(($corruptblockindicator < 1))
      {
         print $outfh "$blockcontent";
         $blocklastartist = $prevartist;
         $startindex += $idx;
         $trackcountcontainer += $trackcountblock;
         
      }
      else
      {
         logmsg(LOG_ERROR, "Rereading block from position $startindex [$corruptblockrereads]\n");
      }
   }until($startindex > 50000);
   

   
   #close(OUTPUT);
   return $trackcountcontainer;
} 




# Returns an array where
# 0 = the full db entry: artist|album|tracknum|track|year|url
# 1 = artist
sub getItemInfo
{
my ($trackContent) = @_;
my $objid = $trackContent->getid();
my %action_in_arg;
my $result;
my $action_res;
my $action_out_arg;
my $year;
my $album;
my $trackno;
my $track;
my $trackartist;
my $artist;
my $url;
my $dbentry;


   %action_in_arg = (
			'ObjectID' => $objid,
			'BrowseFlag' => 'BrowseMetadata',
			'Filter' => '*',
			'StartingIndex' => 0,
			'RequestedCount' => 0,
			'SortCriteria' => '',
		);
	
	$action_res = $gDirSvc->postcontrol('Browse', \%action_in_arg);
	unless ($action_res->getstatuscode() == 200) {
		next;
	}
	$action_out_arg = $action_res->getargumentlist();
	unless ($action_out_arg->{'Result'}) {
		next;
	}
	my $result = $action_out_arg->{'Result'};
	#logmsg(LOG_INFO, "$result\n");
	my $xml = XML::Simple->new();
	my $xmlResult = $xml->XMLin($result);
	
	

   # artist is an array if Composer is set, otherwise it's a scalar. Easiest
   # is to try to read the array, catch the exception (that's what the eval is for)
   # and try to read as a scalar.
   # Note iTunes uses the track artist in the playlists. So try to use track artist
   # with album artist as a fall back.
   eval {
      $trackartist = $xmlResult->{item}->{"upnp:artist"}->[0];
   };
   if($@) # $@ contains the exception
   {
      $trackartist = $xmlResult->{item}->{"upnp:artist"};
   }
   
   if( not length $trackartist) # Supposed to be fastest empty string check
   {
      $artist = $xmlResult->{item}->{"upnp:albumArtist"};
      $trackartist = $artist;
   }
   
   #if( $artist ne $trackartist)
   #{
   #   logmsg(LOG_INFO, "WARNING: '" . $artist . "' is not equal to '" . $trackartist . "'\n");
   #}
   
	$album = $xmlResult->{item}->{"upnp:album"};
	$trackno = $xmlResult->{item}->{"upnp:originalTrackNumber"};
	# Value from $trackContent->gettitle() is not decoded (still has things like &apos;)
	# whereas the xmlResult value IS decoded
	$track = $xmlResult->{item}->{"dc:title"};
	$year = $xmlResult->{item}->{"dc:date"};
	$year =~ m/(.*?)-01-01/sgi;
	$year = $1;

   $url = $trackContent->geturl();
   
   $dbentry = $trackartist . "|" . $album . "|" . sprintf("%02d", $trackno) . "|" . $track . "|" . $year ;
   #$dbentry = decode_entities($dbentry);
   $dbentry = $dbentry . "|" . $url;

	return ($dbentry, $trackartist);
}

sub HELP_MESSAGE()
{
my $cmdline;
   $cmdline = "netupnp";
   #$cmdline =  $cmdline . " [-l]";
   $cmdline =  $cmdline . " [-v]";
   #$cmdline =  $cmdline . " [-p]";
   $cmdline =  $cmdline . "\n";
   logmsg(LOG_ALWAYS, $cmdline);
   # logmsg(LOG_INFO, "   -l Log to file. Log file is created in the\n");
   # logmsg(LOG_INFO, "      initial scan directory with name md5_yyyymmddhhmm\n");
   logmsg(LOG_ALWAYS, "   -v Verbose output\n");
   # logmsg(LOG_INFO, "   -p Pause on exit. Waits for a key to be pressed before terminating.\n");
   exit(0);
}
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
         $!=1;
         print sprintf("%-8s: %s.%04d: %s",($LOG_LABELS{$keyword}//$keyword), $callerfunc, $callerline, $msg);
      }
      else
      {
         $!=1;
         print sprintf("%-8s: %s",($LOG_LABELS{$keyword}//$keyword), $msg);
      }
   }
   return $msg;
}
