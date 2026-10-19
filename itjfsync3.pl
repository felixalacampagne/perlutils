use strict;
use warnings;
use Win32::OLE;          # cpan Win32::OLE
use Win32::OLE::Variant;
use DBI;                 # cpan DBI  cpan DBD::SQLite
use POSIX qw(strftime);
use Time::Piece;
use Getopt::Std;
use File::Copy;
use File::Basename; # Core module to cleanly parse paths, file names, and extensions
use Unicode::Normalize qw(NFC);
use Digest::MD5 qw(md5_hex);
use Data::Dumper;
$Data::Dumper::Useqq = 1; # This forces hidden characters like \n to show up clearly

# WARNING: This does not handle the case where the Jellyfin DB does not contain a UserData
# entry for a track that has been played in iTunes.  In that case, the track will be
# skipped and not synced to Jellyfin.
# To handle such missing tracks will require an update to the itunes-update file
# processor which runs on the NAS as well as updates to this script to select
# tracks which have no UserData and to handle them appropriately.

my $VERSION="4.0.0";

# Enforces that standard output console windows handle wide printed symbols cleanly
binmode(STDOUT, ":encoding(UTF-8)");

# Enforce global UTF-8 encoding across the Windows OLE layout for iTunes
Win32::OLE->Option(CP => Win32::OLE::CP_UTF8);

# 1. Configuration
my $jellyfin_db_path = 'H:/tmp/jellyfin.db';
my $queue_file = 'H:/tmp/itunes-updates.txt';
my $jfuser = 'admin';

my %opts;
getopts('u:d:q:', \%opts);

if( $opts{"d"})
{
   $jellyfin_db_path = $opts{"d"};
}

if( $opts{"q"})
{
   $queue_file = $opts{"q"};
}

if( $opts{"u"})
{
   $jfuser = $opts{"u"};
}

my $user_id = undef; #

print "Connecting to iTunes COM interface...\n";
my $itunes = Win32::OLE->new('iTunes.Application')
    or die "iTunes could not be started: " . Win32::OLE->LastError();


# Connect to the Jellyfin SQLite Database with strict Unicode mappings
print "Connecting to Jellyfin Database...\n";
my $dbh = DBI->connect("dbi:SQLite:dbname=$jellyfin_db_path", "", "", {
    RaiseError         => 1,
    AutoCommit         => 1,
    sqlite_unicode     => 1,
    sqlite_string_mode => 4,
}) or die "Could not connect to database: $DBI::errstr";

# Look up the 32-character Hex ID from the Users table
my $user_sth = $dbh->prepare("SELECT Id FROM Users WHERE LOWER(Username) = LOWER(?) LIMIT 1;");
$user_sth->execute($jfuser);
($user_id) = $user_sth->fetchrow_array();
$user_sth->finish();

if (!$user_id)
{
   die "ERROR: Could not find a Jellyfin user named '$jfuser' in the database!\n";
}
else
{
   print "Found User ID for '$jfuser': $user_id\n";
}

my %jellyfin_track_map = build_jellyfin_track_map($dbh, $user_id);
print "Loaded Jellyfin track map for '$jfuser': " . scalar(keys %jellyfin_track_map) . " entries\n";

my $it_jf_updates = "";  # ITEM_GUID|USER_GUID|LAST_PLAYED_DATE|RATING
my $library_source = $itunes->LibrarySource;
my $playlist       = $library_source->Playlists->ItemByName("Music");
my $tracks         = $playlist->Tracks;
my $count          = $tracks->Count;

print "Found $count tracks in iTunes. Starting bidirectional sync...\n";

my $unmapped_count = 0;
my $processed_Count = 0;
# 4. Process Tracks
for (my $i = 1; $i <= $count; $i++) {
   $processed_Count++;
   print ("Processing track $processed_Count of $count...\n") if ($processed_Count % 200 == 0);
   my $track = $tracks->Item($i);
   next unless $track;

   my $name   = $track->Name   || '';
   my $album  = $track->Album  || '';
   my $artist = $track->Artist || '';
   my $it_location = $track->Location || '';
   if(!$it_location)
   {
      print "WARN: Missing iTunes file for track: $artist: $album: $name\n";
      next;
   }

   # print "it: $artist: $album: $name: $it_location\n";

   # Trim leading and trailing whitespaces cleanly via Regex
   # \s+ matches any whitespace characters. ^ looks at the start, $ looks at the end.
   $name   =~ s/^\s+|\s+$//g;
   $album  =~ s/^\s+|\s+$//g;
   $artist =~ s/^\s+|\s+$//g;

   my $itunes_rating_raw = $track->Rating || 0; # Returns 0, 20, 40, 60, 80, or 100

   # 5. Look up the track metadata from the pre-built Jellyfin map
   my $track_key = build_track_key($it_location);
   my $md5 =  md5_hex($track_key);
   my $jf_entry = $jellyfin_track_map{$md5};

   if (!$jf_entry) {
      print "WARN: No Jellyfin DB Entry found: $artist: $album: $name: $it_location: [$md5] [$track_key] \n";
      #print "" . Dumper($track_key) ."\n";
      #print "" . Dumper(\%jellyfin_track_map) . "\n";
      $unmapped_count++;
      my $hash_key_entry = $jellyfin_track_map{"1b23eebe28362ed358ba29bde865eb9e"};
      my $hash_key = $hash_key_entry->{key};

      # Convert both strings into arrays of their exact byte values
      my @lookup_bytes = unpack("C*", $track_key);
      my @hash_bytes   = unpack("C*", $hash_key);

      print "Lookup string length: " . scalar(@lookup_bytes) . " bytes\n";
      print "Hash key string length:   " . scalar(@hash_bytes) . " bytes\n";

      # Loop through and find exactly where they diverge
      my $max_len = scalar(@lookup_bytes) > scalar(@hash_bytes) ? scalar(@lookup_bytes) : scalar(@hash_bytes);

      print "\n--- BYTE BY BYTE COMPARISON ---\n";
      print "POS\tCHAR\tLOOKUP BYTE\tHASH BYTE\n";
      print "--------------------------------------\n";

      for (my $i = 0; $i < $max_len; $i++) {
         my $l_byte = $lookup_bytes[$i] // 'END';
         my $h_byte = $hash_bytes[$i]   // 'END';

         # Get a printable character if possible
         my $l_char = ($l_byte ne 'END' && $l_byte >= 32 && $l_byte <= 126) ? chr($l_byte) : '?';

         if ($l_byte ne $h_byte) {
            print "[$i]\t'$l_char'\t$l_byte\t\t$h_byte  <-- MISMATCH HERE!\n";
         }
      }


      exit;
      next;
   }

   my $jellyfin_track_id = $jf_entry->{itemid};
   my $jellyfin_date_str = $jf_entry->{lastplayeddate};
   my $jellyfin_play_count = $jf_entry->{playcount} || 0;
   my $jellyfin_rating = defined $jf_entry->{rating} ? $jf_entry->{rating} : 0;

   if( !$jellyfin_rating)
   {
      $jellyfin_rating = 0;
   }

   my $itune_rating_jellyfin = 0;
   if ($itunes_rating_raw > 0) {
      # Convert iTunes 0-100 scale directly to Jellyfin's 0.0-10.0 scale
      $itune_rating_jellyfin = $itunes_rating_raw / 10;
      # print "it rating: raw [$itunes_rating_raw] cnv [$itune_rating_jellyfin]\n";
   }

   # Extract the iTunes Last Played Date
   my $played_date_variant = $track->PlayedDate;
   my $itunes_time         = undef;
   my $it_orig_date_str    = 'N\A';
   if ($played_date_variant && ref($played_date_variant))
   {
      # Force the COM object to coerce itself into a strict text string (VT_BSTR = 8).
      # WARNING: Seems iTunes time is a LOCAL time. localtime->strptime parses the date string as a local time and converts to GMT.
      # The Jellyfin DB stores the time in GMT so this is a necessary step.
      # Aaaggghhh! On minnie the iTunes time is GMT, on tufty it is localtime
      # That doesn't seem to right either.
      # The date string returned by the COM object is the same as the value displayed in iTunes which
      # is therefore presumably the localtime.
      my $date_string = eval { $played_date_variant->As(8); };
      $it_orig_date_str = $date_string;
      if ($date_string && $date_string ne '' && $date_string ne '00:00:00')
      {
         $date_string = substr($date_string, 0, 19);
         # Dynamically parse the resulting text string based on your local Windows time layout
         eval {
            # Layout Option 1: Standard European/UK format (e.g., "10/10/2026 17:00:15")
            $itunes_time = localtime->strptime($date_string, "%d/%m/%Y %H:%M:%S");

         };
         if ($@) {
            eval {
                  # Layout Option 2: Standard US format (e.g., "10/10/2026 05:00:15 PM")
                  $itunes_time = localtime->strptime($date_string, "%m/%d/%Y %H:%M:%S");
            };
         }
         if ($@) {
            eval {
                  # Layout Option 3: Standard ISO/Fallback format (e.g., "2026-10-10 17:00:15")
                  $itunes_time = localtime->strptime($date_string, "%Y-%m-%d %H:%M:%S");
            };
         }

         # If any patterns match cleanly, map the string output for your Jellyfin comparisons
         if (!$itunes_time) {
            warn "WARN: $artist: $album: $name: unrecognized date format: '$date_string'\n";
         }
         else
         {
            $itunes_time = gmtime($itunes_time->epoch);
         }
      }
      else
      {
         # No date which may be because there is an exclusion rating so need to ensure that is
         # tranferred to Jellyfin as well.  This is a special case where the track has been rated but not played.
         if ($itune_rating_jellyfin > 0)
         {
            if( $jellyfin_rating != $itune_rating_jellyfin )
            {
               if( !$jellyfin_play_count )
               {
                  $jellyfin_play_count = 0;
               }
               # ITEM_GUID|USER_GUID|LAST_PLAYED_DATE|RATING
               $it_jf_updates .= "$jellyfin_track_id|$user_id|$jellyfin_date_str|$itune_rating_jellyfin\n";
            }
         }
         next;
      }
   }
   else
   {
      # print "No iTunes last played date for: [$artist] - [$name] (Album: $album)\n";
      next;
   }

   # Parse Jellyfin's timestamp if it exists
   my $jellyfin_time = undef;
   if ($jellyfin_date_str)
   {
      $jellyfin_date_str =~ s/[TZ]/ /g;
      $jellyfin_date_str = substr($jellyfin_date_str, 0, 19);
      eval
      {
         $jellyfin_time = Time::Piece->strptime($jellyfin_date_str, "%Y-%m-%d %H:%M:%S"); # returns GMT time
      };
   }
   else
   {
      $jellyfin_date_str = "";
   }


   # 6. Evaluation Logic
   my $itunes_play_count = $track->PlayedCount || 0;

   # Scenario A: iTunes has a more recent listen -> Update Jellyfin
   if ($itunes_time && (!$jellyfin_time || $itunes_time > $jellyfin_time)) {
      my $itep = $itunes_time->epoch;
      my $jfep = $jellyfin_time ? $jellyfin_time->epoch : 0;
      my $test = ($itep > $jfep) ? "TRUE" : "FALSE";
      # print("it>jf Times: itunes $itep > jellyfin $jfep : $test \n");
      my $itunes_date_str = $itunes_time->strftime("%Y-%m-%d %H:%M:%S");
      $itunes_date_str = $itunes_date_str;
      my $rating = $itune_rating_jellyfin > $jellyfin_rating ? $itune_rating_jellyfin : $jellyfin_rating;

      print "it>jf: $artist: $album: $name: itORIG:$it_orig_date_str itGMT:$itunes_time itDTSTR:$itunes_date_str jfORIG:$jellyfin_date_str itep:$itep jfep: $jfep\n";
      # goto CLEANEXIT;
      $it_jf_updates .= "$jellyfin_track_id|$user_id|$itunes_date_str|$rating\n";
    }
    # Scenario B: Jellyfin has a more recent listen -> Update iTunes
    elsif ($jellyfin_time && (!$itunes_time || $jellyfin_time > $itunes_time)) {

      my $jfep = $jellyfin_time->epoch;
      my $itep = $itunes_time ? $itunes_time->epoch : 0;
      my $date_for_itunes = gmtime($jfep)->strftime("%b %e, %Y %H:%M:%S");
      $date_for_itunes = Variant(VT_DATE, $date_for_itunes);

      print "jf>it: $artist: $album: $name: jfORIG:$jellyfin_date_str jfTIME:$jellyfin_time itORIG:$it_orig_date_str itGMT:$itunes_time jfDTSTR:$date_for_itunes itep:$itep jfep: $jfep\n";
      # goto CLEANEXIT;
      eval {
         $track->{PlayedDate} = $date_for_itunes;
         #print "Synced ?? iTunes (Date Only): [$artist] - [$name] (Album: $album): $date_for_itunes\n";
      };
      if ($@) { warn "WARN: $artist: $album: $name: Error writing to iTunes: $@\n"; }

      eval {
         my $current_itunes_count = $track->PlayedCount || 0;

         # If iTunes has no count then sync it to the jellyfin count, if there is one
         my $new_count = $jellyfin_play_count;
         if ($current_itunes_count == 0 && $jellyfin_play_count > 0)
         {
            $track->{PlayedCount} = $new_count;
            print "jf->it: $artist: $album: $name: Synced Count: $new_count\n";
         }


      };
      if ($@) { warn "WARN: $artist: $album: $name: Error writing to iTunes: $@\n"; }
    }
}

writeitjfsyncfile($it_jf_updates);

print "\n========================================\n";
print "Sync completed successfully.\n";
print "Total unmapped iTunes tracks missed: $unmapped_count\n";
print "========================================\n";

CLEANEXIT:
$dbh->disconnect();
$itunes = undef;
undef $itunes;

sub build_jellyfin_track_map {
   my ($dbh, $user_id) = @_;
   my %track_map;

   my $sth = $dbh->prepare(<<'SQL');
      SELECT
         b.Id AS itemid,
         b.Name AS name,
         b.Album AS album,
         b.Artists AS artist,
         b.Path AS path,
         u.UserId AS userid,
         strftime('%Y-%m-%d %H:%M:%S', u.LastPlayedDate) AS lastplayeddate,
         u.PlayCount AS playcount,
         u.Rating AS rating
      FROM BaseItems b
      LEFT JOIN UserData u
         ON b.Id = u.ItemId
         -- 2. Moved UserData-specific filters here so they don't break the LEFT JOIN
         AND u.LastPlayedDate IS NOT NULL
         AND (LOWER(u.CustomDataKey) = LOWER(b.Id) OR u.CustomDataKey IS NULL OR u.CustomDataKey = '')
         AND (u.UserId = ? or u.UserId is NULL)
      WHERE b.Type = 'MediaBrowser.Controller.Entities.Audio.Audio'
SQL
   $sth->execute($user_id);

   while (my $row = $sth->fetchrow_hashref()) {
      my $location = $row->{path};
      my $artist = defined $row->{artist} ? $row->{artist} : '';
      my $album  = defined $row->{album} ? $row->{album} : '';
      my $name   = defined $row->{name} ? $row->{name} : '';

      if( !defined $row->{path} )
      {
         print "WARN: build_jellyfin_track_map: No path for $artist:$album:$name\n";
         next;
      }

      # There appears to be problem in that there can be duplicate Artist/Album/Track entries in the JF db
      # This is because there are multiple versions of the same albums, ie. different remixes, each having the
      # same tracks. The only difference is in the path name.
      # the Jellyfin 'baseitems.path' looks like:
      # /music/alac/01 pop-rock/Bob Dylan - Blonde On Blonde (rm2013) (1966)/13 Obviously 5 Believers.m4a
      # whereas the iTunes path looks like:
      # \\NASUG\public\music\alac\01 pop-rock\Bob Dylan - Blonde On Blonde (rm2013) (1966)\13 Obviously 5 Believers.m4a

      # maybe it would be better to use the path as the key and convert the iTunes path to a Jellyfin path.
      # But that would be a lot of work and would require a lot of testing.
      my $key    = build_track_key($location);
      my $md5 = md5_hex($key);
      # print  "build_jellyfin_track_map: $artist:$album:$name:$location: [$key] [$md5]\n";
      $track_map{$md5} = {
         userid          => $row->{userid} || $user_id,
         itemid          => $row->{itemid},
         lastplayeddate  => $row->{lastplayeddate},
         playcount       => $row->{playcount} || 0,
         rating          => defined $row->{rating} ? $row->{rating} : 0,
         artist          => $artist,
         album           => $album,
         name            => $name,
         path            => $location,
         key             => $key
      };
   }

   $sth->finish();
   return %track_map;
}

# Jellyfin path is like
# /music/alac/01 pop-rock/Bob Dylan - Blonde On Blonde (rm2013) (1966)/13 Obviously 5 Believers.m4a
# whereas the iTunes path looks like:
# \\NASUG\public\music\alac\01 pop-rock\Bob Dylan - Blonde On Blonde (rm2013) (1966)\13 Obviously 5 Believers.m4a
sub build_track_key {
   my ($path) = @_;
   my $key = $path;

   $key = '' unless defined $key;
   $key = NFC($key);
   $key =~ s/[\x{2018}\x{2019}\x{201B}\x{2032}]/'/g;
   $key =~ s/[\x{201C}\x{201D}\x{2033}]/"/g;
   $key =~ s/\s+/ /g;
   $key =~ s/^\s+|\s+$//g;

   $key =~ s/^\/music\///;
   $key =~ s/^\\\\NASUG\\public\\music\\//;
   $key =~ s/\\/\//g;

   # utf8::downgrade($key, 1);
   # print "build_track_key: $path -> $key\n";

   return lc($key);
}

sub writeitjfsyncfile
{
   my ($data) = @_;
   if ($data && $data ne '')
   {
      backupfile($queue_file);

      open(my $fh, '>>', $queue_file) or die "CRITICAL ERROR: Cannot open queue file for writing: $!";
      print $fh $data;
      close($fh);
      print "Queue file written successfully with updated track data.\n";
   }
   else
   {
      print "No updates to write to the queue file. It remains unchanged.\n";
   }
}

sub backupfile
{
   my ($file) = @_;

   if (!-e $file || -s $file == 0) {
      print "$file is empty or missing. Nothing to backup.\n";
      return;
   }

    my ($filename, $directory, $extension) = fileparse($file, qr/\.[^.]*$/);

    my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);
    my $timestamp = sprintf("%04d%02d%02d_%02d%02d%02d",
                            $year + 1900, $mon + 1, $mday, $hour, $min, $sec);


    my $backup_file = $directory . $filename . "_" . $timestamp . $extension;

    if (copy($file, $backup_file)) {
        print "$file backed up successfully to: $backup_file\n";
    } else {
        warn "Copy failed ($!)\n";
    }
}
