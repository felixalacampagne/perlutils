use 5.010;  # Available since 2007, so should be safe to use this!!
use strict;
use warnings;
use FindBin;           # This should find the location of this script
use lib $FindBin::Bin . '/lib'; # This indicates to look for modules in the script location
use Data::Dumper;
use Win32::TieRegistry ( Delimiter=>"/");


# HKEY_CLASSES_ROOT\Directory\shell\FolderMD5
my $shellKeyName = "Classes/Directory/shell/";
my $shellKey;

# Apparently this can only be read by an Administrator. It may be that it can only be written by Admin
# and the default access mode is read/write. Will need to experiment with that. Anyway it looks like just
# running the app and creating the keys if they are not there will not work. It will need to be an option
# which must be used in an administrator promp.
my $p = "Classes/Directory/shell/"; 

   $shellKey = $Registry->{$shellKeyName}; # or die "No shell keys for Directory: $!\n";
   
   foreach my $keyval ( keys %$shellKey )
   {
      if ( $shellKey->{$keyval} )
      {
         print "$keyval: " , $shellKey->{$keyval}, "\n";
      }
   }

my $fmdsubKeyName="FolderMD5/";
my $fmd = $shellKey->{ $fmdsubKeyName };

if( ! $fmd )
{
   print "$fmdsubKeyName not defined for $shellKeyName\n";
    $shellKey->{ $fmdsubKeyName } =  {"command/" => {} } ;
   my $cmdKey = $shellKey->{ $fmdsubKeyName }->{"command/"};
   
  $cmdKey->{'/'} =  "\"E:\\Development\\Perl64\\perl\\bin\\perl.exe\" \"E:\\Development\\utils\\perlutils\\foldermd5.pl\" -l -p \"%1\"" ;
}

