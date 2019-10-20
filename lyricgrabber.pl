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

sub geturl
{
my ($url) = @_;   
print "GET: ", $url, "\n"; #dbg

my $ua = LWP::UserAgent->new(ssl_opts => {verify_hostname => 0, SSL_verify_mode => SSL_VERIFY_NONE});

$ua->timeout(10);

my $response = $ua->get( $url );

#print "HTTP status: ", $response->status_line( ), "\n"; #dbg
#print "Response content: ", $response->content(), "\n"; #dbg

if (!$response->is_success)
{
   my @now = localtime();
   my $ts = sprintf("%04d-%02d-%02d %02d:%02d:%02d",
                      $now[5]+1900, $now[4]+1, $now[3],
                      $now[2],      $now[1],   $now[0]);
 print "$ts: HTTP status: ", $response->status_line( ), "\n"; #dbg
  exit 10;
}
return $response->content();
}

sub azlyricextract
{
my ($content) = @_;
my $sre = qr/Sorry about that. -->/;
my $ere = qr/<!-- MxM banner -->/;
my $lyric;
if($content =~ m/$sre(.*)$ere/s)
{
   $lyric = $1;
   # print "Found lyric is:\n" . $lyric;
   $lyric =~ s/’/'/g;
   $lyric =~ s/‘/'/g;
   # TIP: To determine what to search for use "View Source" and see what UE displays. Using the
   # characters displayed in the DOS box or after processing by Perl does not work.
   $lyric =~ s/“/"/g;
   $lyric =~ s/”/"/g;
   
   
   #$lyric =~ s/<br>/\n/g;
   $lyric =~ s/<.*?>//gm;

}
else
{
   print "Content failed to match the pattern";
}



   return $lyric;
}

###############################################################
###############################################################
####                    #######################################
#### Main program       #######################################
####                    #######################################
###############################################################
###############################################################

# check args
my $num_args = $#ARGV + 1;


my $murl=$ARGV[0];
$murl = Win32::Clipboard()->Get();
my $lyrpage = geturl($murl);
my $lyric = azlyricextract($lyrpage);
print $lyric;
Win32::Clipboard()->Set($lyric);


exit 0;
