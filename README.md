# perlutils
My collection of Perl utilities

A bunch of utilities and educational exercises using Perl. Most were written many days ago and given the nature of Perl I no longer have any clue what they do, let alone how they work!

Some of the scripts rely on various third party Perl libraries. The sources for these libraries
are lost in the mists of time. As including the libraries in this repo would be bound to violoate
some license or other I can only list the names here and wish anyone wanting to use the scripts all
the luck in the world trying to find them;

- MP3:Tag - Used by the podcast related scripts
- Encode:transliterate_win1251 - probably needed by any script which uses filenames since Perl is really very bad at doing filenames when foreign characters are invovled.
- Normalize::Text::Music_Fields - probably something to with the MP3:Tag library

I keep these libraries together with the FALC library but they could probably be installed in the normal Perl location for libraries by a package manager, or whatever it's called, assuming they are available in whatever repository the package manager uses.

If I recall correctly I modified part of the MP3:Tag library to provide limited support for some additional tags, ie. RVAD and PCAST. Since I no longer recall where the source came from I am not able to suggest that my changes are included in the library. It's therefore unlikely that the tag scripts will work as intended due to the missing support for these two tags (one is related to podcasts and my constantly unsuccessful attempts to pursuade the Apple Podcast app to play my podcasts in the order I want them played. RVAD is relative gain adjustment, probably my attempt to boost the quieter sections of podcasts so I could hear them in the car, a sort of dynamic range compression but way more crude and probably unsuccessful).
  
