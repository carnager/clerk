#!/usr/bin/env perl

binmode(STDOUT, ":utf8");
use warnings;
use strict;
use utf8;
use v5.10;
use autodie;
use Config::Simple;
use Data::Dumper;
use Data::MessagePack;
use DDP;
use File::Basename;
use File::stat;
use File::Slurper 'read_binary';
use Getopt::Std;
use IO::Select;
use IPC::Run qw( timeout start );
use Net::MPD;

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
	my %options=();
	getopts("ta", \%options);
	list_tracks() if defined $options{t};
	list_albums() if defined $options{a};
}


sub create_db {
	# Get database copy and save as messagepack file, if file is either missing
	# or older than latest mpd database update.
	# get number of songs to calculate number of searches needed to copy mpd database
	my $mpd_stats = $mpd->stats();
	my $songcount = $mpd_stats->{songs};
	my $last_update = $mpd_stats->{db_update};

	if (!-f "$db_file" || stat("$db_file")->mtime < $last_update) {
		my $times = int($songcount / 1000 + 1);
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
}

sub backend_call {
	my ($in, $fields) = @_;
	my $input;
	my $out;
	$fields //= "1,2,3";
	my %backends = (
		fzf => [ qw(fzf
			--reverse
			--no-sort
			-m
			-e
			-i
			-d
			\t
			--tabstop=4
			+s
			--ansi),
			"--with-nth=$fields"
		],
		rofi => [
			'rofi',
			'-width',
			'1300',
			'-dmenu',
			'-i',
			'-p',
			' >'
		]
	);
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

sub do_action {
	my @action_items = ("Add\n", "Replace\n");
	my $action = backend_call(\@action_items);
	if ($action eq "Replace\n") {
		$mpd->clear();
	}
	if ($action eq "Replace\n") {
		$mpd->play();
	}
	my $input;
	my ($in) = @_;
	foreach my $line (split /\n/, $in) {
		print "${line}x\n";
		my $uri = (split /[\t\n]/, $line)[-1];
		print "${uri}x\n";
		$mpd->add($uri);
	}
}

# read messagepack file and output strings
sub list_albums {
	my ($rdb) = @_;
	$rdb //= unpack_msgpack();
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
	my $out = backend_call(\@output, "1,2,3");
	do_action($out);
	list_albums($rdb);
}

sub list_tracks {
	my ($rdb) = @_;
	$rdb //= unpack_msgpack();
	my @output;
	my $in;
	for my $entry (@{$rdb}) {
		$in = sprintf "%-${track_l}.${track_l}s\t%-${title_l}.${title_l}s\t%-${artist_l}.${artist_l}s\t%-${album_l}.${album_l}s\t%-s\n", $entry->@{qw/Track Title Artist Album uri/};
		push @output, $in;
	}
	my $out = backend_call(\@output, "1,2,3,4");
	do_action($out);
	list_tracks($rdb)
}

main;
