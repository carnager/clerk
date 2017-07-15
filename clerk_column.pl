#!/usr/bin/perl

# written by Florian Pritz <bluewind@xinu.at>

use Data::Dumper;
my %width = ();
my @lines = ();
while (my $line = <>) {
	chomp $line;
	push @lines, $line;
	my @parts = split(/\t/, $line);
	my $counter = 0;
	for (; $counter < @parts; $counter++) {
		my $partlen = length($parts[$counter]);
		$width{$counter} = $partlen if !defined($width{$counter}) or $partlen > $width{$counter}
	}
}

for my $line (@lines) {
	my @parts = split(/\t/, $line);
	my $counter = 0;
	for (; $counter < @parts; $counter++) {
	  $parts[$counter] =~ s/\s+$//;
		my $partlen = $width{$counter};
		printf "%-*s\t", $partlen, $parts[$counter];
	}
	printf "%s\n", $parts[-1];
}
