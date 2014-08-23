#!/usr/bin/perl
# ps3trophy.pl
# Aug 20, 2011 4:55:10 PM
# jeff hardy (hardyjm at potsdam dot edu)
# scrape downloaded psn trophy page and build hash for html output

use strict;
use Getopt::Long;
use HTML::TokeParser::Simple;

my $script_name = $0;
$script_name =~ s/.*\///;
my $num_args = scalar(@ARGV);

my $corrections;
my $dryrun;
my $help;
my $verbose;
my $path;
my $web;
my $getopt = GetOptions(
	"corrections=s"=>\$corrections,
	"dryrun"=>\$dryrun,
	"help"=>\$help,
	"path"=>\$path,
	"verbose+"=>\$verbose,
	"web=s"=>\$web,
) or die "Invalid arguments\n";
die "Error processing arguments\n" unless $getopt;

my $usage = sprintf <<EOT;
$script_name OPTIONS
	-c, --corrections
		flat text file of trophy corrections
	-d, --dryrun
		show what would be done
	-h, --help
		this help message
	-v, --verbose
		increase verbosity
	-p, --path
		strip paths down to basename for images and such
	-w, --web=title,banner,captions
		print html to STDOUT

Use a web browser to save-as-complete web page the PSN trophies page for game.
Copy the game_trophies.html page into the destination web folder.
Copy the trophy PNG files into the destination web folder.
Copy the previously downloaded mini_trophy.png files into the destination web folder.
Save a screenshot of the banner logo, write some text into captions.txt.

Example:
cat game_trophies.html | $script_name -p -w "title,banner,captions.txt" > index.html
 
EOT

if ($help) {
	die $usage;
}

my %trophy_imgmap = (
	default => 'mini_default.png',
	bronze => 'mini_bronze.png',
	silver => 'mini_silver.png',
	gold => 'mini_gold.png',
	platinum => 'mini_platinum.png',
	unknown => '',
);

my %game;	# stores masthead info
my %trophies_us;
my %trophies_uk;

# parse the "save-as-complete" webpage from psn scrape into the above hashes
scrape_20140607();

my %trophies_corrections;
if ($corrections and -e $corrections) {
	open (FH,$corrections) or die "Cannot open $corrections: $!\n";
	while (<FH>) {
		chomp();
		my ($trophynum,@atoms) = split(/\|/,$_);
		foreach (@atoms) {
			my ($attr,$val) = split(/\=/,$_);
			$trophies_corrections{$trophynum}{$attr} = $val;
		}
	}
	close (FH);
}

if ($verbose > 1) {
	foreach (sort {$a <=> $b} (keys(%trophies_us))) {
		print STDERR "$_:\n";
		#print "\t".$trophies{$_}{img}."\n";
		#print "\t".$trophies{$_}{title}."\n";
		my %trophy = %{$trophies_us{$_}};
		foreach (sort(keys(%trophy))) {
			print STDERR "\t$_: $trophy{$_}\n";
		}
	}
	foreach (sort {$a <=> $b} (keys(%trophies_uk))) {
		print STDERR "$_:\n";
		#print "\t".$trophies{$_}{img}."\n";
		#print "\t".$trophies{$_}{title}."\n";
		my %trophy = %{$trophies_uk{$_}};
		foreach (sort(keys(%trophy))) {
			print STDERR "\t$_: $trophy{$_}\n";
		}
	}
	foreach (sort {$a <=> $b} (keys(%trophies_corrections))) {
		print STDERR "$_:\n";
		#print "\t".$trophies{$_}{img}."\n";
		#print "\t".$trophies{$_}{title}."\n";
		my %trophy = %{$trophies_corrections{$_}};
		foreach (sort(keys(%trophy))) {
			print STDERR "\t$_: $trophy{$_}\n";
		}
	}
}

# the lazy fucks at us.playstation.com have incomplete 
# listings so we overlay: uk -> us -> corrections (US has bigger graphics)
my %trophies;
if (%trophies_uk) {
	foreach (sort {$a <=> $b} (keys(%trophies_uk))) {
		#print STDERR "$_:${$trophies_uk{$_}}{img}:\n";
		$trophies{$_} = $trophies_uk{$_};
	}
}
if (%trophies_us) {
	foreach (sort {$a <=> $b} (keys(%trophies_us))) {
		#print STDERR "$_:${$trophies_us{$_}}{img}:\n";
		$trophies{$_} = $trophies_us{$_};
	}
}
if (%trophies_corrections) {
	foreach my $t (sort {$a <=> $b} (keys(%trophies_corrections))) {
		#print STDERR "$_:${$trophies_us{$_}}{img}:\n";
		#$trophies{$_} = $trophies_corrections{$_};
		my %trophy = %{$trophies_corrections{$t}};
		foreach (sort(keys(%trophy))) {
			#print STDERR "\t$_: $trophy{$_}\n";
			$trophies{$t}{$_} = $trophy{$_};	# apply attr
		}
	}
}

if ($verbose) {
	foreach (sort {$a <=> $b} (keys(%trophies))) {
		print STDERR "$_:\n";
		#print "\t".$trophies{$_}{img}."\n";
		#print "\t".$trophies{$_}{title}."\n";
		my %trophy = %{$trophies{$_}};
		foreach (sort(keys(%trophy))) {
			print STDERR "\t$_: $trophy{$_}\n";
		}
	}
}

# build a nice web page
if ($web) {
	my ($title,$banner,$captions) = split(/,/,$web);
	my $caption = '&nbsp';
	if (-f $captions) {
		$/ = undef;
		open (FH,$captions) or warn "Cannot open $captions: $!\n";
		$caption = <FH>;
		close (FH);
		$/ = "\n";
		$caption =~ s/\n/<br>\n/g;
	}
print <<EOT;
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
	<img src="$banner" alt="$title" title="$title">
</div>
<div class="captionrow">
	<span class="captiontext">$caption</span>
</div>
EOT
foreach (sort {$a <=> $b} (keys(%trophies))) {
	my %trophy = %{$trophies{$_}};
	print "<div class=\"trophyrow\">\n";
	print "\t<div class=\"trophyimage\"><img src=\"".$trophy{img}."\" alt=\"".$trophy{text}."\" title=\"".$trophy{text}."\"></div>\n";
	print "\t<div class=\"trophytitle\"><span class=\"trophyname\">".$trophy{name}."</span><br><span class=\"trophytext\">".$trophy{text}."</span></div>\n";
	
	print "\t<div class=\"trophydate\">".$trophy{date}."</div>\n";
	
	print "\t<div class=\"trophygrid\">\n";
	print_trophy_grid($trophy{metal},$trophy{date});
	print "\t</div>\n";
#	if ($trophy{date}) {
#		print "\t<div class=\"trophydate\">".$trophy{date}."</div>\n";
#		print "\t<div class=\"trophyicon\"><img src=\"".$trophy_imgmap{$trophy{metal}}."\" alt=\"".$trophy{metal}."\" title=\"".$trophy{metal}."\"></div>\n";
#	} else {
#		print "\t<div class=\"trophydate\">&nbsp;</div>\n";
#		print "\t<div class=\"trophyicon\"><img src=\"".$trophy_imgmap{DEFAULT}."\" alt=\"".$trophy{metal}."\" title=\"".$trophy{metal}."\"></div>\n";
#	}
	print "</div>\n";
}
print <<EOT;
</div>
</body>
</html>
EOT
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
			print "\t\t<div class=\"trophyicon\"><img src=\"".$trophy_icon."\" alt=\"".$metal."\" title=\"".$metal."\"></div>\n";
		} else {
			print "\t\t<div class=\"trophyicon\">&nbsp;</div>\n";
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

sub scrape_2012 {
	my $us;
	my $trophyn_us = 0;
	my $hidden = 0;
	my $locked = 0;
	
	my $uk;
	my $trophyn_uk = 0;
	
	while (<STDIN>) {
		# us.playstation.com
		if (m# href="http://us.playstation.com/playstation/psn/profiles/fritxhardy/trophies"#) {
			$us = 1;
			$uk = 0;
		}
		if ($us) {
			# slot determines visibility
			if (m/div class="slot\s+(.*)"/) {
				if (!$1) {
					$hidden = 0;
				} elsif ($1 eq "hiddenTrophy") {
					$hidden = 1;
				}
				$trophyn_us++;
			}
			# slotcontent determines locked/unlocked
			if (m/div class="slotcontent\s+(.*)"/) {
				if (!$1) {
					$locked = 1;
				} elsif ($1 eq "showTrophyDetail") {
					$locked = 0;
				}
			}
			# we are into the trophy section at least
			if ($trophyn_us) {
				if (m/img.*src="(\S+)".*\>/) {
					my $img = $1;
					$img =~ s#.*/## if ($path);
					$trophies_us{$trophyn_us}{img} = $img;
				}
				if ($hidden && $locked) {	# reset with every line until next trophy, so what?
					$trophies_us{$trophyn_us}{text} = '???';
				}
				else {
					if (m/span class="trophyTitleSortField"\>(.*)<\/span\>/) {
						$trophies_us{$trophyn_us}{text} = clean_str($1);
					}
					elsif (m/span class="subtext"\>(.*)<\/span\>/ || m/span class="subtext"\>(.*)$/) {
						$trophies_us{$trophyn_us}{subtext} = clean_str($1);
					}
					elsif (m/span class="dateEarnedSortField".*\>(.*)<\/span\>/) {
						$trophies_us{$trophyn_us}{date} = $1;
					}
					elsif (m/BRONZE|SILVER|GOLD|PLATINUM/) {
						my $metal = $_;
						$metal =~ s/\s+//g;
						$trophies_us{$trophyn_us}{metal} = $metal;
					}
				}
			}
			if (m/<p class="profile_note">Note: The above information is dependent/) {
				$us = 0;
			}
		}
	
		# uk.playstation.com
		if (m# href="http://uk.playstation.com/psn/mypsn/trophies/detail/"#) {
			$uk = 1;
			$us = 0;
		}
		if ($uk == 1) {
			if (m/div class="gameLevelListItem"/) {
				$trophyn_uk++;
			}
			if ($trophyn_uk) {
				if (m/div class="gameLevelImage".*src="(.*)"\s+/) {
					my $img = $1;
					$img =~ s#.*/## if ($path);
					$img =~ s/icon_trophy_padlock.gif/trophy_locksmall.png/ if ($img =~ m/icon_trophy_padlock.gif/);
					$trophies_uk{$trophyn_uk}{img} = $img;
				}
				elsif (m/div class="gameLevelTrophyType".*alt="(.*)"/) {
					my $metal = $1;
					$metal = uc($metal);
					$trophies_uk{$trophyn_uk}{metal} = $metal;
				}
				elsif (m/<p class="title">(.*)<\/p>/) {
					$trophies_uk{$trophyn_uk}{text} = clean_str($1);
				}
				elsif (m/<p class="date">(.*)<\/p>/) {
					$trophies_uk{$trophyn_uk}{date} = clean_str($1);
				}
				elsif (m/^\s+<p>(.*)<\/p>$/ || m/^\s+<p>(.*)$/) {
					$trophies_uk{$trophyn_uk}{subtext} = clean_str($1);
				}
			}
			if (m/div class="sortBarHatchedBtm"/) {
				$uk = 0;
			}
		}
	}
}

sub scrape_20140607 {
# 2014-06-07 USA
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

	my $country = '';
	my $trophyn_us = 0;
	my $hidden = 0;
	my $locked = 0;
	my $trophyn_uk = 0;

	while (<STDIN>) {
		# us.playstation.com
		if (m#.* href="https://secure.cdn.us.playstation.com/.*"#) {
			$country = 'us';
		}
		if ($country eq 'us') {
			if (m/table-overflow-wrapper clearfix/) { # one giant mess of a line
				my @rows = split(/\<tr class=\"trophy-tr\"\>/,$_);
				
				# Trophy row html blocks follow.  It is probably better not to 
				# construct a new object over and over and instead just parse 
				# the whole doc, but since we can isolate the html out of the 
				# trophy table row-by-row, it is easier to digest, and we 
				# number trophies by row number besides, so oh well.
				my $trophyn = 0;
				foreach my $r (@rows) {
					print "$r\n\n" if $verbose > 1;	
					my $p = HTML::TokeParser::Simple->new(\$r);
					my $tokn = 0;
					while ( my $tok = $p->get_token ) {
						if ($verbose > 1) {
							my $asis = $tok->as_is();
							my $tag = $tok->get_tag();
							my $hash = $tok->get_attr();
							my $class = $tok->get_attr('class');
							print "$trophyn $tokn $asis | tag:$tag class:$class\n";
						}
						
						# First row html block is filled with special bits like 
						# percentage, trophy counts, etc, which we use to build 
						# the page masthead.
						if ($trophyn == 0) {
							# game title and image
							#<div class="game-image">
							#<img title="titleTM" alt="titleTM" src="folder/XXX.PNG">
							if ($tok->is_start_tag('div') && $tok->get_attr('class') eq 'game-image') {
								my $imgtag = $p->peek(1);
								$imgtag =~ m/title="(.*)" alt.* src="(.*)"/;
								my $title = clean_str($1);
								my $img = clean_str($2);
								$img =~ s#.*/##;	# eliminate folder path
								print "DEBUG: gametitle=>$title gameimg=>$img\n";
								$game{title} = $title;
								$game{img} = $img;
							}
							
							# game user and avatar
							#<img title="fritxhardy" alt="fritxhardy" src="folder/XXX.png" class="avatar-image">
							if ($tok->is_start_tag('img') && $tok->get_attr('class') eq 'avatar-image') {
								my $user = $tok->get_attr('title');
								my $avatar = $tok->get_attr('src');
								$avatar =~ s#.*/##;	# eliminate folder path
								print "DEBUG: user=>$user avatar=>$avatar\n";
								$game{user} = $user;
								$game{avatar} = $avatar;
							}
							
							# trophy counts
							#<li class="bronze"> ... <li class="silver"> 
							#XX
							if ($tok->is_start_tag('li')) {
								my $metal = $tok->get_attr('class');
								if (!exists($trophy_imgmap{$metal})) { next; }
								my $count = $p->peek(1);
								print "DEBUG: $metal=>$count\n";
								$game{$metal} = $count;
							}
							
							# progress bar
							#<div style="width: 16%;" class="slider">
							if ($tok->is_start_tag('div') && $tok->get_attr('class') eq 'slider') {
								my $progress = $tok->get_attr('style');
								$progress =~ s/.* //;
								$progress =~ s/\%.*//;
								print "DEBUG: progress=>$progress\n";
								$game{progress} = $progress;
							}
						}
						else {								
							# metal or unknown
							#<span class="trophy-icon trophy-type-bronze">
							#<span class="trophy-icon trophy-type-unknown">
							if ($tok->is_start_tag('span') && $tok->get_attr('class') =~ m/trophy-type-(\S+)/) {
								my $metal = $1;
								print $metal."\n";
								$trophies_us{$trophyn}{metal} = $metal;
							}
							
							# image or locked
							#<img title="Let's gear up" alt="Let's gear up" src="the_last_of_us_usa_files/BDF3999478A771D79C603B0B882930D3E827D241.PNG">
							#<img src="the_last_of_us_usa_files/locked_trophy.png">
							if ($tok->is_start_tag('img') && $tok->get_attr('title') ne '') {
								my $img = $tok->get_attr('src');
								$img =~ s#.*/##;
								#print $img."\n";
								$trophies_us{$trophyn}{img} = $img;
							}
							
							# trophy name
							#<h1 class="trophy_name bronze">
							#Rampage!
							if ($tok->is_start_tag('h1') && $tok->get_attr('class') =~ m/trophy_name/) {
								#print $tok->as_is()."\n";
								my $name = $p->peek(1);
								print $name."\n";
								$trophies_us{$trophyn}{name} = clean_str($name);
							}
							
							# trophy text
							#<h2> | tag:h2 class:
							#Kill 40 hybrids in the Single Player Campaign.
							if ($tok->is_start_tag('h2')) {
								#print $tok->as_is()."\n";
								my $text = $p->peek(1);
								print $text."\n";
								$trophies_us{$trophyn}{text} = clean_str($text);
							}
							
							# gamedetails
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
								my $d = $p->peek(11);
								print "$d\n";
								$d =~ s#.*Trophy Earned</p><p class="">##;
								my ($date,$time) = split(/<\/p><p class="">/,$d);
								print "$date $time\n";
								$trophies_us{$trophyn}{date} = "$date $time";
							}
						}
						$tokn++;
					}
					$trophyn++;
					print "\n\n";
				}
			}
		}
	}
}
