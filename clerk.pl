#!/usr/bin/env perl

use Net::MPD;
use v5.10;
use File::stat;
use Data::Dumper;
use warnings;
use IO::Select;
use File::Basename;
use strict;
use IPC::Run qw( timeout start );
use autodie;
use utf8;
use File::Slurper 'read_binary';
binmode(STDOUT, ":utf8");
use Data::MessagePack;
use Config::Simple;

my $config_file = $ENV{'HOME'} . "/.config/clerk/clerk.conf";

# read configuration file
my $cfg = new Config::Simple(filename=>"$config_file");

my $general_cfg = $cfg->param(-block=>"General");
my $mpd_host = $general_cfg->{mpd_host};
my $db_file = $general_cfg->{database};
my $backend = $general_cfg->{backend};

my $columns_cfg = $cfg->param(-block=>"Columns");
my $albumartist_l = $columns_cfg->{albumartist_l};
my $album_l = $columns_cfg->{album_l};
my $date_l = $columns_cfg->{date_l};
my $title_l = $columns_cfg->{title_l};
my $track_l = $columns_cfg->{track_l};
my $artist_l = $columns_cfg->{artist_l};


# open connection to MPD
my $mpd = Net::MPD->connect($ENV{MPD_HOST} // $mpd_host // 'localhost');

sub main {
	create_db();
	list_albums();
}


sub create_db {
	# Get database copy and save as messagepack file, if file is either missing
	# or older than latest mpd database update.
	# get number of songs to calculate number of searches needed to copy mpd database
	my $mpd_stats = $mpd->stats();
	my $songcount = $mpd_stats->{songs};
	my $last_update = $mpd_stats->{db_update};

	if (!-f "$db_file" || stat("$db_file")->mtime < $last_update) {
		print STDERR "::: MPD database copy missing or out of date\n";
		print STDERR "::: Starting database sync\n";
		print STDERR "::: Songs in database: $songcount\n";
		my $times = int($songcount / 1000 + 1);
		print STDERR "==> Requesting $times chunks from MPD\n";
		my @db;
		# since mpd will silently fail, if response is larger than command buffer, let's split the search.
		my $chunk_size = 1000;
		for (my $i=0;$i<=$songcount;$i+=$chunk_size) {
			my $endnumber = $i+$chunk_size; 
			my @temp_db = $mpd->search('filename', '', 'window', "$i:$endnumber");
			push @db, @temp_db;
		}

		# only save relevant tags to keep messagepack file small
		# note: maybe use a proper database instead? See list_album function.
		my @filtered = map { {$_->%{'Album', 'Artist', 'Date', 'AlbumArtist', 'Title', 'Track', 'uri', 'Last-Modified'}} } @db;
		pack_msgpack(\@filtered);
	}
	print STDERR "::: MPD database copy up to date\n";
}

# sub backend_call {
# 	my ($in) = @_;
# 	my $input = join "", (@{$in});
# 	my $out;
# 	my %backends = (
# 		fzf => [ qw(fzf --reverse --no-sort -m -e -i --with-nth=1,2,3 -d "\t" --tabstop=4 +s --ansi --expect=alt-v,alt-b) ],
# 		rofi => [qw(rofi -dmenu -width 1800)]);
# 	my $handle = run (($backends{$backend} // die('backend not found')), \$input, \$out) or die('No selection');
# 
# 	return $out;
# }

sub backend_call {
	my ($in) = @_;
	my $input;
	my $out;
	my %backends = ( fzf => [ qw(fzf --reverse --no-sort -m -e -i --with-nth=1,2,3 -d "\t" --tabstop=4 +s --ansi) ], rofi => ['rofi', '-width', '1300', '-dmenu', '-i', '-p', '> ']);
	my $handle = start $backends{$backend} // die('backend not found'), \$input, \$out;
	$input = join "", (@{$in});
	finish $handle or die "No selection";
	return $out;
}

sub pack_msgpack {
	my ($filtered_db) = @_;
	my $msg = Data::MessagePack->pack($filtered_db);
	my $filename = "$db_file";
	open(my $out, '>:raw', $filename) or die "Could not open file '$filename' $!";
	print $out $msg;
	close $out;
}
	
sub unpack_msgpack {
	my $mp = Data::MessagePack->new->utf8();
	my $msgpack = read_binary("$db_file");
	my $rdb = $mp->unpack($msgpack);
	return $rdb;
}

# read messagepack file and output strings
sub list_albums {
	print STDERR "::: Creating list of albums\n";
	my $rdb = unpack_msgpack();
	my @album_db = do {my %seen; grep { !defined($_->{AlbumArtist}) or !defined($_->{Album}) or
		!defined($_->{Date}) or !$seen{$_->{AlbumArtist}}{$_->{Album}}{$_->{Date}}++ } @{$rdb}};
	my @sorted_db = sort { lc($a->{AlbumArtist}) cmp lc($b->{AlbumArtist}) } @album_db;

	# push list to rofi and receive selected item
	my @output;
	my $in;
	for my $entry (@sorted_db) { 
		my $album_dir = dirname($entry->{uri});
		$album_dir =~ s/\/CD.*$//g;
		$in = sprintf "%-${albumartist_l}.${albumartist_l}s\t%-${date_l}.${date_l}s\t%-${album_l}.${album_l}s\t%s\n", $entry->{AlbumArtist},$entry->{Date}, $entry->{Album}, $album_dir;
		push @output, $in;
	}
	my $out = backend_call(\@output);
    print $out;
	# call rofi function to display possible actions
	my @action_items = ("Add\n", "Insert\n", "Replace\n");
	my $action = backend_call(\@action_items);

	# split output into tag variables and remove possible whitespace
	if ($action eq "Add\n") {
		my $line;
		foreach my $line (split /\n/, $out) {
			my $uri = (split /[\t\n]/, $line)[-1];
			my ($artist, $date, $album) = map { s/\s+$//r } split /[\t\n]/, $line;
			print STDERR "::: Selected album \"$album\" from \"$artist\" released in $date\n";
			print STDERR "==> Adding selected album(s) to current playlist\n";
			$mpd->add($uri);
		}
	}
	elsif ($action eq "Replace\n") {
		my $uri = (split /[\t\n]/, $out)[-1];
		my ($artist, $date, $album) = map { s/\s+$//r } split /[\t\n]/, $out;
		print STDERR "==> Replacing current playlist with selected album(s)\n";
		$mpd->clear();
		$mpd->search_add('Artist' => $artist, 'Album' => $album, 'Date' => $date);
		$mpd->play();
	}
	list_albums();
}

sub list_tracks {
	print STDERR "::: Creating list of tracks\n";
	my $rdb = unpack_msgpack();
	my @output;
	my $in;
	for my $entry (@{$rdb}) {
		$in = sprintf "%-${track_l}.${track_l}s\t%-${title_l}.${title_l}s\t%-${artist_l}.${artist_l}s\t%-${album_l}.${album_l}s\t%-s\n", $entry->{Track},$entry->{Title}, $entry->{Artist}, $entry->{Album}, $entry->{uri};
    push @output, $in;
	}
	my $out = backend_call(\@output);
	my $uri = (split /[\t\n]/, $out)[-1];
	my $songinfo = $mpd->search('filename' => $uri);

	my $artist=$songinfo->{Artist};
	my $album=$songinfo->{Album};
	my $title=$songinfo->{Title};
	my $track=$songinfo->{Track};
	my $date=$songinfo->{Date};
	print "::: Selected \"$title\" from artist \"$artist\" of album \"$album\"\n";

	my @action_items = ("Add\n", "Insert\n", "Replace\n");
	my $action = backend_call(\@action_items);

	if ($action eq "Add\n") {
		print "debug test text";
    	print STDERR "==> Adding selected track to current playlist\n";
    	$mpd->search_add('Artist' => $artist, 'Album' => $album, 'Title' => $title, 'Date' => $date);
   }
	elsif ($action eq "Replace\n") {
    	print STDERR "==> Replacing current playlist with selected track\n";
		$mpd->clear();
    	$mpd->search_add('Artist' => $artist, 'Album' => $album, 'Title' => $title, 'Date' => $date);
    	$mpd->play();
   }
}


main;
