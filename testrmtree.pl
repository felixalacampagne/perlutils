use strict;
use warnings;
use XML::Simple;
use Data::Dumper;

use File::Path qw(make_path remove_tree);
sub cleanroot
{
my $rootdir = shift;

   remove_tree($rootdir,  {keep_root => 1});

}
my $root = "K:/Music";
print "cleaning $root\n";
cleanroot $root;
