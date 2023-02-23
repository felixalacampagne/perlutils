#!/usr/bin/perl
# perl podfromit.pl <itunes music library>

# NB The -t option results in copied files with corrupted artwork whereas the normal
# operation of copying from the iTunes library appears to be working ok, ie. uncorrupted artwork.

# 11 Feb 2023 Do not re-process already processed podcasts, ie. ones called 'WEnn'. 
# 24 Feb 2019 Fix title set by doFixPodTag
# 12-Feb-2019 Noticed that WE51 files have Jun dates but WE50 files have Nov dates. I think this
#             might be related to repeated use of TDRL as the base date which is updated into
#             past on each autorenumber usage. To avoid this autorenumber will now only use
#             the TALB (album name) and TYER (Year) tags to derive the base autorenumber date.
# 27-Dec-2017 Set release date so sorting oldest to newest should give correct play order. This is
#             to ensure multiple weeks should play in the right order when sorted oldest to newest.
# 02-Dec-2017 Tweaks which seem to be needed for iOS11 compatibility.
# 31-Aug-2016 Fixed raw UTF-8 in filename problem. A hyphen in a name was being interpreted
#             as the raw utf-8 sequence after URI decoding. Encoding the name as iso-8859-1 didn't
#             interpret the character correctly. Luckily encoding as cp1250 had the desired result. (F--king Perl!)
# 23-Dec-2015 Fixed -t corrupted artwork. initmp3 must be called before using the mp3::tag lib as
#             the default settings do not work. -t now supports filenames with just the date, no
#             need to specify the time (defaults to 12:00).
#             Added the -f to fix the tags of a bunch of podcasts in a directory - should also work for a single file
# 28-Jun-2015 First "production" version
# 27-Jun-2015 No longer renames the source files. If the destination file exists no processing is
#             performed. This way iTunes stays consistent, doesn't redownload files, and can
#             be used to delete the podcasts, which also helps in keeping it consistent.
# 27-Jun-2015 First working version integrated with podtag. Renames sources file to .done
# 21-Jun-2015 First version. Finds the Podcasts and renames them. Result can be used with
#
# use lib 'lib'; # Remove this when the MP3 library is added to the default installation.
use FindBin;           # This should find the location of this script
use lib $FindBin::Bin . "/lib"; # This indicates to look for modules in the lib directory in script location

use strict;
use warnings;
use utf8;
use Getopt::Std;
use XML::Simple;
use Data::Dumper;
use Mac::iTunes::Library::XML; # From http://search.cpan.org/~dinomite/Mac-iTunes-Library-1.0/
use Mac::iTunes::Library::Playlist;
# APESTRIP imports
use Fcntl qw[:seek];
use File::Copy;
use File::Temp;
use IO::File;
# APESTRIP end
use Time::Local;
use Date::Calc qw(:all);
use POSIX qw(strftime);
use File::Basename;
use File::Spec;
use File::Path qw(make_path);
use File::Basename;
use File::Spec;
use URI::Escape;
use URI::file;
use Encode qw(decode encode);

# WARNING: THe standard version of the library does not support the PCST (or RVAD) tag. A custom
# version of the library with ID3v2.pm.diff changes applied is required to support PCST and
# for this script to work correctly
use MP3::Tag;   # cpan MP3::Tag for most recent version)

my $LOG = SCULog->new();
$LOG->level(SCULog->LOG_INFO);

my $gDestRootdir = "C:\\temp\\recordings";
my $itunesxmlpl = "G:\\iTunesUtilities\\iTunes Music Library.xml";
my $tagfile="";

my $pathname;
my %opts =();


getopts("vi:d:t:f:", \%opts);
# see HELP_MESSAGE() below for usage text. HELP_MESSAGE is called automatically by getopts
# when --help is specified, it also displays some leading garbage which I don't know how
# to prevent, but the usage message is the most prominent.

initMP3();

if( exists( $opts{"v"}))
{
   $LOG->level(SCULog->LOG_TRACE);
}
if( exists( $opts{"i"}))
{
   $itunesxmlpl = $opts{"i"};
}

if( exists( $opts{"d"}))
{
   $gDestRootdir = $opts{"d"};
}

if( exists( $opts{"t"}))
{
   # This is primarily intended for testing the file processing
   my $reldate="";
   my $name="";
   my $location;
   $location = $opts{"t"};

   $location = File::Spec->rel2abs($location);

   if( $location =~ m/^.*\\(.*)_(\d{12})\..*$/ )
   {
      $name = $1;
      $reldate = $2;
   }
   elsif( $location =~ m/^.*\\(.*)_(\d{8})\..*$/ )
   {
      $name = $1;
      $reldate = $2;
      $reldate = $reldate . "1200";

   }

   if(($reldate ne "") && ($name ne ""))
   {
      $LOG->info("Perform one-off processing of $location: $name: $reldate\n");
      processFile($location, $name, $gDestRootdir, $reldate);
   }
   else
   {
      $LOG->error("Invalid filename format for one-off processing: $location\n");
   }
   exit(0);
}

if( exists( $opts{"f"}))
{
   fixFilesInDir($opts{"f"});
   exit(0);
}
##################################
#######                    #######
####### Main program       #######
#######                    #######
##################################

$LOG->debug("Loading iTunes library: $itunesxmlpl\n");
my $itLibrary = Mac::iTunes::Library::XML->parse($itunesxmlpl);

# Turns out that playlists is a hash (%) not an array (@) as used in
# it2twx.pl. As such it needs a different syntax for accessing the members
# Unfortunately the playlists are not keyed on the name.
my %playlists = $itLibrary->playlists();
my @playlistkeys = keys %playlists;
my $podcastkey ="";

foreach my $key (@playlistkeys)
{
   $LOG->trace("Key: " . $key . " Playlist name: " . $playlists{$key}->name() . "\n");
   if($playlists{$key}->name() eq "Podcasts")
   {
      $podcastkey = $key;
   }
}

my $podcastpl = $playlists{$podcastkey};
my @podcasts = $podcastpl->items();

foreach my $podcast (@podcasts)
{
   my @podcast = $podcast;
   if($podcast->trackType() eq "File")  # The undownloaded ones are type "URL"
   {
      my $extn = "";
      my $location = decodeutf8url($podcast->location());
      
      if( $podcast->album() =~ m/^WE\d\d$/ )
      {
         $LOG->debug("Ignoring processed podcast: " . $podcast->album() . " Location: " . $location . "\n");
      }
      else
      {
         $LOG->trace("Downloaded podcast: '" . $podcast->album() . "' Released: " . $podcast->releaseDate() . " Location: " . $location . "\n");
         processFile($location, $podcast->album(), $gDestRootdir, $podcast->releaseDate());
      }
   }
}
exit(0);
##################################
#######                    #######
####### End Main program   #######
#######                    #######
##################################
sub fixFilesInDir
{
my ($dir) = @_;
my $dh;
my @files;

   $dir = File::Spec->rel2abs($dir);
   if( -f $dir )
   {
      doFixPodTag($dir);
      return;
   }
   if( ! -d $dir )
   {
      return;
   }

   opendir $dh, $dir or die "Couldn't open dir '$dir': $!";
   @files = grep { !/^\.\.?$/ } readdir $dh;
   closedir $dh;

   # print "Found @files in $curdir\n";
   foreach my $file (@files)
   {
      my $fullfile = File::Spec->catdir($dir,$file);
      if( -d $fullfile )
      {
         # I suppose could recurse...
         next;
      }
      elsif( $file =~ m/^.*\.mp3$/i )
      {
         # Can ony handle mp3 files...
         doFixPodTag($fullfile);
      }
   }

   # Now apply the numbering required to get the podcasts to play in the desired order
   # This should derive the playorder data from the first file in the list.
   # I'm not sure why but it doesn't seem to read the correct TDLR value at the moment for some
   # files...
   autoTrackNumber($dir);

}

# Calculate the podcast tags play order tags based on the name of the podcast file. This
# assumes the file has been named suitably named, ie. <WEEK><TRACK>-<YEAR><MONTH>DAY_<TITLE).mp3
# The tags will be updated to match the filename... in theory. At the moment there appears to be
# a problem updating the TDRL (release date) tag with an appropriate value.
sub doFixPodTag
{
my ($mp3path) = @_;
my $title;
my $destfilename;
my $destrootdir;
my $releasedate;
my $trackid;
my $trackno;
my $year;
my $month;
my $day;
my $hour=12;
my $minute=00;
my $week;
my $renameto;
my $origname;
my $trackname;

   # Extract the filename from the full path into wedir and mp3file
   # NB. suffix is empty for a normal DOS path (ie. N:\recordings\we01\file.mp3)
   my ($mp3file,$wedir,$suffix) = fileparse( $mp3path );

   if($mp3file =~ m/^(\d{2})(\d{2})-(\d{4})(\d{2})(\d{2})_(.*)\..*$/ )
   {
      $week = $1;
      $trackno = $2;
      $year = $3;
      $month = $4;
      $day = $5;
      $origname = $6;
      # 5250-Boston Calling-20171231
      $trackname = sprintf("%s%s-%s-%s%s%s", $week,$trackno,$origname,$year,$month,$day);
   }
   else
   {
      # Can't do anything with this file
      $LOG->error("doFixPodTag: Unable to parse filename: $mp3file\n");
      return 1;
   }

   $trackid = sprintf("%02d%02d", $week, $trackno);

   $LOG->info("doFixPodTag: File: $mp3file, Week: $week, TrackID: $trackid, Date: $year-$month-$day\n");

   # Add podcast tags to cpoy

   doPodcastTags($mp3path, $trackname, $week, $trackid, $year, $month, $day, $hour, $minute);


   return 0;
}

sub HELP_MESSAGE()
{
$Getopt::Std::STANDARD_HELP_VERSION=1;   # This is to make getopts exit after calling help message
print("Usage: \n");
print("  -v Turn on verbose logging\n");
print("  -i <pathname>  Path to the iTunes Music Library XML file\n");
print("  -d <dirname>   Directory path for processed files\n");
print("  -f <dirname>   Fix tags of processed files in the specified directory. \n");
print("  -t <pathname>  Process a single file, do not load iTunes library.\n");
print("                 Requires the filename format to be;\n");
print("                 PodcastName_ReleaseDate.mp3\n");
print("                 where \n");
print("                    ReleaseDate = YYYYMMDD or YYYYMMDDHHMM\n");
print("                 and supported names are;\n");
print("                    The Archers Omnibus\n");
print("                    Desert Island Discs\n");
print("                    From Our Own Correspondent\n");
print("                    Kermode and Mayo's Film Review\n");
print("                    Boston Calling\n");
print("                    Click\n");
}

sub processFile
{
my ($location, $name, $destroot, $reldate) = @_;
my $destfilename = sanitize($name);
my $extn = "";

   if( $location =~ m/.*(\..*)$/i )
   {
      $extn = $1;
   }
   $destfilename .= $extn;

   $LOG->trace("Processing file: " . $name . " Released: " . $reldate . " Dest name: " . $destfilename . " Original file: " . $location . "\n");
   if( -e $location)
   {
      $LOG->trace("File exists: " . $location . "\n");
      # map the podcast to my preferred play order
      my $trackid = getPodcastTrackNum($name);

      # add the podcast tags to make it play like I want on the iPhone
      # doPodTag will not process the file if the destination file exists.
      doPodTag($location, $name, $destfilename, $destroot, $reldate, $trackid);

      $LOG->debug("Processed file: " . $location . "\n");
   }
   else
   {
      # The file should exist!
      $LOG->warn("File does NOT exist: " . $location . "\n");
   }
}

sub initMP3
{
MP3::Tag->config( write_v24 => 1 );
MP3::Tag->config("id3v23_unsync_size_w",0);
MP3::Tag->config("id3v23_unsync",0);
}

sub getPodcastTrackNum
{
my ($podcast) = @_;
my $trackid = 99;
   # Should use a map or something
   if( $podcast eq "The Archers Omnibus")
   {
      $trackid = 1;
   }
   elsif( $podcast eq "Desert Island Discs")
   {
      $trackid = 20;
   }
   elsif( $podcast eq "Kermode and Mayo's Film Review")
   {
      $trackid = 30;
   }
   elsif( $podcast eq "From Our Own Correspondent Podcast")
   {
      $trackid = 40;
   }
   elsif( $podcast eq "Boston Calling")
   {
      $trackid = 50;
   }
   elsif( $podcast eq "Click")
   {
      $trackid = 60;
   }
   return $trackid;
}

# NB this does not move file to "done"
# The destfilename is decorated with track/date information
sub doPodTag
{
my ($mp3file, $title, $destfilename, $destrootdir, $releasedate, $trackid) = @_;
my $year;
my $month;
my $day;
my $hour;
my $minute;
my $week;
my $renameto;
my $wedir;
my $trackname;

   # Unbelievably the perl Date library doesn't seem able to parse an XML type date.
   # so will have to parse it myself - don't care about the timezone info, if present.
   # "2015-05-31T10:20:00Z";
   # "YYYYMMDDHHMM" also supported for one-off file processing
   if($releasedate =~ m/^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2}).*$/ )
   {
      $year = $1;
      $month = $2;
      $day = $3;
      $hour = $4;
      $minute = $5;
   }
   elsif($releasedate =~ m/^(\d{4})(\d{2})(\d{2})(\d{2})(\d{2}).*$/ )
   {
      $year = $1;
      $month = $2;
      $day = $3;
      $hour = $4;
      $minute = $5;
   }

   ($week,$year) = Week_of_Year($year,$month,$day);
   $trackid = sprintf("%02d%02d", $week, $trackid);


   # trackname is really the value for TITLE tag
   $renameto = sprintf("%s-%04d%02d%02d_%s", $trackid, $year, $month, $day, $destfilename);
   $trackname = sprintf("%s-%s-%04d%02d%02d", $trackid, $title, $year, $month, $day);
   $wedir = File::Spec->catdir($destrootdir, sprintf("we%02d", $week));
   $renameto = File::Spec->catdir($wedir, $renameto);

   if( -e $renameto)
   {
      $LOG->debug("doPodTag: No action: Destination file already exists for $mp3file: $renameto'\n");
      return 1;
   }

   $LOG->info("doPodTag: File: $mp3file, Week: $week, TrackID: $trackid, New filename: $renameto\n");

   # Create WExx directory
   unless(-d $wedir)
   {
      $LOG->info("doPodTag: Creating podcast directory: '" . $wedir . "'\n");
      make_path($wedir)  ;
   }

   # Copy the file to Wexx directory

   if(!copy($mp3file, $renameto))
   {
         # binmode STDOUT, ":encoding(UTF-8)";
         ;
         my $msg = "doPodTag: FAILED Copying " . $mp3file . " to " . $renameto . ": " . $!;
         $LOG->fatal($msg);
         die($msg);
   }

   # remove tags from copy
   # The APE tags seems to cause all sorts of problems so remove them first
   apestrip($renameto);  # Got this from the web - hope it works!!
   #removeID3($renameto);

   # Add podcast tags to cpoy
   doPodcastTags($renameto, $trackname, $week, $trackid, $year, $month, $day, $hour, $minute);

   # Set trackno. of all tracks according to sorted order
   autoTrackNumber($wedir);

   return 0;
}

sub autoTrackNumber
{
my ($curdir) = @_;
my $dh;
my @mp3files;
my @files;
my $file;
my $trackno;
my $filepath;
my $week="";
my $year="";
my $month="";
my $day="";
my $haveBaseDate=0;
my $newtoold=0;
   opendir $dh, $curdir or die($LOG->fatal("autoTrackNumber: Couldn't open dir '$curdir': $!"));
   @files = grep { !/^\.\.?$/ } readdir $dh;
   closedir $dh;

   $LOG->trace("autoTrackNumber: Found @files in $curdir\n");
   foreach $file (@files)
   {
      if( $file =~ m/.*\.(mp3)$/i )
      {
         # Build the list of files to be md5'd
         push(@mp3files, $file);
      }
   }
   @files = sort @mp3files;
   $trackno = 0;
   foreach $file (@files)
   {
      $trackno++;
      $filepath = File::Spec->catdir($curdir,$file);
      my $mp3 = MP3::Tag->new($filepath);

      # Stupidly this gives an error if there are no tags
      # but if it isn't called then the exists check always fails
      $mp3->get_tags;

      if ( exists $mp3->{ID3v2} )
      {
         my $id3v2 = $mp3->{ID3v2};
         $LOG->debug("autoTrackNumber: Setting %s track number to %s\n", $filepath, $trackno);
         $id3v2->remove_frame("TRCK");
         $id3v2->add_frame("TRCK",sprintf("%02d", $trackno));

         # iTunes only really sorts on the release date. Therefore need to make sure
         # higher numbered tracks have more recent release dates. For now will take the
         # release date of the first track, with time 00:00:00 as the start and increase by 1 hour
         # which gives me 24 tracks per week - which is plenty for now....
         # For some incomprehensible the default play order for episodes is newest->oldest - WTF!
         # This order can be changed on a per podcast case - but I want to be able to just drag and
         # drop the podcasts to the iPhone without having to screw around after they have finished copying,
         # ideally I wouldn't even need to copy them into iTunes first.
         # AFAICS there is no way to specify that the normal play order should be oldest->newest which
         # means that I'm probably going to have to make track 1 be the newest track and the last track
         # the oldest. This is probably not going to be too difficult providing there are no more than
         # 24 podcasts per week.
         if($haveBaseDate < 1)
         {

            my $datevalue="";
            # Using TDRL is no longer possible because it is now updated to an entirely artificial value in order
            # to get the play order to work on the iPhone. The first time a file is autonumbered it will have
            # a valid date, but this date might get shifted into the past by renumber. If the file is then
            # used for the base date by autorenumber a second time the date will be shifted even further back
            # in time. If the intended first file is actually the first to arrive then it could be used as the
            # base date multiple times, each time shifting the base date further into the past with the result
            # that files for week X actually have dates before files for week X-1, which maybe explains
            # the dates for WE51 files being in June and WE50 files being in Nov
#            $datevalue = $id3v2->get_frame("TDRL") // "";
#            if($datevalue =~ m/(\d{4})-(\d{2})-(\d{2})T\d{2}:\d{2}:\d{2}/)
#            {
#               $year = $1;
#               $month = $2;
#               $day = $3;
#               # Decided that the release dates should always be on the same day of the week
#               # so convert all dates to week no. and year
#               ($week, $year) = Week_of_Year($year,$month,$day);
#               $LOG->info("autoTrackNumber: Base date from TDRL tag: %04d-%02d-%02d (Week %02d, Year %04d)\n",
#                  $year, $month, $day, $week, $year);
#            }
#            else
#            {
               # If the album title is added by podtag then the week and year
               # of the podcast can be derived and used for the release date base value
               $week = $id3v2->get_frame("TALB") // "";
               $year = $id3v2->get_frame("TYER") // "";
               if($year eq "")
               {
                  my @now = localtime();
                  $year = $now[5]+1900;
               }


               if($week =~ m/WE(\d{2})/)
               {
                  $week = $1;
                  $LOG->debug("autoTrackNumber: Using Base date from TALB/TYER: Week %02d, Year %04d\n", $week, $year);
               }
               else
               {

                  my @now = localtime();
                  $year = $now[5]+1900;
                  $month = $now[4]+1;
                  $day = $now[3];
                  ($week, $year) = Week_of_Year($year,$month,$day);
                  $LOG->debug("autoTrackNumber: Using Base date today: %04d-%02d-%02d (Week %02d, Year %04d)\n",
                     $year, $month, $day, $week, $year);
               }
#            }

            ($year, $month, $day) = Monday_of_Week($week, $year);

            # iTunes podcast play order still forked. Looking for a way to put every podcast
            # in a given week onto a different day sorted so lower tracknumbers are older
            # and so the podcasts for one week don't overlap with the dates of the next week.
            # Using hours no longer works with the iPhone app, the podcats show up in the correct
            # order but when I get to the end of listening to the first one it goes back to the
            # begining of the same podcast. Same for the next button in the car. So I conclude that
            # the podcst app just ignores the time part of the release date.

            # So I want a way to convert the year, week and track into a date. Could use one week per year
            # so ;
            #  year = weeknum +
            #         ((realyear-2018) * 52)
            #  daynum = trackno


            # Use Wednesday as the base release date
            ($year,$month,$day) = Add_Delta_Days($year,$month,$day, 2);
            $haveBaseDate = 1;
         }

         if($haveBaseDate > 0)
         {
            my @tim;
            #@tim = Add_Delta_DHMS($year,$month,$day, 0, 0, 0, 0, ($trackno-2) * 3,0,0);
            my $dayoff;
            $dayoff = ((53 - $week ) * -20) + $trackno;

            @tim = Add_Delta_DHMS($year,$month,$day, 12, 0, 0, $dayoff, 0,0,0);
            my $reldate = sprintf("%04s-%02d-%02dT%02d:00:00Z", $tim[0], $tim[1], $tim[2],$tim[3]);
            $LOG->debug("autoTrackNumber: Calculated release date is %s\n", $reldate);
            $id3v2->remove_frame("TDRL");
            $id3v2->add_frame("TDRL", $reldate);

            # Maybe iPhone will work properly with the "Original release date" tag: TDOR
            $id3v2->remove_frame("TDOR");
            $id3v2->add_frame("TDOR", $reldate);
         }
         $id3v2->write_tag();
      }
      else
      {
         $LOG->info("autoTrackNumber: NO ID3v2 tags in %s\n", $filepath);
      }
   }

}

sub doPodcastTags
{
my ($file, $trackname, $week, $trackid, $year, $month, $day, $hour, $minute) = @_;
my $mp3 = MP3::Tag->new($file);
my $id3v2;
my $westr = sprintf("WE%02d", $week);

   $LOG->info("doPodcastTags: Setting podcast tags for $file: %s %s %s\n",$trackname,$trackid,$westr);

   # Stupidly this gives an error if there are no tags
   # but if it isn't called then the exists check always fails
   $mp3->get_tags;
   if (exists $mp3->{ID3v1})
   {
      $LOG->debug("removeID3: Deleting ID3v1 tag from $file\n");
      my $id3v1 = $mp3->{ID3v1};
      $id3v1->remove_tag();
   }

   if ( exists $mp3->{ID3v2} )
   {
      $LOG->debug("doPodcastTags: Using existing ID3v2 tag for $file\n");
      $id3v2 = $mp3->{ID3v2};
      #$id3v2->remove_tag();
   }
   else
   {
      $LOG->debug("doPodcastTags: Creating new ID3v2 tag for $file\n");
      $id3v2 = $mp3->new_tag("ID3v2");
   }

   # Track title
   $id3v2->remove_frame("TIT2");
   $id3v2->add_frame("TIT2", $trackname);

   # Album
   $id3v2->remove_frame("TALB");
   $id3v2->add_frame("TALB",$westr);

   # Composer
   $id3v2->remove_frame("TCOM");
   $id3v2->add_frame("TCOM",$westr);

   # Artist
   $id3v2->remove_frame("TPE1");
   $id3v2->add_frame("TPE1",$westr);
   $id3v2->remove_frame("TPE2");
   $id3v2->add_frame("TPE2",$westr);

   # Sorting on xxx
   $id3v2->remove_frame("TSOP");
   $id3v2->add_frame("TSOP",$westr);
   $id3v2->remove_frame("TSOA");
   $id3v2->add_frame("TSOA",$westr);

   # Track no.
   $id3v2->remove_frame("TRCK");
   $id3v2->add_frame("TRCK",$trackid);

   # Year
   $id3v2->remove_frame("TYER");
   $id3v2->add_frame("TYER",$year);

   # Podcast tags
   # Managed to fix the tag lib to create an entry which looks like the MP3Tag entry
   # This is the key value for iTunes to recognize a podcast
   $id3v2->remove_frame("PCST");
   $id3v2->add_frame("PCST");

   # Since iOS11 podcasts have been appearing as "Untitled" on the iPhone. The title
   # seems OK in iTunes... but come to think of it I had to revert to a pre-iOS11 version
   # of iTunes because music wouldn't transfer. Anyway I suspect this is related to the Podcast URL
   # tag, which I thing is WFED. Looking at the tags in UE I see that there are two WFED tags in an
   # untitled podcast, only one in a title podcast.
   # 21-Dec-2017 Unfortunately this doesn't appear to have solved the untitled podcast issue, which still exists with
   # the iOS11.2.1 update. Tried changing the URL to start with alphas, maybe URLs starting with numbers
   # are considered to be invalid.
   # I don't remember why the WFED tag is not deleted before being added, maybe it wasn't required,
   # but now it seems it is...
   # iTunes behaviour suggests that the format must be URL like and all tracks that should appear
   # with the same podcast title should have the same URL.

   # This is the tag which iTunes uses to group the podcasts.
   # The leading nul byte is needed for some reason - encoding?? - without
   # it MP3Tag reports bad id3 and does not display the podcast url, with it
   # everything is OK!
   #$id3v2->add_frame("WFED","\x00".$westr);
   $id3v2->remove_frame("WFED");
   $id3v2->add_frame("WFED","\x00https://".$westr.sprintf("%04d", $year));

   # Content type
   $id3v2->remove_frame("TCON");
   $id3v2->add_frame("TCON","Podcast");

   $id3v2->remove_frame("TGID");
   $id3v2->add_frame("TGID", sprintf("%04d%02d%02d%02d%02d", $year, $month, $day, $hour, $minute) . $trackname);

   # Do not add the release date - iTunes will sort on these instead of the track and there
   # is no way to force it to use the track order.
   # Add the release date - it will be adjusted during the autotracknumber
   $id3v2->remove_frame("TDRL");
   $id3v2->add_frame("TDRL", sprintf("%04d-%02d-%02dT%02d:%02d:00", $year, $month, $day, $hour, $minute));

   # Podcasts are always too quiet compared to CD/Radio when played in the car, even when played
   # from the iPhone. I used to apply replaygain using a modified mp3gain (I think) which I thought
   # applied the adjustment to frames in the MP3. Googling for info about replaygain suggests that
   # it is one setting which applies to the entire track and is part of the ID3 tag. So I will try setting
   # it here. I think I had 3.0dB hard coded so that's what I'll use here
   # replaygain used the "Relative Volume Adjustment" tag, RVAD or RVA2 for ID3v2.4
   # Not much info about what values to use for RVAD and MP3::Tag doesn't support it.
   # I've added my own version based on what I did manage to find. The values are magical
   # and are intended to give a +3.0dB gain. The value is based on the output of
   #  $value = (0x69 * 0x100) + 0x33;
   #  $sign = -1;
   #  $vol = 20.0 * log( ( ($value * $sign / 256) + 255 )/255) / log(10);
   #  $vol = 3.00005172185005;
   # Structure I am aiming for in my RVAD tag is
   #    52 56 41 44       RVAD
   #    00 00 00 0A       Tag field size not included header or flags
   #    00 00             Flags
   #    03                Inc/Dec flag - inc L and R channels
   #    10                "Bits used for volume descr"
   #    69 33             Right channel vol change
   #    69 33             Left channel vol change
   #    00 00             Peak right
   #    00 00             Peak left
   # This seems to work (with another mod to ID3v2.pm for RVAD)
   # Tried setting the iTune Volume Adjustment in Options and the result looked pretty similar, 6c6c instead of 6933,
   # I'll use 6c6c, maybe they are both the same value to avoid bigend/littleendian problems
   # Setting the Vol.Adj to +50%, if 6dB=100 then 3dB=50???, resulted in values of 7F7F. This is the value
   # I will use for now. When a new podcast was loaded in iTunes with the gain set by podtag.pl the Vol.Adj. setting
   # was shown in the desired position!!! So it looks like it's working. Remains to be seen whether the value
   # is actually used by the iPhone.
   $id3v2->remove_frame("RVAD");
   $id3v2->add_frame("RVAD", "\x03\x10\x7F\x7F\x7F\x7F\x00\x00\x00\x00");

   # Another Google result suggests iTunes ignores the RVAD flag but uses the
   # COMM tag to contain an iTunNORM value
   # The output for Soundcheck for 3.0 dB:  000001F5 000001F5 000004E5 000004E5 00024CA8 00024CA8 00007FFF 00007FFF 00024CA8 00024CA8
   # So I'll try hard coding that!
   # iTunes did not add this value, so I wont unless the RVAD value appears not to be working.
   # my $sc = "000001F5 000001F5 000004E5 000004E5 00024CA8 00024CA8 00007FFF 00007FFF 00024CA8 00024CA8";
   # $id3v2->add_frame("COMM", "eng", "iTunNORM", $sc);


   # Update the file
   $id3v2->write_tag();

   $mp3->close();
   $LOG->debug("doPodcastTags: tags written to $file\n");
}

sub removeID3
{
my ($file) = @_;
my $mp3 = MP3::Tag->new($file);
   $LOG->info("removeID3: Removing tags from $file\n");
   $mp3->get_tags;

   if ( exists $mp3->{ID3v2} )
   {
      $LOG->info("removeID3: Removing ID3v2 tag from $file\n");
      my $id3v2 = $mp3->{ID3v2};
      $id3v2->remove_tag();
   }
   if (exists $mp3->{ID3v1})
   {
      $LOG->info("removeID3: Removing ID3v1 tag from $file\n");
      my $id3v1 = $mp3->{ID3v1};
      $id3v1->remove_tag();
   }
   $mp3->close();
   $LOG->info("removeID3: Tags removed from $file\n");
}
#####################################################################################################
#######                                                                                       #######
####### APESTRIP Code from https://raw.githubusercontent.com/lbv/base/master/scripts/apestrip #######
#######                                                                                       #######
#####################################################################################################
# read_uint32 BUFFER
#
#   Interpret BUFFER as 4 bytes that contain a little-endian 32bit unsigned
#   integer. Returns that integer.
#
sub read_uint32($) { unpack('V', $_[0]) }


#
# check_for_magic FILE, POS, WHENCE, MAGIC
#
#   Looks inside FILE to check if, starting at the byte pointed at by POS
#   and WHENCE, the MAGIC string can be found. Returns 1 if the magic string
#   is found, 0 otherwise.
#
sub check_for_magic($$$$) {
    my $file   = shift;
    my $pos    = shift;
    my $whence = shift;
    my $magic  = shift;

    my $fh = new IO::File($file, 'r') or die($LOG->fatal("open failed on %s: $!\n", $file));
    my $buf;
    eval {
        $fh->binmode or die($LOG->fatal("binmode failed on %s: $!\n", $file));
        $fh->seek($pos, $whence) or die($LOG->fatal("seek failed on %s: $!\n", $file));

        my $len = length $magic;
        $fh->read($buf, $len) == $len or die($LOG->fatal("read failed on %s: $!\n", $file));
    } or return 0;

    return $buf eq $magic;
}


#
# aperemove FILE, POS, WHENCE
#
#   Modifies the file with name FILE, removing an APEv2 tag that starts at
#   the position given by POS and WHENCE.
#
sub aperemove($$$) {
    my $file   = shift;
    my $pos    = shift;
    my $whence = shift;

    my $fh = new IO::File($file, 'r+') or die($LOG->fatal("open failed on %s: $!\n", $file));
    $fh->binmode or die $!;

    $fh->seek(0, SEEK_END) or die($LOG->fatal("seek failed on %s: $!\n", $file));
    my $fsize = $fh->tell;

    $fh->seek($pos, $whence) or die($LOG->fatal("seek failed on %s: $!\n", $file));
    my $tagpos = $fh->tell;

    # skip tag ID
    $fh->seek(8, SEEK_CUR) or die($LOG->fatal("seek skip tag id failed on %s: $!\n", $file));

    # version
    $fh->read(my $buf, 4) == 4 or die($LOG->fatal("read failed on %s: $!\n", $file));
    my $version = read_uint32($buf);
    die($LOG->fatal("The tag found is not APEv2\n")) if $version != 2000;

    # tag size (items + footer)
    $fh->read($buf, 4) == 4 or die ($LOG->fatal("read failed on %s: $!\n", $file));
    my $tsize = read_uint32($buf);

    # Skip item count
    $fh->seek(4, SEEK_CUR) or die($LOG->fatal("seek failed on %s: $!\n", $file));

    # Flags
    $fh->read($buf, 4) == 4 or die($LOG->fatal("read failed on %s: $!\n", $file));
    my $flags = read_uint32($buf);

    my $is_header = $flags & (1 << 29);
    my $has_footer = ~($flags & (1 << 30));
    my $has_header = $flags & (1 << 31);
    my ($from, $to);
    if ($is_header) {
        $from = $tagpos;
        $to = $from + 32 + $tsize;
    }
    else {
        $from = $tagpos + 32 - $tsize - ($has_header ? 32 : 0);
        $to = $tagpos + 32;
    }

    $LOG->debug( "aperemove: Original file size: $fsize\n");
    $LOG->debug( "aperemove: Stripping from byte $from to byte $to\n");

    if ($to == $fsize) {
        $fh->seek(0, SEEK_SET) or die($LOG->fatal("aperemove: seek failed on %s: $!\n", $file));
        $fh->truncate($from) or die($LOG->fatal("aperemove: truncate failed on %s: $!\n", $file));
    }
    elsif ($from > 0) {
        my $tailsize = $fsize - $to;
        $fh->seek($to, SEEK_SET) or die($LOG->fatal("aperemove: seek failed on %s: $!\n", $file));
        $fh->read($buf, $tailsize) == $tailsize or die($LOG->fatal("aperemove: read failed on %s: $!\n", $file));
        $fh->seek(0, SEEK_SET) or die($LOG->fatal("aperemove: seek failed on %s: $!\n", $file));
        $fh->truncate($from) or die($LOG->fatal("aperemove: truncate failed on %s: $!\n", $file));
        $fh->seek(0, SEEK_END) or die($LOG->fatal("aperemove: seek failed on %s: $!\n", $file));
        $fh->print($buf);
    }
    elsif ($from == 0) {
        $fh->close;
        my $tmpfh = new File::Temp;
        $fh->open($file, 'r') or die($LOG->fatal("aperemove: open failed on %s: $!\n", $file));
        $fh->seek($to, SEEK_SET) or die($LOG->fatal("aperemove: seek failed on %s: $!\n", $file));
        $tmpfh->print($buf) while($fh->read($buf, 4096));
        $fh->close;
        $tmpfh->close;
        move($tmpfh->filename, $file) or die($LOG->fatal("aperemove: move failed on %s to %s: $!\n", $tmpfh->filename, $file));
    }
}

#
# apestrip FILE
#
#   Strip (remove) all APEv2 tags from the MP3 file with name FILE. Based on
#   the information available at:
#   http://wiki.hydrogenaudio.org/index.php?title=APEv2_specification
#
sub apestrip($) {
    my $filename = shift;

    # There are, apparently, 3 places where an APEv2 tag can appear in an
    # MP3 file. The first one is at the very beginning.
    if (check_for_magic($filename, 0, SEEK_SET, 'APETAGEX')) {
        $LOG->debug("apestrip: Removing APEv2 tag from the beginning\n");
        aperemove($filename, 0, SEEK_SET);
    }

    # Or it could be at the very end
    if (check_for_magic($filename, -32, SEEK_END, 'APETAGEX')) {
        $LOG->debug("apestrip: Removing APEv2 tag from the end\n");
        aperemove($filename, -32, SEEK_END);
    }

    # Or finally, it could be at the end, but before an ID3v1 tag
    if (check_for_magic($filename, -128, SEEK_END, 'TAG')
    && check_for_magic($filename, -160, SEEK_END, 'APETAGEX')) {
        $LOG->debug("apestrip: Removing APEv2 tag found before an ID3v1 tag\n");
        aperemove($filename, -160, SEEK_END);
    }
}

##################################
#######                    #######
####### End APESTRIP Code  #######
#######                    #######
##################################



sub decodeutf8url
{
my ($utf8url) = @_;
   my $uri = URI->new($utf8url);
   my $srcpath;

   # This doesn't have the desired effect, the path still contains UTF-8 characters which
   # result in file not found errors. foldermd5 suffered from a similar problem and there
   # the solution was to encode the string as latin-1...
   #Encode::_utf8_on($srcpath);
   $srcpath = decode("UTF-8", $uri->file);
   my $issrc;

   # F--king perl. Tried this with "iso-8859-1" end ended up with a "?" instead of a hypen
   # "iso-8859-1" generally works for foldermd5 so don't know why it fails here. Luckily
   # using cp1250 gives the correct result... Don't know if the decode above is really
   # required but it probably helps to ensure that Perl is interpreting the content of ->file
   # correctly.
   $issrc = encode('cp1250' , $srcpath);
   return $issrc;
}

# Converts invalid filename and undesirable characters, including
# spaces, to underscores
sub sanitize
{
my ($str) = @_;
$str = trim($str);
$str =~ s/[\\\/:\?\*\>\<\$\"\|\' ]/_/g;
$str =~ s/\.+$//;
return $str;
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

package SCULog;
{
# 03 Nov 2014 Updated with stacktrace output for errors.
use Devel::StackTrace;

# This seems to work OK in the class. To use the constans to set the level
# the syntax is like '$log->level(SCULog->LOG_DEBUG);'
use constant { LOG_SILENT => -1, LOG_ALWAYS => 10, LOG_FATAL => 20, LOG_ERROR => 30, LOG_WARN=>40 ,LOG_INFO => 50, LOG_DEBUG => 60, LOG_TRACE => 70};

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
         my $callerfunc = "UnknownCallerFunc(Main??)";
         if(defined $frame)
         {
            $callerfunc = $frame->subroutine;
         }
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
   $self->logmsg(LOG_DEBUG,@_);
}

sub trace
{
my $self = shift;
   $self->logmsg(LOG_TRACE, @_);
}


} # End package SCULog