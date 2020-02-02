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
use HTML::Strip;
use File::Copy;
use File::Basename;
use Data::Dumper;
use Tie::IxHash;

my $script_name = $0; $script_name =~ s/.*\///;
my $usage = sprintf <<EOT;
$script_name OPTIONS --game us:psn.html --game uk:psn.html --game my:psn.html
	-d, --dryrun
		show what would be done
	-h, --help
		this help message
	-i, --include=/path/to/include/graphics
		path to provided graphics when building web
	--game=src:/path/to/game_psn.html
		path to psn save-as-webpage html (files directory derived)
		valid src: us, uk, my
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
my @game;	# prefixed path to playstation.com html file, ex: my:/path/to/resistance_2_ps3.html
my $verbose;
my $web;
my $getopt = GetOptions(
	"dryrun"=>\$dryrun,
	"help"=>\$help,
	"include=s"=>\$include,
	"game=s"=>\@game,
	"verbose+"=>\$verbose,
	"web=s"=>\$web,
) or die "Invalid arguments\n";
die "Error processing arguments\n" unless $getopt;

if ($help || !$num_args) {
	die $usage;
}
if (!@game) {
	die "Error: Require at least one --game.\n\n$usage";
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

# array of game hashrefs
#$game{avatar} = A0031_m.png
#$game{bronze} = 45
#$game{gold} = 1
#$game{img} = 0CAA52366C0F14C85A71FACB36BDD29122DF85D6.PNG
#$game{platinum} = 1
#$game{progress} = 100
#$game{silver} = 9
#$game{source} = my
#$game{title} = Uncharted 4: A Thief's End
#$game{user} = fritxhardy
#$game{trophies}{1} = {
#  'metal' => 'platinum',
#  'unlocked' => 'true',
#  'text' => 'Collect All The Trophies',
#  'name' => 'One Last Time',
#  'img' => 'E2AC09D649FE91D06F7BCD7236CFC5C1A56B3A06.PNG',
#  'source' => 'my'
#}
tie my %games => 'Tie::IxHash';

main: {
	# parse save-as-webpage data
	# each game is prefixed by source
	# us:/path/to/resistance_2_ps3.html
	# uk:/path/to/resistance_2_ps3.html
	# my:/path/to/resistance_2_ps3.html

	foreach my $g (@game) {
		my ($source,$file) = split(/\:/,$g);

		# parse the source with appropriate function
		my $gamedata;
		if ($source eq 'us') {	# us.playstation.com
			$gamedata = scrape_us_psn_20150813($file);
		} elsif ($source eq 'uk') {	# uk.playstation.com
			$gamedata = scrape_uk_psn_20140607($file);
		} elsif ($source eq 'my') {	# my.playstation.com
			$gamedata = scrape_my_psn_20191226($file);
		} else {
			die "Invalid source specification.\n";
		}

		# sprinkle in more metadata
		my ($base, $path, $suffix) = fileparse($file);	# /path/to/resistance_2_ps3.html
		my $id = $base;
		$id =~ s#\.html##;	# resistance_2_ps3
		$$gamedata{source_html} = $file;
		$$gamedata{source_files} = $file;
		$$gamedata{source_files} =~ s#\.html#_files/#;	# resistance_2_ps3_files
		$$gamedata{id} = $id;

		# add parsed data to the list
		$games{$id} = $gamedata;
	}

	# pure debugging final result
	if ($verbose) {
		#print Dumper(\@games);
		foreach my $game (keys(%games)) {
			my %game = %{$games{$game}};
			foreach my $attr (sort(keys(%game))) {
				print "$attr: $game{$attr}\n" unless ($attr eq 'trophies');
			}
			if (defined($game{trophies})) {
				print "trophies:\n";
				my %trophies = %{$game{trophies}};
				foreach my $t (sort {$a <=> $b} (keys(%trophies))) {
					print "\t$t\n";
					my %trophy = %{$trophies{$t}};
					foreach my $attr (sort(keys(%trophy))) {
						print "\t\t$attr: $trophy{$attr}\n";
					}
				}
			}
		}
	}

	# build web directory and copy source graphics
	build_web ($web,\%games,$include) if $web; #&& !$nocopy
	
	# write html into web directory
	write_html ($web,\%games) if $web;
}

sub build_web {
	my ($web,$games,$include) = @_;

	if (-e $web && ! -d $web) {
		die "ERROR: $web already exists and is not a directory, exiting\n";	
	}
	if (!$include) {
		warn "WARNING: No argument for include directory.\nThis may not be a problem if provided graphics are already\npresent in $web, otherwise output will look strange\n";	
	}
	if (! -e $web) {
		warn "WARNING: $web does not exist and will be created, continue? [y|N]\n";
		my $ans = <STDIN>;
		chomp($ans);
		exit unless $ans eq 'y';
		mkdir($web) or die "ERROR: Cannot mkdir $web: $!\n";
	}
	
	print "\n" if $verbose;
	
	# rsync contents of include directory
	if ($include) {
		print "rsync -a $include/ $web: " if $verbose;
		my @rsyncopts = ('-a');
		push (@rsyncopts,'-v') if $verbose;
		my $ret = system("rsync",@rsyncopts,$include."/",$web); $ret >>= 8;
		print "$ret\n" if $verbose;
	}
	
	# copy game and trophy images
	foreach my $g (keys(%$games)) {
		my %game = %{$games{$g}};
		foreach my $attr ('img','avatar') {
			if ($game{$attr}) {
				# ASDF.PNG
				my $imgpath = $game{source_files}.$game{$attr};
				print "cp -a $imgpath $web: " if $verbose;
				my $ret = system("cp","-a",$imgpath, $web); $ret >>= 8;
				print "$ret\n" if $verbose;
			}
		}
	
		my %trophies = %{$game{trophies}};
		foreach my $n (sort {$a <=> $b} (keys(%trophies))) {
			my %trophy = %{$trophies{$n}};
			next if !$trophy{img};
			# ASDF.PNG
			my $imgpath = $game{source_files}.$trophy{img};
			print "cp -a $imgpath $web: " if $verbose;
			my $ret = system("cp","-a",$imgpath,$web); $ret >>= 8;
			print "$ret\n" if $verbose;
		}
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

# 2019-08-11 my.playstation.com
#            <li class="game-trophies-page__tile-container">
#              <button id="ember4194" class="trophy-tile ember-view"><div class="trophy-tile__image-container">
#      <div class="trophy-tile__unlocked-trophy-background"></div>
#      <img alt="Trophy Icon" src="uncharted_4_a_thiefs_end_ps4_files/E2AC09D649FE91D06F7BCD7236CFC5C1A56B3A06.PNG" class="trophy-tile__image">
#</div>
#
#<div class="trophy-tile__info-container
#  ">
#  <div class="trophy-tile__sub-info-container">
#      <div class="trophy-tile__tier-icon trophy-tile__tier-icon--platinum"></div>
#    <div class="trophy-tile__name-rarity-container">
#        <div class="trophy-tile__name">
#          <div id="ember4195" class="ember-view">  <div class="truncate-multiline--truncation-target"><span class="truncate-multiline--last-line-wrapper"><span>One Last Time</span><button class="truncate-multiline--button-hidden" data-ember-action="" data-ember-action-7060="7060">
#<!---->  </button></span></div>
#  
#</div>
#        </div>
#      <div class="trophy-tile__rarity">
#        Ultra Rare <span dir="ltr">0.7%</span>
#      </div>
#    </div>
#  </div>
#      <div class="trophy-tile__detail">
#        <div id="ember4197" class="ember-view">  <div class="truncate-multiline--truncation-target"><span class="truncate-multiline--last-line-wrapper"><span>Collect All The Trophies</span><button class="truncate-multiline--button-hidden" data-ember-action="" data-ember-action-7061="7061">
#<!---->  </button></span></div>
#  
#</div>
#      </div>
#</div>
#</button>
#            </li>
sub scrape_my_psn_20191226 {
	my ($htmlfile) = @_;

	my %game;
	my %trophies;

	# So much crap here we isolate to the section we care about and clean up
	my $htmlstr;
	my $gameon = 1;
	open (my $fh,$htmlfile) or die "Cannot open $htmlfile: $!\n";
	while (<$fh>) {
		#if (m/<div class="game-trophies-page__addon-tile-divider/) { $gameon = 1; next; }
		#if (m/<footer role="contentinfo" class="footer-container">/) { $gameon = 0; last; }
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
		# new trophy increment
		#<li class="game-trophies-page__tile-container">
		if ($tok->is_start_tag('li') && $tok->get_attr('class') eq "game-trophies-page__tile-container") {
			$trophyn++;
			$tokn = 0;
			print "SCRAPE_MY $trophyn\n" if $verbose > 2;
			$trophies{$trophyn}{source} = 'my';
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
			# game avatar
			#<img alt="Jeff Hardy's Avatar" src="star_trek_bridge_crew_ps4_files/A0031_m.png" id="ember1167" class="user-tile-sticky-bar__primary-image user-tile-sticky-bar__primary-image--avatar ember-view">
			if ($tok->is_start_tag('img') and $tok->get_attr('class') eq 'user-tile-sticky-bar__primary-image user-tile-sticky-bar__primary-image--avatar ember-view') {
				my $avatar = $tok->get_attr('src');
				$avatar =~ s#.*/##;	# eliminate folder path
				print "SCRAPE_MY avatar=>$avatar\n" if $verbose > 2;
				$game{avatar} = $avatar;
			}

			# game user
			#<span dir="ltr" class="user-tile-sticky-bar__online-id online-id">fritxhardy</span>
			if ($tok->is_start_tag('span') and $tok->get_attr('class') eq 'user-tile-sticky-bar__online-id online-id') {
				my $user = $p->peek(1);
				print "SCRAPE_MY user=>$user\n" if $verbose > 2;
				$game{user} = $user;
			}

			# game image
			#<img src="uncharted_4_a_thiefs_end_ps4_files/0CAA52366C0F14C85A71FACB36BDD29122DF85D6.PNG" alt="" class="game-tile__image">
			if ($tok->is_start_tag('img') && $tok->get_attr('class') eq 'game-tile__image') {
				my $img = $tok->get_attr('src');
				$img = clean_str($img);
				$img =~ s#.*/##;	# eliminate folder path
				print "SCRAPE_MY img=>$img\n" if $verbose > 2;
				$game{img} = $img;
				$game{source} = 'my';
			}

			# game title
			#<h2 title="Star Trek: Bridge Crew" class="game-tile__title">
			if ($tok->is_start_tag('h2') && $tok->get_attr('class') eq 'game-tile__title') {
				my $title = $tok->get_attr('title');
				$title = clean_str($title);
				print "SCRAPE_MY title=>$title\n" if $verbose > 2;
				$game{title} = $title;
			}

			# progress bar
			#<div class="progress-bar__progress-percentage">90%</div>
			if ($tok->is_start_tag('div') and $tok->get_attr('class') eq 'progress-bar__progress-percentage') {
				my $progress = $p->peek(1);
				$progress =~ s/\%//;
				print "SCRAPE_MY progress=>$progress\n" if $verbose > 2;
				$game{progress} = $progress;
			}

			# trophy counts
			#<div class="trophy-count__platinum-tier trophy-count__tier-count">0</div>
			#<div class="trophy-count__gold-tier trophy-count__tier-count">3</div>
			#<div class="trophy-count__silver-tier trophy-count__tier-count">13</div>
			#<div class="trophy-count__bronze-tier trophy-count__tier-count">15</div>
			if ($tok->is_start_tag('div') and $tok->get_attr('class') =~ m/trophy-count__(\S+)-tier trophy-count__tier-count/) {
				my $metal = $1;
				my $count = $p->peek(1);
				print "SCRAPE_MY $metal=>$count\n" if $verbose > 2;
				$game{$metal} = $count;
			}
		}
		else {
			# unlocked true/false
			#<div class="trophy-tile__unlocked-trophy-background"></div>
			#<div class="trophy-tile__locked-trophy-background"></div>
			if ($tok->is_start_tag('div') && $tok->get_attr('class') =~ m/trophy-tile__(\S+)-trophy-background/) {
				# get trophy lock status as well
				my $unlocked = ($1 eq 'unlocked') ? 'true' : 'false';
				print "SCRAPE_MY $trophyn unlocked=>$unlocked\n" if $verbose > 2;
				$trophies{$trophyn}{unlocked} = $unlocked;
			}

			#<img alt="Trophy Icon" src="uncharted_4_a_thiefs_end_ps4_files/E2AC09D649FE91D06F7BCD7236CFC5C1A56B3A06.PNG" class="trophy-tile__image">
			if ($tok->is_start_tag('img') && $tok->get_attr('alt') eq 'Trophy Icon') {
				my $img = $tok->get_attr('src');
				$img =~ s#.*/##;	# eliminate folder path
				print "SCRAPE_MY $trophyn img=>$img\n" if $verbose > 2;
				$trophies{$trophyn}{img} = $img;
			}

			#<div class="trophy-tile__tier-icon trophy-tile__tier-icon--platinum"></div>
			if ($tok->is_start_tag('div') && $tok->get_attr('class') =~ m/trophy-tile__tier-icon--(\S+)/) {
				print "SCRAPE_MY $trophyn metal=>$1\n" if $verbose > 2;
				$trophies{$trophyn}{metal} = $1;
			}

			#<div class="trophy-tile__name">
			#		<div id="ember4195" class="ember-view">  <div class="truncate-multiline--truncation-target"><span class="truncate-multiline--last-line-wrapper"><span>One Last Time</span><button class="truncate-multiline--button-hidden" data-ember-action="" data-ember-action-7060="7060">
			#<!---->  </button></span></div>
			if ($tok->is_start_tag('div') && $tok->get_attr('class') eq 'trophy-tile__name') {
				# lots of needless spanning so peek and cut
				my $name = $p->peek(20);
				$name =~ s/\<button.*//;

				# strip html
				my $hs = HTML::Strip->new();
				$name = $hs->parse( $name );
				$hs->eof;

				# strip leading and trailing space
				$name =~ s/^\s+|\s+$//g;

				# clean non-ascii
				$name = clean_str($name);

				print "SCRAPE_MY $trophyn name=>$name\n" if $verbose > 2;
				$trophies{$trophyn}{name} = $name;
			}

			#<div class="trophy-tile__detail">
	        #		<div id="ember5090" class="ember-view">  <div class="truncate-multiline--truncation-target"><span class="truncate-multiline--last-line-wrapper"><span>Collect All The Trophies</span><button class="truncate-multiline--button-hidden" data-ember-action="" data-ember-action-5091="5091">
			#<!---->  </button></span></div>
			if ($tok->is_start_tag('div') && $tok->get_attr('class') eq 'trophy-tile__detail') {
				# lots of needless spanning so peek and cut
				my $text = $p->peek(20);
				$text =~ s/\<button.*//;

				# strip html
				my $hs = HTML::Strip->new();
				$text = $hs->parse( $text );
				$hs->eof;

				# strip leading and trailing space
				$text =~ s/^\s+|\s+$//g;

				# clean non-ascii
				$text = clean_str($text);

				print "SCRAPE_MY $trophyn text=>$text\n" if $verbose > 2;
				$trophies{$trophyn}{text} = $text;
			}
		}
		$tokn++;
	}
	print "\n--\n\n" if $verbose > 2;

	$game{trophies} = \%trophies;
	return \%game;
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

	my %game;
	my %trophies;

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
			$trophies{$trophyn}{unlocked} = $1;
			$trophies{$trophyn}{source} = 'uk';
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
				$img =~ s#.*/##;	# eliminate folder path
				print "SCRAPE_UK title=>$title img=>$img\n" if $verbose > 2;
				$game{title} = $title;
				$game{img} = $img;
				$game{source} = 'uk';
			}
			
			# game user and avatar
			#<img class="avatar-image" src="resistance_2_uk_files/A0031_002.png" alt="fritxhardy">
			if ($tok->is_start_tag('img') && $tok->get_attr('class') eq 'avatar-image' && $tok->get_attr('src')) {
				my $user = $tok->get_attr('alt');
				my $avatar = $tok->get_attr('src');
				$avatar =~ s#.*/##;	# eliminate folder path
				print "SCRAPE_UK user=>$user\n" if $verbose > 2;
				print "SCRAPE_UK avatar=>$avatar\n" if $verbose > 2;
				$game{user} = $user;
				$game{avatar} = $avatar;
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
				$game{$metal} = $count;
			}
			
			# progress bar
			#<div class="slider" style="width: 42%;">
			if ($tok->is_start_tag('div') && $tok->get_attr('class') eq 'slider') {
				my $progress = $tok->get_attr('style');
				$progress =~ s/.* //;
				$progress =~ s/\%.*//;
				print "SCRAPE_UK progress=>$progress\n" if $verbose > 2;
				$game{progress} = $progress;
			}
		}
		else {
			# image or locked
			#<img src="resistance_2_uk_files/79C5ACB1375731F2778CFBEBBFE1B5BF55D23BAA.PNG" alt="">
			#<img src="resistance_2_uk_files/locked_trophy.png" alt="">
			if ($tok->is_start_tag('img') && $tok->get_attr('src') !~ m/locked/) {
				my $img = $tok->get_attr('src');
				$img =~ s#.*/##;	# eliminate folder path
				print "SCRAPE_UK $trophyn img=>$img\n" if $verbose > 2;
				$trophies{$trophyn}{img} = $img;
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
				$trophies{$trophyn}{metal} = $metal;
				$trophies{$trophyn}{name} = $name;
			}
			
			# trophy text
			#<h2>
			#Kill 40 hybrids in the Single Player Campaign.
			if ($tok->is_start_tag('h2')) {
				my $text = $p->peek(1);
				print "SCRAPE_UK $trophyn text=>$text\n" if $verbose > 2;
				$trophies{$trophyn}{text} = clean_str($text);
			}
		}
		$tokn++;
	}
	print "\n--\n\n" if $verbose > 2;

	$game{trophies} = \%trophies;
	return \%game;
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
sub scrape_us_psn_20150813 {
	my ($htmlfile) = @_;

	my %game;
	my %trophies;

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
			$trophies{$trophyn}{unlocked} = 'true';
			$trophies{$trophyn}{source} = 'us';
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
				#$imgtag =~ m/title="(\S+)".*src="(\S+)"/;	# can no longer rely on order
				$imgtag =~ m/title="(.*?)"/;
				my $title = clean_str($1);
				$imgtag =~ m/src="(.*?)"/;
				my $img = clean_str($1);
				$img =~ s#.*/##;	# eliminate folder path
				print "SCRAPE_US title=>$title img=>$img\n" if $verbose > 2;
				$game{title} = $title;
				$game{img} = $img;
				$game{source} = 'us';
			}
			
			# game user and avatar
			#<img title="fritxhardy" alt="fritxhardy" src="resistance_2_us_files/A0031_m.png" class="avatar-image">
			if ($tok->is_start_tag('img') && $tok->get_attr('class') eq 'avatar-image') {
				my $user = $tok->get_attr('title');
				my $avatar = $tok->get_attr('src');
				$avatar =~ s#.*/##;	# eliminate folder path
				print "SCRAPE_US user=>$user avatar=>$avatar\n" if $verbose > 2;
				$game{user} = $user;
				$game{avatar} = $avatar;
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
				$game{$metal} = $count;
			}
			
			# progress bar
			#<div style="width: 42%;" class="slider">
			if ($tok->is_start_tag('div') && $tok->get_attr('class') eq 'slider') {
				my $progress = $tok->get_attr('style');
				$progress =~ s/.* //;
				$progress =~ s/\%.*//;
				print "SCRAPE_US progress=>$progress\n" if $verbose > 2;
				$game{progress} = $progress;
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
				$trophies{$trophyn}{unlocked} = 'false';
			}
				
			# metal or unknown
			#<span class="trophy-icon trophy-type-bronze">
			#<span class="trophy-icon trophy-type-unknown">
			if ($tok->is_start_tag('span') && $tok->get_attr('class') =~ m/trophy-type-(\S+)/) {
				my $metal = $1;
				print "SCRAPE_US $trophyn metal=>$metal\n" if $verbose > 2;
				$trophies{$trophyn}{metal} = $metal;
			}
			
			# image or locked
			#<img title="Rampage!" alt="Rampage!" src="resistance_2_us_files/79C5ACB1375731F2778CFBEBBFE1B5BF55D23BAA.PNG">
			#<img src="resistance_2_us_files/locked_trophy.png">
			if ($tok->is_start_tag('img') && $tok->get_attr('title') ne '' && $tok->get_attr('title') ne 'Sony') {
				my $img = $tok->get_attr('src');
				$img =~ s#.*/##;	# eliminate folder path
				print "SCRAPE_US $trophyn img=>$img\n" if $verbose > 2;
				$trophies{$trophyn}{img} = $img;
			}
			
			# trophy name
			#<h1 class="trophy_name bronze">
			#Rampage!
			if ($tok->is_start_tag('h1') && $tok->get_attr('class') =~ m/trophy_name/) {
				#print $tok->as_is()."\n";
				my $name = $p->peek(1);
				print "SCRAPE_US $trophyn name=>$name\n" if $verbose > 2;
				$trophies{$trophyn}{name} = clean_str($name);
			}
			
			# trophy text
			#<h2>
			#Kill 40 hybrids in the Single Player Campaign.
			if ($tok->is_start_tag('h2')) {
				#print $tok->as_is()."\n";
				my $text = $p->peek(1);
				print "SCRAPE_US $trophyn text=>$text\n" if $verbose > 2;
				$trophies{$trophyn}{text} = clean_str($text);
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
				$trophies{$trophyn}{date} = "$date $time";
			}
		}
		$tokn++;
	}
	print "\n--\n\n" if $verbose > 2;

	$game{trophies} = \%trophies;
	return \%game;
}

sub write_html {
	my ($web,$games) = @_;

	my @titles;
	foreach my $g (keys %$games) {
		my %game = %{$games{$g}};
		push(@titles,$game{title});
	}
	my $title = join(',',@titles);

	open (my $out,">$web/index.html") or die "ERROR: Cannot write $web/index.html: $!\n";

	print $out <<EOT;
<html>
<head>
<title>$title</title>
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
EOT

	foreach my $g (keys %$games) {
		my %game = %{$games{$g}};
		my $ttot = $game{platinum}+$game{gold}+$game{silver}+$game{bronze};
		my $caption = $game{caption} ? $game{caption} : '';

		#print $out "$game{title} $game{img} $game{user} $game{avatar} bronze:$game{bronze} silver:$game{silver} gold:$game{gold} platinum:$game{platinum} progress:$game{progress}\n";

		# strip image paths now that we are writing html
		#$game{img} =~ s#.*/##;
		#$game{avatar} =~ s#.*/##;

		print $out "<div class=\"bannerrow\">\n";

		print $out "\t<div class=\"gamegraphic\">\n";
		print $out "\t\t<div class=\"gamegraphic_img\">\n";
		print $out "\t\t\t<img src=\"$game{img}\" title=\"$game{title}\" alt=\"$game{title}\" width=\"167\" height=\"92\">\n";
		print $out "\t\t</div>\n";
		print $out "\t</div>\n";

		print $out "\t<div class=\"gameinfo\">\n";

		print $out "\t\t<div class=\"gameinfo_title\">\n";
		print $out "\t\t\t$game{title}<br>\n";
		print $out "\t\t</div>\n";

		print $out "\t\t<div class=\"gameinfo_avatar\">\n";
		print $out "\t\t\t<img src=\"$game{avatar}\" title=\"$game{user}\" alt=\"$game{user}\" width=\"25\" height=\"25\">\n";
		print $out "\t\t</div>\n";

		print $out "\t\t<div class=\"gameinfo_user\">\n";
		print $out "\t\t$game{user}\n";
		print $out "\t\t</div>\n";

		print $out "\t\t<div class=\"gameinfo_progressbar\">\n";
		print $out "\t\t\t<div class=\"gameinfo_progressslider\" style=\"width: $game{progress}%\"></div>\n";
		print $out "\t\t</div>\n";
		print $out "\t\t<div class=\"gameinfo_progresstext\">$game{progress}%</div>\n";

		print $out "\t</div>\n";

		print $out "\t<div class=\"gametrophygraph\">\n";
		print $out "\t\t<div class=\"gametrophygraph_mini\" style=\"right:41px;bottom:66px;\"><img src=\"trophy_mini_platinum.png\"></div>\n";
		print $out "\t\t<div class=\"gametrophygraph_bar\" style=\"width:61px;bottom:52px;\">$game{platinum} Platinum</div>\n";
		print $out "\t\t<div class=\"gametrophygraph_mini\" style=\"right:77px;bottom:50px;\"><img src=\"trophy_mini_gold.png\"></div>\n";
		print $out "\t\t<div class=\"gametrophygraph_bar\" style=\"width:97px;bottom:36px;\">$game{gold} Gold</div>\n";
		print $out "\t\t<div class=\"gametrophygraph_mini\" style=\"right:113px;bottom:34px;\"><img src=\"trophy_mini_silver.png\"></div>\n";
		print $out "\t\t<div class=\"gametrophygraph_bar\" style=\"width:133px;bottom:20px;\">$game{silver} Silver</div>\n";
		print $out "\t\t<div class=\"gametrophygraph_mini\" style=\"right:149px;bottom:18px;\"><img src=\"trophy_mini_bronze.png\"></div>\n";
		print $out "\t\t<div class=\"gametrophygraph_bar\" style=\"width:169px;bottom:4px;\">$game{bronze} Bronze</div>\n";
		print $out "\t\t<div class=\"gametrophygraph_total\">$ttot</div>\n";
		print $out "\t</div>\n";

		print $out "</div>\n";

		print $out <<EOT;
<div class="captionrow">
	<span class="captiontext"><p>$caption</p></span>
</div>
EOT

		my %trophies = %{$game{trophies}};
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

=head1 NAME

psnextract

=head1 SYNOPSIS

Firefox save trophy game page from PSN US:

 save-as web-page-complete: gamedata-us.html (gamedata-us_files)

Parse data and output to webdir with included graphics:

 psnextract.pl --us gamedata-us.html --include includedir \
 --web outputdir

Combination with UK data:

 psnextract.pl --us gamedata-us.html --uk gamedata-uk.html \
 --include includedir --web outputdir

Designate file for override variables:

 psnextract.pl --us gamedata-us.html --uk gamedata-uk.html \
 --include includdir --override override.txt --web outputdir

=head1 DESCRIPTION

Psnextract is a tool intended to gather trophy data from PlayStation Network, 
parsing downloaded html for use building external web pages.  It is able to 
parse and merge output from both the US and UK sites, and data can be 
overridden at will.

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

File of UK PSN html save-as web-page-complete data to parse.  Assumes Firefox 
format, with file uk_psn.html and accompanying directory uk_psn_files.

=item B<--us=/path/to/us_psn.html>

File of US PSN html save-as web-page-complete data to parse.  Assumes Firefox 
format, with file us_psn.html and accompanying directory us_psn_files.

=item B<-v, --verbose>

Control vebosity of output.  Increase by passing multiple times. 

=item B<-w, --web=/path/to/webdir>

Web destination to which include graphics and items are copied, and inside 
which index.html is written from parsed data.

=back

=head1 HTML SOURCES

Source HTML data is that seen when browsing to specific game/trophy progress 
when logged into us.playstation.com and/or uk.playstation.com, and saving the 
web page with Firefox 'web-page-complete' facility.  This results in an .html 
file and accompanying _files directory containing graphics and css.

The reason for supporting both US and UK trophy data sources and features for 
merging them and overlaying overrides is the following observation:

 US: Datestamps, bigger trophy graphics, often missing or delayed DLC
 UK: No datestamps, abbreviated trophy titles, always up-to-date DLC 

The main issue is missing DLC.  As such, the sources are overlayed on top of 
one another: UK -> US -> overrides.  UK data to provide data for all 
trophies minus datestamps, US to fill in missing datestamps and provide nicer 
graphics, and lastly overrides to fill in any missing info.

In most cases, US data is all that is needed to provide all info.

NOTE: In the current version of the US site, ensure you scroll down to click 
'MORE' to show all trophies before saving the page.  Otherwise the div does not 
contain all information and trophies will be missing.

=head1 OVERRIDES

The overrides facility is used to provide missing info, corrections, addendums, 
and any caption desired for web output.  Overrides are one per line, in format 
item|attribute=value.  Example specifying most possible overrides:

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
dates.

=head1 EXAMPLES

Parse US PSN data:

 psnextract.pl --us=gamedata_us.html

See lots of verbose output:

 psnextract.pl -v -v -v -v --us=gamedata_us.html

Also parse UK PSN data:

 psnextract.pl --us=gamedata_us.html --uk=gamedata_uk.html

Add in overrides:

 psnextract.pl --us=gamedata_us.html --uk=gamedata_uk.html \
 --override=override.txt

Now build a web page with it all:

 psnextract.pl --us=gamedata_us.html --uk=gamedata_uk.html \
 --override=override.txt --web=webdir

Include graphics for complete html output:

 psnextract.pl --us=gamedata_us.html --uk=gamedata_uk.html \
 --override=override.txt --include=includedir --web=webdir

=head1 CHANGES

21041007

-Complete perldocs, pod2text README

93c715124cb18143d9b02ffc5363b75f366a7c89 (20140927)

-Initial release

=cut
