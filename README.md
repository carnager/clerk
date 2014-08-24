# clerk - the only mpd client UI that needs typing

clerk uses dmenu (or rofi) to draw a menu which lets you
manage your mpd server.

# Functions:

* Play random album
* Play x random tracks
* Browse Library (Artist > Album > Tracks)
* Show current Playback Queue
* Show Albums/Tracks by currently playing Artist
* Enable or disable scrobbling (with support for remote mpdscribble)
* Love current song on lastfm (Using lastfm-mpd-cli)
* Rate albums (Stored in flat files for portability & sqlite database)
* Load rated album
* Rate tracks (Stored in flat files for portability & sqlite database)
* Control mpd options (modes, replaygain, crossfade)
* Lookup artist/album/lyrics in webbrowser

Being written completely functional means, every option is accessible
Some example arguments have been added. e.g:
`clerk -rs` will play random songs.

see `clerk -h` for all default arguments.


# Dependencies:

* dmenu2 (https://bitbucket.org/melek/dmenu2) OR
* rofi (https://github.com/DaveDavenport/rofi)
* mpc (will get completely replaced with mppc, once its finished)
* mppc (https://github.com/carnager/mppc)
* sqlite for ratings


# Optional Dependencies

* python-eyed3 (for track ratings)
* metaflac (for track ratings)
* surfraw (for lookup)
* lastfm-mpd-cli for loving tracks (https://github.com/morendi/lastfm-mpd-cli)
