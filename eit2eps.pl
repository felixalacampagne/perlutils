#!/usr/bin/perl
# 12-Nov-2022 Uses NFO file from 'repository' if it exists
# 12-Nov-2021 added 'aired' based on date in filename or current date. Added MD5
#             of nof content as unique id in hope Kodi will better recognise when programes have been deleted.
# 03-Oct-2020 creates the NFO for none EIT files using same defaults as for folder.eps
# 23-Jul-2020 v3_3 calls an external command provide via env.var "ARTCMD" to create artwork.
# 09-Jul-2020 v3_2 optionally put the file nfos in the staging (checking) directory to avoid confusing the media server
#             and do not create nfos in directory containing a '.ignore' file, unless it is the staging directory.
# 02-Jul-2020 v3_1 handles non EIT files: creates show directory, show nfo, adds dummy entry to folder.eps - no file.nfo
# 30-Jun-2020 v3_0 support for Kodi media center: create one directory per show, create tvshow and episode .nfo files
# 01-Dec-2018 v2_5 On a roll!! Implemented the searching for epss in progname dir, drama/folder.eps 
# 30-Nov-2018 v2_0 Creates/updates valid "<prog name>.eps" files in the output directory

# NB Can also be used to create prog directory and artwork when no .eit file is available, just use
# the video file name

use strict;
use v5.10; # So that 'state' is understood!!!
use Getopt::Std;
use File::Spec;
use File::Basename;
use File::Path qw(make_path remove_tree);
use File::Copy;
use Digest::MD5;

# Kludge to provide a command to create the folder artwork for a new program
# the command should contain placeholders for the program name (#PROGNAME#) and the program directory (#PROGDIR#)
my $gARTCMDTMPL=$ENV{ARTCMD} . "";

# TODO This should become a command lien arg, possibly with a default value
my $NFOREPOPATH="\\\\MINNIE\\Development\\website\\tvguide\\tv\\nfo";

# script is intended for use with filename which have the date/channel info removed
# this is to allow the EPS line to be accumulated into a .eps file with the name
# of the programme.
my $eitfile;

my $gDefArtwork="";
my $epsdir = ".";
my $nfodir = "";
my $logfilename;
my %opts;
getopts('a:d:n:l?', \%opts);



if( $opts{"?"} )
{
   HELP_MESSAGE();
}

if( $opts{"d"})
{
   # This is where the program sub-directories are made
   $epsdir = $opts{"d"};
}

if( $opts{"n"})
{
   # This is where the NFO is written to
   $nfodir = $opts{"n"};
}


printf "Root programme directory directory: %s\n", $epsdir;

if( $opts{"l"})
{
   LogToFile(1);
}

# Avoid confusing the idiot mediaserver by putting the nfo in the final directory 
# before the video file is moved to there.
if($nfodir eq "" )
{
   # This is WRONG! NFO should be written to the programme sub-directory by default
   $nfodir = $epsdir;
}
printf "NFO file directory: %s\n", $nfodir;
$eitfile = $ARGV[0];

# Default artwork file will be copied into a newly created program directory to avoid
# the appleTV displaying a random scene from one of the episodes. This is more annoying
# now that all programs get their own directory.
# The default file is the folder.jpg file in the directory where the programm sub-dirs are created 
# unless a file is given on the command line.
# This is obsolete now that a folder.jpg is generated for each programme sub-directory by the external
# command.
$gDefArtwork = File::Spec->catdir($epsdir, "folder.jpg");
if( $opts{"a"} )
{
   $gDefArtwork = $opts{"a"};
}

if(! -f $gDefArtwork)
{
  $gDefArtwork = ""; 
}

my ($eitfilename,$directories,$suffix) = fileparse( $eitfile );
my $filename = "";
my $progname = "";
my $season = "";
my $id = "";
my $ep = "";
my $ext= "";
my $progdesc = "";

# Extract the intended program info from the filename.
# Add non-capture group for handling of missing episode title - to be tested
if($eitfilename =~m/^((.*?) (\d{1,2})x(\d{1,2})(?: *(.*?)))?(\..+)*$/)
{
   $filename = $1;
   $progname = $2;
   $season = $3;
   $id = $4;
   $ep = $5;
   $ext = lc $6;  # NB Includes the dot!!
}
else
{
   die "Invalid filename format: expected 'Program NxN Title.ext' actual: " . $eitfilename;
}

# yyyymmdd hhmm - channelname - programmeinfo
# The raw filename name from the sat box, usually this has already been processed 
if($progname =~ m/^\d{8} \d{4} \- .*? \- (.*$)$/) 
{
   $progname = $1;
}

# program yy-mm-dd episode title
if($progname =~ m/^(.*) \d{2}-\d{2}-\d{2}$/)
{
   $progname = $1;
}


if($ext eq ".eit")
{
   $progdesc = getDescFromEIT($eitfile);
} # end if for eit file
else
{
   $progdesc =    $progname . ": ". $ep . "(" . $season . "x" . $id . ")";
}


my $episode = "Episode " . $id;
if($ep ne "")
{
   $episode = $ep;
}

# There is now a 'repository' of NFO files which should be used when there is no EIT
# or even in place of the EIT. Use of a repository NFO is the default for createFileNFO.
# For consistency the EPS files should be updated from the content of the final NFO file
# ... something for a rainey day!!
printf "Creating NFO for: %s\n", $eitfilename;
my $nfofilename = createFileNFO($nfodir, $progname, $eitfilename, $season, $id, $episode, $progdesc);

my $eprec;
$eprec = "<episode>" .
           "<id>" . $id . "</id>" .
           "<filename>" . $filename . "</filename>" .
           "<name>" . $episode . "</name>" .
           "<description>" . $progdesc . "</description>" .
        "</episode>";


updateeps($epsdir, $season, $id, $progname, $filename, $eprec);



#######################################################
#######  END OF MAIN  #################################
#######################################################
#######################################################
######   FUNCTIONS    #################################
#######################################################
sub getDescFromEIT
{
   my($eitfile) = @_;
   printf "Parsing EIT file: %s\n", $eitfile;
   my $progdesc = "";
   my @proginf;
   my $fh = open my $fh, '<:raw', $eitfile;
   my $bytesread;

   # skip the time info and move to where the first block should be
   my $bytes;
   $bytesread = read $fh, $bytes, 12;
   die "Read $bytesread bytes but expected 12" unless $bytesread == 12;

   # Each 4D block appears to be 'discrete'
   # The 4E blocks appear to be contigious text, intended to be concatenated with no separator
   
   my $tmp;
   my $blk;
   my $blklen;
   my $txtlen;
   my $blkbytesread;
   $bytesread = 1;

   while($bytesread > 0)
   {
     $blkbytesread = 0;
     $bytesread = read $fh, $bytes, 1;
     ($blk) = unpack 'C', $bytes;

     $bytesread = read $fh, $bytes, 1;
     ($blklen) = unpack 'C', $bytes;

     if( $blk == 0x4D)
     {
       #printf "We've got a %02X block of $blklen\n", $blk;
       # Skip language
       $blkbytesread += read $fh, $bytes, 4;

       ($tmp, $txtlen) = unpack 'a3 C', $bytes;

       # Seems the language is sometimes followed by a 0, and sometimes immediately by the text length
       # TODO: is there a way to avoid this??
       if($txtlen == 0)
       {
         $blkbytesread += read $fh, $bytes, 1;
         ($txtlen) = unpack 'C', $bytes;
         #print "There should be $txtlen of text\n";
       }
       #print "There should be $txtlen of text\n";

       # Skip the initial (code-page?) byte. This appears to be optional so eventually
       # will need to include it in the text if it is a printable character
       $blkbytesread += read $fh, $bytes, 1;
       my $title;
       $blkbytesread += read $fh, $title, $txtlen-1;
       #print "This is the block text: $title\n";

       push(@proginf, $title);
     }
     elsif($blk == 0x4E)
     {
       #printf "We've got a %02X block of $blklen\n", $blk;

       # Skip useless crap
       $blkbytesread += read $fh, $bytes, 7;

       # Read to the end of the block
       my $desc;
       $blkbytesread += read $fh, $desc, $blklen-$blkbytesread;
       #print "This is the block text: $desc\n";
       $progdesc = $progdesc . $desc;

     }
     else
     {
       #printf "Read %03x: Block type is %02x, length=%02x\n", $bytesread, $blk, $blklen;
       $blkbytesread += read $fh, $bytes, $blklen;
     }
     if($blkbytesread < $blklen)
     {
       $bytesread = read $fh, $bytes, $blklen-$blkbytesread;
     }
     elsif($blkbytesread > $blklen)
     {
       die "Too many bytes read from block: reported $blklen, actual $blkbytesread \n";
     }

   } # end while for eit file parse


   # Seems the EIT info differs for the UK and BE channels: might be
   # due to different versions of Enigma on the Vu and DB.
   # The UK channels appear to have the program description in the second 4D block, and no 4E blocks.
   # The BE channels have the description spread over the 4E blocks. The BE channels
   # contain more info than I really want in the description, like repetition of the
   # program name, genre, cast etc. Might be possible to extract the description itself by looking
   # for the text between the double line feeds, ie. there is an empty line before the description and one
   # after it, before the Cast info.
   # Fo BE channels the second 4D block appears to contain episode info, which might be handy to
   # have at the end of the description. The first 4D block is the program name.
   if($progdesc eq "")
   {
     $progdesc = $proginf[1];
     $proginf[1]="";
   }

   #printf "Programme info:\n%s\n", $proginf[1];
   #printf "Description:\n%s\n", $progdesc;
   if ( $progdesc =~ m/^.*?(?: ?\r?\n){2,2}(.*?)(?: ?\r?\n){2,2}.*$/s )
   {
     $progdesc = $1;
     #printf "Trimmed description:\n%s\n", $progdesc;
   }
   
   
   
   $progdesc = $progdesc . " " . $proginf[1];
   
   # Remove other annoying stock phrases
   $progdesc =~ s/Contains .*?\. *?//g;
   $progdesc =~ s/Also in HD\. *?//g;
   $progdesc =~ s/\[[S,AD]*\] *?//g;
   printf "Final description:\n%s\n", $progdesc;
   return $progdesc;
}

sub updateeps
{
  my ($epsdir, $season, $id, $progname, $filename, $eprec) = @_;

  # Eventually: check for a directory epsdir/progname and create/update folder.eps in it
  # no progname directory: could check for the progname in the drama folder.eps (very very long term!!)
  # for now: create/update the epsdir/progname.eps
  my @epslines;
  
  my $path = findepsfile($epsdir, $progname);
  print "Updating EPS file: $path\n";
  my $fheps;

  if( -e $path)
  {
    @epslines = loadfile2array($path);
  }

  # Now for some ugly assumptions....
  # The id start and end tags appear on the same line 
  # The show start and end tags appear on the same line 
  # The episode start and end tags appear on the same line, implies the filename block is in the same
  # line as the episode block


  # state:  0 looking for season id
  #         1 looking for show (season end tag resets to 0, loop continues)
  #         2 looking for filename (season end tag, insert eprec before season end tag, exit loop save file
  #        10 epsrec updated, needs to be saved
  #        99 entry already present just exit
  my $state=0;
  my $param;
  my $i;
  my $alen = scalar(@epslines);
  for( $i=0; $i < $alen; $i++)
  {
    my $line = @epslines[$i];
    if( $state == 0)
    {
      if( $line =~ m/<id>$season<\/id>/ )
      {
        print "Found a matching season id.\n";
        $state = 1;
      }
    }
    elsif($state == 1)
    {
      if( $line =~ m/<show>$progname<\/show>/ )
      {
        print "Found a matching season show.\n";
        $state = 2;
      }
      elsif( $line =~ m/<\/season>/ )
      {
        print "Found endof season show.\n";
        $state = 0;
      }
    }
    elsif( $state == 2 )
    {
      if( $line =~ m/<filename>$filename<\/filename>/ )
      {
        # entry is already present
        print "Filename is already present: $line.\n";
        $state = 99;
        last;
      }
      elsif( $line =~ m/<\/season>/ )
      {
        # So ID was matched and show was matched and there is no filename.
        # Therefore so need to insert the new eprec before the current line,
        # and write the file
        print "Filename is not present - updating eps file\n";
        splice @epslines, $i, 0, $eprec . "\n";
        $state = 10;
        last;
      }

    }
  }

  print "Exited loop with state: $state\n";
  if( $state < 10 )
  {
    print "Season is not present - updating eps file\n";
    my $seas;
    $seas = "<season>\n";
    $seas .= "<id>$season</id>\n";
    $seas .= "<show>$progname</show>\n";
    $seas .= $eprec . "\n";
    $seas .= "</season>\n";
    push (@epslines, $seas);
    $state = 10;
  }

  if( $state == 10 )
  {
    print "Saving updated eps to $path\n";
    # Seems that disabling the binmode in loadfile2array avoids the "wide character in print" warning. 
    open($fheps, ">", $path);
    # This magic prevents a space being inserted before each element of the array
    # but it forks up the syntax hilighting of UE
    # The join version does the same as using $". It means join the elements of the array using
    # the first parameters as the separator
    #local $"='';
    #print $fheps "@epslines";
    print $fheps join '', @epslines;
    close($fheps);
  }
  else
  {
  }
}

# Too much hassle to figure out how to use any of the Perl XML libraries to escape the
# the XML reserved characters so this will have to do for now
sub xmlencode
{
my ($str) = @_;

$str =~ s/&/&amp;/g;
$str =~ s/\>/&gt;/g;
$str =~ s/\</&lt;/g;
$str =~ s/\"/&quot;/g;
$str =~ s/\'/&apos;/g;
return $str;
}

sub createFileNFO
{
my ($rootdir, $progname, $vidfilename, $season, $id, $eptitle, $desc) = @_;

my $nfopath = getprogrammepath($rootdir, $progname);
   # kludge to support the creation of nfos in the staging directory or creation in a program name sub-dir of the master root directory. 
   # If an nfo directory is given which is not the same as the master root directory then 
   #   the nfos should not be created in a program name sub-dir. Such a program name sub-dir will/should not exist.
   # If the master root directory is used then the nfos should be created in a program name sub-dir. Such a sub-dir will/should exist.
   # Therefore
   #   if the program name sub-dir exists then use it
   #   if it doesn't exist then use root dir
   #
   # Additional consideration:
   #   If the program name sub-dir contains a .ignore then the nfo file should not be created in it.
   #   If the root dir is used then the .ignore file should be ignored (the staging directory WILL contain a .ignore file)
   if( -e File::Spec->catdir($nfopath, ".ignore"))  # test for /rootdir/prog name/.ignore
   {
      return;
   }
   
   unless(-d $nfopath)
   {
      $nfopath = $rootdir;
   }

my $nfoname = $vidfilename;
my $nfodate = "";
my $uid = "9876";
   # Replace file extension with .nfo
   $nfoname =~ s/\.[^\.]*$/.nfo/g;
   $nfopath = File::Spec->catdir($nfopath, $nfoname);
   if( -s $nfopath )
   {
      print "NFO file $nfopath already exists and will not be overwritten";
      return $nfopath;
   }
   
   # Check whether NFO file is present in the new NFO repository
my $nforepopath = File::Spec->catdir($NFOREPOPATH, $nfoname);   
   if( -s $nforepopath )
   {
      print "NFO file $nfoname is present in the NFO repository: Copying to $nfopath\n";
      copy($nforepopath, $nfopath);
      return $nfopath;
   }
      
   print "createFileNFO: creating nfo file: " . $nfopath . " for " . $vidfilename . "\n";
   my $nfocont = "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\" ?>\n";
   $nfocont .= "<episodedetails>\n";
   $nfocont .= "<title>" . xmlencode($eptitle).  "</title>\n";
   $nfocont .= "<showtitle>" . xmlencode($progname) . "</showtitle>\n";
   
   
   $nfocont .= "<season>" . $season . "</season>\n";
   $nfocont .= "<episode>" . $id . "</episode>\n";   
   
   $nfocont .= "<plot>\n" . xmlencode($desc) . "\n</plot>\n";
   
   # Use md5 of nfo created so far to create an id in case this is what causes Kodi to keep
   # the programmes in the list after they have been deleted.
   $uid = md5sum($nfocont);
   $nfocont .= "<uniqueid type=\"mytvshows\" default=\"true\">" . $uid ."</uniqueid>\n";


   # program yy-mm-dd episode title
   if($vidfilename =~ m/^.* (\d{2})-(\d{2})-(\d{2}) .*$/)
   {
      $nfodate = "20" . $1 . "-" . $2 . "-" . $3;
      $nfocont .= "<aired>" . $nfodate . "</aired>\n";
   }
   else
   {
      # Kodi ignores dateadded, only displays aired.
      # So set aired to the date from the filename if possible, otherwise set aired to the current date.
      my @nowparts = localtime(time());
      $nfodate = sprintf("%04d-%02d-%02d", $nowparts[5]+1900, $nowparts[3], $nowparts[4]+1 );      
      $nfocont .= "<aired>" . $nfodate . "</aired>\n";
   }
   $nfocont .= "</episodedetails>\n";
   saveutf8xfile($nfopath, $nfocont);
   return $nfopath;
}


sub createFolderNFO
{
my ($show, $nfopath) = @_;

   # If path contains a '.ignore' file then do not create the folder NFO. '.ignore' is
   # used by 'Emby' mediaserver 
  unless(-e File::Spec->catdir($nfopath, ".ignore"))
  {
      my $nfocont = "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\" ?>\n";
      $nfocont .= "<tvshow>\n";
      $nfocont .= "<title>" . xmlencode($show) . "</title>\n";
      $nfocont .= "<uniqueid type=\"mytvshows\" default=\"true\">9876</uniqueid>\n";
      $nfocont .= "</tvshow>\n";

      $nfopath = File::Spec->catdir($nfopath, "tvshow.nfo");
      saveutf8xfile($nfopath, $nfocont);  
   }
}

sub initArtwork
{
my ($path, $progname) = @_;

   if($gARTCMDTMPL ne "")
   {
      my $cmd = $gARTCMDTMPL;
      $cmd =~ s/#PROGNAME#/$progname/g;
      $cmd =~ s/#PROGDIR#/$path/g;
      printf "Artwork creation command: %s\n", $cmd;
      
      # TODO Execute the command!
      system($cmd);
   }
   elsif($gDefArtwork ne "")
   {
      copy($gDefArtwork, File::Spec->catdir($path, "folder.jpg"));
   }
}

sub getprogrammepath
{
   my ($epsdir, $progname) = @_;
   my $lcprogname = lc $progname; 
   return File::Spec->catdir($epsdir, $lcprogname); 
}

# Searches for an .eps file in the following:
#   <epsdir>\<progname>\folder.eps
#   <epsdir>\drama\folder.eps show=progname
# If the above are not present then the default return is:
#   <epsdir>\progname.eps
# NB. The returned filename may not exist
sub findepsfile
{
my ($epsdir, $progname) = @_;
my $path;
my @epslines;


  # TODO: filter lcprogname for undesirable characters
  $path = getprogrammepath($epsdir, $progname);  
  print "Searching for $progname EPS in: $path\n";
  
  unless(-d $path)
  {
    print "Creating new show directory: $path\n";
    make_path($path);
    
    initArtwork($path, $progname);

    # Bit ugly doing it here but it avoids parsing the returned path to get the directory...
    createFolderNFO($progname, $path);
  }
  
  if( -d $path)
  {
    print "Found directory for $progname: $path\n";
    $path = File::Spec->catdir($path, "folder.eps");      
    return $path;
  }

  # If directory creation failed then fallback to old 'drama' behaviour
  
  $path = File::Spec->catdir($epsdir, "drama", "folder.eps"); 
  if( -e $path)
  {
    print "Searching for $progname EPS in: $path\n";
    @epslines = loadfile2array($path);
    foreach my $line (@epslines)
    {
      # print "Checking: $line\n";
      if( $line =~ m/<show>$progname<\/show>/ )
      {
        print "Found season for $progname in $path\n";
        return $path;
      }
    }
  }
  $path = File::Spec->catdir($epsdir, $progname . ".eps"); 
  return $path;
}


sub saveutf8xfile
{
my ($path, $data) = @_;

   unlink "$path";
   
   # To have a utf-8 encoded file with unix line endings
   # NB. The order of the 'layers' is important
   # putting the utf8 before unix doesn't work and apparently should not have a space 
   # not have a space between them.
   # NBB The Perl docs helpfully do not make any mention of the "unix" layer.
   
   if(open(my $output, ">", $path) )
   {
      binmode $output, ":unix:encoding(UTF-8)";
      print $output $data;
      close($output);
   }
   else
   {
      print "Failed to create file: " . $path . " : " . $! . "\n";
   }
}


sub loadfile2array
{
# Declare local variables ...
my ($path) = @_;
#print "loadfile2array: loading content of $path\n";
my @contents = "";
my $line = "";

   {
     # temporarily undefs the record separator
     # local(*INPUT, $/);

     open (INPUT, $path)     || die "can't open $path: $!";
     #binmode INPUT, ":encoding(utf-8)";
     @contents = <INPUT>;
     close(INPUT);
   }

	return @contents;
}

# 'state' requires use v5.10 at the top of the script
sub LogToFile
{
state $logtofile = 0;
   if(@_ > 0)
   {
      $logtofile = $_[0];
   }
   return $logtofile;
}

sub HELP_MESSAGE()
{
   print "eit2eps [-l] -d <eps directory> <eit file>\n";
   exit(0);
}

sub md5sum
{  
my $data = shift;
my $digest = "";
my $fh;
   eval
   {    
      my $ctx = Digest::MD5->new;
      $ctx->add($data);
      $digest = $ctx->hexdigest;
   };
   
   if($@)
   { 
      # What does this mean, again... some sort of error??   
      print $@;
      return "";
   }  
   
   return $digest;
}