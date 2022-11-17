#!/usr/bin/perl
# 17-Nov-2022 convert updateeps to use XML parser
# 14-Nov-2022 Add NFO functionality
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
use XML::Simple;
use XML::XPath;   # cpanm install XML::XPath
use XML::Twig;    # Only used to pretty print the output XML        

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
my $nforepopath = $NFOREPOPATH;
my %opts;
getopts('a:d:n:r:l?', \%opts);

print "EIT2EPS v2.0\n";

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

if( $opts{"r"})
{
   # This is where the NFO is written to
   $nforepopath = $opts{"r"};
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
   $progdesc = getDescFromNFORepo($eitfilename, $nforepopath);
   if($progdesc eq "")
   {
      # Should try to find desc from folder.eps
      $progdesc = getDescFromEPS($epsdir, $progname, $season, $id);
      
      if($progdesc eq "")
      {
         # Can't get a description from anywhere else so make a default entry
         $progdesc =    $progname . ": ". $ep . "(" . $season . "x" . $id . ")";
      }
   }
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
# This is not working as needed at the moment... at least an entry in the folder.eps should be used if nothing else is available
# TODO: If there is an NFO in the repo then use it for the desc
#          - update folder.eps with the NFO desc
#       IF there is no repo NFO then
#          If there is an EIT desc then use it for the NFO AND update folder.eps
#          If there is NO EIT desc and folder.eps already contain a match then use the desc from folder.eps for the NFO
#          If there is NO EIT and NO folder.eps then use default values for folder.eps and NFO

# NB To use the EPS file as XML the season blocks need to be embedded in a higher level block - episodes
# my $eprec;
# $eprec = "<episode>" .
#            "<id>" . $id . "</id>" .
#            "<filename>" . $filename . "</filename>" .
#            "<name>" . $episode . "</name>" .
#            "<description>" . $progdesc . "</description>" .
#         "</episode>";

# NB: This initialises the show directory if it doesn't exist, ie. create dir, artwork, tvshow.nfo and folder.eps
updateeps($epsdir, $season, $id, $progname, $filename, $episode, $progdesc);

printf "Creating NFO for: %s\n", $eitfilename;
my $nfofilename = createFileNFO($nfodir, $progname, $eitfilename, $season, $id, $episode, $progdesc);



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
   # printf "Final description:\n%s\n", $progdesc;
   return $progdesc;
}

sub updateeps
{
  my ($epsdir, $season, $id, $progname, $filename, $epname, $epdesc) = @_;
   my $pi = "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\" ?>\n";
  # Eventually: check for a directory epsdir/progname and create/update folder.eps in it
  # no progname directory: could check for the progname in the drama folder.eps (very very long term!!)
  # for now: create/update the epsdir/progname.eps
  #my @epslines;
  
  my $path = findepsfile($epsdir, $progname, 1);
  print "Updating EPS file: $path\n";
  my $xp;

  if( -e $path)
  {
    $xp = XML::XPath->new(filename => $path);
  }
  else
  {
    $xp = XML::XPath->new(xml => $pi . "<episodes></episodes>\n");
  }
  my $rootnode =  $xp->find('/')->get_node(0);
   
  my $nodelist = $xp->find('//episodes'); # should be an XML::XPath::NodeSet of size 1
  my $i = $nodelist->size();
   
  my $episodesnode = $nodelist->get_node(0);

   my $xpcrit;
   $xpcrit = "season[id = '$season' and show = '$progname']";
   $nodelist = $xp->find($xpcrit, $episodesnode);
   $i = $nodelist->size(); 
  
   if($i == 0)
   {
      # season not present for this id aand show so add a new season node
      print "Trying to add season node for season $season\n";
      my $newnode = XML::XPath::Node::Element->new("season");
      $episodesnode->appendChild($newnode);

      addTextElement($newnode, "id", $season);
      addTextElement($newnode, "show", $progname);
      $nodelist = $xp->find($xpcrit, $episodesnode);
      $i = $nodelist->size();  
      print "New Season nodelist (size=$i):\n$nodelist\n";  
   }
   my $seasonnode = $nodelist->get_node(0);

   # When updating EPS it is for the insertion/update of a file entry. So should key on the filename
   # and not the episode number. When searching for the description only need to use the episode number.
   # "episode[id = '$episodenum' and filename = '$episodefile']";
   $xpcrit = "episode[filename = '$filename']";
   $nodelist = $xp->find($xpcrit, $seasonnode);
   $i = $nodelist->size(); 
  
   if($i == 0)
   {
      print "Episode [$xpcrit] is NOT present: adding new episode\n";
      # This might be easier to do by creating a string for the episode, parsing it to a node and then adding it to season
      
      my $newnode = XML::XPath::Node::Element->new("episode");
      $seasonnode->appendChild($newnode);

      # <episode><id>04</id><filename>The Sinner 22-10-09 4x04 Episode 04</filename><name>Episode 04</name><description>s4e4</description></episode>

      addTextElement($newnode, "id", $id);
      addTextElement($newnode, "filename", $filename);
      addTextElement($newnode, "name", $epname);
      addTextElement($newnode, "description", "");
      $nodelist = $xp->find($xpcrit, $seasonnode);
      $i = $nodelist->size(); 
   }
   my $episodenode = $nodelist->get_node(0);

   $xpcrit = "description";
   $nodelist = $xp->find($xpcrit, $episodenode);
   $i = $nodelist->size(); 
   
   if($i == 0)
   {
      # Ensure we have a decription node to deal with
      addTextElement($episodenode, "description", "");
      $nodelist = $xp->find($xpcrit, $episodenode);
      $i = $nodelist->size(); 
           
   }
   if($i == 0)
   {
      print "Failed to find the 'description' entry\n";
   }
   my $descnode = $nodelist->get_node(0);
   
   # Only update the description if new value is not the same as old value and is not zero length
   if($epdesc ne "")
   {
      # Assume there is only one child and it is a text node. Just to be confusing there is no
      # hasChildNodes or get count and the getChildNodes does not return a NodeList. To make
      # matters even worse the index for the child node is 1 based!!!!
      my $origdesc = $descnode->getChildNode(1)->getValue();
      if($origdesc ne $epdesc)
      {
         $episodenode->removeChild($descnode);
         addTextElement($episodenode, "description", $epdesc);
      }
   }

   # For now always re-save the XML, can add flags to indicate save is needed later if nreally necessary
   # This can be used to serialize the XML for writing to a file. NB the processing instruction is omitted
   my $xmlout = $xp->getNodeAsXML(); #  XML::XPath::XMLParser::as_string($rootnode);
   my $twig = XML::Twig->new(pretty_print => 'indented');
   $twig->parse($xmlout);
   $xmlout = $pi . $twig->sprint;   

   # print "XML as string:$xmlout\n";
   
   saveutf8xfile($path, $xmlout);
}

sub addTextElement
{
   my ($parent, $childname, $text) = @_;
   my $element = XML::XPath::Node::Element->new($childname);
   $element->appendChild(XML::XPath::Node::Text->new($text));
   $parent->appendChild($element);
   return;
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

sub getDescFromNFORepo
{
   my ($vidfilename, $nforepodir) = @_;
   my $nfodesc = "";
   my $nfoname = $eitfilename;
   # Replace file extension with .nfo
   $nfoname =~ s/\.[^\.]*$/.nfo/g;
   my $nforepopath = File::Spec->catdir($nforepodir, $nfoname);   
   if( -s $nforepopath )
   {
      print "NFO file $nfoname is present in the NFO repository: Reading desc from repo NFO\n";
      my $xp = XML::XPath->new(filename => $nforepopath);
      my $xpcrit = "//episodedetails/plot/text()";
      my $descnodes =  $xp->find($xpcrit);
      my $i = $descnodes->size();      
      if($i > 0)
      {
         $nfodesc = $descnodes->get_node(0)->getValue();
         $nfodesc =~ s/^\s+|\s+$//g ;
         print "Description from $nforepopath: $nfodesc\n";
      }
   }
   return $nfodesc;
}


sub getDescFromNFORepo_Simple
{
   my ($vidfilename, $nforepodir) = @_;
   my $nfodesc = "";
   my $nfoname = $eitfilename;
   # Replace file extension with .nfo
   $nfoname =~ s/\.[^\.]*$/.nfo/g;
   my $nforepopath = File::Spec->catdir($nforepodir, $nfoname);   
   if( -s $nforepopath )
   {
      my $xmlParser = new XML::Simple;
      print "NFO file $nfoname is present in the NFO repository: Reading desc from repo NFO\n";
      my $xmldoc = $xmlParser->XMLin($nforepopath);

      # Need to remove leading and trailing spaces, LFs, CRs
      $nfodesc = $xmldoc->{plot};
      $nfodesc =~ s/^\s+|\s+$//g ;
   }
   return $nfodesc;
}

# WARNING: folder.eps must be modified to contain the season blocks in a parent block.
# Doesn't appear to matter what the parent block is called, 'seasons' would be most logical
# This is using XML::Simple which is very hard to understand/use. It would be better to use XML::libXML
# however this is not available at all sites and requires many dependencies to be made available and compiled.
# XML::libXML is far to hard to obtain for offline ActiveState installations however it was possible to
# obtain XML::XPath which more or less does what's needed. So this should be converted to use XPath
sub getDescFromEPS
{
   my ($epsdir, $progname, $srcseas, $srceps) = @_;
   my $epsdesc = "";
   my $epsfile = findepsfile($epsdir, $progname, 0);
   if(-s $epsfile)
   {
      my $xp = XML::XPath->new(filename => $epsfile);
      my $xpcrit = "//season[show = '$progname' and id='$srcseas']/episode[id='$srceps']/description/text()";
      my $descnodes =  $xp->find($xpcrit);
      
      foreach my $node ($descnodes->get_nodelist) {
         my $desc = $node->getValue();
         if(length($desc) > length($epsdesc))
         {
            $epsdesc = $desc;
         }          
      }
      print "Description from $epsfile: $epsdesc\n";
#      my $i = $descnodes->size();
#      if($i > 0)
#      {
#         my $n;
#         for($n=0; $n<$i; $n++)
#         {
#            my $desc = $descnodes->get_node($n)->getValue();
#            if(length($desc) > length($epsdesc))
#            {
#              $epsdesc = $desc;
#            }  
#         }
#      }
   }
   return $epsdesc;
}

sub getDescFromEPS_Simple
{
   my ($epsdir, $progname, $srcseas, $srceps) = @_;
   my $epsdesc = "";
   my $epsfile = findepsfile($epsdir, $progname, 0);
   if(-s $epsfile)
   {
      my $xmlParser = new XML::Simple;
      # Try using XML parser to extract the value
      my $xmldoc = $xmlParser->XMLin($epsfile, forcearray=>1);

      my $seasonref = $xmldoc->{season};

      foreach my $season (@$seasonref)
      {
         print "Season: $season->{id}[0]\n";
         
         if($season->{id}[0] eq $srcseas)
         {
            print $season->{episode};
            my $episoderef = $season->{episode};
            for my $episode (@$episoderef)
            {
               print "Episode: $episode->{id}[0]: $episode->{description}[0]\n";
               if($episode->{id}[0] eq $srceps)
               {
                  $epsdesc = $episode->{description}[0];
                  last;
               }
            }
            last;
         }
      }
      print "Description: $epsdesc\n";
      # remove leading and trailing spaces, LFs, CRs
      $epsdesc =~ s/^\s+|\s+$//g ;      
   }
   return $epsdesc
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
   
   $nfocont .= "<plot>" . xmlencode($desc) . "</plot>\n";
   
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
my ($epsdir, $progname, $initshow) = @_;
my $path;
my @epslines;


  # TODO: filter lcprogname for undesirable characters
  $path = getprogrammepath($epsdir, $progname);  
  print "Searching for $progname EPS in: $path\n";
  if($initshow != 0)
  {
     # Bit ugly doing it here but...
     # Now even uglier doing it here I need to read the file ONLY if it already exists!
     unless(-d $path)
     {
       print "Creating new show directory: $path\n";
       make_path($path);
       
       initArtwork($path, $progname);

       createFolderNFO($progname, $path);
     }
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
