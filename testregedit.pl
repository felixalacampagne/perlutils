use 5.010;  # Available since 2007, so should be safe to use this!!
use strict;
use warnings;
use FindBin;           # This should find the directory of this script
use lib $FindBin::Bin . '/lib'; # This indicates to look for modules in the script location
use Data::Dumper;
use Win32::TieRegistry ( Delimiter=>"/");
use Win32;
use File::Spec;

my $GSCRIPTPATH = "";
my $GPERLPATH = "";

sub addfmd5toKey
{
my ($shellKeyName, $options) = @_;
   addScriptEntryToKey($shellKeyName,"FolderMD5X/", $options, 0); 
}

sub addfmd5RecalctoKey
{
   my ($shellKeyName, $options) = @_;
   addScriptEntryToKey($shellKeyName,"FolderMD5 RecalculateX/", $options, 1); 
}

sub addScriptEntryToKey
{
my ($shellKeyName, $scriptKeyName, $options, $extended) = @_;   
# Probably makes more sense for the perl and the script  paths to be supplied
# as they will be common for all entries
# chunky: C:\development\Perl64\bin\perl.exe "C:/Development/utils/perlutils\foldermd5.pl" -l -p "%1"
if( $GPERLPATH eq "" )
{
   
my $secure_perl_path = $Config{perlpath};
if ($^O ne 'VMS') {
    $secure_perl_path .= $Config{_exe}
    unless $secure_perl_path =~ m/$Config{_exe}$/i;
}
   $GPERLPATH = $^X;
   print "Perl executable path: $GPERLPATH\n";
}

if( $GSCRIPTPATH eq "" )
{
   $GSCRIPTPATH =  File::Spec->catdir($FindBin::Bin, $FindBin::Script) ;
   print "Perl script path: $GSCRIPTPATH\n";
}

my $perlpath = $GSCRIPTPATH;
my $scriptpath = $GSCRIPTPATH;

my $shellKey;   
   $shellKey = $Registry->{$shellKeyName}; # or die "No shell keys for Directory: $!\n";
   
#   foreach my $keyval ( keys %$shellKey )
#   {
#      if ( $shellKey->{$keyval} )
#      {
#         print "$keyval: " , $shellKey->{$keyval}, "\n";
#      }
#   }


   # Running as normal user the FolderMD5 key cannot be read so it is created, without error.
   # The subkeys/values are then created and read without error BUT nothing appears in the registry!
   # For some reason DVD/shell/ is the only one which reports it cannot create the FolderMD5 key.
   # From an admin prompt it appears to work - at least it updated the values on chunky
   my $fmdsubKeyName = $scriptKeyName;
   my $fmdKey = $shellKey->{ $fmdsubKeyName };
   
   if( ! $fmdKey )
   {
      print "Creating $fmdsubKeyName for $shellKeyName\n";
      $shellKey->{ $fmdsubKeyName } =  {"command/" => {} } ;
   }

   # Always add/update the value as the path/options may have changed
   $fmdKey = $shellKey->{ $fmdsubKeyName };
   if( $fmdKey )
   {
      if( $extended == 1 )
      {
         $fmdKey->{'/Extended'} = "";
      }
      
      my $cmdKey = $fmdKey->{"command/"};
      if( $cmdKey )
      {
         if( $options ne "" )
         {
            $options = " " . $options;
         }
         print "Updating 'command' values for  '$shellKeyName'\n";
         $cmdKey->{'/'} =  "\"$perlpath\" \"$scriptpath\"$options \"%1\"" ;
      }
      else
      {
         print "Cannot read '$fmdsubKeyName/command' key for '$shellKeyName'\n";
      }
   }
   else
   {
      print "Cannot create/read '$fmdsubKeyName' key for '$shellKeyName'\n";
   }

}

sub registerfmd5
{
my $shellRootName = "";

   # Apparently this can only be read by an Administrator. It may be that it can only be written by Admin
   # and the default access mode is read/write. Will need to experiment with that. Anyway it looks like just
   # running the app and creating the keys if they are not there will not work. It will need to be an option
   # which must be used in an administrator prompt.

   # There is some scope here for iterating over a list but note that not all options are the same
   $shellRootName = "Classes/Directory/shell/";
   addfmd5toKey($shellRootName, "-l -p");

   $shellRootName = "Classes/Drive/shell/";
   addfmd5toKey($shellRootName, "-l -p");

   $shellRootName = "Classes/DVD/shell/";
   addfmd5toKey($shellRootName, "-c -l -p");

   # Previously these were under 'FolderMD5 Update' but now use the same name as for Drive,Directory
   $shellRootName = "Classes/iTunes.m4v/shell/";
   addfmd5toKey($shellRootName, "-l -p");

   $shellRootName = "Classes/WMP11.AssocFile.MP3/shell/";
   addfmd5toKey($shellRootName, "-l -p");

   $shellRootName = "Classes/WMP.FlacFile/shell/";
   addfmd5toKey($shellRootName, "-l -p");

   $shellRootName = "Classes/WMP11.AssocFile.MP4/shell/";
   addfmd5toKey($shellRootName, "-l -p");

   # The other type of key is for the 'Extended' context menu entry, the 'Shift-click' menu,
   # where the force recalculate item appears, ie. 'FolderMD5 Recalculate'
   # This is only added for Drive and Directory (makes no sense for DVD which is assumed to be read only)
   # This requires the '"Extended"="' value adding to the 'FolderMD5 Recalculate' key.
   addfmd5RecalctoKey("Classes/Drive/shell/", "-r -l -p");
   addfmd5RecalctoKey("Classes/Directory/shell/", "-r -l -p");
}
####### main part of prgram - should be a function so it can be added to foldermd5 'as-is'
if ( Win32::IsAdminUser != 0 )
{
   registerfmd5();
}
else
{
   # Could use Win32::RunAsAdmin (https://metacpan.org/pod/Win32%3a%3aRunAsAdmin) which
   # restarts the script in a Admin console, which closes immediately which sort of ugly.
   # No doubt workaround is possible but for now I'll keep it simple
   print "The (re-)register option is only available when running as Administrator\n";
}
