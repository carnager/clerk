# clerk

MPD client using bash and rofi

# Screenshot (V3)
![Screenshot]
(images/clerk_multi_keys.jpg)

# Features:

* Play random Album/Tracks
* Add/Insert/Replace Albums/Songs
* Manage current Queue
* Locate Album/Track in Library
* Toggle scrobbling
* Love current Song on last.fm
* Rate Albums/Tracks
* Load rated Albums/Tracks
* Play Similar Songs
* Control mpd options
* Customizable Hotkeys

Written completely functional, nearly every option is accessible
from command line.
For example `clerk --random track` will play random songs.

see `clerk -h` for all default arguments.

From every database related menu it's possible to add/insert/replace one or multple entries.
For this to work, you need a recent rofi build from git.

# Dependencies:

* rofi (https://github.com/DaveDavenport/rofi)
* mpc
* python-mpd2 (https://github.com/Mic92/python-mpd2)
* a version of column with `-s` support.

# Optional Dependencies

* lastfm-mpd-cli for loving tracks (https://github.com/morendi/lastfm-mpd-cli)
  (Not needed when using mpdas instead of mpdscribble)
* mpd-sima (for Similar Artists playback)
* perl

# Installation

1. Install dependencies (each binary needs to be in your $PATH)
2. Copy config.clerk to $HOME/.config/clerk/config and edit it.
3. Copy clerk and clerk_helper to $PATH
4. Run clerk

For arch linux there is a package in [AUR](https://aur.archlinux.org/packages/clerk-git/)

# Important

clerk heavily depends on a well structured database.
All your files need these tags in order for clerk to work as intended:
* albumartist
* artist
* date
* album
* tracknumber
* title
