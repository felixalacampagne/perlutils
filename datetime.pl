use 5.010;
use strict;
# Might be better as a JScript as that is available by 'default'
my @now = localtime();
my $ts = sprintf("%04d%02d%02d%02d%02d",
  $now[5]+1900, $now[4]+1, $now[3],
  $now[2],      $now[1]);
print $ts;
