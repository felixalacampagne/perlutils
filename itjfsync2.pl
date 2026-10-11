use strict;
use warnings;
use Win32::OLE;
use Win32::OLE::Variant;
use DBI;
use POSIX qw(strftime);
use Time::Piece;
use Getopt::Std;

# Enforces that standard output console windows handle wide printed symbols cleanly
binmode(STDOUT, ":encoding(UTF-8)");

# Enforce global UTF-8 encoding across the Windows OLE layout for iTunes
Win32::OLE->Option(CP => Win32::OLE::CP_UTF8);

# 1. Configuration
my $jellyfin_db_path = 'H:\tmp\jellyfin.db';
my $jfuser = 'admin';

my %opts;
getopts('u:d:', \%opts);

if( $opts{"d"})
{
   $jellyfin_db_path = $opts{"d"};
}

if( $opts{"u"})
{
   $jfuser = $opts{"u"};
}

my $user_id = undef; #          = '9C8D1F02-C8B0-4017-8FFF-5527AB26B874';         # Your Jellyfin User GUID

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

if (!$user_id) {
    die "ERROR: Could not find a Jellyfin user named '$jfuser' in the database!\n";
} else {
    print "Found User ID for '$jfuser': $user_id\n";
}


# Prepare the SQL statement for writing to Jellyfin
my $sth = $dbh->prepare(<<"SQL");
INSERT INTO UserData (ItemId, UserId, CustomDataKey, PlayCount, LastPlayedDate, Rating,
                      IsFavorite, PlaybackPositionTicks, Played)
VALUES (?, ?, ?, ?, ?, ?, 0, 0, 1)
ON CONFLICT(ItemId, UserId, CustomDataKey) DO UPDATE SET
    PlayCount = excluded.PlayCount,
    LastPlayedDate = excluded.LastPlayedDate,
    Rating = excluded.Rating;
SQL

# 3. Connect to iTunes via COM
print "Connecting to iTunes COM interface...\n";
my $itunes = Win32::OLE->new('iTunes.Application')
    or die "iTunes could not be started: " . Win32::OLE->LastError();

my $library_source = $itunes->LibrarySource;
my $playlist       = $library_source->Playlists->ItemByName("Music");
my $tracks         = $playlist->Tracks;
my $count          = $tracks->Count;

print "Found $count tracks in iTunes. Starting bidirectional sync with trimmed lookup values...\n";

my $unmapped_count = 0;

# 4. Process Tracks
for (my $i = 1; $i <= $count; $i++) {
    my $track = $tracks->Item($i);
    next unless $track;

    my $name   = $track->Name   || '';
    my $album  = $track->Album  || '';
    my $artist = $track->Artist || '';

   # ?? NEW STEP: Trim leading and trailing whitespaces cleanly via Regex
   # \s+ matches any whitespace characters. ^ looks at the start, $ looks at the end.
   $name   =~ s/^\s+|\s+$//g;
   $album  =~ s/^\s+|\s+$//g;
   $artist =~ s/^\s+|\s+$//g;

   my $itunes_rating_raw = $track->Rating || 0; # Returns 0, 20, 40, 60, 80, or 100

   # 5. Look up the Track GUID and its current Jellyfin UserData info
   my $lookup_sth = $dbh->prepare(<<"SQL");
      SELECT b.Id, u.LastPlayedDate, u.PlayCount, u.Rating
      FROM BaseItems b
      LEFT JOIN UserData u
         ON b.Id = u.ItemId AND u.UserId = ? AND LOWER(u.CustomDataKey) = LOWER(b.Id)
      WHERE b.Type = 'MediaBrowser.Controller.Entities.Audio.Audio'
         AND LOWER(b.Name) = LOWER(?)
         AND LOWER(b.Album) = LOWER(?)
         AND LOWER(b.Artists) = LOWER(?)
      LIMIT 1;
SQL
   $lookup_sth->execute($user_id, $name, $album, $artist);
   my ($jellyfin_track_id, $jellyfin_date_str, $jellyfin_play_count, $jellyfin_rating) = $lookup_sth->fetchrow_array();
   $lookup_sth->finish();

   # Report when there is no Jellyfin DB entry for the track
   if (!$jellyfin_track_id) {
      print "WARN Unmapped Track: No Jellyfin DB Entry found for: [$artist] - [$name] (Album: $album)\n";
      $unmapped_count++;
      next;
   }

   if( !$jellyfin_rating)
   {
      $jellyfin_rating = 0;
   }

   my $itune_rating_jellyfin = 0;
   if ($itunes_rating_raw > 0) {
      # Convert iTunes 0-100 scale directly to Jellyfin's 0.0-10.0 scale
      $itune_rating_jellyfin = $itunes_rating_raw / 10;
   }

    # Extract the iTunes Last Played Date
   my $played_date_variant = $track->PlayedDate;
   my $itunes_time         = undef;

   # For some reason the Jellyfin updates keep happening even though correct the values are in the DB.
   # This maybe because the seconds are lost so I've removed the seconds from all date formats.
   # Actually it was more likely due to the localtime vs GMT mismatch so canprobably restore the seconds.
   if ($played_date_variant && ref($played_date_variant))
   {
      # Force the COM object to coerce itself into a strict text string (VT_BSTR = 8).
      # WARNING: The time is a LOCAL time. localtime->strptime parses the date string as a local time and converts to GMT.
      # The Jellyfin DB stores the time in GMT so this is a necessary step.
      my $date_string = eval { $played_date_variant->As(8); };

      if ($date_string && $date_string ne '' && $date_string ne '00:00:00')
      {
         $date_string = substr($date_string, 0, 19); # Trim to "MM/DD/YYYY HH:MM:SS" or "DD/MM/YYYY HH:MM:SS" depending on locale
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
            warn "Could not match date string format for value: '$date_string'\n";
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
               eval {
                  $sth->execute($jellyfin_track_id, $user_id, $jellyfin_track_id, $jellyfin_play_count, $jellyfin_date_str, $itune_rating_jellyfin);
                  print "Synced to Jellyfin (Rating Only): [$artist] - [$name] (Album: $album): Rating updated to $itune_rating_jellyfin\n";
               };
               if ($@) { warn "Error writing rating to Jellyfin for: [$artist] - [$name] (Album: $album): [$jellyfin_play_count]: $@\n"; }
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
         $jellyfin_time = Time::Piece->strptime($jellyfin_date_str, "%Y-%m-%d %H:%M:%S");
      };
   }

   # 6. Evaluation Logic
   my $itunes_play_count = $track->PlayedCount || 0;

   # Scenario A: iTunes has a more recent listen -> Update Jellyfin
   if ($itunes_time && (!$jellyfin_time || $itunes_time > $jellyfin_time)) {
      my $itep = $itunes_time->epoch;
      my $jfep = $jellyfin_time ? $jellyfin_time->epoch : 0;
      my $test = ($itep > $jfep) ? "TRUE" : "FALSE";
      print("it>jf Times: itunes $itep > jellyfin $jfep : $test \n");
      my $itunes_date_str = $itunes_time->strftime("%Y-%m-%d %H:%M:%S");
      my $rating = $itune_rating_jellyfin > $jellyfin_rating ? $itune_rating_jellyfin : $jellyfin_rating;
     eval {
            $sth->execute($jellyfin_track_id, $user_id, $jellyfin_track_id, $itunes_play_count, $itunes_date_str, $rating);
            print "Synced to Jellyfin: [$artist] - [$name] (Album: $album): $itunes_date_str\n";
        };
        if ($@) { warn "Error writing to Jellyfin for: [$artist] - [$name] (Album: $album): $@\n"; }
    }

    # Scenario B: Jellyfin has a more recent listen -> Update iTunes
    elsif ($jellyfin_time && (!$itunes_time || $jellyfin_time > $itunes_time)) {

      my $jfep = $jellyfin_time->epoch;
      my $itep = $itunes_time ? $itunes_time->epoch : 0;
      my $test = ($jfep > $itep) ? "TRUE" : "FALSE";
      print("jf>it Times: jellyfin $jfep > itunes $itep : $test\n");
      # "%m/%d/%Y %I:%M:%S %p"  doesn't seem to work
      # but 'Jan 1,1970' does seems to work
      # %b %e, %Y   YES! It worked
      # %b %e, %Y %H:%M:%S This seems to work as well - although a localtime correction seems to be applied to it
      # ie. the date displayed in Perl is 'GMT' but the date displayed in iTunes is summertime CET (GMT+2).
      my $date_for_itunes = localtime($jellyfin_time)->strftime("%b %e, %Y %H:%M:%S");
      # print "Formatted datestring for variant date: $date_for_itunes\n";
      $date_for_itunes = Variant(VT_DATE, $date_for_itunes);
      # print "Updating iTunes Last Played Date for: [$artist] - [$name] (Album: $album): $date_for_itunes\n";
      eval {
         $track->{PlayedDate} = $date_for_itunes;
         print "Synced ?? iTunes (Date Only): [$artist] - [$name] (Album: $album): $date_for_itunes\n";
      };
      if ($@) { warn "Error writing to iTunes for: [$artist] - [$name] (Album: $album): $@\n"; }

      eval {
         my $current_itunes_count = $track->PlayedCount || 0;

         # If iTunes has no count then sync it to the jellyfin count, if there is one
         my $new_count = $jellyfin_play_count;
         if ($current_itunes_count == 0 && $jellyfin_play_count > 0)
         {
            $track->{PlayedCount} = $new_count;
            print "Synced iTunes (Count): [$artist] - [$name] (Album: $album) : $new_count\n";
         }


      };
        if ($@) { warn "Error writing to iTunes for: [$artist] - [$name] (Album: $album): $@\n"; }
    }
}

# 7. Clean up & Final Report Summary
$sth->finish();
$dbh->disconnect();
$itunes = undef;
undef $itunes;

print "\n========================================\n";
print "Sync completed successfully.\n";
print "Total unmapped iTunes tracks missed: $unmapped_count\n";
print "========================================\n";
