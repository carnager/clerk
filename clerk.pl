#!/usr/bin/perl

binmode(STDOUT, ":utf8");
use v5.10;
use warnings;
use strict;
use utf8;
use Config::Simple;
use Data::MessagePack;
#use DDP;
use Encode qw(decode encode);
use File::Basename;
use File::Path qw(make_path);
use File::Slurper 'read_binary';
use File::stat;
use Try::Tiny;
use FindBin qw($Bin $Script);
use Getopt::Long qw(:config no_ignore_case bundling);
use HTTP::Date;
use Scalar::Util qw(looks_like_number);
use IPC::Run qw( timeout start );
use List::Util qw(any max maxstr);
use Net::MPD;
use Pod::Usage qw(pod2usage);
use POSIX qw(tzset);
use autodie;

my $self="$Bin/$Script";
my ($cfg, $mpd);
my %rvar; # runtime variables

sub main {
	parse_config();
	parse_options(@ARGV);
	tmux_prerequisites();

	renew_db()     if $rvar{renewdb};
	do_instaact()  if $rvar{instaact};
	do_instarand() if $rvar{instarand};

	if ($rvar{tmux_ui}) {
		tmux_ui();
	} else {
		my $go = select_action();
		do {
			maybe_renew_db();
			$go->();
			tmux_jump_to_queue_maybe();
		} while ($rvar{endless});
	}
}

sub parse_config {
	$rvar{config_file} = $ENV{CLERK_CONF}
	                  // $ENV{HOME} . '/.config/clerk/clerk.conf';
	$cfg //= Config::Simple->new(filename=>$rvar{config_file});

	my $g = $cfg->param(-block=>'General');
	%rvar = (%rvar,
		mpd_host     => $g->{mpd_host},
		tmux_config  => $g->{tmux_config},
		songs        => $g->{songs},
		chunksize    => $g->{chunksize},
		player       => $g->{player},
		tagging      => $g->{tagging},
		randomartist => $g->{randomartist},
		jump_queue   => $g->{jump_queue}
	);

	my $c = $cfg->param(-block=>'Columns');
	$rvar{max_width} = {
		album       => $c->{album_l},
		date        => $c->{date_l},
		title       => $c->{title_l},
		track       => $c->{track_l},
		artist      => $c->{artist_l},
		rating      => $c->{rating_l},
		albumartist => $c->{albumartist_l}
	};

	$rvar{db} = { file => $g->{database}, mtime => 0 };
}

sub parse_options {
	local @ARGV = @_;
	my $parse_act = sub {
		my ($name, $bool) = @_;
		if ($bool && defined $rvar{action}) {
			warn "Will override already set action: $rvar{action}\n";
		}
		$rvar{action} = "$name" if $bool;
	};

	my $choices = sub {
		my ($rvar, @choices) = @_;

		return sub {
			my ($name, $value) = @_;
			if (any { $value eq $_ } @choices) {
				$$rvar = $value;
			} else {
				die "Value: $value none of " . join(', ', @choices) . "\n";
			}
		};
	};

	$rvar{backend} = 'rofi';
	GetOptions(
		'help|h' => sub { pod2usage(1) },

		# general
		'renewdb|u' => \$rvar{renewdb},
		'tmux-ui!'  => \$rvar{tmux_ui},
		'endless!'  => \$rvar{endless},
		'backend=s' => $choices->(\$rvar{backend}, qw/fzf rofi/),
		'f'         => sub { $rvar{backend} = 'fzf'; },

		# action
		'tracks|t'    => $parse_act,
		'albums|a'    => $parse_act,
		'playlists|p' => $parse_act,
		'randoms|r'   => $parse_act,
		'latests|l'   => $parse_act,

		# instaact
		'instaact=s' => $choices->(\$rvar{instaact},
			qw/help_pane rand_pane tmux_help/),

		# instarand
		'instarand=s' => $choices->(\$rvar{instarand}, qw/track album/),
		'T'           => sub { $rvar{instarand} = 'track'; },
		'A'           => sub { $rvar{instarand} = 'album'; },
	) or pod2usage(2);

	$rvar{tmux_ui} = (
		$rvar{action} ||
		$rvar{renewdb} ||
		$rvar{instaact} ||
		(defined $rvar{tmux_ui} && !$rvar{tmux_ui})
	)? 0 : 1;

	# verify combinations if options

	if ($rvar{backend} eq 'fzf' && $rvar{instarand}) {
		die "Backend $rvar{backend} and instant random for $rvar{instarand} is not possible\n";
	}

	if (($rvar{action} // '') ne 'randoms' && defined $rvar{instarand}) {
		die "-T or -A without -r not allowed\n";
	}
}

sub do_instaact {
	local $_ = $rvar{instaact};
	if    (/help_pane/) { tmux_spawn_help_pane() }
	elsif (/rand_pane/) { tmux_spawn_random_pane() }
	elsif (/tmux_help/) { help() }
	exit;
}

sub do_instarand {
	local $_ = $rvar{instarand};
	if    (/track/) { random_tracks() }
	elsif (/album/) { random_album() }
	exit;
}

sub select_action {
	local $_ = $rvar{action} // '';
	if    (/tracks/)    { return sub { action_db_tracks(ask_to_pick_tracks()) } } 
	elsif (/albums/)    { return sub { action_db_albums(ask_to_pick_albums()) } }
	elsif (/playlists/) { return sub { action_playlist(ask_to_pick_playlists()) } }
	elsif (/randoms/)   { return sub { action_random(ask_to_pick_random()) } }
	elsif (/latests/)   { return sub { action_db_albums(ask_to_pick_latests()) } }

	return sub {};
}

sub db_needs_update {
	mpd_reachable();
	my $last = $mpd->stats->{db_update};
	return !-f $rvar{db}{file} || stat($rvar{db}{file})->mtime < $last;
}

sub renew_db {
	# Get database copy and save as messagepack file, if file is either missing
	# or older than latest mpd database update.
	# get number of songs to calculate number of searches needed to copy mpd database
	mpd_reachable();
	my @track_ratings = $mpd->sticker_find("song", "rating");
	my %track_ratings = map {$_->{file} => $_->{sticker}} @track_ratings;

	my $mpd_stats = $mpd->stats();
	my $songcount = $mpd_stats->{songs};
	my $times = int($songcount / $rvar{chunksize} + 1);

	if ($rvar{backend} eq "rofi") {
		system('notify-send', '-t', '5', 'clerk', 'Updating Cache File');
	}
	elsif ($rvar{backend} eq "fzf") {
		print STDERR "::: No cache found or cache file outdated\n";
		print STDERR "::: Chunksize set to $rvar{chunksize} songs\n";
		print STDERR "::: Requesting $times chunks from MPD\n";
	}

	my @db;
	# since mpd will silently fail, if response is larger than command buffer, let's split the search.
	my $chunk_size = $rvar{chunksize};
	for (my $i=0;$i<=$songcount;$i+=$chunk_size) {
		my $endnumber = $i+$chunk_size;
		my @temp_db = $mpd->search('filename', '', 'window', "$i:$endnumber");
		push @db, @temp_db;
	}

	# only save relevant tags to keep messagepack file small
	# note: maybe use a proper database instead? See list_album function.
	my @filtered = map {
		$_->{mtime} = str2time($_->{'Last-Modified'});
		$_->{rating} = $track_ratings{$_->{uri}};
		+{$_->%{qw/Album Artist Date AlbumArtist Title Track rating uri mtime/}}
	} @db;
	pack_msgpack(\@filtered);
}

sub maybe_renew_db {
	renew_db() if db_needs_update();
}

sub help {
	open (my $fh, '<', $rvar{tmux_config});
	my @out;
	while (my $l = <$fh>) {
		push @out, $l if $l =~ /bind-key/;
	}
	print @out;
	<STDIN>;
}

sub backend_call {
	my ($in, $fields, $random) = @_;
	my $input;
	my $out;
	$random //= "ignore";
	$fields //= "1,2,3,4";
	my %backends = (
		fzf => [ qw(fzf
			--reverse
			--no-sort
			-m
			-e
			--no-hscroll
			-i
			-d
			\t
			--tabstop=4
			+s
			--ansi),
			"--bind=esc:$random,alt-a:toggle-all,alt-n:deselect-all",
			"--with-nth=$fields"
		],
		rofi => [ "rofi", "-width", "1300", "-matching", "regex", "-dmenu", "-kb-row-tab", "", "-kb-move-word-forward", "", "-kb-accept-alt", "Tab", "-multi-select", "-no-levensthein-sort", "-i", "-p", "> "  ]
	);
	my $handle = start $backends{$rvar{backend}} // die('backend not found'), \$input, \$out;
	$input = join "", (@{$in});
	finish $handle or die "No selection";
	return $out;
}

sub pack_msgpack {
	my ($filtered_db) = @_;
	my $msg = Data::MessagePack->pack($filtered_db);
	my $filename = $rvar{db}{file};
	open(my $out, '>:raw', $filename) or die "Could not open file '$filename' $!";
	print $out $msg;
	close $out;
}
	
sub unpack_msgpack {
	my $mp = Data::MessagePack->new->utf8();
	my $msgpack = read_binary($rvar{db}{file});
	my $rdb = $mp->unpack($msgpack);
	return $rdb;
}

sub get_rdb {
	my $mtime = stat($rvar{db}{file})->mtime;
	if ($rvar{db}{mtime} < $mtime) {
		$rvar{db}{ref}   = unpack_msgpack();
		$rvar{db}{mtime} = $mtime;
	}
	return $rvar{db}{ref};
}

sub random_album {
    mpd_reachable();
    $mpd->clear();
    my @album_artists = $mpd->list('albumartist');
    my $artist_r = $album_artists[rand @album_artists];
    my @album = $mpd->list('album', 'albumartist', $artist_r);
    my $album_r = $album[rand @album];
    my @date = $mpd->list('date', 'albumartist', $artist_r, 'album', $album_r);
    my $date_r = $date[rand @date];
    $mpd->find_add('albumartist', $artist_r, 'album', $album_r, 'date', $date_r);
    $mpd->play();
    tmux_jump_to_queue_maybe();
}

sub random_tracks {
	mpd_reachable();
	$mpd->clear();
	for (my $i=1; $i <= $rvar{songs}; $i++) {
		my @artists = $mpd->list($rvar{randomartist});
		my $artist_r = $artists[rand @artists];
		my @albums = $mpd->list('album', 'artist', $artist_r);
		my $album_r = $albums[rand @albums];
		my @tracks = $mpd->find('artist', $artist_r, 'album', $album_r);
		my $track_r = $tracks[rand @tracks];
		my $foo = $track_r->{uri};
		$mpd->add($foo);
		$mpd->play();
	}
	tmux_jump_to_queue_maybe();
}

sub formatted_albums {
	my ($rdb, $sorted) = @_;

	my %uniq_albums;
	for my $i (@$rdb) {
		my $newkey = join "", $i->@{qw/AlbumArtist Date Album/};
		if (!exists $uniq_albums{$newkey}) {
			my $dir = (dirname($i->{uri}) =~ s/\/CD.*$//r);
			$uniq_albums{$newkey} = {$i->%{qw/AlbumArtist Album Date mtime/}, Dir => $dir};
		} else {
			if ($uniq_albums{$newkey}->{'mtime'} < $i->{'mtime'}) {
				$uniq_albums{$newkey}->{'mtime'} = $i->{'mtime'}
			}
		}
	}

	my @albums;
	my $fmtstr = join "", map {"%-${_}.${_}s\t"} ($rvar{max_width}->@{qw/albumartist date album/});

	my @skeys;
	if ($sorted) {
		@skeys = sort { $uniq_albums{$b}->{mtime} <=> $uniq_albums{$a}->{mtime} } keys %uniq_albums;
	} else {
		@skeys = sort keys %uniq_albums;
	}

	for my $k (@skeys) {
		my @vals = ((map { $_ // "Unknown" } $uniq_albums{$k}->@{qw/AlbumArtist Date Album/}), $uniq_albums{$k}->{Dir});
		my $strval = sprintf $fmtstr."%s\n", @vals;
		push @albums, $strval;
	}

	return \@albums;
}

sub formatted_tracks {
	my ($rdb) = @_;
	my $fmtstr = join "", map {"%-${_}.${_}s\t"} ($rvar{max_width}->@{qw/track title artist album rating/});
	$fmtstr .= "%-s\n";
	my @tracks = map {
		sprintf $fmtstr,
		        (map { $_ // "-" } $_->@{qw/Track Title Artist Album/}),
				"r=" . ($_->{rating} // '0'),
				$_->{uri};
	} @{$rdb};

	return \@tracks;
}

sub formatted_playlists {
	my ($rdb) = @_;
	my @save = ("Save");
	push @save, $rdb;
	my @playlists = map {
		sprintf "%s\n", $_->{playlist}
	} @{$rdb};
	@save = ("Save current Queue\n", "---\n");
	@playlists = sort @playlists;
	unshift @playlists, @save;
	return \@playlists;
}

sub tmux_prerequisites {
	$ENV{TMUX_TMPDIR} = '/tmp/clerk/tmux';
	make_path($ENV{TMUX_TMPDIR}) unless(-d $ENV{TMUX_TMPDIR});
}

sub tmux {
	my @args = @_;
	system 'tmux', @args;
}

sub tmux_jump_to_queue_maybe {
	tmux qw/selectw -t :=queue/ if ($rvar{jump_queue} eq "true");
}

sub tmux_spawn_random_pane {
	tmux 'splitw', '-d', $self, '--backend=fzf', '--randoms';
	tmux qw/select-pane -D/;
}

sub tmux_spawn_help_pane {
	tmux 'splitw', '-d', $self, '--instaact=tmux_help';
	tmux qw/select-pane -D/;
}

sub tmux_has_session {
	tmux qw/has -t/, @_;
	return $? == -0;
}

sub tmux_ui {
	maybe_renew_db();
	unless (tmux_has_session('music')) {
		my @win = qw/neww -t music -n/;
		my @clerk = ($self, '--backend=fzf', '--endless');
		tmux '-f', $rvar{tmux_config}, qw/new -s music -n albums -d/, @clerk, '-a';
		tmux @win, 'tracks', @clerk, '-t';
		tmux @win, 'latest', @clerk, '-l';
		tmux @win, 'playlists', @clerk, '-p';
		tmux @win, 'queue', $rvar{player};
		tmux qw/set-environment CLERKBIN/, $self;
	}
	tmux qw/attach -t music/;
	tmux qw/selectw -t queue/;
}

sub ask_to_pick_tracks {
	return backend_call(formatted_tracks(get_rdb()), "1,2,3,4");
}

sub ask_to_pick_albums {
	return backend_call(formatted_albums(get_rdb(), 0), "1,2,3");
}

sub ask_to_pick_latests {
	return backend_call(formatted_albums(get_rdb(), 1), "1,2,3");
}

sub ask_to_pick_playlists {
	mpd_reachable();
	my @pls = $mpd->list_playlists;
	return backend_call(formatted_playlists(\@pls), "1,2,3");
}

sub ask_to_pick_random {
	return backend_call(["Tracks\n", "Albums\n", "---\n", "Mode: $rvar{randomartist}\n", "Number of Songs: $rvar{songs}\n"]);
}

sub ask_to_pick_song_number {
	return backend_call([map { $_ . "\n" } qw/5 10 15 20 25 30/]);
}

sub ask_to_pick_track_settings {
	return backend_call(["artist\n", "albumartist\n"]);
}


sub ask_to_pick_ratings {
	return backend_call([map { $_ . "\n" } (qw/1 2 3 4 5 6 7 8 9 10 ---/), "Delete Rating"]);
}

sub action_db_albums {
	my ($out) = @_;

	my @sel = util_parse_selection($out);

	my $action = backend_call(["Add\n", "Replace\n", "---\n", "Rate Album(s)\n"]);
	mpd_reachable();
	{
		local $_ = $action;
		if    (/^Add/)                { mpd_add_items(\@sel) }
		elsif (/^Replace/)            { mpd_replace_with_items(\@sel) }
		elsif (/^Rate Album\(s\)/)    { mpd_rate_with_albums(\@sel) }
	}
}

sub action_db_tracks {
	my ($out) = @_;

	my @sel = util_parse_selection($out);

	my $action = backend_call(["Add\n", "Replace\n", "---\n", "Rate Track(s)\n"]);
	mpd_reachable();
	{
		local $_ = $action;
		if    (/^Add/)                { mpd_add_items(\@sel) }
		elsif (/^Replace/)            { mpd_replace_with_items(\@sel) }
		elsif (/^Rate Track\(s\)/)    { mpd_rate_with_tracks(\@sel) }
	}
}

sub action_playlist {
	my ($out) = @_;

	if ($out =~ /^Save current Queue/) {
		mpd_save_cur_playlist();
		maybe_renew_db();
	} else {
		my @sel = util_parse_selection($out);
		my $action = backend_call(["Add\n", "Replace\n", "Delete\n"]);

		mpd_reachable();
		local $_ = $action;
		if    (/^Add/)     { mpd_add_playlists(\@sel) }
		elsif (/^Delete/)  { mpd_delete_playlists(\@sel) }
		elsif (/^Replace/) { mpd_replace_with_playlists(\@sel) }
	}
}

sub action_random {
	my ($out) = @_;

	mpd_reachable();
	{
		local $_ = $out;
		if    (/^Track/)                         { random_tracks() }
		elsif (/^Album/)                         { random_album() }
		elsif (/^Mode: $rvar{randomartist}/)     { action_track_mode(ask_to_pick_track_settings()) }
		elsif (/^Number of Songs: $rvar{songs}/) { action_song_number(ask_to_pick_song_number()) }
	}
}

sub action_song_number {
	my ($out) = @_;

	$rvar{songs} = max map { split /[\t\n]/ } (split /\n/, $out);

	$cfg->param("General.songs", $rvar{songs});
	$cfg->save();
}

sub action_track_mode {
	my ($out) = $_[0];
	chomp $out;
	$rvar{randomartist} = $out;

	$cfg->param("General.randomartist", $rvar{randomartist});
	$cfg->save();
}

sub util_parse_selection {
	my ($sel) = @_;
	map { (split /[\t\n]/, $_)[-1] } (split /\n/, decode('UTF-8', $sel));
}

sub mpd_add_items {
	$mpd->add($_) for @{$_[0]};
}

sub mpd_rate_items {
	my ($sel, $rating, $mode) = @_;
	chomp $rating;
	$rating = undef if $rating =~ /^Delete Rating/;
	if ($rvar{tagging} eq "true") {
		$mpd->send_message('rating', "$_\t$mode\t${rating}") for @{$_[0]};;
	}
	$mpd->sticker_value("song", encode('UTF-8', $_), $mode, $rating) for @{$_[0]};
}

sub mpd_replace_with_items {
	$mpd->clear;
	mpd_add_items(@_);
	$mpd->play;
}

sub mpd_rate_with_albums {
	my @list_of_files;
	my $rating = ask_to_pick_ratings();
	chomp $rating;
	my @final_list;
	foreach my $album_rate (@{$_[0]}) {
		my @files = $mpd->search('filename', $album_rate);
		my @song_tags = $files[0];
		my @songs_to_tag = $mpd->search('albumartist', $song_tags[0]->{AlbumArtist}, 'album', $song_tags[0]->{Album}, 'date', $song_tags[0]->{Date});
		foreach my $songs (@songs_to_tag) {
			push @list_of_files, $songs->{uri};
		}
	}
	push @final_list, [ @list_of_files ];
	if ($rating eq "---") {
		#noop
	} else {
		mpd_rate_items(@final_list, $rating, "albumrating");
	}
}

sub mpd_rate_with_tracks {
	my $rating = ask_to_pick_ratings();
	if ($rating eq "---\n") {
		#noop
	} else {
		mpd_rate_items(@_, $rating, "rating");
	}
}

sub mpd_save_cur_playlist {
	tzset();
	$mpd->save(scalar localtime);
}

sub mpd_add_playlists {
	$mpd->load($_) for @{$_[0]};
}

sub mpd_replace_with_playlists {
	$mpd->clear;
	mpd_add_playlists(@_);
	$mpd->play;
}

sub mpd_delete_playlists {
	$mpd->rm($_) for @{$_[0]};
}

# quirk to ensure mpd does not croak just because of timeout
sub mpd_reachable {
	$mpd //= Net::MPD->connect($ENV{MPD_HOST} // $rvar{mpd_host} // 'localhost');
	try {
		$mpd->ping;
	} catch {
		$mpd->_connect;
	};
}

main;

__END__

=encoding utf8

=head1 NAME

clerk - mpd client, based on rofi

=head1 SYNOPSIS

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

clerk version 2.0

=cut

=head1 LICENSE
Copyright (C) 2015-2017  Rasmus Steinke <rasi@xssn.at>
This program is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.
This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.
You should have received a copy of the GNU General Public License
along with this program.  If not, see <http://www.gnu.org/licenses/>.
See LICENSE for the full license text.
=cut

