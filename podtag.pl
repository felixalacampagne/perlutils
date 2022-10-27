#!/usr/bin/perl
#
# 08 Aug 2014 Tried to add replay gain and the iTunes equivalent. The descriptions
#   for both are quite vaugue and I don't know if this is the same kind of replygain
#   that I used to add in the old script. I guess I will need to do some A-B compares
#   to see if there is any effect. I guess it is unlikely to cause a problem providing the
#   tags are valid - requires RVAD modification to MP3::Tag library.
# 07 Aug 2014 Tidied up the log messages so they are easier to read.
# 06 Aug 2014 iTunes converts to local time, to start track one at 22:00 to allow
#   for CET summertime of +2 GMT so all track appear in the same day. Use
#   date arithmetic for the unlikley event that there are ever more than 22
#   tracks also start with track one on Wednesday 22:00.
# 05 Aug 2014 autoRenumber now auto adjusts the release date to give date ordering
#   which matches the filename and track number ordering. This should mean that iTunes
#   will automatically play the tracks in the correct order. iTunes default playorder is
#   the highly useless "newest to oldest", so the release date needs to be manipulated to
#   ensure the first podcast in the week has the most recent release date.
# 31 July 2014 Include the date string in the track title in addition to weekno and pseudo
#   trackno. There can be two episodes from the same podcast in the same week and having the date 
#   ensures they are sorted correctly.
# 29 July 2014 iTunes will sort on the release date if it is present instead of the track
#   number with no way to prevent it from doing so except to remove the release date tag
# 28 July 2014 Figured out why icon displayed by windows is corrupted - unsynchronisation,
#   now disabled and icons look OK. Previously corrupt ones are recovered when the autorenumbering is 
#   done, or by mp3tag.
# 14 July 2014 Added logging. Does not delete the existing ID3v2 tag. Does delete each frame which is
#   going to be updated, otherwise the new content is appended to the existing content resulting in two titles
#   two artists, two contents etc. which is not good. I think the cover image is not being preserved correctly though.
# 12 July 2014 Working pretty much like I want it to.
#   Fixed the WFED tag causing BAD ID3 in mp3tag - WFED tag requires a leading nul character.
#   Original file is marked suffixed with ".done" instead of being deleted. This avoids the Juice podcast script 
#   processing files multiple times.
# 10 July 2014 Nearly working! 
#
#
# DONE: The PCST tag is not understood by the library and does not seem to be written. This is
# very annoying because it is what defines the track as being a podcast in iTunes and
# without it the track will not appear in the podcasts app.
# I therefore customized the MP3::Tag library to create a PCST entry. The result is recognised 
# by iTunes as a podcasts.

use lib 'lib'; # Remove this when the MP3 library is added to the default installation.
use strict;
use warnings;
use strict;
use Getopt::Std;
#use File::Find::Rule;

# WARNING: THe standard version of the library does not support the PCST (or RVAD) tag. A custom
# version of the library with ID3v2.pm.diff changes applied is required to support PCST and
# for this script to work correctly
use MP3::Tag;   # ppm install MP3::Tag (or cpan MP3::Tag for most recent version)
use utf8;
 
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

my $destrootdir="D:\\recordings";
my $donedir = "";

use constant { LOG_SILENT => -1, LOG_ALWAYS => 10, LOG_FATAL => 20, LOG_ERROR => 30, LOG_INFO => 40, LOG_DEBUG => 50};
# NB 'use constant' creates subroutines (WTF???) so "x,y" must be used in the map instead of the normal "x=>y".
my %LOG_LABELS = ( LOG_ALWAYS, "ALWAYS", LOG_FATAL, "FATAL", LOG_ERROR, "ERROR", LOG_INFO, "INFO", LOG_DEBUG, "DEBUG");
my $LOG_LEVEL=LOG_INFO; 
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


sub autoTrackNumber
{
my ($curdir) = @_;
my $dh;
my @mp3files;
my @files;
my $file;
my $trackno;
my $filepath;

my $year="";
my $month="";
my $day="";
my $haveBaseDate=0;
   opendir $dh, $curdir or die(logmsg(LOG_FATAL, "autoTrackNumber: Couldn't open dir '$curdir': $!"));
   @files = grep { !/^\.\.?$/ } readdir $dh;
   closedir $dh;

   logmsg(LOG_INFO, "autoTrackNumber: Found @files in $curdir\n");
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
         logmsg(LOG_INFO, "autoTrackNumber: Setting %s track number to %s\n", $filepath, $trackno);
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
            my $week="";
            my $datevalue="";
            $datevalue = $id3v2->get_frame("TDRL") // "";
            if($datevalue =~ m/(\d{4})-(\d{2})-(\d{2})T\d{2}:\d{2}:\d{2}/)
            {
               $year = $1;
               $month = $2;
               $day = $3;
               # Decided that the release dates should always be on the same day of the week
               # so convert all dates to week no. and year
               ($week, $year) = Week_of_Year($year,$month,$day);
               logmsg(LOG_INFO, "autoTrackNumber: Base date from TDRL tag: %04d-%02d-%02d (Week %02d, Year %04d)\n", 
                  $year, $month, $day, $week, $year);
            }
            else
            {
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
                  logmsg(LOG_INFO, "autoTrackNumber: Using Base date from TALB/TYER: Week %02d, Year %04d\n", $week, $year);
               }
               else
               {
                  
                  my @now = localtime();
                  $year = $now[5]+1900;
                  $month = $now[4]+1;
                  $day = $now[3];
                  ($week, $year) = Week_of_Year($year,$month,$day);
                  logmsg(LOG_INFO, "autoTrackNumber: Using Base date today: %04d-%02d-%02d (Week %02d, Year %04d)\n", 
                     $year, $month, $day, $week, $year);
               }
            }

            ($year, $month, $day) = Monday_of_Week($week, $year);
            
            # Use Wednesday as the base release date
            ($year,$month,$day) = Add_Delta_Days($year,$month,$day, 2);
            $haveBaseDate = 1;
         }
         
         if($haveBaseDate > 0)
         {
            # Track 1 must be the newest, the last track the oldest
            # which is counterintuitive but it is the default play order for the iTunes app.
            # So track 1 will correspond to hour 23, track 23 to hour 01
            # Need to use 22:00 as base time as iTunes converts the date from UTC to 
            # local time, so the first couple of tracks appear in the next day.
            # Max. GMT offset in Be is +2hrs.
            my @tim = Add_Delta_DHMS($year,$month,$day, 22,0,0, 0,-$trackno,0,0);
            my $reldate = sprintf("%04s-%02d-%02dT%02d:00:00", $tim[0], $tim[1], $tim[2],$tim[3]);
            logmsg(LOG_INFO, "autoTrackNumber: Calculated release date is %s\n", $reldate);
            $id3v2->remove_frame("TDRL");   
            $id3v2->add_frame("TDRL", $reldate);
         }

         $id3v2->write_tag();
      }      
      else
      {
         logmsg(LOG_INFO, "autoTrackNumber: NO ID3v2 tags in %s\n", $filepath);
      }
   }
   
}

sub doPodcastTags
{
my ($file, $trackname, $week, $trackid, $year, $month, $day, $hour, $minute) = @_;
my $mp3 = MP3::Tag->new($file);
my $id3v2;
my $westr = sprintf("WE%02d", $week);

   logmsg(LOG_INFO, "doPodcastTags: Setting podcast tags for $file: %s %s %s\n",$trackname,$trackid,$westr);
   
   # Stupidly this gives an error if there are no tags
   # but if it isn't called then the exists check always fails    
   $mp3->get_tags;   
   if (exists $mp3->{ID3v1}) 
   {
      logmsg(LOG_INFO, "removeID3: Deleting ID3v1 tag from $file\n");
      my $id3v1 = $mp3->{ID3v1};
      $id3v1->remove_tag();
   }
      
   if ( exists $mp3->{ID3v2} ) 
   {
      #logmsg(LOG_INFO,  "doPodcastTags: Deleting existing ID3v2 tag for $file\n");
      logmsg(LOG_INFO, "doPodcastTags: Using existing ID3v2 tag for $file\n");
      $id3v2 = $mp3->{ID3v2};
      #$id3v2->remove_tag();
   }
   else
   {
      logmsg(LOG_INFO, "doPodcastTags: Creating new ID3v2 tag for $file\n");
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
   $id3v2->add_frame("PCST");
   
   # This is the tag which iTunes uses to group the podcasts.
   # The leading nul byte is needed for some reason - encoding?? - without
   # it MP3Tag reports bad id3 and does not display the podcast url, with it
   # everything is OK!
   $id3v2->add_frame("WFED","\x00".$westr);

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
   logmsg(LOG_INFO, "doPodcastTags: tags written to $file\n");
}

sub removeID3
{
my ($file) = @_;
my $mp3 = MP3::Tag->new($file);
   logmsg(LOG_INFO,  "removeID3: Removing tags from $file\n");
   $mp3->get_tags;

   if ( exists $mp3->{ID3v2} ) 
   {
      logmsg(LOG_INFO,  "removeID3: Removing ID3v2 tag from $file\n");
      my $id3v2 = $mp3->{ID3v2};
      $id3v2->remove_tag();        
   }
   if (exists $mp3->{ID3v1}) 
   {
      logmsg(LOG_INFO, "removeID3: Removing ID3v1 tag from $file\n");
      my $id3v1 = $mp3->{ID3v1};
      $id3v1->remove_tag();
   }
   $mp3->close();
   logmsg(LOG_INFO, "removeID3: Tags removed from $file\n");
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

    my $fh = new IO::File($file, 'r') or die(logmsg(LOG_FATAL, "open failed on %s: $!\n", $file));
    my $buf;
    eval {
        $fh->binmode or die(logmsg(LOG_FATAL, "binmode failed on %s: $!\n", $file));
        $fh->seek($pos, $whence) or die(logmsg(LOG_FATAL, "seek failed on %s: $!\n", $file));

        my $len = length $magic;
        $fh->read($buf, $len) == $len or die(logmsg(LOG_FATAL, "read failed on %s: $!\n", $file));
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

    my $fh = new IO::File($file, 'r+') or die(logmsg(LOG_FATAL, "open failed on %s: $!\n", $file));
    $fh->binmode or die $!;

    $fh->seek(0, SEEK_END) or die(logmsg(LOG_FATAL, "seek failed on %s: $!\n", $file));
    my $fsize = $fh->tell;

    $fh->seek($pos, $whence) or die(logmsg(LOG_FATAL, "seek failed on %s: $!\n", $file));
    my $tagpos = $fh->tell;

    # skip tag ID
    $fh->seek(8, SEEK_CUR) or die(logmsg(LOG_FATAL, "seek skip tag id failed on %s: $!\n", $file));

    # version
    $fh->read(my $buf, 4) == 4 or die(logmsg(LOG_FATAL, "read failed on %s: $!\n", $file));
    my $version = read_uint32($buf);
    die(logmsg(LOG_FATAL, "The tag found is not APEv2\n")) if $version != 2000;

    # tag size (items + footer)
    $fh->read($buf, 4) == 4 or die (logmsg(LOG_FATAL, "read failed on %s: $!\n", $file));
    my $tsize = read_uint32($buf);

    # Skip item count
    $fh->seek(4, SEEK_CUR) or die(logmsg(LOG_FATAL, "seek failed on %s: $!\n", $file));

    # Flags
    $fh->read($buf, 4) == 4 or die(logmsg(LOG_FATAL, "read failed on %s: $!\n", $file));
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

    logmsg(LOG_DEBUG,  "aperemove: Original file size: $fsize\n");
    logmsg(LOG_DEBUG,  "aperemove: Stripping from byte $from to byte $to\n");

    if ($to == $fsize) {
        $fh->seek(0, SEEK_SET) or die(logmsg(LOG_FATAL, "aperemove: seek failed on %s: $!\n", $file));
        $fh->truncate($from) or die(logmsg(LOG_FATAL, "aperemove: truncate failed on %s: $!\n", $file));
    }
    elsif ($from > 0) {
        my $tailsize = $fsize - $to;
        $fh->seek($to, SEEK_SET) or die(logmsg(LOG_FATAL, "aperemove: seek failed on %s: $!\n", $file));
        $fh->read($buf, $tailsize) == $tailsize or die(logmsg(LOG_FATAL, "aperemove: read failed on %s: $!\n", $file));
        $fh->seek(0, SEEK_SET) or die(logmsg(LOG_FATAL, "aperemove: seek failed on %s: $!\n", $file));
        $fh->truncate($from) or die(logmsg(LOG_FATAL, "aperemove: truncate failed on %s: $!\n", $file));
        $fh->seek(0, SEEK_END) or die(logmsg(LOG_FATAL, "aperemove: seek failed on %s: $!\n", $file));
        $fh->print($buf);
    }
    elsif ($from == 0) {
        $fh->close;
        my $tmpfh = new File::Temp;
        $fh->open($file, 'r') or die(logmsg(LOG_FATAL, "aperemove: open failed on %s: $!\n", $file));
        $fh->seek($to, SEEK_SET) or die(logmsg(LOG_FATAL, "aperemove: seek failed on %s: $!\n", $file));
        $tmpfh->print($buf) while($fh->read($buf, 4096));
        $fh->close;
        $tmpfh->close;
        move($tmpfh->filename, $file) or die(logmsg(LOG_FATAL, "aperemove: move failed on %s to %s: $!\n", $tmpfh->filename, $file));
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
        logmsg(LOG_DEBUG, "apestrip: Removing APEv2 tag from the beginning\n");
        aperemove($filename, 0, SEEK_SET);
    }

    # Or it could be at the very end
    if (check_for_magic($filename, -32, SEEK_END, 'APETAGEX')) {
        logmsg(LOG_DEBUG, "apestrip: Removing APEv2 tag from the end\n");
        aperemove($filename, -32, SEEK_END);
    }

    # Or finally, it could be at the end, but before an ID3v1 tag
    if (check_for_magic($filename, -128, SEEK_END, 'TAG')
    && check_for_magic($filename, -160, SEEK_END, 'APETAGEX')) {
        logmsg(LOG_DEBUG, "apestrip: Removing APEv2 tag found before an ID3v1 tag\n");
        aperemove($filename, -160, SEEK_END);
    }
}

##################################
#######                    #######
####### End APESTRIP Code  #######
#######                    #######
##################################




sub usage {
    print
"podtag <Original mp3 file> [<Destination directory> [<Done directory>]]\n";
    exit;
}

##################################
#######                    #######
####### Main program       #######
#######                    #######
##################################


MP3::Tag->config( write_v24 => 1 );

# Not sure what "unsync" is about but apparently it fixes the image corruption
# which seems to happen when a tag containing an image is modified. The posts
# concerning this issue refer to a line in ID3c2.pm similar to 
#     $flags = chr(128) if $tag_data =~ s/\xFF(?=[\x00\xE0-\xFF])/\xFF\x00/g;
# JPEGs seem to always contain "FFD8 FFE0" at the start of the data. This is changed
# to "FFD8 FF 00 E0" without increasing the size of the field. Since the image 
# data is binary the body might also be corrupted in the same way.
# Unsetting the "id3v23_unsync" option prevents the FFE0 sequence from being
# corrupted and Windows shows the file icon normally. No idea what other
# impact the flag might have, Google suggests that it's something for legacy
# mp3 players....
# Sooo, coming under the heading "way too much information": the unsync
# stuff is something to do with preventing data in the tag from being interpreted by 
# a player as valid mp3 audio data when it doesn't understand id3 tags. The FFE0 to 
# FFFF values mean something like "a section of music data starts here", so one of 
# these values in the middle of the tag would cause a player which doesn't recognise 
# the id3 tag to start interpreting the tag as music, probably resulting in a burst
# of static. To avoid this the syncronization sequence is broken by inserting a nul
# between the FF and the second byte. When this is done the tag header indicates 
# it by setting bit 8 of byte 6 (0x80) so the tag can be "de unsynchronised" when
# it is read. See http://id3lib.sourceforge.net/id3/id3v2.3.0.html
# Apparently Windows doesn't understand the concept of "unsynchronisation" but mp3tag does, 
# which explains why the images look OK in mp3tag but appear corrupt in Explorer. 
# My podcast player can understand the id3 tag so no worries about 
# disabling the "unsynchronisation"

MP3::Tag->config("id3v23_unsync_size_w",0);
MP3::Tag->config("id3v23_unsync",0);

#our $opt_d;
#my $opt_string = 'd:';
#getopts( 'd:', $opt_d ) or usage();
#my $dir = $opt_d;

my $mp3file = $ARGV[0];

if(@ARGV > 1)
{
   $destrootdir = $ARGV[1];
}

if(@ARGV > 2)
{
   $donedir = $ARGV[2];
}
# Now can add the desired tags for the podcast.
# Note sure how to handle this yet. Can calculate the week number
# from the current time, or maybe get it from the creation date of the file
# or even from the file title, since all my podcasts are from teh BBC and
# they are using a pretty standard format.
# Also need to figure out a track number. This is sort of done
# by looking at the title and assigning a "priority", can do the same
# for the track but this will result in podcasts with the same track no.
# Could maybe prefix with the week number, especially if using the filename date.
#
# Podcast filenames look like digitalp_20140708-2030a.mp3
my $year;
my $month;
my $day;
my $hour;
my $minute;
my $week;
my $trackid;
logmsg(LOG_INFO, "podtag: Filename: $mp3file\n");
if( $mp3file =~ m/.*_(\d{4})(\d{2})(\d{2})\-(\d{2})(\d{2})\w?\.mp3$/i )
{
      $year = $1;
      $month = $2;
      $day = $3;
      $hour = $4;
      $minute = $5;
     
}
else
{
      my @now = localtime();
      $year = $now[5]+1900;
      $month = $now[4]+1;
      $day = $now[3];
      $hour = $now[2];
      $minute = $now[1]; 
}

# NB: Would be nice to read date from the release date tag however currently (07-08-14) the podcasts
# do not have the tag.

# Use Date::Calc function to get consistent week number <-> date conversions
# Date::Calc.Week_of_Year gives a more "correct" value and is consistent with the value
# returned by Date::Calc.Monday_of_Week used in autotracknumber
($week,$year) = Week_of_Year($year,$month,$day); 

# Now to decide on the track number. This is currently determined by a command line
# script based on a number of known filenames, with unrecognized names being
# put at the end. Will do the same here, using the weeknumber as a track prefix so
# The order should at least respect chronological order, although using the date in the
# filename will probably make this redundant as the week number will always be the same
# regardless of when the file was downloaded. This might cause a problem when downloading
# really old podcasts, but will deal with that if it really is a problem
my $trackname;
my $fullpath = File::Spec->rel2abs($mp3file);
my ($filename,$directories,$suffix) = fileparse( $fullpath );

if( $mp3file =~ m/(.*)(fooc)_20(\d{6})(.*\.mp3)$/i )
{
   $trackid = 20;
   $trackname = $2;
}
elsif( $mp3file =~ m/(.*)(markkermodesfilmreviews)_20(\d{6})(.*\.mp3)$/i )
{
   $trackid = 22;
   $trackname = $2;
}
elsif( $mp3file =~ m/(.*)(kermode)_20(\d{6})(.*\.mp3)$/i )
{
   $trackid = 23;
   $trackname = $2;
}
elsif( $mp3file =~ m/(.*)(archersomni)_20(\d{6})(.*\.mp3)$/i )
{
   $trackid = 1;
   $trackname = $2;
}
elsif( $mp3file =~ m/(.*)(did)_20(\d{6})(.*\.mp3)$/i )
{
   $trackid = 30;
   $trackname = $2;
}
elsif( $mp3file =~ m/(.*?)[\\\/]?(\w+)_20(\d{6})(.*\.mp3)$/i )
{
   $trackid = 80;
   $trackname = $2;
}
else
{
   $trackid = 99;
	$trackname = $filename;
}

$trackid = sprintf("%02d%02d", $week, $trackid);

logmsg(LOG_INFO, "podtag: File: $mp3file Week: $week TrackID: $trackid Trackname: $trackname\n");
# Used to rename the files because the play order was determined by
# the filename. No longer the case with podcasts on iPhone so no
# need to rename. Although maybe it still makes sense - can copy the
# file to it's WExx directory then list all files in the directory sorted
# by name and renumber all tracks. For this to work correctly the
# name of the file should be prefixed with the date as well as the trackid
# so multiple occurrences with the same id get sorted by
# date.
my $renameto;
my $wedir;

   $renameto = sprintf("%s-%04d%02d%02d_%s.mp3", $trackid, $year, $month, $day, $trackname);
   $trackname = sprintf("%s-%s-%04d%02d%02d", $trackid, $trackname, $year, $month, $day);
   
   logmsg(LOG_INFO, "New filename: $renameto\n");

   $wedir = File::Spec->catdir($destrootdir, sprintf("we%02d", $week));
   
   # Create WExx directory
   unless(-d $wedir)
   {
      #print "Creating album directory: " . $mpalbumdir . "\n";
      make_path($wedir)  ;
   }   
   
   # Copy the file to Wexx directory
   $renameto = File::Spec->catdir($wedir, $renameto);    
   if(!copy($mp3file, $renameto))
   {
         # binmode STDOUT, ":encoding(UTF-8)";
         ;
         die(logmsg(LOG_FATAL, "podtag: FAILED Copying " . $mp3file . " to " . $renameto . ": " . $!));
   }   
   
   # remove tags from copy
   # The APE tags seems to cause all sorts of problems so remove them first
   apestrip($renameto);  # Got this from the web - hope it works!!
   #removeID3($renameto);
   
   # Add podcast tags to cpoy
   doPodcastTags($renameto, $trackname, $week, $trackid, $year, $month, $day, $hour, $minute);
   
   
   # Set trackno. of all tracks according to sorted order
   autoTrackNumber($wedir);
   
   # delete original - to risky for now (needs more error handling), so move the file to a done location and rename to .done
   # so it doesn't get included in subsequent .mp3 searches.
   # unlink $mp3file;   
   if($donedir ne "" )
   {
      # Move file to the done directory
      my $donefile = File::Spec->catdir($donedir, $filename . ".done");
      if(copy($mp3file, $donefile))
      {
         
         unlink $mp3file;
         logmsg(LOG_INFO, "podtag: Original file " . $mp3file . " moved to " . $donefile . "\n");
      } 
      else
      {
         logmsg(LOG_ERROR, "podtag: Failed to copy " . $mp3file . " to " . $donefile . ": " . $!);
      }
   }
   
   # done