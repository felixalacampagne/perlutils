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

# cpanm Log::Log4perl
BEGIN {
   if (eval { require Log::Log4perl; Log::Log4perl->import(qw(:easy)); 1; }) {
      Log::Log4perl->easy_init({
         level  => 'INFO',
         layout => '%d{yy-MM-dd HH:mm:ss} %m%n',
         utf8  => 1
      });
   }
   else {
      package NoOpLogger;
      sub new { bless {}, shift }

      sub _emit {
         my ($self, @parts) = @_;
         my @expanded;
         foreach my $part (@parts) {
            if (ref($part) eq 'CODE') {
               push @expanded, $part->();
            }
            else {
               push @expanded, $part;
            }
         }
         my $msg = join('', @expanded);
         my $ts  = POSIX::strftime('%y-%m-%d %H:%M:%S', localtime());
         print "$ts $msg\n";
      }

      sub debug {
         my $self = shift;
         # $self->_emit(@_);
      }
      sub info  { my $self = shift; $self->_emit(@_); }
      sub warn  { my $self = shift; $self->_emit(@_); }
      sub error { my $self = shift; $self->_emit(@_); }
      package main;
   }
}

my $logger = eval { Log::Log4perl->get_logger(); } || NoOpLogger->new();

my $VERSION="4.0.3";

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

$logger->info("Connecting to iTunes COM interface...");
my $itunes = Win32::OLE->new('iTunes.Application')
    or die "iTunes could not be started: " . Win32::OLE->LastError();


# Connect to the Jellyfin SQLite Database with strict Unicode mappings
$logger->info("Connecting to Jellyfin Database...");
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
   $logger->info("Found User ID for '$jfuser': $user_id");
}

my %jellyfin_track_map = build_jellyfin_track_map($dbh, $user_id);
$logger->info("Loaded Jellyfin track map for '$jfuser': " . scalar(keys %jellyfin_track_map) . " entries");

my $it_jf_updates = "";  # ITEM_GUID|USER_GUID|LAST_PLAYED_DATE|RATING
my $library_source = $itunes->LibrarySource;
my $playlist       = $library_source->Playlists->ItemByName("Music");
my $tracks         = $playlist->Tracks;
my $count          = $tracks->Count;

$logger->info("Found $count tracks in iTunes. Starting bidirectional sync...");

my $unmapped_count = 0;
my $processed_Count = 0;
# 4. Process Tracks
for (my $i = 1; $i <= $count; $i++)
{
   $processed_Count++;
   $logger->info("Processing track $processed_Count of $count...") if ($processed_Count % 200 == 0);
   my $track = $tracks->Item($i);
   next unless $track;

   # Extract track information into sanitized variables (except date which needs special handling)
   my $name   = $track->Name   || '';
   my $album  = $track->Album  || '';
   my $artist = $track->Artist || '';
   my $it_location = $track->Location || '';
   my $itunes_rating_raw = $track->Rating || 0; # Returns 0, 20, 40, 60, 80, or 100

   # Use tracklog for track details when writing a log message
   my $tracklog = sprintf("%s: %s: %s", $artist, $album, $name);

   if(!$it_location)
   {
      $logger->info("WARN: Missing iTunes file for track: $tracklog");
      next;
   }

   # Trim leading and trailing whitespaces cleanly via Regex
   # \s+ matches any whitespace characters. ^ looks at the start, $ looks at the end.
   $name   =~ s/^\s+|\s+$//g;
   $album  =~ s/^\s+|\s+$//g;
   $artist =~ s/^\s+|\s+$//g;

   # 5. Look up the track metadata from the pre-built Jellyfin map
   my $track_key = build_track_key($it_location);
   my $jf_entry = $jellyfin_track_map{$track_key};

   if (!$jf_entry) {
      $logger->warn("WARN: No Jellyfin DB Entry found for track: $tracklog: $it_location: [$track_key] ");
      $unmapped_count++;
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

   # Extract the iTunes Last Played Date.
   # If present it will be a local time string using the Windows locale format which makes it difficult to
   # parse with certainty. Since I only use the D/M/Y format that's all I'm really interested in but you
   # never know when a Windows system might randomly change it's format back to the default US version.
   # Once the date string is parsed into a date it is converted to GMT (UTC) and this is the value
   # in itunes_time. I tried giving itunes_time a default value but that sort of broke the change detection
   # logic so I keep the 'undef' as it is part of the logic. Any logging of the date must take this into
   # account as the undef variable causes an error when used in a string insead of resulting in a value of 'undef'.
   my $played_date_variant = $track->PlayedDate;
   my $itunes_time         = undef;
   my $it_orig_date_str    = 'N\A';

   if ($played_date_variant && ref($played_date_variant))
   {
      # Force the COM object to coerce itself into a strict text string (VT_BSTR = 8).
      # The date string returned by the COM object is the same as the value displayed in iTunes which
      # is therefore presumably the localtime.
      my $date_string = eval { $played_date_variant->As(8); };
      $it_orig_date_str = $date_string;
      if ($date_string && $date_string ne '' && $date_string ne '00:00:00')
      {
         $date_string = substr($date_string, 0, 19);
         eval {
            # Standard European/UK format (e.g., "10/10/2026 17:00:15")
            $itunes_time = localtime->strptime($date_string, "%d/%m/%Y %H:%M:%S");
         };
         if ($@)
         {
            eval # Standard US format (e.g., "10/10/2026 05:00:15 PM")
            {
                  $itunes_time = localtime->strptime($date_string, "%m/%d/%Y %H:%M:%S");
            };
         }
         if ($@)
         {
            eval # Standard ISO/Fallback format (e.g., "2026-10-10 17:00:15")
            {
                  $itunes_time = localtime->strptime($date_string, "%Y-%m-%d %H:%M:%S");
            };
         }

         # If any patterns match cleanly, map the string output for your Jellyfin comparisons
         if (!$itunes_time)
         {
            $logger->info("WARN: $tracklog: unrecognized date format: '$date_string'");
         }
         else
         {
            $itunes_time = gmtime($itunes_time->epoch);
         }
      }
      else
      {
         # Date variant did not return a value. This is not the same as the Date variant being null/undef.
         # It could be because there an exclusion rating means it was never played
         # so need to ensure the rating is tranferred to Jellyfin as well.
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

   # When iTunes has a more recent listen -> Update Jellyfin
   if ($itunes_time && (!$jellyfin_time || $itunes_time > $jellyfin_time))
   {
      my $itunes_date_str = $itunes_time->strftime("%Y-%m-%d %H:%M:%S");
      $itunes_date_str = $itunes_date_str;

      my $rating = $itune_rating_jellyfin > $jellyfin_rating ? $itune_rating_jellyfin : $jellyfin_rating;

      $logger->info(sprintf("it->jf: %s: itGMT:%s jfGmt:%s", $tracklog, safeDateStr($itunes_time), safeDateStr($jellyfin_time)));
      # goto CLEANEXIT;
      $it_jf_updates .= "$jellyfin_track_id|$user_id|$itunes_date_str|$rating\n";
   }
   # When Jellyfin has a more recent listen -> Update iTunes
   elsif ($jellyfin_time && (!$itunes_time || $jellyfin_time > $itunes_time))
   {
      # Strangely the date for setting the iTunes date played value needs to be in GMT - or at least that
      # is what appear to be happening here, and the correct values are displayed in iTunes!
      my $jfep = $jellyfin_time->epoch;
      my $date_for_itunes = gmtime($jfep)->strftime("%b %e, %Y %H:%M:%S");
      $date_for_itunes = Variant(VT_DATE, $date_for_itunes);

      $logger->info(sprintf("jf->it: %s: jfGMT:%s itGMT:%s", $tracklog, safeDateStr($jellyfin_time), safeDateStr($itunes_time)));
      # goto CLEANEXIT;
      eval {
         $track->{PlayedDate} = $date_for_itunes;
      };
      if ($@) { $logger->info("WARN: $tracklog: Error writing to iTunes: $@"); }

      eval {
         my $current_itunes_count = $track->PlayedCount || 0;

         # If iTunes has no count then sync it to the jellyfin count, if there is one
         my $new_count = $jellyfin_play_count;
         if ($current_itunes_count == 0 && $jellyfin_play_count > 0)
         {
            $track->{PlayedCount} = $new_count;
            $logger->info("jf->it: $tracklog: Synced Count: $new_count");
         }
      };
      if ($@) { $logger->info("WARN: $tracklog: Error writing to iTunes: $@"); }
   }
}

writeitjfsyncfile($it_jf_updates);

$logger->info("========================================");
$logger->info("Sync completed successfully.");
$logger->info("Total unmapped iTunes tracks missed: $unmapped_count");
$logger->info("========================================");

CLEANEXIT:
$dbh->disconnect();
$itunes = undef;
undef $itunes;

sub safeStr
{
   my ($val) = @_;
   return $val ? $val : '';
}

sub safeDateStr
{
   my ($val) = @_;
   my $datestr = "";
   eval
   {
      $datestr = $val->strftime("%Y-%m-%d %H:%M:%S");
   };

   return $datestr;
}

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
         $logger->info("WARN: build_jellyfin_track_map: No path for $artist:$album:$name");
         next;
      }

      # Use the path as the key as there can be duplicate Artist/Album/Track entries.
      # This is because there are multiple versions of the same albums, ie. different remixes, each having the
      # same tracks. The only difference is in the path name.
      # The Jellyfin 'baseitems.path' looks like:
      # /music/alac/01 pop-rock/Bob Dylan - Blonde On Blonde (rm2013) (1966)/13 Obviously 5 Believers.m4a
      # whereas the iTunes path looks like:
      # \\NASUG\public\music\alac\01 pop-rock\Bob Dylan - Blonde On Blonde (rm2013) (1966)\13 Obviously 5 Believers.m4a
      # build_track_key strips of the different prefixes and replace the \ with / so the paths match. The path
      # must be lowercased as the iTunes path is sometimes does not match the case of the actual filename.

      my $key    = build_track_key($location);
      $logger->debug(sub{ sprintf("build_jellyfin_track_map: %s:%s:%s:%s: [%s]", $artist, $album, $name, $location, $key) });

      $track_map{$key} = {
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
   $key =~ s/^\\\\NASUG\\public\\music\\//i;
   $key =~ s/\\/\//g;

   $key = lc($key);
   $logger->debug( sub{ sprintf("build_track_key: %s -> %s", $path, $key) });

   return $key;
}

sub debug_compare_strings {
   my ($left, $right) = @_;

   my @left_bytes  = unpack("C*", defined $left ? $left : '');
   my @right_bytes = unpack("C*", defined $right ? $right : '');

   $logger->info("Lookup string length: ",  scalar(@left_bytes),  " bytes");
   $logger->info("Hash key string length:   " , scalar(@right_bytes) , " bytes");

   my $max_len = scalar(@left_bytes) > scalar(@right_bytes) ? scalar(@left_bytes) : scalar(@right_bytes);

   $logger->info("\n--- BYTE BY BYTE COMPARISON ---");
   $logger->info("POS\tCHAR\tLOOKUP BYTE\tHASH BYTE");
   $logger->info("--------------------------------------");

   for (my $i = 0; $i < $max_len; $i++) {
      my $l_byte = $left_bytes[$i] // 'END';
      my $r_byte = $right_bytes[$i] // 'END';
      my $l_char = ($l_byte ne 'END' && $l_byte >= 32 && $l_byte <= 126) ? chr($l_byte) : '?';

      if ($l_byte ne $r_byte) {
         $logger->info("[$i]\t'$l_char'\t$l_byte\t\t$r_byte  <-- MISMATCH HERE!");
      }
   }
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
      $logger->info("Queue file written successfully with updated track data.");
   }
   else
   {
      $logger->info("No updates to write to the queue file. It remains unchanged.");
   }
}

sub backupfile
{
   my ($file) = @_;

   if (!-e $file || -s $file == 0) {
      $logger->info("$file is empty or missing. Nothing to backup.");
      return;
   }

    my ($filename, $directory, $extension) = fileparse($file, qr/\.[^.]*$/);

    my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);
    my $timestamp = sprintf("%04d%02d%02d_%02d%02d%02d",
                            $year + 1900, $mon + 1, $mday, $hour, $min, $sec);


    my $backup_file = $directory . $filename . "_" . $timestamp . $extension;

    if (copy($file, $backup_file)) {
        $logger->info("$file backed up successfully to: $backup_file");
    } else {
        $logger->info("Copy failed ($!)");
    }
}
