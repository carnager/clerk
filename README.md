# clerk

MPD client using rofi or fzf

# Screenshot (V4)
![Screenshot](https://pic.53280.de/clerk.png)

# Features:

* Play random album/tracks
* Add/Replace albums/songs
* Rate albums/tracks
* Filter lists by rating
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

for the tagging_client:
* metaflac (flac)
* vorbiscomment (vorbis-tools)
* mid3v2 (mutagen)

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

It's also possible to store ratings in file tags. Currently this is supported for flac, ogg and mp3 files.
For this to work, simply set `tagging=true` in clerk.conf file and set your music_path.

It’s even possible to tag files not on the same machine (On MPD setups with remote clients).
Simply copy your clerk.conf and clerk_rating_client to the machine hosting your audio files and
make sure it runs there.

For the moment I use metaflac, mid3v2 and vorbiscomment to tag files, because I haven't found a good perl library
for tagging.

## Filtering

clerk integrates ratings fully into its database and exposes the ratings in track and album lists.
To filter by a specific rating use "r=n" as part of your input.

# Usage

```
Usage:
    clerk [command] [-f]

      Commands:
        -a           Add/Replace album(s) to queue.
        -l           Add/Replace album(s) to queue (sorted by mtime)
        -t           Add/Replace track(s) to queue.
        -p           Add stored playlist to queue
        -r [-A, -T]  Replace current playlist with random songs/album
        -u           Update caches

      Options:
        -f           Use fzf interface

      Without further arguments, clerk starts a tabbed tmux interface
      Hotkeys for tmux interface can be set in $HOME/.config/clerk/clerk.tmux

    clerk version 4.0
```

# Hotkeys

```
Tab:   select item(s)
Enter: perform action on item

```

## Hotkeys for tmux interface

```
F1:    albums view
F2:    tracks view
F3:    albums view (sorted by mtime)
F4:    playlist view
F5:    queue view (uses ncmpcpp by default, can be changed in clerk.conf)
F10:   random pane
C-F5:  previous song
C-F6:  toggle playback
C-F7:  stop playback
C-F8:  next song
C-F1:  show hotkeys
C-q:   quit clerk tmux interface
```

All tmux hotkeys can be changed in clerk.tmux file.
