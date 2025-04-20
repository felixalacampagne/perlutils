#!/usr/bin/perl

# Parse mkvmerge 'identity' JSON details and generate transcoding options file
#
# Example command line:
#   perl genMKVopts.pl -i identity.json -o options.json
#
# 30 Jan 2024 BBC3 changed the tracks in the .TS stream which messed up the hardcoded ids
# used in the transcoding to remove the 'nar' and dvb subtitles and to display srt subtitles
# by default. mkvmerge can be used to generate a listing of the tracks. Parsing this list
# is beyond what can be done from the DOS command line (for me at least) so in comes
# this script to extract the appropriate ids and create an mkvmerge options files for the
# transcoding


use strict;
use FindBin;           # This should find the location of this script
use lib $FindBin::Bin . "/lib"; # This indicates to look for modules in the lib directory in script location


use IO::Handle;
use Data::Dumper;
use File::Spec;
use File::Basename;
use File::Copy;
use File::stat;
use Cwd;
use Encode;
use Getopt::Std;
use Term::ReadKey;
use FALC::SCULog;
use Win32::Console;
use JSON;
my $VERSION="GENMKVOPTS v0.1 202412301100";


my $LOG = FALC::SCULog->new();
my $CONSOLE=Win32::Console->new;
my $CONSOLESTARTTILE=$CONSOLE->Title();

my $identfile = "identity.json";
my $optfile = "mkvopts.json";
  
my @gTracks = (); # To difficult to return arrays etc. from a function so resort to a global value

my $logtofile = 0;
my $logfh;
my $logfilename;
my %opts;
getopts('vli:o:', \%opts);

if( $opts{"i"})
{
   $identfile = $opts{"i"};
}
$identfile = File::Spec->rel2abs($identfile);

if( $opts{"o"})
{
   $optfile = $opts{"o"};
}
$optfile = File::Spec->rel2abs($optfile);

if( $opts{"v"} == 1)
{
   $LOG->level(FALC::SCULog->LOG_DEBUG);
}
if( $opts{"l"} == 1)
{
   $logtofile = 1;
}

$LOG->debug("Loading identity file $identfile\n");
(-f $identfile)  or die "Invalid identity file: $!: $identfile";
loadIdentity($identfile);

my $dbg = Dumper @gTracks;
# Instead of dumping the array as a single VAR it dumps each element as
# a new var, eg. VAR1, VAR2, which might indicate there is something wrong in the
# way the arrays are reconstitued from the config file. The code using the arrays
# seems to work OK though so not going to worry too much about it - it's Perl so
# have learnt not to expect anything to make much sense.
$LOG->trace("gTracks contains:\n". $dbg . "\n");

if ( $logtofile == 1 )
{
   my @now = localtime();
   my $ts = sprintf("%04d%02d%02d%02d%02d", 
                        $now[5]+1900, $now[4]+1, $now[3],
                        $now[2],      $now[1]);
   $logfilename = $identfile . ".log";
   $logfilename = File::Spec->rel2abs($logfilename);
   print 'Redirecting output to ' . $logfilename . "\n";
   open ($logfh, '>', $logfilename);
   # Extra attempt to get the output visible in UltraEdit during the processing
   $logfh->autoflush(1); 
   # select new filehandle
   select $logfh;
   $|=1;
}

$LOG->info($VERSION . "\n");

# This bit of perl black magic is supposed to make stdout flush 
# each line even when redirected to a file, but it doesn't seem to work inside
# the logtofile if block and it doesn't seem to work here either when logfh is selected.
# At least the output is actually going into the file though.
$|=1;

generateMKVOptions($optfile);

settitle(""); # reset to original - we might be called again so should not leave anything in the title

if ( defined $logfh )
{
   close($logfh);
}
select STDOUT;


########### End of main program

sub generateMKVOptions
{
my $ME="generateMKVOptions: "; # function name for log output
my ($optout) = @_;	
my $vidid = -1;
my $subid = -1;
my $ac3id = -1;
my $mp2id = -1;


	foreach my $trackref (@gTracks)
	{	
		my %track = %{$trackref};
		my $dbg = Dumper %track;	
		$LOG->trace("$ME Track:\n". $dbg . "\n");
		my $type = $track{'type'};
		my $trackid = $track{'id'};
		$LOG->debug("$ME Type: " . $type . " ID: " . $trackid . "\n");
		if($type eq 'audio')
		{
			if(	$track{'codec'} eq 'AC-3')
			{
				$ac3id = $trackid;
				$LOG->debug("$ME AC3: $ac3id\n");
			}
			elsif($track{'codec'} eq 'MP2')
			{
				my $lang = $track{'properties'}{'language'};
				$LOG->debug("$ME MP2 lang: $lang\n");
				if($lang ne 'nar')
				{
					$mp2id = $trackid;	
					$LOG->debug("$ME MP2: $mp2id\n");
				}
			}
		}
		elsif($type eq 'subtitles')
		{
			if(	$track{'codec'} eq 'SubRip/SRT')
			{
				$subid = $trackid;
				$LOG->debug("$ME Subs: $subid\n");
			}      		
		}
		elsif($type eq 'video')
		{
				$vidid = $trackid;
				$LOG->debug("$ME Video: $vidid\n");
		}
	}
my @mkvopts = ();
my @trackorder = ();
# --audio-tracks 4 
# --language 4:en 
# --subtitle-tracks 3 
# --language 3:en 
# --forced-display-flag 3:yes 
# --track-order 0:0,0:4,0:3 		 
my $audid = ($ac3id > -1) ? $ac3id : $mp2id;
	if($audid > -1)
	{
		push(@mkvopts, "--audio-tracks");
		push(@mkvopts, "$audid");
		push(@mkvopts, "--language");
		push(@mkvopts, "$audid:en");
		
		push(@trackorder, "0:$audid");
	}
	
	if($subid > -1)
	{
		# To add a 1s subtitle delay use: --sync $subid:1000
   	push(@mkvopts, "--subtitle-tracks");
   	push(@mkvopts, "$subid");
		push(@mkvopts, "--language");
		push(@mkvopts, "$subid:en");
		push(@mkvopts, "--forced-display-flag");
		push(@mkvopts, "$subid:yes");
		push(@trackorder, "0:$subid");
	}
  
  if((scalar(@trackorder) > 0) && ($vidid > -1))
  {
  	my $tord = "0:$vidid," . join(',', @trackorder);
  	push(@mkvopts, "--track-order");
  	push(@mkvopts, "$tord");
  }
   
   my $json = to_json(\@mkvopts, {utf8 => 1, pretty => 1, canonical => 1});
   savetext($optout, $json); 


}


sub printfile
{
# Declare local variables ...
my ($path) = @_;
#print "loadfile2array: loading content of $path\n";
my @contents = "";
my $line = "";

   open my $fh, "<", $path     || die "can't open $path: $!";
   binmode INPUT, ":encoding(utf-8)";
   while( $line = <$fh> )
   {
      print "$line\n";
   }
   close($fh);

}

sub settitle
{
my $title = shift;
	# Must keep original title at start as it is required to prevent sleep
	if($title ne "")
	{
		$title =': ' . $title;
	}
	$CONSOLE->Title($CONSOLESTARTTILE . $title);
}

sub savetext
{
my ($path, $data) = @_;

   unlink "$path";
   if(open(my $output, ">", $path) )
   {
      binmode $output, ":unix:encoding(UTF-8)";
      print $output $data;
      close($output);
   }
   else
   {
      warn "Failed to save file: " . $path . " : " . $! . "\n";
   }
}

sub loadtext 
{
   my ($file) = @_;
   
   my $fulfile = File::Spec->rel2abs($file);
   
   open my $fh, '<', $fulfile or die "Can't open file $fulfile: $!";
     
   binmode $fh, ":encoding(utf-8)";   
   my $file_content;
   
   read $fh, $file_content, -s $fh;
   return $file_content
}

sub genDefaultConfig
{
my ($file) = @_;
my %bootstrapconfig = ();
my @CFGregexes;
   # H264 channels (VU+) for SmartCut editing
   push(@CFGregexes, "VTM 2 HD - ");
   push(@CFGregexes, "BBC .* HD - Doctor Who");
   push(@CFGregexes, "BBC Two HD - ");
   push(@CFGregexes, "BBC Three HD - ");
   push(@CFGregexes, "BBC Four HD - ");
   push(@CFGregexes, "ITV HD - ");
   push(@CFGregexes, "Channel 5 HD - Yellowstone");
   push(@CFGregexes, "BBC One Lon HD - The Sixth Commandment");
   push(@CFGregexes, "Play5 - Greys Anatomy"); 
   push(@CFGregexes, "VTM 3 - ");
   push(@CFGregexes, "VTM 4 - MASH");
   push(@CFGregexes, "Play6 - ");


   # MPEG2 channels (VU+) for Cuttermaran editing
   push(@CFGregexes, "BBC Three - ");
   push(@CFGregexes, "ITV(?: *\\+ *1)? - ");
   push(@CFGregexes, "Channel 5 - ");
   push(@CFGregexes, "5STAR(?: *\\+1)? - ");
   push(@CFGregexes, "Channel 4(?: *\\+ *1)? - ");
   push(@CFGregexes, "E4(?: *\\+1)? - ");
   push(@CFGregexes, "ITV4 - The Americans");
   
   $bootstrapconfig{'FilenamePatterns'}  = \@CFGregexes;
   my $json = to_json(\%bootstrapconfig, {utf8 => 1, pretty => 1, canonical => 1});
   savetext($file, $json);     
}

sub loadIdentity
{
my ($file) = @_;  
my $json = loadtext($file);
my $mapref = decode_json($json);
my %identity = %{$mapref};
	$LOG->debug("Load JSON content of file $file\n");
  @gTracks = @{$identity{'tracks'}};
}