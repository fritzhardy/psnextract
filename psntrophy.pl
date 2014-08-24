#!/usr/bin/perl
# psntrophy.pl
# Aug 20, 2011 4:55:10 PM
# jeff hardy (jeff at fritzhardy dot com)
# scrape downloaded psn trophy page into hash and build custom html output

use strict;
use Getopt::Long;
use HTML::TokeParser::Simple;

my $script_name = $0; $script_name =~ s/.*\///;
my $usage = sprintf <<EOT;
$script_name OPTIONS --us|--uk=/psn.html
	-a, --addendum=/path/to/addendum
		flat text file of game and trophy addendums and corrections
	-d, --dryrun
		show what would be done
	-h, --help
		this help message
	-i, --include=/path/to/include/graphics
		path to provided graphics when building web
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
my $addendum;
my $dryrun;
my $help;
my $include;
my $uk;	# path to uk html file
my $us;	# path to us html file
my $verbose;
my $web;
my $getopt = GetOptions(
	"addendum=s"=>\$addendum,
	"dryrun"=>\$dryrun,
	"help"=>\$help,
	"include=s"=>\$include,
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
	die "Error: Require one of us or uk else nothing to do.\n\n$usage";	
}

# global hash of trophy types to filename
my %trophy_imgmap = (
	default => 'trophy_mini_default.png',	# faded, unearned
	bronze => 'trophy_mini_bronze.png',
	silver => 'trophy_mini_silver.png',
	gold => 'trophy_mini_gold.png',
	platinum => 'trophy_mini_platinum.png',
	unknown => '',
);

# global hash into which game info gleaned from 
# us and uk scrapes is stored for use in the web masthead
my %game;

# build us/uk hashes from html save-as-webpage data
my %trophies_us = scrape_us_psn_20140607($us) if $us;
my %trophies_uk = scrape_uk_psn_20140607($uk) if $uk;

# build addendums hash from local file
my %trophies_add = parse_trophy_addendum($addendum) if ($addendum);

# continue to see the following:
# us: datestamps, bigger trophy graphics, often misses dlc
# uk: dlc, no datestamps
# add: local file to add datestamps and other gamedata
# therefore we overlay for precedence: uk -> us -> add
my %trophies;
if (%trophies_uk) {
	foreach my $n (sort {$a <=> $b} (keys(%trophies_uk))) {
		if ($verbose) {
			#print STDERR "$_:${$trophies_uk{$_}}{img}:\n";
			my %trophy = %{$trophies_uk{$n}};
			foreach (sort(keys(%trophy))) {
				print "UK: $n $_=>$trophy{$_}\n";
			}
			print "\n";
		}
		$trophies{$n} = $trophies_uk{$n};
	}
}
if (%trophies_us) {
	foreach my $n (sort {$a <=> $b} (keys(%trophies_us))) {
		if ($verbose) {
			#print STDERR "$_:${$trophies_us{$_}}{img}:\n";
			my %trophy = %{$trophies_us{$n}};
			foreach (sort(keys(%trophy))) {
				print "US: $n $_=>$trophy{$_}\n";	
			}
			print "\n";
		}
		$trophies{$n} = $trophies_us{$n};
	}
}
if (%trophies_add) {
	foreach my $n (sort {$a <=> $b} (keys(%trophies_add))) {
		my %trophy = %{$trophies_add{$n}};
		foreach (sort(keys(%trophy))) {
			print "AD: $n $_=>$trophy{$_}\n" if $verbose;
			$trophies{$n}{$_} = $trophy{$_};	# apply individual attr value
		}
		print "\n" if $verbose;
	}
}

# pure debugging final result
if ($verbose) {
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

# build a nice web page
build_web ($web,\%game,\%trophies,$include) if $web;

sub build_web {
	my ($web,$game,$trophies,$include) = @_;
	
	my ($title,$caption);
	
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
	
	open (my $out,">$web/index.html") or die "ERROR: Cannot write $web/index.html: $!\n";
#	my $caption = '&nbsp';
#	if (-f $captions) {
#		$/ = undef;
#		open (FH,$captions) or warn "Cannot open $captions: $!\n";
#		$caption = <FH>;
#		close (FH);
#		$/ = "\n";
#		$caption =~ s/\n/<br>\n/g;
#	}
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
	min-height: 96px;
	border-top: 2px solid #dddddd;
	border-bottom: 2px solid #dddddd;
}
.captionrow {
	clear: both;
	width: 780px;
	min-height: 2px;
	border-bottom: 2px solid #dddddd;
}
.captiontext {
	margin: 5px 5px 5px 5px;
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
}
</style>
<body>
<div class="table">
<div class="bannerrow">
EOT

print $out "$game{title} $game{img} $game{user} $game{avatar} bronze:$game{bronze} silver:$game{silver} gold:$game{gold} platinum:$game{platinum} progress:$game{progress}\n";

print $out <<EOT;
</div>
<div class="captionrow">
	<span class="captiontext">$caption</span>
</div>
EOT

foreach (sort {$a <=> $b} (keys(%trophies))) {
	my %trophy = %{$trophies{$_}};
	print $out "<div class=\"trophyrow\">\n";
	print $out "\t<div class=\"trophyimage\"><img src=\"".$trophy{img}."\" alt=\"".$trophy{text}."\" title=\"".$trophy{text}."\"></div>\n";
	print $out "\t<div class=\"trophytitle\"><span class=\"trophyname\">".$trophy{name}."</span><br><span class=\"trophytext\">".$trophy{text}."</span></div>\n";
	
	print $out "\t<div class=\"trophydate\">".$trophy{date}."</div>\n";
	
	print $out "\t<div class=\"trophygrid\">\n";
	print $out print_trophy_grid($out,$trophy{metal},$trophy{date});
	print $out "\t</div>\n";
#	if ($trophy{date}) {
#		print "\t<div class=\"trophydate\">".$trophy{date}."</div>\n";
#		print "\t<div class=\"trophyicon\"><img src=\"".$trophy_imgmap{$trophy{metal}}."\" alt=\"".$trophy{metal}."\" title=\"".$trophy{metal}."\"></div>\n";
#	} else {
#		print "\t<div class=\"trophydate\">&nbsp;</div>\n";
#		print "\t<div class=\"trophyicon\"><img src=\"".$trophy_imgmap{DEFAULT}."\" alt=\"".$trophy{metal}."\" title=\"".$trophy{metal}."\"></div>\n";
#	}
	print $out "</div>\n";
}

print $out <<EOT;
</div>
</body>
</html>
EOT
}

sub parse_trophy_corrections {
	my ($corrections) = @_;
	my %corrections;
	open (FH,$corrections) or die "Cannot open $corrections: $!\n";
	while (<FH>) {
		chomp();
		my ($trophynum,@atoms) = split(/\|/,$_);
		foreach (@atoms) {
			my ($attr,$val) = split(/\=/,$_);
			$corrections{$trophynum}{$attr} = $val;
		}
	}
	close (FH);
	return %corrections;
}
	

sub print_trophy_grid {
	my ($metal,$date) = @_;
	my $trophy_icon = $date ? $trophy_imgmap{$metal} : $trophy_imgmap{DEFAULT};
	
	my %metal_weight = (
		DEFAULT => 0,
		BRONZE => 1,
		SILVER => 2,
		GOLD => 3,
		PLATINUM => 4,
	);
	
	for (my $t = 1; $t <= 4; $t++) {
		if ($t == $metal_weight{$metal}) {
			return "\t\t<div class=\"trophyicon\"><img src=\"".$trophy_icon."\" alt=\"".$metal."\" title=\"".$metal."\"></div>\n";
		} else {
			return "\t\t<div class=\"trophyicon\">&nbsp;</div>\n";
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
			$htmlstr .= $_;
		}
	}
	close ($fh);
	
	# Trophy row html blocks follow.  It is probably better not to 
	# construct a new object over and over and instead just parse 
	# the whole doc, but since we have isolate the html out of the 
	# trophy table row-by-row, it is easier to digest, and we 
	# number trophies by row number besides, so oh well.
	my @rows = split(/\<tr class=\"trophy-tr\"\>/,$htmlstr);
	my %trophies;
	my $trophyn = 0;
	foreach my $r (@rows) {
		print "$r\n\n" if $verbose > 3;	
		my $p = HTML::TokeParser::Simple->new(\$r);
		my $tokn = 0;
		while ( my $tok = $p->get_token ) {
			if ($verbose > 2) {
				my $asis = $tok->as_is();
				my $tag = $tok->get_tag();
				my $hash = $tok->get_attr();
				my $class = $tok->get_attr('class');
				print "$trophyn $tokn $asis | tag:$tag class:$class\n";
			}
			
			# First row html block is filled with special bits like 
			# percentage, trophy counts, etc, which we stuff into the 
			# global %game hash for use in the masthead.
			if ($trophyn == 0) {
				# game title and image
				#<div class="game-image">
				#<img title="Resistance 2TM" alt="Resistance 2TM" src="resistance_2_us_files/8F0B2E25C3524F1EF9EE87AD1999F7FD8A5EC4F8.PNG">
				if ($tok->is_start_tag('div') && $tok->get_attr('class') eq 'game-image') {
					my $imgtag = $p->peek(1);
					$imgtag =~ m/title="(.*)" alt.* src="(.*)"/;
					my $title = clean_str($1);
					my $img = clean_str($2);
					$img =~ s#.*/##;	# eliminate folder path
					print "SCRAPE_US gametitle=>$title gameimg=>$img\n" if $verbose > 1;
					$game{title} = $title;
					$game{img} = $img;
				}
				
				# game user and avatar
				#<img title="fritxhardy" alt="fritxhardy" src="resistance_2_us_files/A0031_m.png" class="avatar-image">
				if ($tok->is_start_tag('img') && $tok->get_attr('class') eq 'avatar-image') {
					my $user = $tok->get_attr('title');
					my $avatar = $tok->get_attr('src');
					$avatar =~ s#.*/##;	# eliminate folder path
					print "SCRAPE_US user=>$user avatar=>$avatar\n" if $verbose > 1;
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
					if (!exists($trophy_imgmap{$metal})) { next; }
					my $count = $p->peek(1);
					print "SCRAPE_US $metal=>$count\n" if $verbose > 1;
					$game{$metal} = $count;
				}
				
				# progress bar
				#<div style="width: 42%;" class="slider">
				if ($tok->is_start_tag('div') && $tok->get_attr('class') eq 'slider') {
					my $progress = $tok->get_attr('style');
					$progress =~ s/.* //;
					$progress =~ s/\%.*//;
					print "SCRAPE_US progress=>$progress\n" if $verbose > 1;
					$game{progress} = $progress;
				}
			}
			else {		
				# metal or unknown
				#<span class="trophy-icon trophy-type-bronze">
				#<span class="trophy-icon trophy-type-unknown">
				if ($tok->is_start_tag('span') && $tok->get_attr('class') =~ m/trophy-type-(\S+)/) {
					my $metal = $1;
					print "SCRAPE_US $trophyn metal=>$metal\n" if $verbose > 1;
					$trophies{$trophyn}{metal} = $metal;
				}
				
				# image or locked
				#<img title="Rampage!" alt="Rampage!" src="resistance_2_us_files/79C5ACB1375731F2778CFBEBBFE1B5BF55D23BAA.PNG">
				#<img src="resistance_2_us_files/locked_trophy.png">
				if ($tok->is_start_tag('img') && $tok->get_attr('title') ne '') {
					my $img = $tok->get_attr('src');
					$img =~ s#.*/##;	# eliminate folder path
					print "SCRAPE_US $trophyn img=>$img\n" if $verbose > 1;
					$trophies{$trophyn}{img} = $img;
				}
				
				# trophy name
				#<h1 class="trophy_name bronze">
				#Rampage!
				if ($tok->is_start_tag('h1') && $tok->get_attr('class') =~ m/trophy_name/) {
					#print $tok->as_is()."\n";
					my $name = $p->peek(1);
					print "SCRAPE_US $trophyn name=>$name\n" if $verbose > 1;
					$trophies{$trophyn}{name} = clean_str($name);
				}
				
				# trophy text
				#<h2> | tag:h2 class:
				#Kill 40 hybrids in the Single Player Campaign.
				if ($tok->is_start_tag('h2')) {
					#print $tok->as_is()."\n";
					my $text = $p->peek(1);
					print "SCRAPE_US $trophyn text=>$text\n" if $verbose > 1;
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
					print "SCRAPE_US $trophyn date=>$date $time\n" if $verbose > 1;
					$trophies{$trophyn}{date} = "$date $time";
				}
			}
			$tokn++;
		}
		# track the trophy source in case it is overlaid later
		unless ($trophyn == 0) {
			print "SCRAPE_US $trophyn src=>$us\n" if $verbose > 1;
			$trophies{$trophyn}{src} = $us;
		} 
		
		$trophyn++;
		print "\n\n" if $verbose > 1;
	}
	return %trophies;
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
