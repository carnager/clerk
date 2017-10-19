# clerk

MPD client using rofi or fzf

# Screenshot (V4)
![Screenshot](https://pic.53280.de/clerk.png)

# Features:

* Play random album/tracks
* Add/Replace albums/songs
* Rate albums/tracks
* Load rated albums/tracks
* Customizable hotkeys
* Rofi and fzf interfaces
* Optional tmux interface for fzf mode

see `clerk -h` for all default arguments.

# Dependencies:

* rofi (https://github.com/DaveDavenport/rofi)
* fzf
* tmux
* perl-net-mpd
* perl-data-messagepack
* perl-file-slurper
* perl-config-simple
* perl-try-tiny
* perl-ipc-run
* perl-http-date

For Archlinux you can install it from [AUR](https://aur.archlinux.org/packages/clerk-git/)

# Installation

1. Install dependencies
2. Copy clerk.conf and clerk.tmux to $HOME/.config/clerk/config and edit paths to database file and clerk.tmux
3. Copy clerk script to $PATH and make it executable.
4. Run clerk

# Ratings

Clerk can rate albums and tracks, which will be saved in MPDs sticker database as rating or albumrating.
Track ratings should be compatible with all other MPD clients that support them.
Albumratings are a unique feature to clerk, as far as I know.

It's also possible to store ratings in file tags. Currently this is supported for flac and mp3 files.
For this to work, simply set `tagging=true` in clerk.conf file and set your music_path.

It’s even possible to tag files not on the same machine (On MPD setups with remote clients).
Simply copy your clerk.conf and clerk_rating_client to the machine hosting your audio files and
make sure it runs there.
