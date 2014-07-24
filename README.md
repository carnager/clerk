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
* Love current song on lastfm
* Rate albums (using rating.txt in album folder - needs local access to
* directories)
* Load rated album
* Rate tracks (stored in comment tag - needs local access to files)
* Control mpd options (modes, replaygain, crossfade)
* Lookup artist/album/lyrics in webbrowser

g
# Dependencies:

* dmenu2 (https://bitbucket.org/melek/dmenu2) OR
* rofi (https://github.com/DaveDavenport/rofi)
* mpc (will get completely replaced with mppc, once its finished)
* mppc (https://github.com/carnager/mppc)


# Optional Dependencies

* python-eyed3 (for track ratings)
* metaflac (for track ratings)
* surfraw (for lookup)
