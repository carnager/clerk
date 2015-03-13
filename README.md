# clerk - mpd client, based on rofi (or dmenu)

# CHANGES IN RATINGS!
If you used ratings in clerk, be aware that the way they are handled
changed in recent commits. To be able to properly use them, make sure
to delete $HOME/.config/clerk/helper_config and then re-create it
by running clerk. Then Chose the Backup function from the Ratings menu.

This will write the new ratings files.

What has changed? Ratings are no longer bound to file names. Instead
a search is executed on the tags mentioned in ratings files. All matches
will then be rated by the filename from mpd library.


# Functions:

* Play random album
* Play x random tracks
* Browse Library (Artist > Album > Tracks)
* Browse local filesystem (needs unix socket in mpd.conf)
* Show current Playback Queue
* Show Albums/Tracks by currently playing Artist
* Enable or disable scrobbling (with support for remote mpdscribble)
* Love current song on lastfm (Using lastfm-mpd-cli)
* Rate albums (Stored in flat files for portability & mpds sticker database)
* Rate tracks (Stored in flat files for portability & mpds sticker database)
* Load rated albums/tracks
* Play Similar Songs (based on lastfm)
* Control mpd options (modes, replaygain, crossfade)
* Lookup artist/album/lyrics in webbrowser

Written completely functional, nearly every option is accessible
from command line.
For example `clerk --random track` will play random songs.

see `clerk -h` for all default arguments.


# Dependencies:

* dmenu2 (https://bitbucket.org/melek/dmenu2) OR
* rofi (https://github.com/DaveDavenport/rofi)
* mpc
* python-mpd2 (https://github.com/Mic92/python-mpd2)

Hint: When using rofi, you can use Shift+Enter to execute several commands
e.g. adding more than one song.

# Optional Dependencies

* surfraw (for lookup)
* lastfm-mpd-cli for loving tracks (https://github.com/morendi/lastfm-mpd-cli)
  (Not needed when using mpdas instead of mpdscribble)
* mpd-sima (for Similar Artists playback)

# Installation

1. Install dependecies (each binary needs to be in your $PATH)
2. Copy config.example to $HOME/.config/clerk/config and edit it.
3. Copy clerk and clerk_helper to $PATH
4. Run clerk

For arch linux there is a package in [AUR](https://aur.archlinux.org/packages/clerk-git/)

# Important

clerk is heavily depending on a well structured database.
All your files need these tags in order for clerk to work as intended:
* albumartist
* artist
* date
* album
* tracknumber
* title

Some software (beets, I look at you!) loves to add duplicate tags.
For example beets adds track and tracknumber tags, no matter what file format
is handled. MPD will return tracknumber twice for such files.
Make sure to clean your tags, if you used beets to tag them.

#### A word on album ratings
mpd's sticker database is very limited and only allows stickers to be associated
with files. Originally it was planned to extend stickers for other types too
(and documentation even claims it does), but this hasn't happened yet.
So what clerk does is to associate an album rating with first file of an album,
to keep the database clean and duplicate-free.
It's a somewhat ugly workaround, but it works pretty good.

Also mpd deletes stickers instantly, when files move or get renamed.
For this reason I keep flat files in directory of the album for both track and
album ratings. With those files and a tiny bash script it's possible to rebuild
the sticker database in very little time.

So if you plan to use ratings, it's a good idea to have music_path option
in config file. If your music is on a different machine just mount it locally.
