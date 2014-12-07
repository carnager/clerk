#!/bin/bash

# example script to import clerks flat rating files back into mpds sticker
# database. This example is for albumratings and works for flac, ogg and mp3.
# files. music_path has to be set in clerks config file.
# If you have a nicer script to do this, let me know :)

source $HOME/.config/clerk/config

findfiles () {
if [[ "$1" == "flac" ]] || [[ "$1" == "ogg" ]]; then
    cd "$(dirname "$2")"
    info="$(mutagen-inspect 01-*.flac)"
    artist="$(echo "$info" | grep "^ARTIST=" | awk -F "=" '{ print $2 }')"
    album="$(echo "$info" | grep "^ALBUM=" | awk -F "=" '{ print $2 }')"
    date="$(echo "$info" | grep "^DATE=" | awk -F "=" '{ print $2 }')"
    albumrating="$(grep "albumrating=" "$music_path"/"$2" | awk -F "=" '{ print $2 }')"

    if [[ -z "$(mpc find artist "$artist" album "$album" date "$date" disc "1" track "1")" ]]; then
        uri="$(mpc find artist "$artist" album "$album" date "$date" track "1")"
    else
        uri="$(mpc find artist "$artist" album "$album" date "$date" disc "1" track "1")"
    fi
    mpc sticker "$uri" set albumrating "$albumrating"

elif [[ "$1" == "mp3" ]]; then
    cd "$(dirname "$2")"
    info="$(mutagen-inspect 01-*.mp3)"
    artist="$(echo "$info" | grep "^TPE2=" | awk -F "=" '{ print $2 }')"
    album="$(echo "$info" | grep "^TALB=" | awk -F "=" '{ print $2 }')"
    date="$(echo "$info" | grep "^TDRC=" | awk -F "=" '{ print $2 }')"
    albumrating="$(grep "albumrating=" "$music_path"/"$2" | awk -F "=" '{ print $2 }')"

    if [[ -z "$(mpc find artist "$artist" album "$album" date "$date" disc "1" track "1")" ]]; then
        uri="$(mpc find artist "$artist" album "$album" date "$date" track "1")"
    else
        uri="$(mpc find artist "$artist" album "$album" date "$date" disc "1" track "1")"
    fi
    mpc sticker "$uri" set albumrating "$albumrating"
fi
}

cd "$music_path"
find . -name \*.albumrating | while read file; do findfiles $1 "$file"; done
