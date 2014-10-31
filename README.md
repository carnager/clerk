# clerk - the only mpd client UI that needs typing

clerk uses dmenu (or rofi) to draw a menu which lets you
manage your mpd server.

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
* Load rated album
* Rate tracks (Stored in flat files for portability & mpds sticker database)
* Control mpd options (modes, replaygain, crossfade)
* Lookup artist/album/lyrics in webbrowser

Being written completely functional means, every option is accessible
Some example arguments have been added. e.g:
`clerk -rs` will play random songs.

see `clerk -h` for all default arguments.


# Dependencies:

* dmenu2 (https://bitbucket.org/melek/dmenu2) OR
* rofi (https://github.com/DaveDavenport/rofi)
* mpc
* mppc (https://github.com/carnager/mppc) (for features, mpc does not provide)


# Optional Dependencies

* surfraw (for lookup)
* lastfm-mpd-cli for loving tracks (https://github.com/morendi/lastfm-mpd-cli)
