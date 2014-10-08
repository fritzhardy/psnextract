#!/usr/bin/perl
# psnextract.pl
# ctime 20110820165510
# jeff hardy (jeff at fritzhardy dot com)
# scrape downloaded psn trophy page into hash and build custom html output
#
# #############
# Copyright (C) 2014, Jeff Hardy <hardyjm@potsdam.edu>
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA 02111-1307,
# USA.
# #############
#
# see 'perldoc ./psnextract.pl'

use strict;
use Getopt::Long;
use HTML::TokeParser::Simple;
use File::Copy;
use File::Basename;

my $script_name = $0; $script_name =~ s/.*\///;
my $usage = sprintf <<EOT;
$script_name OPTIONS --us|--uk=/psn.html
	-d, --dryrun
		show what would be done
	-h, --help
		this help message
	-i, --include=/path/to/include/graphics
		path to provided graphics when building web
	-o, --override=/path/to/override
		flat text file of game and trophy overrides and corrections
	--uk=/path/to/uk_psn.html
		path to uk_psn save-as-webpage html (files directory derived)
	--us=/path/to/us_psn.html
		path to us_psn save-as-webpage html (files directory derived)
	-v, --verbose
		increase verbosity
	-w, --web=/path/to/webdir
		web destination to place html and graphics

Use a web browser to save-as-complete web page the PSN trophies page for game.
Copy the game_trophies.html page into the destination web folder.
Copy the trophy PNG files into the destination web folder.
Copy the previously downloaded mini_trophy.png files into the destination web folder.
Save a screenshot of the banner logo, write some text into captions.txt.

Example:
cat game_trophies.html | $script_name -p -w "title,banner,captions.txt" > index.html
 
EOT

my $num_args = scalar(@ARGV);
my $dryrun;
my $help;
my $include;
my $override;
my $uk;	# path to uk html file
my $us;	# path to us html file
my $verbose;
my $web;
my $getopt = GetOptions(
	"dryrun"=>\$dryrun,
	"help"=>\$help,
	"include=s"=>\$include,
	"override=s"=>\$override,
	"uk=s"=>\$uk,
	"us=s"=>\$us,
	"verbose+"=>\$verbose,
	"web=s"=>\$web,
) or die "Invalid arguments\n";
die "Error processing arguments\n" unless $getopt;

if ($help || !$num_args) {
	die $usage;
}
if (!$us && !$uk) {
	die "Error: Require one or both of --us or --uk else nothing to do.\n\n$usage";	
}

# global hash of trophy to mini filename
my %trophy_mini = (
	unknown => '',							# no mini icon
	default => 'trophy_mini_default.png',	# faded, unearned
	bronze => 'trophy_mini_bronze.png',
	silver => 'trophy_mini_silver.png',
	gold => 'trophy_mini_gold.png',
	platinum => 'trophy_mini_platinum.png',
);

# global hash of trophy to image filename
my %trophy_small = (
	locked => 'trophy_small_locked.png',		# unearned
);

# global hash into which sub-hashes containing trophy info 
# gleaned from us, uk, and overrides are stored for use in web body
# %trophies{us} %trophies{uk} %trophies{override} %trophies{final}
my %trophies;

# global hash into which sub-hashes containing game info 
# gleaned from us, uk, and overrides are stored for use in web masthead
# %game{us} %game{uk} %game{override} %game{final}
my %game;

main: {
	# build us/uk hashes from html save-as-webpage data
	scrape_us_psn_20140607($us) if $us;
	scrape_uk_psn_20140607($uk) if $uk;
	
	# build addendums hash from local file
	parse_overrides($override) if ($override);
	
	# continue to see the following:
	# us: datestamps, bigger trophy graphics, often misses dlc
	# uk: usually dlc, no datestamps
	# override: local file to add datestamps and other gamedata
	# therefore we overlay for precedence: uk -> us -> overrides
	merge_gamedata();
	merge_trophies();
	
	# pure debugging final result
	if ($verbose) {
		if ($game{final} && $verbose) {
			foreach my $a (sort (keys(%{$game{final}}))) {
				print "$a=>${$game{final}}{$a}\n";
			}
			print "\n";
		}
		if ($trophies{final} && $verbose) {
			my %trophies = %{$trophies{final}};
			foreach my $n (sort {$a <=> $b} (keys(%trophies))) {
				print "$n\n";
				#print "\t".$trophies{$_}{img}."\n";
				#print "\t".$trophies{$_}{title}."\n";
				my %trophy = %{$trophies{$n}};
				foreach (sort(keys(%trophy))) {
					print "  $_=>$trophy{$_}\n";
				}
				print "\n";
			}
		}
	}
	
	# build web directory and copy source graphics
	build_web ($web,$game{final},$trophies{final},$include) if $web; #&& !$nocopy
	
	# write html into web directory
	write_html ($web,$game{final},$trophies{final}) if $web;
}

sub build_web {
	my ($web,$game,$trophies,$include) = @_;
	
	my %trophies = %$trophies;
	
	if (-e $web && ! -d $web) {
		die "ERROR: $web already exists and is not a directory, exiting\n";	
	}
	if (!$include) {
		warn "WARNING: No argument for include directory.\nThis may not be a problem if provided graphics are already\npresent in $web, otherwise output will look strange\n";	
	}
	if (! -e $web) {
		warn "WARNING: $web does not exist and will be created, contine? [y|N]\n";
		my $ans = <STDIN>;
		chomp($ans);
		exit unless $ans eq 'y';
		mkdir($web) or die "ERROR: Cannot mkdir $web: $!\n";
	}
	
	# when save-as-webpage with firefox, image paths in the html are relative 
	# to the saved html file, so in order to ensure we find the images, we will 
	# need to store and reference preceding paths from our us/uk arguments 
	my %sources;	
	if ($us) {
		my ($usbase, $uspath, $ussuffix) = fileparse($us);	# /path/to/resistance_2_us.html or just resistance_2_us.html
		#print "$us => usbase: $usbase, uspath: $uspath, ussuffix: $ussuffix\n";
		my $usfiles = $usbase;
		$usfiles =~ s#\.html#_files/#;		# resistance_2_us_files, assuming firefox behavior
		$sources{$usfiles} = $uspath;
	}
	if ($uk) {
		my ($ukbase, $ukpath, $uksuffix) = fileparse($uk);	# /path/to/resistance_2_uk.html or just resistance_2_uk.html
		#print "$uk => ukbase: $ukbase, ukpath: $ukpath, uksuffix: $uksuffix\n";
		my $ukfiles = $ukbase;
		$ukfiles =~ s#\.html#_files/#;		# resistance_2_uk_files, assuming firefox behavior
		$sources{$ukfiles} = $ukpath;
	}
	
	#foreach (sort(keys(%sources))) {
	#	print "$_ $sources{$_}\n";	
	#}
	
	# rsync contents of include directory
	if ($include) {
		print "rsync -a $include/ $web: " if $verbose;
		my @rsyncopts = ('-a');
		push (@rsyncopts,'-v') if $verbose;
		my $ret = system("rsync",@rsyncopts,$include."/",$web); $ret >>= 8;
		print "$ret\n" if $verbose;
	}
	
	# copy game images
	# definitely a hack to figure out file paths
	foreach my $attr ('img','avatar') {
		if ($game{final}{$attr}) {
			# resistance_2_files/ASDF.PNG
			my ($base, $path, $suffix) = fileparse($game{final}{$attr});
			#print "$game{final}{$attr} => base: $base, path: $path, suffix: $suffix\n";
			# /path/to/ + resistance_2_files/ASDF.PNG
			my $imgpath = $sources{$path}.$game{final}{$attr};
			print "cp -a $imgpath $web: " if $verbose;
			my $ret = system("cp","-a",$imgpath, $web); $ret >>= 8;
			print "$ret\n" if $verbose;
		}
	}
	
	# copy trophy images
	foreach my $n (sort {$a <=> $b} (keys(%trophies))) {
		my %trophy = %{$trophies{$n}};
		next if !$trophy{img};
		# resistance_2_files/ASDF.PNG
		my ($base, $path, $suffix) = fileparse($trophy{img});
		#print "$trophy{img} => base: $base, path: $path, suffix: $suffix\n";
		# /path/to/ + resistance_2_files/ASDF.PNG
		my $imgpath = $sources{$path}.$trophy{img};
		print "cp -a $imgpath $web: " if $verbose;
		my $ret = system("cp","-a",$imgpath,$web); $ret >>= 8;
		print "$ret\n" if $verbose;
	}
}

sub clean_str {
	my ($str) = @_;
	my $clean_str;
	my $last_ord;
	for (my $i=0; $i<length($str); $i++) {
		my $substr = substr($str,$i,1);
		my $ord = ord($substr);
		if ($ord >= 32 && $ord < 127) {
			$clean_str .= $substr;	
		}
		elsif ($ord == 174 && $last_ord == 194) {
			$clean_str .= '&#0174';
		}
		elsif ($ord == 128 && $last_ord == 226) {
			$clean_str .= "\'";
		}
		$last_ord = $ord;
	}
	return $clean_str;
}

sub merge_gamedata {
	# uk
	if ($game{uk}) {
		my %game_uk = %{$game{uk}};
		foreach my $a (sort(keys(%game_uk))) {
			print "UK: $a=>$game_uk{$a}\n" if $verbose > 1;
			$game{final}{$a} = $game_uk{$a};
		}
		print "\n" if $verbose > 1;
	}
	# us
	if ($game{us}) {
		my %game_us = %{$game{us}};
		foreach my $a (sort(keys(%game_us))) {
			print "US: $a=>$game_us{$a}\n" if $verbose > 1;
			$game{final}{$a} = $game_us{$a};
		}
		print "\n" if $verbose > 1;
	}
	# overrides
	if ($game{override}) {
		my %game_over = %{$game{override}};
		foreach my $a (sort(keys(%game_over))) {
			print "OVER: $a=>$game_over{$a}\n" if $verbose > 1;
			$game{final}{$a} = $game_over{$a};
		}
		print "\n" if $verbose > 1;
	}
	print "\n--\n\n" if $verbose > 1;
}

sub merge_trophies {
	# uk
	if ($trophies{uk}) {
		my %trophies_uk = %{$trophies{uk}};
		foreach my $n (sort {$a <=> $b} (keys(%trophies_uk))) {
			if ($verbose) {
				#print STDERR "$_:${$trophies_uk{$_}}{img}:\n";
				my %trophy = %{$trophies_uk{$n}};
				foreach (sort(keys(%trophy))) {
					print "UK: $n $_=>$trophy{$_}\n" if $verbose > 1;
				}
				print "\n" if $verbose > 1;
			}
			$trophies{final}{$n} = $trophies_uk{$n};
		}
	}
	# us
	if ($trophies{us}) {
		my %trophies_us = %{$trophies{us}};
		foreach my $n (sort {$a <=> $b} (keys(%trophies_us))) {
			if ($verbose) {
				#print STDERR "$_:${$trophies_us{$_}}{img}:\n";
				my %trophy = %{$trophies_us{$n}};
				foreach (sort(keys(%trophy))) {
					print "US: $n $_=>$trophy{$_}\n" if $verbose > 1;	
				}
				print "\n" if $verbose > 1;
			}
			$trophies{final}{$n} = $trophies_us{$n};
		}
	}
	# overrides
	if ($trophies{override}) {
		my %trophies_over = %{$trophies{override}};
		foreach my $n (sort {$a <=> $b} (keys(%trophies_over))) {
			my %trophy = %{$trophies_over{$n}};
			foreach (sort(keys(%trophy))) {
				print "OVER: $n $_=>$trophy{$_}\n" if $verbose > 1;
				$trophies{final}{$n}{$_} = $trophy{$_};	# apply individual attr value
			}
		}
		print "\n" if $verbose > 1;
	}
	print "\n--\n\n" if $verbose > 1;
}

sub parse_overrides {
	my ($override) = @_;
	#game|title=>Resistance 2: The Sequel to Resistance 1, Followed by Resistance 3
	#game|user=>wasntme69
	#1|name=>Platinum Baby
	#1|date=>Never
	#32|date=>Fri Jul 02 21:29:00 EDT 2010
	#33|name=>Something Else
	#33|date=>Fri Jul 09 22:17:00 EDT 2010
	#99|name=>Imaginary
	open (FH,$override) or die "Cannot open $override: $!\n";
	while (<FH>) {
		chomp();
		my ($object,@atoms) = split(/\|/,$_);
		foreach (@atoms) {
			my ($attr,$val) = split(/\=>/,$_);
			if ($object eq 'game') {
				print "OVER $attr=>$val\n" if $verbose > 2;
				$game{override}{$attr} = $val;
			} else {
				print "OVER $object $attr=>$val\n" if $verbose > 2;
				$trophies{override}{$object}{$attr} = $val;	# store by number
			}
		}
	}
	close (FH);
	print "\n--\n\n" if $verbose > 2;
}

# 2014-06-07 UK
#<tr>
#	<td class="trophy-unlocked-false">
#		<div class="absolute-position-wrapper">
#			<span class="trophy-icon trophy-type-platinum"></span>
#		</div>
#		<div class="itemWrap singleTrophyTile">
#			<a href="http://uk.playstation.com/psn/mypsn/trophies/detail/?title=72967">
#				<div class="cellWrap cell1">
#					<img src="the_last_of_us_uk_files/locked_trophy.png" alt="">
#                </div>
#
#                <div class="cellWrap cell2 image">
#					<hgroup>
#						<h1>
#						</h1>
#						<h1 class="trophy_name platinum">
#							It can't be for nothing
#						</h1>
#						<h2>
#							Platinum Trophy
#						</h2>
#					</hgroup>
#				</div>
#			</a>
#		</div>
#	</td>
#	<td>
#		<span class="locked">
#			&nbsp;
#		</span>
#	</td>
#</tr>
sub scrape_uk_psn_20140607 {
	my ($htmlfile) = @_;
	
	# We clean up and concatenate what we what we want here 
	# to protect against careless line breaks in the html
	my $htmlstr;
	my $gameon = 0;
	open (my $fh,$htmlfile) or die "Cannot open $htmlfile: $!\n";
	while (<$fh>) {
		if (m/<div class="CM162-compare-game-trophies /) { $gameon = 1; next; }
		if (m/<footer class="r2d2 full-width-footer">/) { $gameon = 0; last; }
		if ($gameon) {
			chomp($_);
			s/^\s+//;
			s/\s+$//;
			$htmlstr .= $_;
		}
	}
	close ($fh);
	
	#print $htmlstr;
	
	# Game data and trophy row html blocks follow
	my $p = HTML::TokeParser::Simple->new(\$htmlstr);
	my $trophyn = 0;
	my $tokn = 0;
	while ( my $tok = $p->get_token ) {
		# new trophy increment and unlocked true/false
		#<td class="trophy-unlocked-false">
		#<td class="trophy-unlocked-true">
		if ($tok->is_start_tag('td') && $tok->get_attr('class') =~ m/trophy-unlocked-(\S+)/) {
			$trophyn++;
			$tokn = 0;
			print "\n" if $verbose > 2;
			# get trophy lock status as well
			print "SCRAPE_UK $trophyn unlocked=>$1\n" if $verbose > 2;
			$trophies{uk}{$trophyn}{unlocked} = $1;
			$trophies{uk}{$trophyn}{source} = 'uk';
		}
		
		# debug
		if ($verbose > 2) {
			my $asis = $tok->as_is();
			my $tag = $tok->get_tag();
			my $hash = $tok->get_attr();
			my $class = $tok->get_attr('class');
			print "$trophyn $tokn $asis | tag:$tag class:$class\n";
		}
		
		# First batch of html before trophies contains gamedata bits such as 
		# percentage, trophy counts, etc, which we stuff into the global %game 
		# hash for use in the masthead banner row.
		if ($trophyn == 0) {
			# game title and image
			#<div class="game-image">
			#<img src="resistance_2_uk_files/8F0B2E25C3524F1EF9EE87AD1999F7FD8A5EC4F8.PNG" alt="Resistance 2TM">
			if ($tok->is_start_tag('div') && $tok->get_attr('class') eq 'game-image') {
				my $imgtag = $p->peek(2);
				$imgtag =~ m/src="(.*)" alt="(.*)"/;
				my $img = clean_str($1);
				my $title = clean_str($2);
				#$img =~ s#.*/##;	# eliminate folder path
				print "SCRAPE_UK title=>$title img=>$img\n" if $verbose > 2;
				$game{uk}{title} = $title;
				$game{uk}{img} = $img;
			}
			
			# game user and avatar
			#<img class="avatar-image" src="resistance_2_uk_files/A0031_002.png" alt="fritxhardy">
			if ($tok->is_start_tag('img') && $tok->get_attr('class') eq 'avatar-image' && $tok->get_attr('src')) {
				my $user = $tok->get_attr('alt');
				my $avatar = $tok->get_attr('src');
				#$avatar =~ s#.*/##;	# eliminate folder path
				print "SCRAPE_UK user=>$user\n" if $verbose > 2;
				print "SCRAPE_UK avatar=>$avatar\n" if $verbose > 2;
				$game{uk}{user} = $user;
				$game{uk}{avatar} = $avatar;
			}
			
			# trophy counts
			#<li class="bronze"> 
			#18
			#<li class="silver">
			#2
			if ($tok->is_start_tag('li')) {
				my $metal = $tok->get_attr('class');
				if (!exists($trophy_mini{$metal})) { next; }
				my $count = $p->peek(1);
				print "SCRAPE_UK $metal=>$count\n" if $verbose > 2;
				$game{uk}{$metal} = $count;
			}
			
			# progress bar
			#<div class="slider" style="width: 42%;">
			if ($tok->is_start_tag('div') && $tok->get_attr('class') eq 'slider') {
				my $progress = $tok->get_attr('style');
				$progress =~ s/.* //;
				$progress =~ s/\%.*//;
				print "SCRAPE_UK progress=>$progress\n" if $verbose > 2;
				$game{uk}{progress} = $progress;
			}
		}
		else {
			# image or locked
			#<img src="resistance_2_uk_files/79C5ACB1375731F2778CFBEBBFE1B5BF55D23BAA.PNG" alt="">
			#<img src="resistance_2_uk_files/locked_trophy.png" alt="">
			if ($tok->is_start_tag('img') && $tok->get_attr('src') !~ m/locked/) {
				my $img = $tok->get_attr('src');
				#$img =~ s#.*/##;	# eliminate folder path
				print "SCRAPE_UK $trophyn img=>$img\n" if $verbose > 2;
				$trophies{uk}{$trophyn}{img} = $img;
			}
			
			# metal/unknown and name
			#<h1 class="trophy_name unknown">
			#<h1 class="trophy_name bronze">
			#Rampage!
			if ($tok->is_start_tag('h1') && $tok->get_attr('class') =~ m/trophy_name\s+(\S+)/) {
				my $metal = $1;
				my $name = $p->peek(1);
				print "SCRAPE_UK $trophyn metal=>$metal\n" if $verbose > 2;
				print "SCRAPE_UK $trophyn name=>$name\n" if $verbose > 2;
				$trophies{uk}{$trophyn}{metal} = $metal;
				$trophies{uk}{$trophyn}{name} = $name;
			}
			
			# trophy text
			#<h2>
			#Kill 40 hybrids in the Single Player Campaign.
			if ($tok->is_start_tag('h2')) {
				my $text = $p->peek(1);
				print "SCRAPE_UK $trophyn text=>$text\n" if $verbose > 2;
				$trophies{uk}{$trophyn}{text} = clean_str($text);
			}
		}
		$tokn++;
	}
	print "\n--\n\n" if $verbose > 2;
}

# 2014-06-07 us.playstation.com
# <tr class="trophy-tr">
#	<td class="trophy-td trophy-unlocked-true">
#		<div class="absolute-position-wrapper">
#			<span class="trophy-icon trophy-type-platinum">
#			</span>
#		</div>
#		<div class="itemWrap singleTrophyTile">
#			<a href="javascript:void(0)">
#				<div class="cellWrap cell1">
#					<img src="the_last_of_us_usa_files/locked_trophy.png">
#				</div>
#				<div class="cellWrap cell2 image">
#					<hgroup>
#						<h1 class="trophy_name platinum">It can't be for nothing</h1>
#						<h2>Platinum Trophy</h2>
#					</hgroup>
#				</div>
#			</a>
#		</div>
#	</td>
#	<td class="trophy-td">
#		<span class="locked"></span>
#	</td>
#	<td class="trophy-td">
#	</td>
#	<td class="trophy-td">
#	</td>
#	<td class="trophy-td">
#	</td>
#</tr>
sub scrape_us_psn_20140607 {
	my ($htmlfile) = @_;
	
	# We clean up and concatenate what we what we want here 
	# to protect against careless line breaks in the html
	my $htmlstr;
	my $gameon = 0;
	open (my $fh,$htmlfile) or die "Cannot open $htmlfile: $!\n";
	while (<$fh>) {
		#if (m/table-overflow-wrapper clearfix/) { # one giant mess of a line
		if (m/<!-- END CM162 Compare Game Trophies -->/) { $gameon = 1; next; }
		if (m/<!-- START - FOOTER INCLUDE -->/) { $gameon = 0; last; }
		if ($gameon) {
			chomp($_);
			s/^\s+//;
			s/\s+$//;
			$htmlstr .= $_;
		}
	}
	close ($fh);
	
	# Game data and trophy row html blocks follow
	my $p = HTML::TokeParser::Simple->new(\$htmlstr);
	my $trophyn = 0;
	my $tokn = 0;
	while ( my $tok = $p->get_token ) {
		# new trophy increment
		#<tr class="trophy-tr">
		if ($tok->is_start_tag('tr') && $tok->get_attr('class') eq 'trophy-tr') {
			$trophyn++;
			$tokn = 0;
			print "\n" if $verbose > 2;
			# assume trophy unlocked since we only find out cases of locked later
			print "SCRAPE_US $trophyn unlocked=>true\n" if $verbose > 2;
			$trophies{us}{$trophyn}{unlocked} = 'true';
			$trophies{us}{$trophyn}{source} = 'us';
		}
		
		# debug
		if ($verbose > 2) {
			my $asis = $tok->as_is();
			my $tag = $tok->get_tag();
			my $hash = $tok->get_attr();
			my $class = $tok->get_attr('class');
			print "$trophyn $tokn $asis | tag:$tag class:$class\n";
		}
		
		# First batch of html before trophies contains gamedata bits such as 
		# percentage, trophy counts, etc, which we stuff into the global %game 
		# hash for use in the masthead banner row.
		if ($trophyn == 0) {
			# game title and image
			#<div class="game-image">
			#<img title="Resistance 2TM" alt="Resistance 2TM" src="resistance_2_us_files/8F0B2E25C3524F1EF9EE87AD1999F7FD8A5EC4F8.PNG">
			if ($tok->is_start_tag('div') && $tok->get_attr('class') eq 'game-image') {
				my $imgtag = $p->peek(1);
				$imgtag =~ m/title="(.*)" alt.* src="(.*)"/;
				my $title = clean_str($1);
				my $img = clean_str($2);
				#$img =~ s#.*/##;	# eliminate folder path
				print "SCRAPE_US title=>$title img=>$img\n" if $verbose > 2;
				$game{us}{title} = $title;
				$game{us}{img} = $img;
			}
			
			# game user and avatar
			#<img title="fritxhardy" alt="fritxhardy" src="resistance_2_us_files/A0031_m.png" class="avatar-image">
			if ($tok->is_start_tag('img') && $tok->get_attr('class') eq 'avatar-image') {
				my $user = $tok->get_attr('title');
				my $avatar = $tok->get_attr('src');
				#$avatar =~ s#.*/##;	# eliminate folder path
				print "SCRAPE_US user=>$user avatar=>$avatar\n" if $verbose > 2;
				$game{us}{user} = $user;
				$game{us}{avatar} = $avatar;
			}
			
			# trophy counts
			#<li class="bronze"> 
			#18
			#<li class="silver">
			#2
			if ($tok->is_start_tag('li')) {
				my $metal = $tok->get_attr('class');
				if (!exists($trophy_mini{$metal})) { next; }
				my $count = $p->peek(1);
				print "SCRAPE_US $metal=>$count\n" if $verbose > 2;
				$game{us}{$metal} = $count;
			}
			
			# progress bar
			#<div style="width: 42%;" class="slider">
			if ($tok->is_start_tag('div') && $tok->get_attr('class') eq 'slider') {
				my $progress = $tok->get_attr('style');
				$progress =~ s/.* //;
				$progress =~ s/\%.*//;
				print "SCRAPE_US progress=>$progress\n" if $verbose > 2;
				$game{us}{progress} = $progress;
			}
		}
		else {			
			# locked or unlocked
			#<td class="trophy-td trophy-unlocked-false">
			#<td class="trophy-td trophy-unlocked-true">
			#if ($tok->is_start_tag('td') && $tok->get_attr('class') =~ m/trophy-unlocked-(\S+)/) {
			#	print "SCRAPE_US $trophyn unlocked=>$1\n" if $verbose > 2;
			#	$trophies{us}{$trophyn}{unlocked} = $1;
			#}
			
			# span locked
			#<span class="locked">
			if ($tok->is_start_tag('span') && $tok->get_attr('class') eq 'locked') {
				print "SCRAPE_US $trophyn unlocked=>false\n" if $verbose > 2;
				$trophies{us}{$trophyn}{unlocked} = 'false';
			}
				
			# metal or unknown
			#<span class="trophy-icon trophy-type-bronze">
			#<span class="trophy-icon trophy-type-unknown">
			if ($tok->is_start_tag('span') && $tok->get_attr('class') =~ m/trophy-type-(\S+)/) {
				my $metal = $1;
				print "SCRAPE_US $trophyn metal=>$metal\n" if $verbose > 2;
				$trophies{us}{$trophyn}{metal} = $metal;
			}
			
			# image or locked
			#<img title="Rampage!" alt="Rampage!" src="resistance_2_us_files/79C5ACB1375731F2778CFBEBBFE1B5BF55D23BAA.PNG">
			#<img src="resistance_2_us_files/locked_trophy.png">
			if ($tok->is_start_tag('img') && $tok->get_attr('title') ne '') {
				my $img = $tok->get_attr('src');
				#$img =~ s#.*/##;	# eliminate folder path
				print "SCRAPE_US $trophyn img=>$img\n" if $verbose > 2;
				$trophies{us}{$trophyn}{img} = $img;
			}
			
			# trophy name
			#<h1 class="trophy_name bronze">
			#Rampage!
			if ($tok->is_start_tag('h1') && $tok->get_attr('class') =~ m/trophy_name/) {
				#print $tok->as_is()."\n";
				my $name = $p->peek(1);
				print "SCRAPE_US $trophyn name=>$name\n" if $verbose > 2;
				$trophies{us}{$trophyn}{name} = clean_str($name);
			}
			
			# trophy text
			#<h2>
			#Kill 40 hybrids in the Single Player Campaign.
			if ($tok->is_start_tag('h2')) {
				#print $tok->as_is()."\n";
				my $text = $p->peek(1);
				print "SCRAPE_US $trophyn text=>$text\n" if $verbose > 2;
				$trophies{us}{$trophyn}{text} = clean_str($text);
			}
			
			# trophy gamedetails
			#<div class="GameDetails">
			#<h6 title="fritxhardy">
			#fritxhardy
			#</h6>
			#<p class="">
			#Trophy Earned
			#</p>
			#<p class="">
			#January 22, 2010
			#</p>
			#<p class="">
			#06:50:58 PM EST
			#</p>
			#</div>
			if ($tok->is_start_tag('div') && $tok->get_attr('class') eq 'GameDetails') {
				#<h6 title="fritxhardy">fritxhardy</h6><p class="">Trophy Earned</p><p class="">January 22, 2010</p><p class="">06:50:58 PM EST</p>
				my $dat = $p->peek(11);
				$dat =~ s#.*Trophy Earned</p><p class="">##;
				my ($date,$time) = split(/<\/p><p class="">/,$dat);
				print "SCRAPE_US $trophyn date=>$date $time\n" if $verbose > 2;
				$trophies{us}{$trophyn}{date} = "$date $time";
			}
		}
		$tokn++;
	}
	print "\n--\n\n" if $verbose > 2;
}

sub write_html {
	my ($web,$game,$trophies) = @_;
	my %trophies = %$trophies;
	
	my $ttot = $game{final}{platinum}+$game{final}{gold}+$game{final}{silver}+$game{final}{bronze};
	my $caption = $game{final}{caption} ? $game{final}{caption} : '';
	
	open (my $out,">$web/index.html") or die "ERROR: Cannot write $web/index.html: $!\n";
	print $out <<EOT;
<html>
<head>
<title>$game{final}{title}</title>
<style type="text/css">
.table {
	width: 780px;
	font-family: Helvetica;
	background-color: #f5f5f5;
}
.bannerrow {
	clear: both;
	width: 780px;
	height: 100px;
	border-top: 2px solid #dddddd;
	border-bottom: 2px solid #dddddd;
}
.gamegraphic {
	float: left;
	#border-right: 2px solid #ffffff;
	position: relative;
	width: 220px;
	height: 100%;
}
.gamegraphic_img {
	#box-shadow: 10px 10px 5px #888888;
	width: 167px;
	height: 92px;
	position: absolute;
	left: 6px;
	bottom: 4px;
}
.gameinfo {
	float: left;
	#border: 2px solid #ffffff;
	width: 340px;
	height: 100%;
	position: relative;
}
.gameinfo_title {
	font: 700 6.25em Helvetica;
	font-size: 24px;
	text-align: center;
	margin-top: 6px;
	text-shadow: 1px 1px 0 rgb(223, 227, 229), 2px 2px 0 rgba(0, 0, 0, 0.25);
	color: #3f3f3f;
}
.gameinfo_avatar {
	position: absolute;
	left: 5px;
	bottom: 5px;
}
.gameinfo_user {
	font-size: 12px;
	position: absolute;
	left: 30px;
	bottom: 8px;
}
.gameinfo_progressbar {
	height: 10px;
	width: 150px;
	float: left;
	overflow: hidden;
	background: #ffffff;
	border: 1px solid #808080;
	position: absolute;
	right: 33px;
	bottom: 8px;
}
.gameinfo_progressslider {
	height: 8px;
	margin: 1px 0px 1px 0px;
	background-color: #0068bf;
}
.gameinfo_progresstext {
	height: 8px;
	float: left;
	font-size: 12px;
	position: absolute;
	right: 1px;
	bottom: 14px;
}
.gametrophygraph {
	float: left;
	#border: 2px solid #ffffff;
	width: 220px;
	height: 100%;
	position: relative;
}
.gametrophygraph_bar {
	height: 16px;
	margin-top: 0px;
	margin-bottom: 1px;
	position: absolute;
	right: 6px;
	border: 1px solid #e6e6e6;
	background: -webkit-linear-gradient(#fdfcfd, #dfdfdf); /* For Safari 5.1 to 6.0 */
	background: -o-linear-gradient(#fdfcfd, #dfdfdf); /* For Opera 11.1 to 12.0 */
	background: -moz-linear-gradient(#fdfcfd, #dfdfdf); /* For Firefox 3.6 to 15 */
	background: linear-gradient(#fdfcfd, #dfdfdf); /* Standard syntax (must be last) */
	font-size: 11px;
}
.gametrophygraph_mini {
	margin-top: 0px;
	margin-bottom: 0px;
	position: absolute;	
}
.gametrophygraph_total {
	position: absolute;
	right: 12;
	bottom: 6;
	font-size: 26px;
	#color: #3f3f3f;
	text-shadow: 0 2px 3px rgba(255, 255, 255, 0.3), 0 -1px 2px rgba(0, 0, 0, 0.2);
	#text-shadow: 0 -4px 3px rgba(255, 255, 255, 0.3), 0 3px 4px rgba(0, 0, 0, 0.2);
	color: #ffffff;
}
.captionrow {
	clear: both;
	width: 780px;
	min-height: 2px;
	border-bottom: 2px solid #dddddd;
}
.captiontext {
	#margin: 15px 15px 15px 15px;
	text-align: left;
	font-size: 12px;
	font-weight: normal;
}
.trophyrow {
	clear: both;
	width: 780px;
	min-height: 59px;
	margin: 0px 0px 0px 0px;
	border-bottom: 2px solid #dddddd;
	overflow: hidden;
}
.trophyimage {
	float: left;	
}
.trophyimage img {
	float: left;
	width: 50px;
	height: 50px;
	margin: 5px 5px 5px 5px;
}
.trophytitle {
	float: left;
	width: 300px;
	margin: 5px 5px 5px 5px;	
}
.trophyname {
	margin: 0px 0px 0px 0px;
	text-align: left;
	font-size: 13px;
	font-weight: bold;
}
.trophytext {
	font-size: 10px;
	font-weight: normal;
}
.trophydate {
	float: left;
	width: 218px;
	margin: 5px 5px 5px 5px;
	font-size: 12px;	
}
.trophygrid {
	float: left;
	width: 150px;
	margin: 5px 5px 5px 5px;
}
.trophyicon {
	float: left;
	width: 26px;
	margin: 0px 10px 0px 0px;
	#border-top: 1px solid #000000;
}
</style>
<body>
<div class="table">
<div class="bannerrow">
EOT

	#print $out "$game{final}{title} $game{final}{img} $game{final}{user} $game{final}{avatar} bronze:$game{final}{bronze} silver:$game{final}{silver} gold:$game{final}{gold} platinum:$game{final}{platinum} progress:$game{final}{progress}\n";

	# strip image paths now that we are writing html
	$game{final}{img} =~ s#.*/##;
	$game{final}{avatar} =~ s#.*/##;

	print $out "\t<div class=\"gamegraphic\">\n";
	print $out "\t\t<div class=\"gamegraphic_img\">\n";
	print $out "\t\t\t<img src=\"$game{final}{img}\" title=\"$game{final}{title}\" alt=\"$game{final}{title}\" width=\"167\" height=\"92\">\n";
	print $out "\t\t</div>\n";
	print $out "\t</div>\n";
	
	print $out "\t<div class=\"gameinfo\">\n";
	
	print $out "\t\t<div class=\"gameinfo_title\">\n";
	print $out "\t\t\t$game{final}{title}<br>\n";
	print $out "\t\t</div>\n";
	
	print $out "\t\t<div class=\"gameinfo_avatar\">\n";
	print $out "\t\t\t<img src=\"$game{final}{avatar}\" title=\"$game{final}{user}\" alt=\"$game{final}{user}\" width=\"25\" height=\"25\">\n";
	print $out "\t\t</div>\n";
	
	print $out "\t\t<div class=\"gameinfo_user\">\n";
	print $out "\t\t$game{final}{user}\n";
	print $out "\t\t</div>\n";
	
	print $out "\t\t<div class=\"gameinfo_progressbar\">\n";
	print $out "\t\t\t<div class=\"gameinfo_progressslider\" style=\"width: $game{final}{progress}%\"></div>\n";
	print $out "\t\t</div>\n";
	print $out "\t\t<div class=\"gameinfo_progresstext\">$game{final}{progress}%</div>\n";
	
	print $out "\t</div>\n";
	
	print $out "\t<div class=\"gametrophygraph\">\n";
	print $out "\t\t<div class=\"gametrophygraph_mini\" style=\"right:41px;bottom:66px;\"><img src=\"trophy_mini_platinum.png\"></div>\n";
	print $out "\t\t<div class=\"gametrophygraph_bar\" style=\"width:61px;bottom:52px;\">$game{final}{platinum} Platinum</div>\n";
	print $out "\t\t<div class=\"gametrophygraph_mini\" style=\"right:77px;bottom:50px;\"><img src=\"trophy_mini_gold.png\"></div>\n";
	print $out "\t\t<div class=\"gametrophygraph_bar\" style=\"width:97px;bottom:36px;\">$game{final}{gold} Gold</div>\n";
	print $out "\t\t<div class=\"gametrophygraph_mini\" style=\"right:113px;bottom:34px;\"><img src=\"trophy_mini_silver.png\"></div>\n";
	print $out "\t\t<div class=\"gametrophygraph_bar\" style=\"width:133px;bottom:20px;\">$game{final}{silver} Silver</div>\n";
	print $out "\t\t<div class=\"gametrophygraph_mini\" style=\"right:149px;bottom:18px;\"><img src=\"trophy_mini_bronze.png\"></div>\n";
	print $out "\t\t<div class=\"gametrophygraph_bar\" style=\"width:169px;bottom:4px;\">$game{final}{bronze} Bronze</div>\n";
	print $out "\t\t<div class=\"gametrophygraph_total\">$ttot</div>\n";
	print $out "\t</div>\n";

	print $out <<EOT;
</div>
<div class="captionrow">
	<span class="captiontext"><p>$caption</p></span>
</div>
EOT

	foreach (sort {$a <=> $b} (keys(%trophies))) {
		my %trophy = %{$trophies{$_}};
		
		# strip image paths now that we are writing html
		$trophy{img} =~ s#.*/##;
		
		print $out "<div class=\"trophyrow\">\n";
		# image
		if ($trophy{img}) {
			print $out "\t<div class=\"trophyimage\"><img src=\"".$trophy{img}."\" alt=\"".$trophy{text}."\" title=\"".$trophy{text}."\"></div>\n";
		} else {
			print $out "\t<div class=\"trophyimage\"><img src=\"".$trophy_small{locked}."\" alt=\"".$trophy{text}."\" title=\"".$trophy{text}."\"></div>\n";
		}
		# name and text
		print $out "\t<div class=\"trophytitle\"><span class=\"trophyname\">".$trophy{name}."</span><br><span class=\"trophytext\">".$trophy{text}."</span></div>\n";
		# date
		print $out "\t<div class=\"trophydate\">".$trophy{date}."</div>\n";
		# mini trophygrid
		print $out "\t<div class=\"trophygrid\">\n";
		print $out print_trophy_mini($trophy{metal},$trophy{unlocked});
		print $out "\t</div>\n";
		print $out "</div>\n";
	}

	print $out <<EOT;
</div>
</body>
</html>
EOT
}

sub print_trophy_mini {
	my ($metal,$unlocked) = @_;
	#print "$metal $unlocked\n";
	
	# earned if unlocked true, default faded one if unearned
	my $trophy_icon = $unlocked eq 'true' ? $trophy_mini{$metal} : $trophy_mini{default};
	
	# unknown hidden trophies have no position at all
	my %metal_position = (
		unknown => -1,
		bronze => 0,
		silver => 1,
		gold => 2,
		platinum => 3,
	);
	
	my $trophy_mini_html;
	for (my $t = 0; $t <= 3; $t++) {
		if ($t == $metal_position{$metal}) {
			$trophy_mini_html .= "\t\t<div class=\"trophyicon\"><img src=\"".$trophy_icon."\" alt=\"".$metal."\" title=\"".$metal."\"></div>\n";
		} else {
			$trophy_mini_html .= "\t\t<div class=\"trophyicon\">&nbsp;</div>\n";
		}
	}
	return $trophy_mini_html;
}

#sub scrape_psn_2012 {
#	my $us;
#	my $trophyn_us = 0;
#	my $hidden = 0;
#	my $locked = 0;
#	
#	my $uk;
#	my $trophyn_uk = 0;
#	
#	while (<STDIN>) {
#		# us.playstation.com
#		if (m# href="http://us.playstation.com/playstation/psn/profiles/fritxhardy/trophies"#) {
#			$us = 1;
#			$uk = 0;
#		}
#		if ($us) {
#			# slot determines visibility
#			if (m/div class="slot\s+(.*)"/) {
#				if (!$1) {
#					$hidden = 0;
#				} elsif ($1 eq "hiddenTrophy") {
#					$hidden = 1;
#				}
#				$trophyn_us++;
#			}
#			# slotcontent determines locked/unlocked
#			if (m/div class="slotcontent\s+(.*)"/) {
#				if (!$1) {
#					$locked = 1;
#				} elsif ($1 eq "showTrophyDetail") {
#					$locked = 0;
#				}
#			}
#			# we are into the trophy section at least
#			if ($trophyn_us) {
#				if (m/img.*src="(\S+)".*\>/) {
#					my $img = $1;
#					$img =~ s#.*/## if ($path);
#					$trophies_us{$trophyn_us}{img} = $img;
#				}
#				if ($hidden && $locked) {	# reset with every line until next trophy, so what?
#					$trophies_us{$trophyn_us}{text} = '???';
#				}
#				else {
#					if (m/span class="trophyTitleSortField"\>(.*)<\/span\>/) {
#						$trophies_us{$trophyn_us}{text} = clean_str($1);
#					}
#					elsif (m/span class="subtext"\>(.*)<\/span\>/ || m/span class="subtext"\>(.*)$/) {
#						$trophies_us{$trophyn_us}{subtext} = clean_str($1);
#					}
#					elsif (m/span class="dateEarnedSortField".*\>(.*)<\/span\>/) {
#						$trophies_us{$trophyn_us}{date} = $1;
#					}
#					elsif (m/BRONZE|SILVER|GOLD|PLATINUM/) {
#						my $metal = $_;
#						$metal =~ s/\s+//g;
#						$trophies_us{$trophyn_us}{metal} = $metal;
#					}
#				}
#			}
#			if (m/<p class="profile_note">Note: The above information is dependent/) {
#				$us = 0;
#			}
#		}
#	
#		# uk.playstation.com
#		if (m# href="http://uk.playstation.com/psn/mypsn/trophies/detail/"#) {
#			$uk = 1;
#			$us = 0;
#		}
#		if ($uk == 1) {
#			if (m/div class="gameLevelListItem"/) {
#				$trophyn_uk++;
#			}
#			if ($trophyn_uk) {
#				if (m/div class="gameLevelImage".*src="(.*)"\s+/) {
#					my $img = $1;
#					$img =~ s#.*/## if ($path);
#					$img =~ s/icon_trophy_padlock.gif/trophy_locksmall.png/ if ($img =~ m/icon_trophy_padlock.gif/);
#					$trophies_uk{$trophyn_uk}{img} = $img;
#				}
#				elsif (m/div class="gameLevelTrophyType".*alt="(.*)"/) {
#					my $metal = $1;
#					$metal = uc($metal);
#					$trophies_uk{$trophyn_uk}{metal} = $metal;
#				}
#				elsif (m/<p class="title">(.*)<\/p>/) {
#					$trophies_uk{$trophyn_uk}{text} = clean_str($1);
#				}
#				elsif (m/<p class="date">(.*)<\/p>/) {
#					$trophies_uk{$trophyn_uk}{date} = clean_str($1);
#				}
#				elsif (m/^\s+<p>(.*)<\/p>$/ || m/^\s+<p>(.*)$/) {
#					$trophies_uk{$trophyn_uk}{subtext} = clean_str($1);
#				}
#			}
#			if (m/div class="sortBarHatchedBtm"/) {
#				$uk = 0;
#			}
#		}
#	}
#}

=head1 NAME

psnextract.pl

=head1 SYNOPSIS

=over 4

=item Firefox save PSN US web page:

save-as-webpage gamedata-us.html

=item Parse data and output to webdir with included graphics:

 psnextract.pl --us gamedata-us.html --include includedir \
 --web outputdir

=item Combination with UK data:

 psnextract.pl --us gamedata-us.html --uk gamedata-uk.html \
 --include includedir --web outputdir

=item Designate file for override variables:

 psnextract.pl --us gamedata-us.html --uk gamedata-uk.html \
 --include includdir --override override.txt --web outputdir

=back

=head1 DESCRIPTION

Psnextract is a tool intended to gather trophy data from PlayStation Network, 
parsing downloaded html for use building external web pages.

=head1 INSTALLATION

Script requirements are as follows:

 HTML::TokeParser::Simple;

Installation consists of merely untarring the script, and likely making use of 
the included graphics with the include argument.  At this time, html output 
formatting and styles are hardcoded, so any customization must be done via 
programmatic changes within the script.

=head1 OPTIONS

=over 4

=item B<-d, --dry-run>

Do not actually do any operations.  Combines well with --verbose to debug 
problems.

=item B<-h, --help>

Print brief usage message.

=item B<-i, --include=/path/to/include/graphics>

Path to directory of graphics and other items to include when building web. The 
include directory provided in the package includes all items necessary for 
building web pages as is done in the write_html function.  Adjustments to that 
function may well require additions to include.

=item B<-o, --override=/path/to/override>

File of corrections and additions with which to override game and trophy values 
parsed from html.  Format is item|attribute=value.  See OVERRIDES.

=item B<--uk=/path/to/uk_psn.html>

File of UK PSN html save-as-webpage data to parse.  Assumes Firefox format, 
with file uk_psn.html and accompanying directory uk_psn_files.

=item B<--us=/path/to/us_psn.html>

File of US PSN html save-as-webpage data to parse.  Assumes Firefox format, 
with file us_psn.html and accompanying directory us_psn_files.

=item B<-v, --verbose>

Control vebosity of output.  Increase by passing multiple times. 

=item B<-w, --web=/path/to/webdir>

Web destination to which include graphics and items are copied, and inside 
which index.html is written from parsed data.

=back

=head1 MULTIPLE HTML SOURCES

The purpose for supporting both US and UK data sources and merging them with 
overrides is the following observation:

 US: Datestamps, bigger trophy graphics, often missing or delayed DLC
 UK: No datestamps, always up-to-date DLC 

The main issue is missing DLC.  As such, the sources are overlayed on top of 
one another: UK -> US -> overrides.  UK data to provide data for all 
trophies minus datestamps, US to fill in missing datestamps and provide nicer 
graphics, and lastly overrides to fill in any missing info.

In most cases, US data is all that is needed to provide all info.

=head1 OVERRIDES

The overrides facility is used to provide missing info, corrections, addendums, 
and any caption desired for web output.  Overrides are one per line, in format 
item|attribute=value.  Example specifying all possible overrides:

 game|title=>Game of the Ages
 game|caption=>This is a terrific game
 game|img=>awesome.jpg
 game|user=>foobar
 game|avatar=>foobar.jpg
 game|progress=>50
 game|bronze=>12
 game|silver=>34
 game|gold=>56
 game|platinum=>78
 1|date=>Fri Aug 24 22:49:00 EDT 2012
 2|date=>Fri Aug 24 20:45:00 EDT 2012
 3|date=>Fri Nov 12 22:22:00 EST 2010
 4|date=>Fri Aug 31 21:44:00 EDT 2012
 5|date=>Sun Sep 16 15:15:00 EDT 2012

Every game line is overriding info that will appear in the masthead, while  
numbered lines provide info for the given trophy.  It is most common to use the 
overrides file only to specify caption, and in the event of missing DLC, trophy 
date.

=head1 EXAMPLES

=over 4

=item Parse US PSN data:

 psnextract.pl --us=gamedata_us.html

=item See lots of verbose output:

 psnextract.pl -v -v -v -v --us=gamedata_us.html

=item Also parse UK PSN data:

 psnextract.pl --us=gamedata_us.html --uk=gamedata_uk.html

=item Add in overrides:

 psnextract.pl --us=gamedata_us.html --uk=gamedata_uk.html \
 --override=override.txt

=item Now build a web page with it all:

 psnextract.pl --us=gamedata_us.html --uk=gamedata_uk.html \
 --override=override.txt --web=webdir

=item Include graphics for complete html output:

 psnextract.pl --us=gamedata_us.html --uk=gamedata_uk.html \
 --override=override.txt --include=includedir --web=webdir

=back

=head1 CHANGES

21041007

-Complete perldocs, pod2text README

93c715124cb18143d9b02ffc5363b75f366a7c89 (20140927)

-Initial release

=cut
