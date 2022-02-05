use strict;
use warnings;
use Win32::Clipboard;
use Getopt::Std;
 
 
###############################################################
###############################################################
####                    #######################################
#### Main program       #######################################
####                    #######################################
###############################################################
###############################################################
my $clip;
my $cliptxt;
my $cliptxtorig;
my $cnt = 0;
 
# Forking Perl. Just wnted to be able to put the search and replace patterns into
# a variable - easy peasy, right! No Forking way! The search pattern is easy
# enough - just use the qr syntax. Unfortunately it's not so simple for the
# replace pattern. Assigning a string containing the group match place holders
# causes syntax errors like
#    Use of uninitialized value $1 in regexp compilation
# Using backslash before the $ solves that problem but then the backslash, the dollar and the
# number all appear in the result instead of the match group. Similar for a single quoted string,
# the dollar and the number appear in the result.
# Apparently the Perl geniuses didn't think about this case, only one of the most obvious things
# to want to do.....
# There is a sort of workaround. The replace pattern must be double quoted and single quoted
# and a special flag, ee, used on the substitute expression. Apparently the ee flag is very dangerous
# if used with user input on webpages as it can lead to remote exeuction. Not a problme
# in this case though.
#
# Anyway I now have a framework (big fancy word for it!!) for having multiple search and replaces
# and being able to abort after one of them is successful.
my @searchreplpairs;
 
   # NB. the replace string must use the single/double quotes to avoid error messages
   # NNB. Must be careful with the order, eg. original 'virement' pattern will match anything with a space in it!!!!
   push(@searchreplpairs, [qr/^EBAEI-(\d{4,4})  *?(.*?) *$/, '"    CRID 50031827 $2 [EBAEI-$1]"']);
   #push(@searchreplpairs, [qr/[\/\+ ]/, '""']);    # + + + 123 / 1234 / 12345 + + +  value for processing 'virement' references
   # Less dangerous version of the 'virement' scrubber
   push(@searchreplpairs, [qr/( *\+){0,3} *(\d) *(\d) *(\d) *\/* *(\d) *(\d) *(\d) *(\d) *\/* *(\d) *(\d) *(\d) *(\d) *(\d)( *\+){0,3} */,
      '"$1$2$3$4$5$6$7$8$9$10$11$12"']);
   #
   $clip = Win32::Clipboard();
 
   $cliptxtorig = $clip->GetText();
   $cliptxt = $cliptxtorig;
  
   foreach my $pair (@searchreplpairs)
   {
      my $spatt = $pair->[0];
      my $rpat = $pair->[1];
     
      print "Search: $spatt Replace: $rpat\n";
      $cnt = $cliptxt =~ s/$spatt/$rpat/gee;
 
      if($cnt>0)
      {
         print "We have a match for $spatt!!\n";
         last;  # Perl equivalent of break
      }
   }
 
$clip->Set($cliptxt);
 
print "Orig: $cliptxtorig\nTransform: $cliptxt\n";
 