#!/usr/bin/perl
use strict;
use warnings;
use Data::Dumper;

use XML::LibXML;

my $parser = XML::LibXML->new();


 my $epsfile = "N:\\Videos\\mp4\\the pact\\folder.eps";
    my $doc    = $parser->parse_file($epsfile);
    my $query  = "//season[id='2']/episode[id='02']/description";
    my($node)   = $doc->findnodes($query);

   print "Found node: $node\n";
   # Update a node and write the updated xml
   # $node->setData("$date");
   # $doc->toFile($newfile);