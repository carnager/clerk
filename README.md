# clerk - mpd client, based on rofi (or dmenu)

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
* Play Similar Songs (based on lastfm)
* Control mpd options (modes, replaygain, crossfade)
* Lookup artist/album/lyrics in webbrowser

Being written completely functional means, nearly every option is accessible
from command line.
For example `clerk --random track` will play random songs.

see `clerk -h` for all default arguments.


# Dependencies:

* dmenu2 (https://bitbucket.org/melek/dmenu2) OR
* rofi (https://github.com/DaveDavenport/rofi)
* mpc
* mppc (https://github.com/carnager/mppc) (for features, mpc does not provide)


# Optional Dependencies

* surfraw (for lookup)
* lastfm-mpd-cli for loving tracks (https://github.com/morendi/lastfm-mpd-cli)
* mpd-sima (for Similar Artists playback)

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
