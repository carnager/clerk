#!/usr/bin/env perl

binmode(STDOUT, ":utf8");
use v5.10;
use warnings;
use strict;
use Data::Dumper;
use utf8;
use Config::Simple;
use Data::MessagePack;
use Data::Section::Simple qw(get_data_section);
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

my $xdg_config_home = $ENV{'XDG_CONFIG_HOME'} || "$ENV{'HOME'}/.config";
my $xdg_data_home = $ENV{'XDG_DATA_HOME'} || "$ENV{'HOME'}/.local/share";

sub main {
	create_files_if_needed();
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

sub create_files_if_needed {
	my $clerk_conf_content = get_data_section('clerk.conf');
	my $clerk_tmux_content = get_data_section('clerk.tmux');
	
	my $clerk_conf_file = "$xdg_config_home/clerk/clerk.conf";
	my $clerk_tmux_file = "$xdg_config_home/clerk/clerk.tmux";

	unless(-e "$xdg_config_home/clerk" or mkdir "$xdg_config_home/clerk") {
		die "Unable to create \"$xdg_config_home/clerk\"\n";
	}

	unless(-e "$xdg_data_home/clerk" or mkdir "$xdg_data_home/clerk") {
		die "Unable to create \"$xdg_data_home/clerk\"\n";
	}

	if (! -f $clerk_conf_file) {
		open my $fh, ">", $clerk_conf_file;
		print {$fh} $clerk_conf_content;
		close $fh;
	}
	if (! -f $clerk_conf_file) {
		open my $fh, ">", $clerk_conf_file;
		print {$fh} $clerk_conf_content;
		close $fh;
	}

	if (! -f $clerk_tmux_file) {
		open my $fh, ">", $clerk_tmux_file;
		print {$fh} $clerk_tmux_content;
		close $fh;
	}
}

sub parse_config {
	$rvar{config_file} = $ENV{CLERK_CONF}
	                  // "$xdg_config_home/clerk/clerk.conf";
	$cfg //= Config::Simple->new(filename=>$rvar{config_file});

	$rvar{tmux_config} = $ENV{CLERK_TMUX}
	                  // "$xdg_config_home/clerk/clerk.tmux";

	$rvar{db} = $ENV{CLERK_DATABASE}
	                  // "$xdg_data_home/clerk/database.mpk";

	$cfg //= Config::Simple->new(filename=>$rvar{config_file});
	

	my $g = $cfg->param(-block=>'General');
	my $r = $cfg->param(-block=>'Rofi');
	%rvar = (%rvar,
		mpd_host     => $g->{mpd_host},
		songs        => $g->{songs},
		chunksize    => $g->{chunksize},
		player       => $g->{player},
		tagging      => $g->{tagging},
		randomartist => $g->{randomartist},
		jump_queue   => $g->{jump_queue},
		backend      => $g->{backend},
		rofi_width   => $r->{width} // 'default',
		rofi_theme   => $r->{theme} // 'default'
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

	%rvar = (%rvar,
    );

	$rvar{db} = { file => $rvar{db}, mtime => 0 };
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

	#$rvar{backend} = 'rofi';
	GetOptions(
		'help|h' => sub { pod2usage(1) },

		# general
		'renewdb|u' => \$rvar{renewdb},
		'tmux-ui!'  => \$rvar{tmux_ui},
		'endless!'  => \$rvar{endless},
		'backend=s' => $choices->(\$rvar{backend}, qw/fzf rofi fuzzel/),
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
	my @album_ratings = $mpd->sticker_find("song", "albumrating");
	my %track_ratings = map {$_->{file} => $_->{sticker}} @track_ratings;
	my %album_ratings = map {$_->{file} => $_->{sticker}} @album_ratings;
	

	my $mpd_stats = $mpd->stats();
	my $songcount = $mpd_stats->{songs};
	my $times = int($songcount / $rvar{chunksize} + 1);
    
	if ($rvar{backend} eq "rofi") {
		system('notify-send', '-t', '5000', 'clerk', 'Updating Cache File');
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
		$_->{albumrating} = $album_ratings{$_->{uri}};
		+{$_->%{qw/Album Artist Date AlbumArtist Title Track rating albumrating uri mtime/}}
	} @db;
	pack_msgpack(\@filtered);
    if ($rvar{backend} eq "rofi") {
        system('notify-send', '-t', '5000', 'clerk', 'DONE: Updating Cache File');
    }
    elsif ($rvar{backend} eq "fzf") {
        print STDERR "::: Cache files updated\n";
    }
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
	$fields //= "1,2,3,4,5";
	my %backends = (
		fzf => [ "fzf", "--reverse", "--no-sort", "-m", "-e", "--no-hscroll", "-i", "-d", "\t", "--tabstop=4", "+s", "--ansi", "--bind=esc:$random,alt-a:toggle-all,alt-n:deselect-all", "--with-nth=$fields" ],
		rofi => [ "rofi", "-matching", "regex", "-dmenu", "-kb-row-tab", "", "-kb-move-word-forward", "", "-kb-accept-alt", "Tab", "-multi-select", "-no-levensthein-sort", "-i", "-p", "> " ],
		fuzzel => [ "fuzzel", "--dmenu" ]
	);

	if ($rvar{backend} eq 'rofi') {
		if ($rvar{rofi_width} ne 'default') {
			push $backends{rofi}->@*, '-width', $rvar{rofi_width};
		}

		if ($rvar{rofi_theme} ne 'default') {
			push $backends{rofi}->@*, '-theme', $rvar{rofi_theme};
		}
	}

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
		my @albums = $mpd->list('album', $rvar{randomartist}, $artist_r);
		my $album_r = $albums[rand @albums];
		my @tracks = $mpd->find($rvar{randomartist}, $artist_r, 'album', $album_r);
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
	my $index = 0;
	for my $i (@$rdb) {
		my $newkey = join "", $i->@{qw/AlbumArtist Date Album/};
		if (!exists $uniq_albums{$newkey}) {
			$uniq_albums{$newkey} = {$i->%{qw/AlbumArtist Album Date albumrating mtime/}, Index => $index};
		} else {
			if ($uniq_albums{$newkey}->{'mtime'} < $i->{'mtime'}) {
				$uniq_albums{$newkey}->{'mtime'} = $i->{'mtime'}
			}
		}
	$index++;;
	}

	my @albums;
	my $fmtstr = join "", map {"%-${_}.${_}s\t"} ($rvar{max_width}->@{qw/albumartist date album rating/});

	my @skeys;
	if ($sorted) {
		@skeys = sort { $uniq_albums{$b}->{mtime} <=> $uniq_albums{$a}->{mtime} } keys %uniq_albums;
	} else {
		@skeys = sort keys %uniq_albums;
	}

	for my $k (@skeys) {
		my @vals = ((map { $_ // "Unknown" } $uniq_albums{$k}->@{qw/AlbumArtist Date Album/}), "r=" . ($uniq_albums{$k}->{albumrating} // '0'), $uniq_albums{$k}->{Index});
		my $strval = sprintf $fmtstr."%s\n", @vals;
		push @albums, $strval;
	}
	return \@albums;
}

sub formatted_tracks {
	my ($rdb) = @_;
	my $fmtstr = join "", map {"%-${_}.${_}s\t"} ($rvar{max_width}->@{qw/track title artist album rating/});
	$fmtstr .= "%-s\n";
	my $i = 0;
	my @tracks;
	@tracks = map {
		sprintf $fmtstr,
		        (map { $_ // "-" } $_->@{qw/Track Title Artist Album/}),
				"r=" . ($_->{rating} // '0'),
				$i++;
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
	tmux qw/selectw -t :=queue/ if $ENV{CLERK_JUMP_QUEUE};
}

sub tmux_spawn_random_pane {
	tmux 'splitw', '-d', '-l', '10', $self, '--backend=fzf', '--randoms';
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
		$ENV{CLERK_JUMP_QUEUE} = 1 if ($rvar{jump_queue} // '') eq 'true';
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
	return backend_call(formatted_tracks(get_rdb()), "1,2,3,4,5");
}

sub ask_to_pick_albums {
	return backend_call(formatted_albums(get_rdb(), 0), "1,2,3,4");
}

sub ask_to_pick_latests {
	return backend_call(formatted_albums(get_rdb(), 1), "1,2,3,4");
}

sub ask_to_pick_playlists {
	mpd_reachable();
	my @pls = $mpd->list_playlists;
	return backend_call(formatted_playlists(\@pls), "1,2,3");
}

sub ask_to_pick_random {
	return backend_call(["Tracks\n", "Albums\n", "---\n", "Mode: $rvar{randomartist}\n", "Number of Songs: $rvar{songs}\n", "---\n", "Cancel\n"]);
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
	@sel = map { $rvar{db}{ref}->[$_] } @sel;
	my (@uris, @tracks);
	for my $album (@sel) {
		push @tracks, lookup_album_tags($album->{AlbumArtist}, $album->{Album}, $album->{Date});
	}
	foreach (@tracks) {
		push @uris, $_->{uri};
	}

	my $action = backend_call(["Add\n", "Insert\n", "Replace\n", "---\n", "Rate Album(s)\n"]);
	mpd_reachable();
	{
		local $_ = $action;
		if    (/^Add/)                { mpd_add_items(\@uris) }
		elsif (/^Insert/)             { mpd_insert_albums(\@uris) }
		elsif (/^Replace/)            { mpd_replace_with_items(\@uris) }
		elsif (/^Rate Album\(s\)/)    { mpd_rate_with_albums(\@uris) }
	}
}

sub lookup_album_tags {
	my ($albumartist, $album, $date) = @_;
	return grep { $albumartist eq $_->{AlbumArtist} && $album eq $_->{Album} && $date eq $_->{Date} } $rvar{db}{ref}->@*;
}

sub get_tags_from_rdb {
}

sub action_db_tracks {
	my ($out) = @_;
 
	my @sel = util_parse_selection($out);
	@sel = map { $rvar{db}{ref}->[$_] } @sel;
	my (@uris);

	foreach (@sel) {
		push @uris, $_->{uri};
	}

	my $action = backend_call(["Add\n", "Insert\n", "Replace\n", "---\n", "Rate Track(s)\n"]);
	mpd_reachable();
	{
		local $_ = $action;
		if    (/^Add/)                { mpd_add_items(\@uris) }
		elsif (/^Insert/)             { mpd_insert_tracks(\@uris) }
		elsif (/^Replace/)            { mpd_replace_with_items(\@uris) }
		elsif (/^Rate Track\(s\)/)    { mpd_rate_with_tracks(\@uris) }
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
	map { (split /[\t\n]/, $_)[-1] } (split /\n/, $sel);
}

sub mpd_add_items {
    $mpd->add($_) for @{$_[0]};
}

sub mpd_insert_tracks {
    my $song;
    my $bla = $mpd->playlist_info();
    my $pos = ($mpd->current_song->{Pos} +1);
    my $prio = "255";
    foreach $song (reverse(@{$_[0]})) {
        $mpd->prio_id($prio, $mpd->add_id($song, $pos));
        $prio--;
        $pos++;
    }
}

sub mpd_insert_albums {
    my $song;
    my $bla = $mpd->playlist_info();
    my $pos = ($mpd->current_song->{Pos} +1);
    my $prio = "255";
    foreach $song (@{$_[0]}) {
        $mpd->prio_id($prio, $mpd->add_id($song, $pos));
        $prio--;
        $pos++;
    }
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
	my @list_of_files = @_;
	my $rating = ask_to_pick_ratings();
	chomp $rating;

	if ($rating eq "---") {
		#noop
	} else {
		mpd_rate_items(@list_of_files, $rating, "albumrating");
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
  Hotkeys for tmux interface can be set in $HOME/.config/clerk/clerk.tmux

clerk version 4.0.5

=cut

__DATA__

@@ clerk.conf
[General]
# MPD_HOST will override this
mpd_host=localhost

# music root for rating_client
music_root=/mnt/Music

# player for queue tab
player=ncmpcpp

# number of songs clerk will get at once for creating its cache files
songs=20

# if mpd drops the connection while updating, reduce this.
chunksize=30000

# enable this to jump to queue after adding songs in tmux ui.
jump_queue=true

# Use albumartist or artist for random tracks?
randomartist=albumartist

# write tags to audio files. Needs running clerk_rating_client on machine with audio files
# ratings will always be written to sticker database.
tagging=false

# define graphical backend. Possible options: rofi, fuzzel
backend=rofi


[Columns]
# width of columns
albumartist_l=50
album_l=50
artist_l=50
date_l=6
title_l=50
track_l=2
rating_l=4

[Rofi]
# to use rofi default values, set "default" here
width=default
theme=default

@@ clerk.tmux
# !Dont move this section.
## Key Bindings
bind-key -n F1   selectw -t :=albums                        # show album list                
bind-key -n F2   selectw -t :=tracks                        # show tracks
bind-key -n F3   selectw -t :=latest                        # show album list (latest first)
bind-key -n F4   selectw -t :=playlists                     # load playlist
bind-key -n F5   selectw -t :=queue                         # show queue
bind-key -n C-F5 run-shell 'mpc prev --quiet'               # previous song
bind-key -n C-F6 run-shell 'mpc toggle --quiet'             # toggle playback
bind-key -n C-F7 run-shell 'mpc stop > /dev/null'           # stop playback
bind-key -n C-F8 run-shell 'mpc next --quiet'               # next song
bind-key -n F10  run-shell '$CLERKBIN --instaact=rand_pane' # play random album/songs
bind-key -n C-F1 run-shell '$CLERKBIN --instaact=help_pane' # show help
bind-key -n C-q  kill-session -t music                      # quit clerk


# Status bar
set-option -g status-position top
set -g status-interval 30
set -g status-justify centre
set -g status-left-length 40
set -g status-left ''
set -g status-right ''


# Colors
set -g status-bg colour235
set -g status-fg default
setw -g window-status-current-bg default
setw -g window-status-current-fg default
setw -g window-status-current-attr dim
setw -g window-status-bg default
setw -g window-status-fg white
setw -g window-status-attr bright
setw -g window-status-format ' #[fg=colour243,bold]#W '
setw -g window-status-current-format ' #[fg=yellow,bold]#[bg=colour235]#W '



# tmux options
set -g set-titles on
set -g set-titles-string '#T'
set -g default-terminal "screen-256color"
setw -g mode-keys vi
set -sg escape-time 1
set -g repeat-time 1000
set -g base-index 1
setw -g pane-base-index 1
set -g renumber-windows on
unbind C-b
set -g prefix C-a
unbind C-p
bind C-p paste-buffer

