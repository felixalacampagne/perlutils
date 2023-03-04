use 5.010;  # Available since 2007, so should be safe to use this!!
use strict;
use warnings;
use FindBin;           # This should find the location of this script
use lib $FindBin::Bin . '/lib'; # This indicates to look for modules in the script location
use Data::Dumper;
use Win32::TieRegistry ( Delimiter=>"/");


# HKEY_CLASSES_ROOT\Directory\shell\FolderMD5
my $shellRootName = "Classes/Directory/shell/";


# Apparently this can only be read by an Administrator. It may be that it can only be written by Admin
# and the default access mode is read/write. Will need to experiment with that. Anyway it looks like just
# running the app and creating the keys if they are not there will not work. It will need to be an option
# which must be used in an administrator promp.

addfmd5toKey($shellRootName, "-l -p");

$shellRootName = "Classes/Drive/shell/";
addfmd5toKey($shellRootName, "-l -p");

$shellRootName = "Classes/DVD/shell/";
addfmd5toKey($shellRootName, "-c -l -p");


sub addfmd5toKey
{
my ($shellKeyName, $options) = @_;
# Probably makes more sense for the perl and the script  paths to be supplied
# as they will be common for all entries
# chunky: C:\development\Perl64\bin\perl.exe "C:/Development/utils/perlutils\foldermd5.pl" -l -p "%1"
my $perlpath = "C:\\Development\\Perl64\\perl\\bin\\perl.exe";
my $scriptpath = "C:\\Development\\utils\\perlutils\\foldermd5.pl";

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
   my $fmdsubKeyName="FolderMD5/";
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
