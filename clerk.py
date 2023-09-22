#!/usr/bin/env python

# import modules
from mpd import MPDClient;
# msgpack is used for adding unique ids to mpd database. Also improves startup time by using local cache
import msgpack;
import sys;
import os;
import subprocess;
import random;
import toml;

### Connect to MPD
# create variables for MPDClient
m = MPDClient()

parameter = "> "
#### FUNCTIONS
def create_config():
    config_content = """
[general]
# Important: String for prompt has to be PLACEHOLDER, define the string in menu_prompt
menu_tool         = ["rofi", "-dmenu", "-i", "-p", "PLACEHOLDER", "-multi-select"]
menu_prompt       = "> "
mpd_host          = ""
number_of_tracks  = "20"
random_artist     = "albumartist"
sync_online_list  = true
sync_command      = ["/path/to/musiclist"]

[columns]
artist_width      = "40"
albumartist_width = "40"
date_width        = "6"
album_width       = "200"
id_width          = "0"
title_width       = "40"
track_width       = "4"
"""
    content_fix = config_content.split("\n",1)[1]
    with open(xdg_config+"/clerk/config", 'w') as configfile:
        configfile.writelines(content_fix)

### chech for XDG directory and create if needed
xdg_data = os.environ.get('XDG_DATA_HOME', os.environ.get('HOME')+"/.local/share")
xdg_config = os.environ.get('XDG_CONFIG_HOME', os.environ.get('HOME')+"/.config")
if not os.path.exists(xdg_data+"/clerk"):
    os.makedirs(xdg_data+"/clerk")
if not os.path.exists(xdg_config+"/clerk"):
    os.makedirs(xdg_data+"/clerk")

### Configuration
# create config if it doesn't exist
if not os.path.exists(xdg_config+"/clerk/config"):
    create_config()

# Read Configuration
config = toml.load(xdg_config+"/clerk/config")
menu_tool = config['general']['menu_tool']
menu_prompt = config['general']['menu_prompt']
menu_tool = [w.replace('PLACEHOLDER', menu_prompt) for w in menu_tool]
mpd_host = config['general']['mpd_host']
number_of_tracks = config['general']['number_of_tracks']
number_of_tracks = int(number_of_tracks)
sync_online_list = config['general']['sync_online_list']
sync_command = config['general']['sync_command']
artist_width = config['columns']['artist_width']
albumartist_width = config['columns']['albumartist_width']
album_width = config['columns']['album_width']
track_width = config['columns']['track_width']
title_width = config['columns']['title_width']
id_width = config['columns']['id_width']
date_width = config['columns']['date_width']
random_artist = config['general']['random_artist']

### function to create menus in menu_tool
# trim value if "yes", means only the last element of a line will be returned.
# used for album/track lists, where the last element is the unique ID.
def _menu(input_list, trim, custom_menu = menu_tool):
    list_of_albums = input_list
    menu = subprocess.Popen(custom_menu, stdin=subprocess.PIPE, stdout=subprocess.PIPE)
    for line in list_of_albums:
        menu.stdin.write((line + "\n").encode())
    stdout, _ = menu.communicate()
    new=stdout.decode().splitlines()
    results = []
    for line in new:
        match trim:
            case "yes":
                x = line.rstrip().split(' ')[-1]
            case "no":
                x = line.rstrip()
                return x
        results.append(x)
    return results

### create a local album and track cache and add unique id to each entry
def create_cache():
    db=m.search('filename', '')
    latest_cache = []
    album_cache = []
    tracks_cache = []
    album_cache_temp = []
    latest_cache_temp = []
    album_set = set()
    latest_set = set()
    
    latest_db = sorted(db, key=lambda d: d['last-modified'])
    
    for track in db:
        if type(track['track']) is list:
            trackn=track['track'][0]
        else:
            trackn=track['track']
        if type(track['artist']) is list:
            artist=track['artist'][0]+" and "+track['artist'][1]
        else:
            artist=track['artist']
        if type(track['date']) is list:
            date=track['date'][0]
        else:
            date=track['date']
        album_cache_temp.append({'albumartist': track['albumartist'], 'date': date, 'album': track['album']})
        tracks_cache.append({'track': trackn, 'title': track['title'], 'artist': artist, 'album': track['album'], 'date': date})
    
    for track in latest_db:
        if type(track['track']) is list:
            trackn=track['track'][0]
        else:
            trackn=track['track']
        if type(track['artist']) is list:
            artist=track['artist'][0]+" and "+track['artist'][1]
        else:
            artist=track['artist']
        if type(track['date']) is list:
            date=track['date'][0]
        else:
            date=track['date']
        latest_cache_temp.append({'albumartist': track['albumartist'], 'date': date, 'album': track['album']})

    for d in album_cache_temp:
        t = tuple(d.items())
        if t not in album_set:
            album_set.add(t)
            album_cache.append(d)
    for d in latest_cache_temp:
        y = tuple(d.items())
        if y not in latest_set:
            latest_set.add(y)
            latest_cache.append(d)
    for i, dictionary in enumerate(album_cache, start=0):
            dictionary['id'] = str(i)
    for i, dictionary in enumerate(latest_cache, start=0):
        dictionary['id'] = str(i)
    for i, dictionary in enumerate(tracks_cache, start=0):
        dictionary['id'] = str(i)

    with open(xdg_data+"/clerk/album.cache", "wb") as outfile:
        packed = msgpack.packb(album_cache)
        outfile.write(packed)

    with open(xdg_data+"/clerk/tracks.cache", "wb") as outfile:
        packed = msgpack.packb(tracks_cache)
        outfile.write(packed)

    with open(xdg_data+"/clerk/latest.cache", "wb") as outfile:
        latest_cache.reverse()
        packed = msgpack.packb(latest_cache)
        outfile.write(packed)

# read local album cache
def read_album_cache(mode):
    match mode:
        case "album":
            cache_file = "album.cache"
        case "latest":
            cache_file = "latest.cache"
    with open(xdg_data+"/clerk/"+cache_file, "rb") as inputfile:
        mpd_msgpack = inputfile.read()
        album_cache = msgpack.unpackb(mpd_msgpack)
        return album_cache


def read_tracks_cache():
    with open(xdg_data+"/clerk/tracks.cache", "rb") as inputfile:
        mpd_msgpack = inputfile.read()
        tracks_cache = msgpack.unpackb(mpd_msgpack)
        return tracks_cache

def add_album(mode):
    album_cache = read_album_cache(mode)
    list_of_albums = []
    # generate a columns view of albums with fixed width for each column
    for album in album_cache:
        a = ' '.join([f'{x:{y}}' for x, y in zip(album.values(), [albumartist_width, date_width, album_width, id_width])])
        list_of_albums.append(a)
    
    # show a list of albums using menu_tool
    album_result = _menu(list_of_albums, "yes")
    if album_result == []:
        sys.exit()
    
    # choose what to do with selected album
    list_of_options = ['Add', 'Insert', 'Replace', '---', 'Rate']
    action = _menu(list_of_options, "no")
    if action == "":
        sys.exit()

    # lookup selected album in local cache
    match = []
    for album in album_result:
        for search in album_cache:
            if album == search['id']:
                match.append(search)
                #break
    action_album(match, action)
        
def action_album(albums, action):
    match action:
        case "Replace":
            m.clear()
            for match in albums:
                m.findadd('albumartist', match['albumartist'], 'album', match['album'], 'date', match['date'])
            m.play()
        case "Add":
            for match in albums:
                m.findadd('albumartist', match['albumartist'], 'album', match['album'], 'date', match['date'])
        case "Insert":
            position=int(m.currentsong()['pos'])
            pos=position + 1
            for match in albums:
                results = m.find('albumartist', match['albumartist'], 'album', match['album'], 'date', match['date'])
                for x in results:
                    m.addid(x['file'], pos)
        case "Rate":
            for match in albums:
                value = input_rating(match['albumartist'], match['album'])
                results = m.find('albumartist', match['albumartist'], 'album', match['album'], 'date', match['date'])
                for track in results:
                    if str(value) == "Delete":
                        m.sticker_delete('song', track['file'], 'albumrating')
                    elif str(value) == "---":
                        print("Nothing")
                    else:
                        m.sticker_set('song', track['file'], 'albumrating', str(value))
            if sync_online_list == True:
                subprocess.run(sync_command)

def add_tracks():
    tracks_cache = read_tracks_cache()
    list_of_tracks = []
    for track in tracks_cache:
        try:
            a = ' '.join([f'{x:{y}}' for x, y in zip(track.values(), [track_width, title_width, artist_width, album_width, date_width, id_width])])
        except:
            print("")
        list_of_tracks.append(a)
    track_result = _menu(list_of_tracks, "yes")
    if track_result == []:
        sys.exit()
    list_of_options = ['Add', 'Insert', 'Replace', '---', 'Rate']
    action = _menu(list_of_options, "no")
    if action == "":
        sys.exit()
        
    match = []
    for track in track_result:
        for search in tracks_cache:
            if search['id'] == track:
                match.append(search)
    action_tracks(match, action)
    
def action_tracks(tracks, action):
    match action:
        case "Replace":
            m.clear()
            for match in tracks:
                m.findadd('artist', match['artist'], 'album', match['album'], 'date', match['date'], 'track', match['track'], 'title', match['title'])
            m.play()
        case "Add":
            for match in tracks:
                m.findadd('artist', match['artist'], 'album', match['album'], 'date', match['date'], 'track', match['track'], 'title', match['title'])
        case "Insert":
            position=int(m.currentsong()['pos'])
            pos=position + 1
            for match in tracks:
                results = m.find('artist', match['artist'], 'album', match['album'], 'date', match['date'], 'track', match['track'], 'title', match['title'])
                for x in results:
                    m.addid(x['file'], pos)
        case "Rate":
            for match in tracks:
                value = input_rating(match['albumartist'], match['title'])
                results = m.find('artist', match['artist'], 'album', match['album'], 'date', match['date'], 'track', match['track'], 'title', match['title'])
                for track in results:
                    if str(value) == "Delete":
                        m.sticker_delete('song', track['file'], 'rating')
                    elif str(value) == "---":
                        print("Nothing")
                    else:
                        m.sticker_set('song', track['file'], 'rating', str(value))

def input_rating(artist, album):
    rating_options = ['1', '2', '3', '4', '5', '6', '7', '8', '9', '10', '---', 'Delete']
    prompt = artist+" - "+album+" "+menu_prompt
    custom_menu = [w.replace('> ', prompt) for w in menu_tool]
    rating = _menu(rating_options, "no", custom_menu)
    if not rating:
        sys.exit()
    return(rating)

def current_track():
    currentsong = m.currentsong()
    rofi_options = ['Rate Track', 'Rate Album']
    action = _menu(rofi_options, "no")
    if action == "":
        sys.exit()
    if action == "Rate Album":
        value = input_rating(currentsong['albumartist'], currentsong['album'])
        results = m.find('albumartist', currentsong['albumartist'], 'album', currentsong['album'], 'date', currentsong['date'])
        for track in results:
            if str(value) == "Delete":
                m.sticker_delete('song', track['file'], 'albumrating')
            else:
                m.sticker_set('song', track['file'], 'albumrating', str(value))
    if sync_online_list == True:
        subprocess.run(sync_command)
    elif action == "Rate Track":
        value = input_rating(currentsong['albumartist'], currentsong['title'])
        if str(value) == "Delete":
            m.sticker_delete('song', track['file'], 'rating')
        else:
            m.sticker_set('song', currentsong['file'], 'rating', str(value))

def random_album():
    artist = m.list('albumartist')
    artist = random.sample(artist, 1)
    for x in artist:
        result = m.find('albumartist', x['albumartist'])
    album = random.sample(result, 1)
    m.clear()
    for x in album:
        m.findadd('albumartist', x['albumartist'], 'album', x['album'], 'date', x['date'])
    m.play()

def random_tracks():
    artist = m.list(random_artist)
    artists = random.sample(artist, number_of_tracks)
    m.clear()
    for x in artists:
        result = m.find(random_artist, x[random_artist])
        track = random.sample(result, 1)
        for x in track:
            m.findadd('file', x['file'])
    m.play()
    
def check_update():
    if not os.path.exists(xdg_data+"/clerk/tracks.cache"):
        create_cache()

help_text = """
clerk version: 5.0
        
Options:

     -a  add Album
     -l  add Album (sorted by mtime)
     -t  add Track(s)
     -A  Play random Album
     -T  Play random Tracks
     -c  Rate current Track
     -u  Update local caches
"""



# check for config option "mpd_host", otherwise set it to "localhost"
if 'mpd_host' in globals():
    mpd_host = mpd_host
else:
    mpd_host = "localhost"

# Check for MPD_HOST environment variable, otherwise use mpd_host variable
mpd_host = os.environ.get('MPD_HOST', mpd_host)
m.connect(mpd_host, 6600)

# Create cache files if needed
check_update()

if len(sys.argv) > 1:
    match sys.argv[1]:
        case "-a":
            add_album("album")
        case "-l":
            add_album("latest")
        case "-t":
            add_tracks()
        case "-A":
            random_album()
        case "-T":
            random_tracks()
        case "-c":
            current_track()
        case "-u":
            create_cache()
        case "-x":
            create_config()
        case "-h":
            print(help_text)
else:
    print(help_text)
