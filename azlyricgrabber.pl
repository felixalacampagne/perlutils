#!/usr/bin/perl
# Ideally it would be possible to drag an azlyric link from IE and drop it on the grabber which would then
# receive the URL as the first parameter. Unfortunately windows pops up a stupid message and the script
# doesn't get invoked at all. Same thing from Chrome (without the stupid message).
# So, next easiest way to use that I can think of is to copy link to the clipboard and have
# the script try to load whatever is on the clipboard as a url.
# Rather than load the result of a google search in the browser and then reload the page in the grabber
# it would be nicer to use the google search link directly. This requires extracting the real URL
# which is embedded in a link to google.
# 01-Jan-2021 First version of extracting URL from google search link
use strict;
use warnings;
use Win32::Clipboard;
use LWP::UserAgent;
use LWP::Protocol::https;
use IO::Socket::SSL qw( SSL_VERIFY_NONE );
use URI::Escape;


sub geturl
{
my ($url) = @_;   
print "GET: ", $url, "\n"; #dbg

my $ua = LWP::UserAgent->new(ssl_opts => {verify_hostname => 0, SSL_verify_mode => SSL_VERIFY_NONE});

$ua->timeout(10);


# Use Opera user-agent string to try to avoid the 'unusual activity' rejection 
# 
  my @headers = (
'User-Agent' => 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/78.0.3904.108 Safari/537.36 OPR/65.0.3467.78',
'Accept' => 'text/html, image/gif, image/jpeg, image/png, */*',
'Accept-Charset' => 'iso-8859-1,*,utf-8',
'Accept-Language' => 'en-US',
);
my $response = $ua->get( $url, @headers);

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

sub getSongPages
{
my ($content) = @_;   
my @songpages = ();
my $sre = qr/<!-- album songlists -->/;
my $ere = qr/<!-- album songlists end -->/;
   if($content =~ m/$sre(.*)$ere/s)
   {
      $content = $1;
      # print "Song pages are in:\n" . $content;
      
      # List items look like:
      # <a href="youwontletmedownagain.html">You Won't Let Me Down Again</a><br>
      # NB Typical Perl shirt: cannot include the 'g' flag in the qr variable (gives a deprecation error, of all things!).
      # Hence the repetition of regex expression with the pattern variable inside is the get the
      # effect of the g flag
      my $pat = qr#<a href="(.*)">(.*)</a>#;
      my $string;
      while($content =~ /$pat/g ) 
      {
         # print "$1 $2\n";
         my %pageref = (
            page => $1,
            title => $2);
         push(@songpages, \%pageref);
      }
   }
   else
   {
      print "Content failed to match the pattern";
   }
   
   return @songpages
}
sub fmtSong
{
my ($title, $lyric) = @_;   
   return "<song>\n<title>" . $title . "</title>\n<lyric>\n" . $lyric . "\n</lyric>\n</song>\n";
}


sub getLinkFromGoogle
{
my ($rawurl) =@_;
my $sre = qr#https://www.google.com/url?#;

   # https://www.google.com/url?sa=t&rct=j&q=&esrc=s&source=web&cd=&cad=rja&uact=8&ved=2ahUKEwi4wqa2l_vtAhVGzKQKHVlXAKEQFjADegQIARAC&url=https%3A%2F%2Fwww.azlyrics.com%2Flyrics%2Fjoanosborne%2Fwherewestart.html&usg=AOvVaw1allyhbzRU4ATQ200OxJtp
   if($rawurl =~ m/^$sre.*?&url=(.*?)&.*$/s)
   {
      my $encurl = $1;
      print "Found a Google URL: $encurl\n";
      $rawurl = uri_unescape($encurl);
      print "Decoded URL: $rawurl\n";
   }
   return $rawurl;
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


my $murl;# =$ARGV[0];
$murl = Win32::Clipboard()->Get();
my $lyrics = "<songs>\n";
my $baseurl;
my $lyrpage;
my $lyric;


# Google search page links contain the real link embedded in google garbage and urlencoded
# https://www.google.com/url?sa=t&rct=j&q=&esrc=s&source=web&cd=&cad=rja&uact=8&ved=2ahUKEwi4wqa2l_vtAhVGzKQKHVlXAKEQFjADegQIARAC&url=https%3A%2F%2Fwww.azlyrics.com%2Flyrics%2Fjoanosborne%2Fwherewestart.html&usg=AOvVaw1allyhbzRU4ATQ200OxJtp
$murl = getLinkFromGoogle($murl); 


($baseurl) = $murl =~ m/(.*\/).*$/;

# The current page is not listed in the links. Currently means the song from the source
# page does not have a title in the output
$lyrpage = geturl($murl);
# my $lyric = azlyricextract($murl);
# $lyrics = $lyrics . fmtSong("", $lyric);

my @songpages = getSongPages($lyrpage);
   foreach my $pageref (@songpages)
   {
      # AZLyrics keeps locking me out due to unusual activity
      # assuming this is because all pages are fetched too rapidly
      # so try to emulate me right-clicking and loading in another tab...
      sleep (5 + int(rand(10)));
      #print "page: " . %{$pageref}{"page"} . "\n";
      # . "   title: " . $pageref->title . "\n";
      my $page = $pageref->{page};
      my $title = $pageref->{title};
      my $url = $baseurl . $page;
      #print "page: " . $pageref . "  URL: " . $url ;
      $lyrpage = geturl( $url);
      $lyric = azlyricextract($lyrpage);
      $lyrics = $lyrics . fmtSong($title, $lyric);
   }

$lyrics = $lyrics . "</songs>\n";
# download each page and extract lyric, merging into a 
# single file with xml-like tags marking the tracks which can
# then be processed by a UE script?

print $lyrics;
Win32::Clipboard()->Set($lyrics);


exit 0;
