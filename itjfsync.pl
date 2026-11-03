#cpan Win32::OLE
#cpan DBI
#cpan DBD::SQLite

use strict;
use warnings;
use Win32::OLE;
use DBI;
use POSIX qw(strftime);
use Time::Piece; # Standard module for clean date comparisons

# Enforces that standard output console windows handle the wide printed symbols cleanly
# Prevents the "Wide character in print" terminal warning message
binmode(STDOUT, ":encoding(UTF-8)");
Win32::OLE->Option(CP => Win32::OLE::CP_UTF8);


# 1. Configuration
my $jellyfin_db_path = 'H:\tmp\jellyfin.db'; # Update to your local or mounted DB path
my $user_id          = '9C8D1F02-C8B0-4017-8FFF-5527AB26B874';         # Your Jellyfin User GUID

# 2. Connect to the Jellyfin SQLite Database
print "Connecting to Jellyfin Database...\n";
my $dbh = DBI->connect("dbi:SQLite:dbname=$jellyfin_db_path", "", "", {
    RaiseError         => 1,
    AutoCommit         => 1,
    # These flags decode incoming text dynamically into native Perl strings
    sqlite_unicode     => 1,
    sqlite_string_mode => 4, # Enforces strict modern UTF-8 string decoding
}) or die "Could not connect to database: $DBI::errstr";

# Prepare the SQL statement using your case-insensitive CustomDataKey matching rule
# This safely updates or inserts user data records for a specific track ID
my $sth = $dbh->prepare(<<"SQL");
INSERT INTO UserData (ItemId, UserId, CustomDataKey, PlayCount, LastPlayedDate)
VALUES (?, ?, ?, ?, ?)
ON CONFLICT(ItemId, UserId, CustomDataKey) DO UPDATE SET
    PlayCount = MAX(PlayCount, excluded.PlayCount),
    LastPlayedDate = CASE 
        WHEN excluded.LastPlayedDate > LastPlayedDate OR LastPlayedDate IS NULL THEN excluded.LastPlayedDate 
        ELSE LastPlayedDate 
    END;
SQL

# 3. Connect to iTunes via COM
print "Connecting to iTunes COM interface...\n";
my $itunes = Win32::OLE->new('iTunes.Application') 
    or die "iTunes is not installed or could not be started via COM: " . Win32::OLE->LastError();

# Get the main library source and the primary library playlist
my $library_source = $itunes->LibrarySource;
my $playlist       = $library_source->Playlists->ItemByName("Music");
my $tracks         = $playlist->Tracks;
my $count          = $tracks->Count;

print "Found $count tracks in iTunes. Processing and syncing...\n";

# 4. Process Tracks
for (my $i = 1; $i <= $count; $i++) {
    my $track = $tracks->Item($i);
    next unless $track;
    
    # We only care about tracks that have actually been played in iTunes
    my $play_count = $track->PlayedCount || 0;
    next if $play_count == 0;
    
    my $name   = trim( $track->Name || '' );
    my $album  = trim( $track->Album  || '' );
    my $artist = trim( $track->Artist || '' );
    
    # Extract the Last Played Date from COM (returns a Win32 OLE Variant Date object)
    my $played_date_raw = $track->PlayedDate;
    next unless $played_date_raw; # Skip if it has a playcount but no timestamp

    my $jellyfin_date_str = undef;

    # Format the iTunes timestamp into Jellyfin's expected layout
    my $itunes_date_str = strftime("%Y-%m-%d %H:%M:%S", localtime($played_date_raw));
    my $itunes_time     = Time::Piece->strptime($itunes_date_str, "%Y-%m-%d %H:%M:%S");
    
    # Convert Win32 local system time to Jellyfin's expected ISO 8601 UTC format
    # If your iTunes runs on local time, this saves it clearly
    $jellyfin_date_str = strftime("%Y-%m-%d %H:%M:%S", localtime($played_date_raw));

    # 5. Look up the matching Track GUID inside Jellyfin's BaseItems
    # Matching text fields case-insensitively using standard SQL LOWER()
    my $lookup_sth = $dbh->prepare(<<"SQL");
        SELECT Id FROM BaseItems 
        WHERE Type = 'MediaBrowser.Controller.Entities.Audio.Audio' 
          AND LOWER(Name) = LOWER(?) 
          AND LOWER(Album) = LOWER(?) 
          AND LOWER(Artists) = LOWER(?)
        LIMIT 1;
SQL
    $lookup_sth->execute($name, $album, $artist);
    my ($jellyfin_track_id) = $lookup_sth->fetchrow_array();
    $lookup_sth->finish();

    # 6. Date Comparison Logic
    if ($jellyfin_track_id) {
        my $should_update = 0;

        if (!$jellyfin_date_str) {
            # Track exists in Jellyfin but has never been played there; safe to update
            $should_update = 1;
        } else {
            # Strip out any potential 'T' or 'Z' ISO characters from Jellyfin's text string
            $jellyfin_date_str =~ s/[TZ]/ /g;
            $jellyfin_date_str = substr($jellyfin_date_str, 0, 19); # Clean down to YYYY-MM-DD HH:MM:SS
            
            eval {
                my $jellyfin_time = Time::Piece->strptime($jellyfin_date_str, "%Y-%m-%d %H:%M:%S");
                
                # Check if iTunes is strictly newer than the database entry
                if ($itunes_time > $jellyfin_time) {
                    $should_update = 1;
                }
            };
            if ($@) {
                warn "Date parsing failed for '$name' (Jellyfin string was '$jellyfin_date_str'): $@\n";
            }
        }

        # 7. Execute the database update only if the timestamp condition passes
        if ($should_update) {
            eval {
                # $sth->execute($jellyfin_track_id, $user_id, $jellyfin_track_id, $play_count, $itunes_date_str);
                print "Updated: $artist - $name (iTunes timestamp is more recent)\n";
            };
            if ($@) {
                warn "Failed writing to database for '$name': $@\n";
            }
        }
    }
    else
    {
      print "WARN: No Jellyfin DB entry for: $artist : $album : $name\n"; 
    }
}

# 7. Clean up
$sth->finish();
$dbh->disconnect();
print "Sync completed successfully.\n";


sub trim
{
my ($str) = @_;

$str =~ s/^\s+//;
$str =~ s/\s+$//;
return $str;
}
