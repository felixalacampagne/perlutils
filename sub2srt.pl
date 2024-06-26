#!/usr/bin/perl -w

# sub2srt  - Convert subtitles from microdvd or subrip ".sub" to subviewer ".srt" format
#
# 04 May 2019 Filter teletext page number subtitles (microdvd only - the ProjectX format)
#
#    (c) 2003-2005 Roland "Robelix" Obermayer <roland@robelix.com>
#
#    This program is free software; you can redistribute it and/or modify
#    it under the terms of the GNU General Public License as published by
#    the Free Software Foundation; either version 2 of the License, or
#    (at your option) any later version.
#
#    This program is distributed in the hope that it will be useful,
#    but WITHOUT ANY WARRANTY; without even the implied warranty of
#    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#    GNU General Public License for more details.
#
#    You should have received a copy of the GNU General Public License
#    along with this program; if not, write to the Free Software
#    Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.

use strict;
my $version = "0.5.3";

use Getopt::Long;
Getopt::Long::Configure("pass_through","no_ignore_case");
my $help = 0;
my $fps = 25;
my $showvers = 0;
my $debug = 0;
my $quiet = 0;
my $dos = 0;
my $license = 0;
my $ntsc = 0;
my $ntsc24 = 0;
my $force = 0;
GetOptions("help|h",    \$help,
	   "fps|f=f",   \$fps,
	   "ntsc|n", 	\$ntsc,
	   "ntsc24|n2", \$ntsc24,
	   "force",	\$force,
	   "version|v", \$showvers,
	   "debug|d",   \$debug,
	   "quiet|q",   \$quiet,
	   "license|l", \$license,
	   "dos",       \$dos);
	   
if ($quiet) { $debug = 0; }

if ($help) { help(); }

if ($showvers) { version(); }

if ($license) { license(); }

if ($ntsc) { $fps = 29.97; }

if ($ntsc24) { $fps = 23.976; }

my $infile = shift || '';
if (!$infile) { help(); }

my $outfile = shift || '';
if (!$outfile) { 
	$outfile = $infile;
	$outfile =~ s/(\.sub|\.txt)$//i;
	$outfile .= ".srt";
}

if (! -f $infile) {
	print "Input file $infile does not exist.\n";
	exit 0;
}

print "Input-file:  $infile\n" if ($debug);
print "Output-file: $outfile\n" if ($debug);

if (-f "$outfile" && !$force) {
	my $overwrite = "";
	while ( $overwrite ne "y" && $overwrite ne "n" ) {
		print "File \"$outfile\" already exists. Overwrite? <y|n> ";
		$overwrite = <STDIN>;
		$overwrite =~ s/\n//;
	}
	if ($overwrite ne "y") {
		exit 0;
	}
}

print "Trying to detect input format...\n" if ($debug);

my $format = detect_format($infile);
if (!$format) {
	print "Could not detect $infile format!\n";
	exit 0;
}

my $le = ($dos) ? "\r\n" : "\n";

print "Converting from $format to srt\n" if ($format ne "srt" && !$quiet);

open INFILE, "$infile" or die "Unable to open $infile for reading\n";
open OUTFILE, ">$outfile" or die "Unable to open $outfile for writing\n";

if ($format eq "subrip") {
	conv_subrip();
}
elsif ($format eq "microdvd") {
	conv_microdvd();
}
elsif ($format eq "txtsub") {
	conv_txtsub();
}
elsif ($format eq "srt") {
	print "Input file is already subviewer srt format.\n";
}

close INFILE;
close OUTFILE;


sub conv_subrip {
	my $converted = 0;
	my $ignored = 0;
	my $failed = 0;
	while (my $line1 = <INFILE>) {
		$line1 =~ s/[\n\r]*$//;
		if ($line1 =~ m/^(\d\d:\d\d:\d\d\.\d\d),(\d\d:\d\d:\d\d\.\d\d)$/) {
			my $starttime  = $1;
			my $endtime = $2;
			$starttime =~ s/\./,/;
			$endtime =~ s/\./,/;
			$starttime .= "0";
			$endtime .= "0";
			my $text = <INFILE>;
			$text =~ s/[\n\r]*$//;
			my $empty = <INFILE>;
			
			$converted++;
		
			print "  Subtitle #$converted: start: $starttime, end: $endtime, Text: $text\n" if ($debug);
			
			# convert line-ends
			$text =~ s/\[br\]/$le/g;
			
			write_srt($converted, $starttime, $endtime, $text);
		
		} else {
			if (!$converted) {
				print "  Header line: $line1 ignored\n" if ($debug);
			} else {
				$failed++;
				print "  failed to convert: $line1\n" if ($debug);
			}
		}
	}
	print "$converted subtitles written\n" if (!$quiet);
	print "$failed lines failed\n" if (!$quiet && $failed);
}

# This is the format produced by ProjectX from the teletext subtitles
# A pipe character, '|', indicates a line break in the text. 
# {startframe}{endframe}textext|text[CR]LF
sub conv_microdvd {
	my $converted = 0;
	my $ignored = 0;
	my $failed = 0;
	my $lastendframe = 0;
	
	while (my $line = <INFILE>) {
		$line =~ s/[\n\r]*$//;
		# First line usually starts with ﻿ - EF BB BF
		$line =~ s/^﻿//;
		if ( $line =~ m/^\{(\d+)\}\{(\d+)\}(.+)$/ ) {
			my $startframe = $1;
			my $endframe = $2;
			my $text = $3;
			
			# CPA Suddenly started to get the teletext number flashing up during quiet moments which
			# is really annoying. Seems to be BBC 1 and 2 only.
			if($text =~ m/^888$/ )
			{
			   $ignored++;
			   print "Ignored tetetext page number at $startframe\n" if ($debug);
			}
			else
			{
   			$converted++;
   
   			# CPA
   			if($startframe == $lastendframe )
   			{
   				$startframe ++;
   				print "Start frame is same as previous end frame at $lastendframe, incrementing to $startframe\n" if ($debug);
   			}
   			# End CPA
   			$lastendframe = $endframe;	
   			my $starttime = frames_2_time($startframe);
   			my $endtime = frames_2_time($endframe);
   						
   			print "  Subtitle #$converted: start: $starttime, end: $endtime, Text: $text\n" if ($debug);
   			
   			# convert pipe chars to line breaks
   			$text =~ s/\|/$le/g;
   			
   			write_srt($converted, $starttime, $endtime, $text);
		   }
		} 
		else 
		{
			$failed++;
			print "  failed to convert: $line\n" ; #if ($debug);
		}
	}
	print "$converted subtitles written\n" if (!$quiet);
	print "$failed lines failed\n" if (!$quiet && $failed);
}

# Like ProjectX format but text is on the line AFTER the frame range
sub conv_txtsub {
	my $converted = 0;
	my $failed = 0;
	my $starttime = "";
	while (my $line1 = <INFILE>) {
		$line1 =~ s/[\n\r]*$//;
	
		if ($line1 =~ m/^\[(\d\d:\d\d:\d\d)\.?(\d\d\d)?\]$/) {
			$starttime = $1;
			if ($2) {
				$starttime = $starttime .",". $2;
			} else {
				$starttime = $starttime .",000";
			}
		} else {
			my $text = $line1;
			
			my $line2 = <INFILE> || "";
			$line2 =~ s/[\n\r]*$//;
			
			if ($line2 =~ m/^\[(\d\d:\d\d:\d\d)\.?(\d\d\d)?\]$/) {
				my $endtime  = $1;
				if ($2) {
					$endtime = $endtime .",". $2;
				} else {
					$endtime = $endtime .",000";
				}

				# ignore if text is empty
				if ($text) {
					$converted ++;
					print "  Subtitle #$converted: start: $starttime, end: $endtime, Text: $text\n" if ($debug);
					# convert line-ends
					$text =~ s/\|/$le/g;
					$text =~ s/\[br\]/$le/g;
	
					write_srt($converted, $starttime, $endtime, $text);
				}
				$starttime = $endtime;
			} else {
				# falied to convert
				if (!$converted) {
					print "  Header line: $line1 ignored\n" if ($debug);
				} else {
					$failed++;
					print "  failed to convert: $line1\n" if ($debug);
				}
			}
		}
	}
	print "$converted subtitles written\n" if (!$quiet);
	print "$failed lines failed\n" if (!$quiet && $failed);
}

sub write_srt {
	my $nr = shift;
	my $start = shift;
	my $end = shift;
	my $text = shift;
	
	print OUTFILE "$nr$le";
	print OUTFILE "$start --> $end$le";
	print OUTFILE "$text$le";
	print OUTFILE "$le";
}

sub frames_2_time {
	# convert frames to time 
	# used for microdvd format
	my $frames = shift;
	my $seconds = $frames / $fps;
	my $ms = ($seconds - int($seconds)) * 1000;
	if ( ($ms - int($ms)) >= 0.5 ) {
		# round up
		$ms = $ms + 1;
	}
	$ms = sprintf("%03u", $ms);
	$seconds = int($seconds);
	my $s = $seconds % 60;
	my $min = int($seconds / 60);
	my $m = $min % 60;
	my $h = int($min / 60); 
	$s = sprintf("%02u", $s);
	$m = sprintf("%02u", $m);
	$h = sprintf("%02u", $h);
	print "    $frames frames -> $seconds sec -> $h:$m:$s,$ms\n" if ($debug);
	
	return "$h:$m:$s,$ms";
}

sub detect_format {
	my $file = shift;
	open INFILE, "$file" or die "Failed to open $file.\n";
	my $detected = "";
	my $i = 0;
	while (my $line = <INFILE>) {
		$line =~ s/[\n\r]*$//;
		print "  Trying line $i: $line \n" if $debug;
		
		# microdvd format
		# looks like:
		# {startframe}{endframe}Text
		
		if ( $line =~ m/^\{\d+\}\{\d+\}.+$/ ) {
			print "  seems to be microdvd format\n" if ($debug);
			my $line2 = <INFILE>;
			$line2 =~ s/[\n\r]*$//;
			print "  checking next line: $line2\n" if ($debug);
			if ($line2 =~ m/^\{\d+\}\{\d+\}.+$/) {
				print "microdvd format detected!\n" if ($debug);
				$detected = "microdvd";
			}
		}
		
		# trying subrip format
		# 3 lines:
		# hh:mm:ss.ms,hh:mm:ss.ms
		# text
		# (empty line)
		
		if ($line =~ m/^\d\d:\d\d:\d\d\.\d\d,\d\d:\d\d:\d\d\.\d\d$/) {
			print "  seems to be subrip format\n" if ($debug);
			my $line2 = <INFILE>;
			$line2 =~ s/[\n\r]*$//;
			my $line3 = <INFILE>;
			$line3 =~ s/[\n\r]*$//;
			my $line4 = <INFILE>;
			$line4 =~ s/[\n\r]*$//;
			print "  checking the next lines:\n    $line2\n    $line3\n    $line4\n" if ($debug);
			if ($line2 =~ m/^.+$/ && $line3 =~ m/^$/ && $line4 =~ m/^\d\d:\d\d:\d\d\.\d\d,\d\d:\d\d:\d\d\.\d\d$/) {
				print "subrip format detected!\n" if ($debug);
				$detected = "subrip";
			}
		}
		
		# trying subviewer .srt format
		
		if ($line =~ m/^\d\d:\d\d:\d\d\,\d\d\d\s-->\s\d\d:\d\d:\d\d\,\d\d\d$/) {
			print "subviewer .srt format detected!\n" if ($debug);
			$detected = "srt";
		}
		
		# trying txtsub format 
		# (I called it so since it's often named .txt and I haven't found any common name for this)
		# it looks like:
		# [starttime]
		# subtitle-text
		# [endtime]
		# (the endtime can be the starttime of the next sub)
		# I've seen two variants with slightly diffrent time-formats
		# a) [00:02:05.000]
		# b) [00:02:05]
		# Both are supported
		
		if ($line =~ m/^\[\d\d:\d\d:\d\d(\.\d\d\d)?\]$/) {
			print "  seems to be txtsub format\n" if ($debug);
			my $line2 = <INFILE>;
			$line2 =~ s/[\n\r]*$//;
			my $line3 = <INFILE>;
			$line3 =~ s/[\n\r]*$//;
			print "  checking the next lines:\n    $line2\n    $line3\n" if ($debug);
			if ($line2 !~ m/\[\d\d:\d\d:\d\d(\.\d\d\d)?\]$/ && $line3 =~ m/\[\d\d:\d\d:\d\d(\.\d\d\d)?\]$/) {
				print "txtsub format detected!\n" if ($debug);
				$detected = "txtsub";
			}
		}
		
		$i++;
		last if ($detected or $i > 50);
	}
	close INFILE;
	return $detected;
}

sub help {
print <<__HELP__;

sub2srt [options] inputfile.sub [outputfile.srt]

    Convert subrip and microdvd ".sub" subtitle files to subviewer ".srt" format
    (the format accepted by ogmmerge for multiplexing into ogm files)
    

Options:
    -h --help           Display this message.
    -v --version	Display Program version.
    -l --license	Display License information.

    -f=n --fps=n	Fps to be used if input file is frame-based microdvd-format
			Default: 25 fps. Ignored if input format is time-based.
			
    -n  --ntsc		Sets the framerate to 29.97 fps. Overrides --fps.
    -n2 --ntsc24	Sets the framerate to 23.976 fps. Overrides --fps and --ntsc.
			 
    --dos		Create output file with DOS line end (cr+lf)
			Default: unix line end (lf)

    --force		Overwrite existing files without prompt
   
    -d --debug		Print debug information
    -q --quiet		No output


inputfile.sub
    Input file
    Both types usally have the ending .sub, the format is autodetected.


[outputfile.srt]
    Output file
    Default: inputfile.srt
    
__HELP__
exit 2;
}

sub license {
print <<__VERSION__;

    sub2srt $version - Convert subtitles from .sub to .srt format
    (c) 2003 Roland "Robelix" Obermayer <roland\@robelix.com>
    Project Homepage: http://www.robelix.com/sub2srt/
    Please report problems, ideas, patches... to sub2srt\@robelix.com


    This program is free software; you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation; either version 2 of the License, or
    (at your option) any later version.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with this program; if not, write to the Free Software
    Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.

__VERSION__
exit 2;
}

sub version {
	print "sub2srt $version\n";
	exit 2;
}
