#!/usr/bin/perl
# perl it2gmp.pl <itunes XML format playlist> <mp3 player path>
# see end for additional change details
#             NB. This is v2 in case the forking stuff can't be made to work.
# 02 Apr 2020 Multiple simultaneous conversions working in spite of the broken waitpid function. Uses the
#             presence of the tmp file to indicate a finished job.
# 03 Apr 2020 Having stumbled across a way to get waitpid to work use of tmp file is abandoned. Conversion
#             is directly from the original src file (without deletion at the end!!)
# 04 Apr 2020 Fix for rand returning same value before output file has been created.
#             Could actually call this the release version!
#             On speedy 30GB was output to a local HDD (V:) in 3hours using 8 processes.
# 05 Apr 2020 Track count allows for running jobs
# 14 Sep 2020 Tweaks to file name conversion from experience with old version on holiday
#             Added playlist order conversion option, instead of random selection, which is still the default.
# 13 Jan 2024 Take size of files already present in destination directory into account. This is
#             because the tool is most often used to write to a temp directory on large disks in multiple sessions
#             where the overall size of the directory should not exceed the total size specified.
#             Uses composer instead of artist to reduce number of single file directories belong to
#             uncommon 'one-hit wonder' artists.
#             NB. deletion of old files is DISABLED by default: use -nok (--nokeep) to prevent deletion

use 5.010;  
use strict;
use XML::Simple;
use Data::Dumper;
use Mac::iTunes::Library::XML; # cpanm Mac::iTunes::Library From http://search.cpan.org/~dinomite/Mac-iTunes-Library-1.0/
use Mac::iTunes::Library::Playlist;
use Win32::DriveInfo;  # Not installed by default: cpanm Win32::DriveInfo
use File::Basename;
use File::Spec;
use File::Copy;
use File::Path qw(make_path remove_tree);
use File::Temp qw(tempfile);
use File::Find;
use File::stat;
use URI::Escape;
use URI::file;
use Encode qw(decode encode);
use Date::Calc qw(Today_and_Now Delta_DHMS);

use Win32::API;
use Getopt::Long;

Getopt::Long::Configure("pass_through", "bundling_override");

my $RESERVEDSPACE=20;  # Stop when less than 20MB are available
# Requires FFMPEG to be defined as the command to execute ffmpeg
my $FFMPEG=$ENV{FFMPEG} . "";

my @timestart = Today_and_Now();
my $log = SCULog->new(); 
$log->level(SCULog->LOG_DEBUG);

my $itunesxmlpl = "N:\\Music\\playlists\\music.xml";
my $playerroot="K:\\Music";
my $maxfiles = 0;
my $maxbytes = 0;
my $procs = 3;
my $keepoldfiles = 0;
my $playerdrv;
my $pathname;
my %cnvjobs = (); # hash of hash references to conversion jobs in progress
my $rndtrk = 1;   # 1-randomly select tracks to convert from list, 0-convert tracks using playlist order

my $optpl = "";
my $optmp = "";
my $optcnt = 0;
my $optsz = 0;
my $optkeep = 1;
my $optjob = 0;
my $optorder = 0;
# set FFMPEG=%UTLDIR%\ffmpeg\ffmpeg
# set FFMPEG=%UTLDIR%\ffmpeg\bin\ffmpeg
# perl it2gmpA.pl -p "N:\Music\playlists\music.xml" -m "k:\Music"
# perl it2gmpA.pl -m "V:\mediaplayer\Music" -s 10GB -j 8
# perl it2gmpA.pl -m "V:\mediaplayer\Music" -c 500 -j 8
# perl it2gmpA.pl -m "c:\temp\Music" -s 2GB
GetOptions('playlist|p=s' => \$optpl,
           'mplayer|m=s' => \$optmp,
           'count|c=i' => \$optcnt,
           'size|s=s' => \$optsz,
           'keep|k!' => \$optkeep,
           'jobs|j=i' => \$optjob,
           'ordered|o' => \$optorder);

if($optorder != 0)
{
   $rndtrk = 0;  # Copy files in playlist order instead of randomly  
}

if($optpl ne "")
{
   $itunesxmlpl = $optpl;
}

if($optmp ne "")
{
   $playerroot=$optmp;
}

if($optsz ne "")
{
   $maxbytes = $optsz;
   if($optsz =~ /\d+MB$/i)
   {
      $maxbytes *= 1000000;
   }
   elsif($optsz =~ /\d+GB$/i)
   {
      $maxbytes *= 1000000000;
   }
}

if($optjob > 1)
{
   # 3 = four simultaneous jobs
   $procs = $optjob - 1;
}


$maxfiles = $optcnt;
$keepoldfiles = $optkeep;

$log->debug("iTunes XML Playlist: %s\n", $itunesxmlpl);
$log->debug("Mediaplayer root:    %s\n", $playerroot);
if($maxfiles > 0)
{
   $log->debug("Max. files:          %d\n", $maxfiles);
}
if($maxbytes > 0)
{
   $log->debug("Max. bytes:          %d\n", $maxbytes);
}

if($maxbytes < 0)
{
   exit(1);
}
if($FFMPEG eq "")
{
   print "FFMPEG environment variable must be set to point to the ffmpeg executable";
   exit(1);
}
if($itunesxmlpl eq "" || $playerroot eq "")
{
   $log->info("perl it2tw.pl <iTunes XML Playlist> <player music root>\n");
   exit(1);
}

my $itLibrary = Mac::iTunes::Library::XML->parse($itunesxmlpl);
my @items = $itLibrary->playlists();


$playerroot = File::Spec->rel2abs($playerroot);
$playerdrv = substr $playerroot,0,1;

if($keepoldfiles == 0)
{
   $log->debug("Deleting old files.\n");
   cleanroot($playerroot);
}

$log->debug("Adding new files.\n");

# Need to pick tracks randomly from the playlist since it is probably sorted and probably much larger
# than the destination can handle.
# So will need to loop until either the space runs out or all tracks are transferred.

# Need some Perl magic here since I have no idea what "$pl->items()" represents - 
# treating it as an array seems to work as desired
# Just have to know that the playlist is in item 1
my $pl = @items[1];
my @plItems = $pl->items();
my $plcount = @plItems;
my $plIdx = 0;


my $trackcnt = 0;

# Take into account the size of the files already present in the destination directory
my $initialbytecount = dirsize($playerroot);

my $bytecount = 0;
$log->debug("Number of items in playlist: %d\n", $plcount);

my $track;
my @timefilecopy = Today_and_Now();

# By default $tracktotal is the number of items in the list, which assumes the random selection
# does not select the same file twice which is probably OK, especially when there are way
# more tracks than will fit on a normally sized 'media player', ie. a 32GB USB drive is pretty much
# the max. the car player can handle.
# If a max no. of track was specified then simply use it as limit
my $tracktotal = $plcount;
if(($maxfiles > 0) && ($maxfiles < $tracktotal))
{
   $tracktotal = $maxfiles; 
}

$log->debug("Max. number of tracks to write: %d\n", $tracktotal);
my $asyncpid = 0;
my $asyncdestfile = "";
my $avgsz = 0;
my $runningjobs = 0;
my $dirbytetotal = $initialbytecount;
if($maxbytes > 0)
{
   my $space = $maxbytes - $initialbytecount;
   $log->debug("Initial available space in directory: %s (%s)\n", formatsize($space), $space);
}
while(($trackcnt + $runningjobs) < $tracktotal)
{
   wakeywakey();
   $dirbytetotal = $initialbytecount + $bytecount;
   if( checkFreeSpace($playerdrv, $RESERVEDSPACE) < 1)
   {
      $log->info("Out of diskspace on %s:\\ - exiting\n", $playerdrv);
      last;  
   }
   elsif($maxbytes > 0)
   {
      if($dirbytetotal >= ($maxbytes - ($avgsz * $runningjobs)  ))
      {
         $log->debug("Max. bytecount (%d) exceeded: %d (jobs:%d avg:%d pend:%d)\n", $maxbytes, $dirbytetotal, $runningjobs, $avgsz, ($avgsz * $runningjobs));
         last;
      }
      $log->info("Written Tracks: %d Bytes: %d Remaining: %s\n", $trackcnt, $bytecount, formatsize($maxbytes-$dirbytetotal));
   }
   else
   {
      $log->info("Written Tracks: %d Bytes: %d\n", $trackcnt, $bytecount);
   }
   if($trackcnt > 0)
   {
      $avgsz = $bytecount / $trackcnt;
   }
   # Aaaggghhh! Rand returned the same value in close succession. The job
   # for the first value was started but had not yet created the destination file
   # so the check for the existence of the file was false. This shouldn't really be
   # an issue, just repeated effort, but bloody ffmpeg stopped with a prompt to
   # overwrite the existing file, so the whole process ground to an invisible halt.
   # It might be possible to tell ffmpeg not to prompt but it will also be more
   # efficient to prevent choosing the same value twice. Could use splice to
   # remove the value or just set it to a 'deleted' value.
   if($rndtrk != 0)
   {
      do
      {
         $plIdx = int(rand($plcount)); 
         $track = $plItems[$plIdx];
      }while(!defined($track));
   }
   else
   {
      $track = $plItems[$plIdx];
   }
   $plItems[$plIdx] = undef; # Prevent track from being selected again (for random mode)
   $plIdx++;                 # Move index to next track (for ordered mode)
   
   # Determine track parent folder name
   # Location is in the format of a URL, with URL escapes. URI converts to a "normal", de-escaped, filename.
   # For files/dirs containing accents etc. to be created correctly the encoding of the variables
   # must be changed. Once changed the encoding seems to "stick", ie. can be passed from one var to another.
   # vars which have been made safe for filename as suffixed with FS.
   my $uri = URI->new($track->location());
   my $srcpathFS = $uri->file;
   Encode::_utf8_on($srcpathFS);
   $srcpathFS = getFSname($srcpathFS);
   
   # Composer is better than artist for compilations because 'artist' can result in many single
   # file directories but 'composer' is usually the album title instead of being the same as artist
   # so all the 'one track wonders' are grouped in their own directory
   my $albumFS = sanitize(getFSname($track->album()));   
   my $artistFS = sanitize(getFSname($track->composer())); # sanitize(getFSname($track->artist()));
   
   my ($volFS, $directoriesFS, $fileFS) = File::Spec->splitpath($srcpathFS);

   # NB No need to sanitize $fileFS - it is already an actual filename, so therefore must be valid.
   # On the other hand the tag values may contain invalid filename characters. 
   
   # Instead of using artist\album\track will use artist\album-trackfilename 
   my $mpalbumdirFS = File::Spec->catfile($playerroot, $artistFS);
   $fileFS = $albumFS . "-" . $fileFS;
   my $destpathFS = File::Spec->catfile($mpalbumdirFS, $fileFS);

   # Dest will always be an mp3 file. Conversion handled below based on source filetype (extension)
   $destpathFS =~ s/\.[^\.]*$/.mp3/g; 
   #$log->debug("Dest Filepath: %s\n", $destpathFS);
   
   # Before here there are unlikely to be exceptions
   # but since the filesystem is now involved there might be exceptions, eg.
   # bad filename, missing network disk, so try to trap them and continue in
   # case the exception condition is transient.
   # Apparently 'eval' is the Perl equivalnet of try...catch
   
   eval
   {
      unless(-d $mpalbumdirFS)
      {
         $log->debug("Creating album directory: %s\n", $mpalbumdirFS);
         make_path($mpalbumdirFS);
      }
   
      unless(-f $destpathFS)
      {
         $log->info("Track %s to %s\n", $srcpathFS,  $destpathFS);
         
         # Direct copy only possible if source is mp3
         # Otherwise convert source to mp3 using destpathFS as the output
         if($srcpathFS =~ m/.*\.m4a$/i)
         {
            # If an async conversions has been launched wait for it to stop
            $runningjobs = keys %cnvjobs; # This is how you have to find the size!!!!!
            if($runningjobs > $procs)
            {
               $log->debug("No. jobs in progress: %d.\n", $runningjobs);

               my $wprc=-1;
               while($wprc == -1)
               {
                  # Forking piece of shirt doesn't even wait for any child to exit and 
                  # always returns -1. This is with waitpid(0,0) which as far as I can tell
                  # from the piss poor documenation should wait indefinitely for any child to terminate.
                  # BUT when I give pid=-1 and 2nd param=10000 waitpid starts to 
                  # return the PIDs of the finished jobs! Why the fork couldn't the docs
                  # say that's how it works! actually it is completely unclear what the
                  # second parameter is for, is it just for flags, in which case what are
                  # the possible values, or is it for timeout as well, in which case
                  # how to specify no timeout????
                  # 
                  $log->debug("Waiting for a job to finish.\n");
                  $wprc = waitpid(-1, 360000);
                  #$log->debug("waitpid return: %d\n", $wprc);
                  if(exists $cnvjobs{$wprc})
                  {
                     $asyncdestfile = $cnvjobs{$wprc}->{'dst'};
                     my $outsz = stat($asyncdestfile)->size;
                     $log->debug("Job %d terminated. Size of converted file %s: %d\n", $wprc, $asyncdestfile, $outsz);
                     $bytecount += $outsz;
                     $trackcnt++;
                     delete ($cnvjobs{$wprc});
                     # More Perl madness, can 'last' out of while loop but not a do...while loop - WTF?? 
                     last;
                  }
               }
               
               $runningjobs = keys %cnvjobs;
               $log->debug("Size of job list after wait loop: %d\n", $runningjobs);
               if(($maxbytes>0) && ($bytecount >= ($maxbytes - ($avgsz * $runningjobs)  )))
               {
                  $log->debug("Max. bytecount exceeded with %d jobs still running: %d (%d @ %d), \n", $runningjobs, $bytecount, ($avgsz * $runningjobs), $avgsz);
                  last;
               }
            }
            
            $asyncdestfile = $destpathFS;

            my $ffmpegcmd;
            #$log->info("Converting AAC file " . $srcpathFS . " to MP3 file " .  $destpathFS . "\n");
            # ffmpeg -i <infile>.m4a -c:v copy -map 0 -metadata:s:v title="cover" -metadata:s:v comment="Cover (Front)"  -id3v2_version 3 -write_id3v1 1 -codec:a libmp3lame -q:a 0 <outfile>.mp3
            $ffmpegcmd = sprintf("\"%s\" -i \"%s\" -n -nostdin -hide_banner -nostats -loglevel error -c:v copy -map 0 -metadata:s:v title=\"cover\" -metadata:s:v comment=\"Cover (Front)\" -id3v2_version 3 -write_id3v1 1 -codec:a libmp3lame -q:a 0 \"%s\"", $FFMPEG, $srcpathFS, $destpathFS);
            $log->debug("Launching conversion command: %s\n", $ffmpegcmd);
            
            $asyncpid = fork();
            if($asyncpid == 0)
            {
               # This bit is performed by the CHILD
               $log->debug("CHILD: Start: %s\n", $asyncdestfile);
               system($ffmpegcmd);
               $log->debug("CHILD: Done: %s\n", $asyncdestfile);
               exit(0);
            }
            # Although the most obvious real world use of a hash is to store multiple hashes (since a hash is the
            # closest thing to a struct in Perl) it is very difficult to figure out how to actually do it!
            # Apparently the following should just create the hash keyed by pid in the hash 
            
            $cnvjobs{$asyncpid}{'pid'} = $asyncpid;
            $cnvjobs{$asyncpid}{'dst'} = $asyncdestfile;
            $runningjobs = keys %cnvjobs;
            $log->debug("Added job %d to list: running jobs = %d\n", $asyncpid, $runningjobs);
         }
         elsif($srcpathFS =~ m/.*\.mp3$/i)
         {
            if(!copy($srcpathFS,  $destpathFS))
            {
               $log->warn("FAILED to copy " . $srcpathFS . " to " .  $destpathFS . ": " . $! . "\n");
            }
            else
            {
               $trackcnt++;
               $bytecount += stat($destpathFS)->size;
            }
         }
         else
         {
            $log->warn("UNSUPPORTED file type: " . $srcpathFS . "\n");
         }
      }  
      1; # Must always return 1 from the eval block
   } # end of eval
   or do
   {
      my $error = $@ || 'Unknown failure';
      $log->error(" Error: %s: Failed to transfer %s\n", $error, $destpathFS);
   };

}



# Wait for any pending conversion jobs to finish
my $runningjobs = keys %cnvjobs; # This is how you have to find the size!!!!!
while($runningjobs > 0)
{
   $log->debug("No. jobs still in progress: %d. Waiting for conversion jobs to complete\n", $runningjobs);
   my $donepid = 0;
   my $wpc = waitpid(-1, 10000);
   if(exists $cnvjobs{$wpc})
   {
      $asyncdestfile = $cnvjobs{$wpc}->{'dst'};
      my $outsz = stat($asyncdestfile)->size;
      $log->debug("Size of converted file %s: %d\n", $asyncdestfile, $outsz);
      $bytecount += $outsz;
      $trackcnt++;
      delete ($cnvjobs{$wpc});
   }
  
   $runningjobs = keys %cnvjobs;
}

if($maxbytes>0)
{
   $log->debug("Total bytes: written: %d remaining: %d\n", $bytecount, $maxbytes - $bytecount);
}





if($trackcnt > 0)
{
   my @timeend = Today_and_Now();
   my @elapsed = Delta_DHMS(@timestart, @timeend); # ($days,$hours,$minutes,$seconds)
   
   $log->info("Finished at:                 %s\n", ymdhmsString(@timeend));
   
   @elapsed = Delta_DHMS(@timestart, @timefilecopy);
   $log->info("Elapsed time;\n");
   $log->info("   delete files:             %02d:%02d:%02d\n", $elapsed[1],$elapsed[2],$elapsed[3]);
   
   @elapsed = Delta_DHMS(@timefilecopy, @timeend);
   $log->info("   copy files:               %02d:%02d:%02d\n", $elapsed[1],$elapsed[2],$elapsed[3]);
   
   @elapsed = Delta_DHMS(@timestart, @timeend);
   $log->info("   total:                    %02d:%02d:%02d\n", $elapsed[1],$elapsed[2],$elapsed[3]);
   $log->info("Tracks written:              %d out of %d\n", $trackcnt, $tracktotal);
   $log->info("Bytes written:               %d\n", $bytecount); 
} 

exit(0);

sub checkFreeSpace
{
my $drv = shift;
my $mbreq = shift;
my $bytesreq = $mbreq * 1024 * 1024;
   
my $freebytes = (Win32::DriveInfo::DriveSpace($drv))[6];
my $ret = ($freebytes > $bytesreq) ? 1 : 0;
$log->debug("%s:\\: Free %s (%d)  Min: %s (%d)  Ret: %d\n", $drv, formatsize($freebytes), $freebytes, formatsize($bytesreq), $bytesreq, $ret);
return $ret
}

# Returns the total size in bytes of the files in the given directory and sub-directories
sub dirsize
{
my ($dir) = @_;
my $total  = 0;
   find(sub { $total += -s if -f }, $dir);
   return $total;
}

# Returns number of files in the given directory and sub-directories
sub dircount
{
my ($destdir) = @_;
my $fcount = 0;
   find(sub { $fcount += 1 if -f }, $destdir);
   return $fcount;
}

sub formatsize {
my $size = $_[0];
   foreach ('B','KB','MB','GB','TB','PB')
   {
      return (sprintf("%.2f",$size) . "$_") if $size < 1024;
      $size /= 1024;
   }
   return "Too large!";
}

# Removes all files and folders from the root dir
sub cleanroot
{
my $rootdir = shift;
   $rootdir = File::Spec->rel2abs($rootdir);
   $log->debug("Cleaning directory: %s\n", $rootdir);
   remove_tree($rootdir,  {keep_root => 1});
}


# Perl seems to keep strings as utf-8 internally. Unfortunately it doesn't
# convert the names to the OS encoding when opening/deleteing files/directories.
# This is the only way which seems to work...
sub getFSname
{
my ($perlname) = @_;
my $encoding = 'iso-8859-1'; # Win32::Codepage::get_encoding()
   
   # Extra tweak required here which wasn't required in foldermd5. Need to
   # turn on the "string is utf-8" flag before re-encoding and then it works like
   # it should do. Fk only know what Perl thinks the encoding is?
   Encode::_utf8_on($perlname);
   return encode($encoding , $perlname);
   #return $perlname;
}

# Converts invalid filename characters to underscores
# Fed up with bad characters constantly causing the transfer to fail
# so instead of trying to remove the bad ones, just keep the basic alphanumeric chars
# 
sub sanitize
{
my ($str) = @_;

#$str =~ s/[\\\/:\?\*\>\<\$\"\|]//g;
$str =~ s/[^A-Za-z0-9 ]//g;
$str = trim($str);
$str =~ s/\s{2,}/ /g;
$str =~ s/\.+$//;
return $str;
}

sub trim
{
my ($str) = @_;

$str =~ s/^\s+//;
$str =~ s/\s+$//;
return $str;
}

sub ymdhmsString
{
my @starttime;

if(@_ > 0)
{
   @starttime = @_;
}
else
{
   @starttime = Today_and_Now();
}

my $nowstr = sprintf("%04d.%02d.%02d. %02d:%02d:%02d", $starttime[0],$starttime[1],$starttime[2],$starttime[3],$starttime[4],$starttime[5]);

return $nowstr;
}

sub wakeywakey
{
   # Want to use EXECUTION_STATE WINAPI SetThreadExecutionState(_In_  EXECUTION_STATE esFlags);
   my $ES_SYSTEM_REQUIRED = 1;
   my $ES_DISPLAY_REQUIRED = 2;
   my $ES_USER_PRESENT = 4;
   my $ES_CONTINUOUS = 0x80000000;

   my $SetThreadExecutionState = Win32::API::More->new('kernel32', 'SetThreadExecutionState', 'N', 'N');

   if (defined $SetThreadExecutionState)
   {
      # This should just reset the idle timer back to zero
      #print "Calling SetThreadExecutionState with 'System Required'\n";
      my $rc = $SetThreadExecutionState->Call($ES_SYSTEM_REQUIRED);
      #$LOG->debug("'System Required' sent... ");
   }
   else
   {
      $log->error("SetThreadExecutionState did NOT load!!  ");
   }
}



package SCULog;
{
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
      %LOG_LABELS = ( LOG_ALWAYS, " ", LOG_FATAL, "F", LOG_ERROR, "E", LOG_WARN, "W", LOG_INFO, "I", LOG_DEBUG, "D", LOG_TRACE, "T");   
   }
   # The class is supplied as the first parameter
   # Not sure what it is used for!!!
   my $class = shift;
   my $self = {};  # this becomes the "object", in this case an empty anonymous hash
   bless $self;    # this associates the "object" with the class

   $self->level(LOG_INFO);
   $self->{"_LOG_LABELS"} = \%LOG_LABELS;
   return $self;   
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

sub ts
{
my $self = shift;
my @starttime;

if(@_ > 0)
{
   @starttime = @_;
}
else
{
   @starttime = Date::Calc::Today_and_Now();
}

my $nowstr = sprintf("%02d%02d%02d %02d%02d%02d", $starttime[0]-2000,$starttime[1],$starttime[2],$starttime[3],$starttime[4],$starttime[5]);

return $nowstr;
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
      my $prefix = sprintf("%s:%s: ", $self->ts(), ($labels{$keyword}//$keyword)); 
      if(($keyword == LOG_ERROR) || ($keyword == LOG_FATAL))
      {
         # NB. The frame subroutine value refers to the subroutine being called (an SCULog method normally) at line X in package Y.
         # Therefore need frame(X-1)->subroutine to know who is doing the calling.
         eval
         {
            # this seems to be error prone!!
            my $trace = Devel::StackTrace->new(ignore_class => 'SCULog');
            my $frame;
            
            # Get the package and line info
            $frame = $trace->next_frame;
            my $calledfunc = $frame->subroutine;  # Method being called at line X
            my $callerline = $frame->line;
            my $callerpackage=$frame->package;

            # Get the function doing the calling at line X
            $frame = $trace->next_frame;
            if(defined $frame)
            {
               my $callerfunc = $frame->subroutine;
               print sprintf("%s%s(%04d): %s", $prefix, $callerfunc, $callerline, $msg);
            }
         } # end eval
         or do
         {
            my $error = $@ || 'Unknown failure';
            print sprintf(" Error: Failed to obtain location of error: %s:\n", $error);
            print sprintf("%s%s", $prefix, $msg);
         };
      }
      else
      {
         $!=1;
         print sprintf("%s%s", $prefix, $msg);
      }
   }
   return $msg;
}
}
   # v2: Compilations mess things up. Will not preserve the src structure, instead tracks will
   # be written to PlayerRoot\AlbumName\Track. Like this plus no parsing of the src path is required
   # v2 also does an update, removing tracks present in dest and not in the playlist and only adding
   # tracks which are not already in dest - which will speed up the process considerably.
# 03 Nov 2014 Added logging using the new log class. Added output of trace info for errors back into
#  the log class as I found a way to make it work from within a class.
# 04 Nov 2014 Run into problems with filename with accents - attempts to solve the problem.
# 05 Nov 2014 accents in dirnames and filenames under control! Could use some optimization...
# 06 Nov 2014 tidied up the filesystem compatible variables in the copy routine. 
#             Seems to be working with accents OK now. There is still a question as to how come
#             the delete routine manages to match the filesystem names against the UTF8 keylist
#             names while the reverse does not work, ie. keylist names cannot be used to create
#             or test files/dirs containing accents unless they are re-encoded.
# 15 Aug 2017 Uses <root>\artist\album\track as the destination path. On large drives there were too many
#             directories in the root when using just <root>\album\track. Didn't need to change the file
#             list key which remains album\track and the delete routine also still behaves as required.
# 20 May 2018 All iTunes libraries are now useing ALAC and mp3. The ALAC files need to be 
#             converted to MP3 for use with the "media player", ie. the USB stick used in
#             the car. The car can probably handle ALAC but the files take up too much space
#             and I don't want to buy a bigger stick. Anyway, I still have the Creative Zen
#             which only handles MP3, and one day I might want to create an MP3 CD.
#             Seems the way to convert to MP3 is with FFMPEG. The audio conversion happens
#             without a problem however it forks up the transfer of the cover art!!! So
#             a really long command line is needed just to get the image transferred correctly.
#             (forking Unix people)
#             the FFMPEG line is;
#             ffmpeg -i <infile>.m4a -c:v copy -map 0 -metadata:s:v title="cover" -metadata:s:v comment="Cover (Front)"  -id3v2_version 3 -write_id3v1 1 -codec:a libmp3lame -q:a 0 <outfile>.mp3
# 19 Jan 2020 Added free diskspace check. Should avoid partial files which may cause problems for the player. 
# 22 Jan 2020 Cannot assume that entire playlist will fit on the device. Therefore remove all files in the 
#             destination and add new files selected randomly from the (probably sorted) playlist until the entire
#             list is added or the available space is consumed.
# 23 Jan 2020 Add some stats at the end, remove obsolete commented code
# 28 Mar 2020 More strict output filename santization. Hopefully better error handling.
# 30 Mar 2020 Added limits for files and bytes and named options for in and out paths. This should allow
#             the mediaplayer files to be written to the local hard disk and then simply copied
#             to the media player in one go - hopefully this will be quicker than the 48+hrs needed
#             to write directly to the 32GB USB drive!
# 31 Mar 2020 Converting to a local disk still seems rather slow so now the conversion should happen
#             while the next file is being copied. This hopes that reading a file from the NAS to
#             local disk is faster than converting from the NAS to the local disk. It probably wont
#             be, but at least I'll know! If it isn't then maybe the async code can be adapted
#             to perform multiple simultaneous conversions.