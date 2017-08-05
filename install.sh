#!/usr/bin/env bash

dependencies=(
	"Config::Simple"
	"Data::Printer"
	"inc::Module::Install"
	"Data::MessagePack"
	"File::Path"
	"Net::MPD"
	)

printf "%s\n" "This script will install needed cpan modules"
printf "%s\n" "and copy configs to $HOME/.config/clerk"

read -e -p "Proceed? (Y/n) > " go_on
go_on=${go_on:-y}

case $go_on in
	[Nn]) 	exit;
		;;
esac

read -e -p "Configure cpanp to install modules via pacman? (Y/n) > " cpan_arch
cpan_arch=${cpan_arch:-y}


case $cpan_arch in
	[Yy])	if [[ -z $(pacman -Qsq perl-cpanplus-dist-arch) ]]
	then
		read -e -p "perl-cpanplus-dist-arch package not found. Install? (Y/n) > " cpanp_dist_install
		cpanp_dist_install=${cpanp_dist_install:-y}
		case $cpanp_dist_install in
			[Yy]) 	yes | sudo pacman -S perl-cpanplus-dist-arch
				;;
		esac
	fi
	setupdistarch;
esac

read -e -p "Install dependencies for clerk? (Y/n) > " deps_choice
deps_choice=${deps_choice:-y}

case "${deps_choice}" in
	[Yy]) 
		for dep in "${dependencies[@]}"
		do
			cpanp i "${dep}"
		done
		sudo pacman -S perl-config-simple perl-http-date perl-ipc-run 
		;;
esac

read -e -p "Set installation directory. (Default: $HOME/bin) > " foo
foo=${foo:-$HOME/bin}
case $foo in
	[Yy]) 	export path="$HOME/bin";
		;;
	*)	export path="$foo";
		;;
esac

read -e -p "Install clerk to $path? (Y/n) > " install
install=${install:-y}

case $install in
	[Yy])	cp clerk $path;
		if [[ ! -d "${HOME}/.config/clerk" ]]
		then
			mkdir "${HOME}/.config/clerk"
		fi
		cp clerk.tmux clerk.conf "${HOME}/.config/clerk"
		sed -i "s@PLACEHOLDER@"$HOME"@" "${HOME}/.config/clerk/clerk.conf"
		;;
	*)	exit;
esac
