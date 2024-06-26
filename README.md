# perlutils
My collection of Perl utilities

A bunch of utilities and educational exercises using Perl. Most were written many days ago and given the nature of Perl I no longer have any clue what they do, let alone how they work!

Some of the scripts rely on third party Perl libraries not part of the standard Perl distribution;

- MP3::Tag - Used by the podcast related scripts. If I recall correctly I modified part of the MP3:Tag library to provide limited support for some additional tags, ie. RVAD and PCAST (PCAST is related to podcasts and my constantly unsuccessful attempts to pursuade the Apple Podcast app to play my podcasts in the order I want them played. RVAD is relative gain adjustment, probably my attempt to boost the quieter sections of podcasts so I could hear them in the car, a sort of dynamic range compression but way more crude and probably unsuccessful). I just put my modified files in the same 'lib' directory as for my own library modules. I don't remember where I got the source from originally but the library is now
available as a cpan module: cpanm install MP3::Tag. I have no idea how to get my changes into the distribution so it is unlikely the podcast scripts will work as intended with the cpan version.
- XML::XPath - used by eit2eps: cpanm install XML::XPath
- XML::Twig - used by eit2eps: cpanm install XML::Twig


Sadly the Eclipse git utility is virutally useless when it comes to merging conflicting files with anything more than a single conflict so must install an additional app and do merges from a git command line - IntelliJ does this better but it's over the top to install it just to make merges easier especially when the git projects are not maven/java based (and I don't know if the free version has the same git merge feature as the paid version). 

So this is how to setup git to do merges using a helpful merge tool - KDiff3:

- Install kdiff3: best to use a path without spaces since git is essentially a Unix program
- Update git global config
    ```
    git config --global merge.tool kdiff3
    git config --global mergetool.keepBackup false
    git config --global mergetool.kdiff3.path 'G:\win\KDiff3\kdiff3.exe'
    git config --global difftool.prompt false
    ```
    The remove backups option in kdiff3 settings should be disabled.
    The mergetool settings will be used by the 'git difftool' command except for the prompt setting, which must be
    explicitly disabled to avoid being prompted every time a diff is performed.
- OR manually edit gitconfig (no doubt hidden away somewhere inaccessible on the system, try %APP_DATA%)
    ```
    [difftool]
            prompt = false
            trustExitCode = false
    [merge]
            tool = kdiff3
    [mergetool]
            prompt = false
            keepBackup = false
            keepTemporaries = false
    [mergetool "kdiff3"]
            path = <path to kdiff3 binary in your system>
    ```
- to merge a branch into the current branch use commands like
    ```
    git merge branch_name & git mergetool
    git commit -m "Message to avoid weird editor appearing"
    ```
  it might be possible to put the two commands on separate lines so the mergetool is only used when there are conflicts. The commit should only be performed if 'git status' reports all conflicts are fixed.
  
Google suggests that Notepad++ might be an alternative to using kdiff3 which would be great since kdiff3 is not available in all locations. As always with cursed Unix tools if it sounds too good to be true then it is - the configuration instructions look great until you actually come to use them, there is NO 'compare.exe' in the 'standard' installation of Notepad++
