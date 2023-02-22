# perlutils
My collection of Perl utilities

A bunch of utilities and educational exercises using Perl. Most were written many days ago and given the nature of Perl I no longer have any clue what they do, let alone how they work!

Some of the scripts rely on third party Perl libraries not part of the standard Perl distribution;

- MP3:Tag - Used by the podcast related scripts. If I recall correctly I modified part of the MP3:Tag library to provide limited support for some additional tags, ie. RVAD and PCAST (PCAST is related to podcasts and my constantly unsuccessful attempts to pursuade the Apple Podcast app to play my podcasts in the order I want them played. RVAD is relative gain adjustment, probably my attempt to boost the quieter sections of podcasts so I could hear them in the car, a sort of dynamic range compression but way more crude and probably unsuccessful). I just put my modified files in the same 'lib' directory as for my own library modules. I don't remember where I got the source from originally but the library is now
available as a cpan module: cpanm install MP3::Tag. I have no idea how to get my changes into the distribution so it is unlikely the podcast scripts will work as intended with the cpan version.
- XML::XPath - used by eit2eps: cpanm install XML::XPath
- XML::Twig - used by eit2eps: cpanm install XML::Twig
