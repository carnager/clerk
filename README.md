# clerk - mpd client, based on rofi (or dmenu)

# multi_keys branch
This is the multi_keys branch of clerk. This branch might replace regular clerk soon.
The only difference is that it's possible to trigger different actions, depending on
pressed key.
This branch only works with rofi. dmenu is not supported.

An image says more than 100 words:
![multi_keys branch]
(images/clerk_multi_keys.jpg)


# CHANGES IN RATINGS!
From clerk 1.0 on ratings are stored in json format.
If you still used old ratings use the following steps to
create the new files:

* make sure, mpds stickers are up to date. (they should, clerk sends ratings to mpd)
* run `clerk_helper importtrackratings` and
* `clerk_helper importalbumratings` to create new ratings files.

The new files are 100% tag based. Even if your files move within your collection,
you can always re-import your ratings into mpd's sticker database with `clerk_helper sendstickers`,
as long as the tags havent changed.

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
* python-notify2

Hint: When using rofi, you can use Shift+Enter to execute several commands
e.g. adding more than one song.

# Optional Dependencies

* surfraw (for lookup)
* lastfm-mpd-cli for loving tracks (https://github.com/morendi/lastfm-mpd-cli)
  (Not needed when using mpdas instead of mpdscribble)
* mpd-sima (for Similar Artists playback)

# Installation

1. Install dependencies (each binary needs to be in your $PATH)
2. Copy config.clerk to $HOME/.config/clerk/config and edit it.
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
I tried to work around most cases, but still. keep your tags clean!
