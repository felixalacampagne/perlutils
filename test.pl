#!/usr/bin/perl
# Obsolete - functionality implemented as a chromium browser extension...
#
# Ideally it would be possible to drag an azlyric link from IE and drop it on the grabber which would then
# receive the URL as the first parameter. Unfortunately windows pops up a stupid message and the script
# doesn't get invoked at all. Smae thing from Chrome (without the stupid message).
# So, next easiest way to use that I can think of is to copy link to the clipboard and have
# the script try to load whatever is on the clipboard as a url
use strict;
use warnings;
use Win32::Clipboard;
use LWP::UserAgent;
use LWP::Protocol::https;
use IO::Socket::SSL qw( SSL_VERIFY_NONE );
use Data::Dumper;
sub getarray
{
my @songs = ();
   my $pr;
   my $ti;
   
   for(my $i=0; $i < 10; $i++)
   {
   $pr = "page" . $i;
   $ti = "title" . $i;
   
   my %pageref = (
      page => $pr,
      title => $ti);
   push(@songs, \%pageref);
   }  
   return @songs;  
}

my @songpages = getarray();

foreach my $song (@songpages)
{
   #print Dumper($song);
print $song->{page} . "\n";
}

exit 0;
