#!/usr/bin/perl

# Automatically move files from VUUltimo to local disk (SSD) for editing.
# Should have been a simple thing to do with a DOS batch file but the
# wildcards don't work, *Homeland*.ts return nothing when there are 
# matching files. Could possibly use "FINDSTR" but not without a lot
# of trickery. So perl it is...

# 11 Nov 2023 Config file is specified by command line option. A single set of regexes 
# is loaded from the config file. The all option takes precedence and does not need a config file.
# 01 Nov 2023 Move regexes to a config file so changes to the programme list
# don't show up as git changes. 
# 29 Jul 2023 Acutally use the generated unique file name to avoid overwriting 
# existing destination files with the same name. Use a temporary filename while
# the move is ongoing to make it easier to spot which files are not yet complete.
# 09 Dec 2016 Move matching .eit files aswell. They are useful for prog info
# especially if I end up watching the .ts files without converting to .m4v
# as is the case with popular series, eg. Game Of Thrones


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
my $VERSION="GETFILES2EDIT v2.0 20231111a";


my $LOG = FALC::SCULog->new();
my $CONSOLE=Win32::Console->new;
my $CONSOLESTARTTILE=$CONSOLE->Title();

my @CFGregexes;   # regexes from config file
my @allregex;     # For all recordings
 
# TODO: specify on command line
my $file = "getfile2edit.json";  

  
my @gRegexes = ();
my $srcdir = "";
my $dstdir = "";
my $logtofile = 0;
my $pauseonexit = 0;
my $logfh;
my $logfilename;

# Copy everything
push(@allregex, ".*");

my %opts;

getopts('bvlpac:', \%opts);

if( $opts{"c"})
{
   # Load config from specified file. Should contain a SINGLE list of regexes
   $file = $opts{"c"};
}
$file = File::Spec->rel2abs($file);

if( $opts{"b"} == 1)
{
   # Bootstrap config file using command line name if provided
   genDefaultConfig($file);
   exit(0);
}

if( $opts{"v"} == 1)
{
   $LOG->level(FALC::SCULog->LOG_DEBUG);
}
if( $opts{"l"} == 1)
{
   $logtofile = 1;
}
if( $opts{"p"} == 1)
{
   $pauseonexit = 1;
}

if( $opts{"a"} == 1)
{
   @gRegexes = @allregex;
}
else
{
   (-f $file)  or die "Invalid conifg file: $!: $file";
   loadConfig($file);
   @gRegexes = @CFGregexes;
}

my $dbg = Dumper @gRegexes;
# Instead of dumping the array as a single VAR it dumps each element as
# a new var, eg. VAR1, VAR2, which might indicate there is something wrong in the
# way the arrays are reconstitued from the config file. The code using the arrays
# seems to work OK though so not going to worry too much about it - it's Perl so
# have learnt not to expect anything to make much sense.
$LOG->debug("gRegexes contains:\n". $dbg . "\n");

$srcdir = $ARGV[0];
shift(@ARGV); #Removes first element
$dstdir = $ARGV[0];

if($srcdir eq "")
{
   $srcdir = "X:\\movie";
}

if($dstdir eq "")
{
   $dstdir = "Q:\\video\\h264";
}

$srcdir = File::Spec->rel2abs($srcdir);
$dstdir = File::Spec->rel2abs($dstdir);

(-d $srcdir) or die "Invalid destination directory: $!: $srcdir";
(-d $dstdir) or die "Invalid source directory: $!: $dstdir";

if ( $logtofile == 1 )
{
   my @now = localtime();
   my $ts = sprintf("%04d%02d%02d%02d%02d", 
                        $now[5]+1900, $now[4]+1, $now[3],
                        $now[2],      $now[1]);
   my $suffix = filename2key($dstdir);
   $logfilename = File::Spec->catdir($srcdir, "findOwn_" . $ts . "_" . $suffix . ".log");
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

processDir($srcdir, $dstdir);

settitle(""); # reset to original - we might be called again so should not leave anything in the title

if ( defined $logfh )
{
   close($logfh);
}
select STDOUT;

if($pauseonexit == 1)
{
   if( $logtofile == 1 )
   {
      printfile($logfilename);
   }

   print "Press a key to exit . . . ";
   ReadMode 'cbreak';
   my $key = ReadKey(0);
   ReadMode 'normal';
}
########### End of main program
sub getTSFiles
{
my ($dir) = @_;
my @tsfiles;
my $dirkey;
my $dh;
my @files;
my $fullfile;

   opendir $dh, $dir or die "Couldn't open dir '$dir': $!";
   @files = grep { !/^\.\.?$/ } readdir $dh;
   closedir $dh;

   foreach my $file (@files)
   {
      #if($file =~ m/.*\.(ts|eit)$/i)
      if($file =~ m/.*\.ts$/i)
      {
         $fullfile = File::Spec->catdir($dir,$file);
         if( -f $fullfile )
         {
            push(@tsfiles, $fullfile);
         }
      }
   }
   return @tsfiles;
}


sub getUniqueDestName
{
my ($dir, $file) =  @_;
my $unqname;
my $name = $file;
my $extn = "";
my $cnt=1;
my $ts;

   # If it doesn't exist then just use the original name
   $unqname = File::Spec->catdir($dir,$file);
   if( ! -f $unqname)
   {
      return $unqname;
   }

   if($file =~ m/^(.*)(\..*)$/ )
   {
      $name = $1;
      $extn = $2;   
   }
   
   # Try inserting a version number betzeen 1 and 9 into the file name
   $cnt = 1;
   for($cnt = 1; $cnt < 10; $cnt++)
   {
      $unqname = File::Spec->catdir($dir, $name . "." . $cnt . $extn);
      if( ! -f $unqname)
      {
         return $unqname;
      }
   }
   
   # In desperation use a timestamp, in theory the file can't already exist!!!
   my @now = localtime();
   $ts = sprintf("%04d%02d%02d%02d%02d%02d", 
                        $now[5]+1900, $now[4]+1, $now[3],
                        $now[2],      $now[1],   $now[0]);
   return File::Spec->catdir($dir, $name . "." . $ts . $extn);
}

sub processDir
{
my $ME="processDir: "; # function name for log output
my ($origdir, $destdir) = @_;
my @tsfiles;
my $destpath;
my $tsfilename;
my $dirs;
my $suffix;
my $fullregex;

   # Dedicated function for .ts files so...
   # - Make list of .ts
   # - Check each filename (only filename) against the reg.exp
   #   - Move matching files (using DOS command?) to dest.

   @tsfiles = getTSFiles($origdir);
   $LOG->info($ME . "Count of .TS files found in '$origdir': " . @tsfiles . "\n");
   foreach my $tsfullfile (@tsfiles)
   {
      ($tsfilename,$dirs,$suffix) = fileparse( $tsfullfile );
      foreach my $regex (@gRegexes)
      {
         $fullregex = ".*?" . $regex . ".*";
         if($tsfilename =~ m/$regex/)
         {
            # As always with Perl cannot simply create a function which returns a boolean value
            # as there is no boolean type and returning 0 and 1 for some ridiculous Perl reason
            # are not always interpreted as false and true in conditions.
            $LOG->info($ME . "File '$tsfilename' matches '$regex'\n");
            if(isFileInUse( $tsfullfile) == 0)
            {
               $destpath = getUniqueDestName($destdir, $tsfilename);
               $LOG->info($ME . "Moving '$tsfilename' to $destpath.\n");
               settitle("Moving: $tsfilename");
               
               # Use a temp filename while move is progress as it can take a while and don't
               # want the file to be picked up by other utilities. eit move does not need temp
               # file since it is small and moved quickly
               my $inprogname = $destpath . ".f2emvinprog";
               move($tsfullfile, $inprogname);
               move($inprogname, $destpath);
               
               # Cannot passively handle .eit when it is found as a separate file as it should only be moved if
               # the related .ts file is moved
               (my $eitfullfile = $tsfullfile) =~ s/\.ts$/.eit/;
               $LOG->info($ME . "Checking for '$eitfullfile'.\n");
               if( -f $eitfullfile )
               {
                  my $eitfile;
                  ($eitfile,$dirs,$suffix) = fileparse( $eitfullfile );
                  $destpath = getUniqueDestName($destdir, $eitfile);
                  $LOG->info($ME . "Moving '$eitfullfile' to $destpath.\n");
                  move($eitfullfile, $destpath);
               }
               else
               {
                  $LOG->info($ME . "No eit file found for  '$tsfullfile'.\n");
               }
            }
            else
            {
               $LOG->info($ME . "'$tsfilename' appears to be in use and will not be moved\n");
            }
            
            last; #This means break!
         }
         else
         {
            $LOG->debug($ME . "File '$tsfilename' does NOT match '$regex'.\n");
         }
      }
   }
}

sub isFileInUse
{
	my $ME="isFileInUse: ";
my ($pathname) = @_;
my $bInUse = 0;
my $size1;
my $size2;
my $stat;

   $LOG->debug("isFileInUse: stat '$pathname'\n");
   if( -f $pathname )
   {
      $stat = stat($pathname);
      $size1 = $stat->size;
      sleep(20);  # Size does not seem to update very frequently
      $stat = stat($pathname);
      $size2 = $stat->size;
   
      if($size1 != $size2)
      {
         $LOG->info($ME . "isFileInUse: '$pathname' size changed from $size1 to $size2, assuming file IS in use\n");
         $bInUse = 1;
      }
      else
      {
         $LOG->debug($ME . "isFileInUse: '$pathname' size remained constant at $size1, assuming file NOT in use\n");
      }
   }
   else
   {
      $LOG->info($ME . "isFileInUse: '$pathname' is NOT a file!!!! Returning true\n");
      $bInUse = 1;
   }
   return $bInUse;
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

sub loadConfig
{
my ($file) = @_;  
my $json = loadtext($file);
my $mapref = decode_json($json);
my %config = %{$mapref};

   @CFGregexes = @{$config{'FilenamePatterns'}};
}