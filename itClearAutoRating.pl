# Script to workaround the auto generated album (grey) rating which gets
# automatically applied to all tracks in an album if one or two tracks
# have been manually rated.
#
# The trick is to set a rating of '1' for the album rating. This results in
# a no star track rating unless the track was manually assigned a rating.
# Note one star is equal to a value of 20.
use strict;
use warnings;
use Win32::OLE;

# Connect to the running iTunes instance or launch it
my $itunes = Win32::OLE->new('iTunes.Application') 
    or die "Could not start or connect to iTunes: $!";

# Grab the currently highlighted tracks
my $tracks = $itunes->SelectedTracks;

if (defined $tracks) {
    my $count = $tracks->Count;
    print "Processing $count selected track(s)...\n";
    
    # Track collections in the iTunes COM API are 1-indexed
    for (my $i = 1; $i <= $count; $i++) {
        my $track = $tracks->Item($i);
    my $name   = $track->Name   || '';
    my $album  = $track->Album  || '';
    my $artist = $track->Artist || ''; 
    my $kind = $track->AlbumRatingKind || ''; 
    my $arating = $track->AlbumRating || '0'; 
     
      print "$artist: $album: $name: [$kind] [$arating]\n";      
        # AlbumRatingKind == 1 means the rating is 'Computed' (auto-generated)
        if ($track->AlbumRatingKind == 1) 
        {
            if( $arating != 1 )
            {
               print "Updating  $artist: $album: $name:\n";
               # Set AlbumRating to 1 (a 1% manual override that clears the gray stars)
               $track->{AlbumRating} = 1; 
            }
        }
    }
    print "Done! Auto-ratings have been cleared for your selection.\n";
} else {
    print "Error: Please select one or more tracks in iTunes before running this script.\n";
}
