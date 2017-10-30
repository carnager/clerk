# clerk

MPD client using rofi or fzf

## Screenshot (V4)
![Screenshot](https://pic.53280.de/clerk.png)

## Features:

* Play random album/tracks
* Add/Replace albums/songs
* Filter lists by rating
* Customizable hotkeys
* Rofi and fzf interfaces
* Optional tmux interface for fzf mode
* Rate albums/tracks
* Optionally store ratings in file tags

## Dependencies:

* rofi (https://github.com/DaveDavenport/rofi)
* fzf
* tmux
* perl-net-mpd
* perl-data-messagepack
* perl-data-sections-simple
* perl-file-slurper
* perl-config-simple
* perl-try-tiny
* perl-ipc-run
* perl-http-date

for the tagging_client:
* metaflac (flac)
* vorbiscomment (vorbis-tools)
* mid3v2 (mutagen)


## Installation

### Arch Linux

* install [clerk-git from AUR](https://aur.archlinux.org/packages/clerk-git/)

### Debian/Ubuntu

* install deb package from [release page](https://github.com/carnager/clerk/releases)

### Others

* Install dependencies
* Copy `clerk` and `clerk_rating_client` scripts to $PATH and make them executable.
* Run clerk

## Ratings

Clerk can rate albums and tracks, which will be saved in MPDs sticker database as rating or albumrating.
Track ratings should be compatible with all other MPD clients that support them.
Albumratings are a unique feature to clerk, as far as I know.

### clerk_rating_client

It's also possible to store ratings in file tags. Currently this is supported for flac, ogg and mp3 files.
For this to work, simply set `tagging=true` in clerk.conf file and set your music_path.

It’s even possible to tag files not on the same machine (On MPD setups with remote clients).
Simply copy your `clerk.conf` and `clerk_rating_client` to the machine hosting your audio files, edit `music_path`
in config and start `clerk_rating_client`. A systemd user service is available.

For the moment I use metaflac, mid3v2 and vorbiscomment to tag files, because I haven't found a good perl library
for this task.

### Filtering

clerk integrates ratings fully into its database and exposes the ratings in track and album lists.
To filter by a specific rating use `r=n` as part of your input. Sadly filtering for `r=1` will also show `r=10`.
in rofi interface you can work around this by filtering for `r=1\s`. in fzf interface `r=1$` works.

If you don't like to see ratings in your track/album listings, simply increase the album_l setting in config.

## Usage

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

## Hotkeys

### Global

```
Tab:   select item(s)
Enter: perform action on item
```

### Hotkeys for tmux interface

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

## Files and Variables

clerk uses `$XDG_CONFIG_HOME` and `$XDG_DATA_HOME` for its files. Both variables are usally unset
and default to `$HOME/.config` and `$HOME/local/share`. These files are stored by clerk:

### XDG_CONFIG_HOME

* `clerk.conf`:   config file.
* `clerk.tmux`:   clerk's tmux config

### XDG_DATA_HOME

* `database.mpk`: clerk's local database

Use `CLERK_CONF`, `CLERK_TMUX` and `CLERK_DATABASE` variables to override file locations.
