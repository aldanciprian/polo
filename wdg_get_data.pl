#!/usr/bin/perl 
use Data::Dumper;               # Perl core module
use strict;                     # Good practice
use warnings;                   # Good practice
use Time::localtime;
use Time::Piece;
use File::Basename;


my $sleep_intv = 10;

sub timestamp;

while (1)
{
	my $filename = 'wdg_get_data.txt';
	open(my $fh, '<', $filename) or die "Could not open file '$filename' $!";
	my $last_line;
	$last_line = $_,while (<$fh>);
	close $fh;

	chomp($last_line);


	my $lastTime =  Time::Piece->strptime($last_line,'%Y-%m-%d_%H-%M-%S');
	my $crt_time = timestamp();
	my $crtTime = Time::Piece->strptime($crt_time,'%Y-%m-%d_%H-%M-%S');


	my $delta = $crtTime - $lastTime;
	print basename($0,".pl")." [$crt_time] - [$last_line] $delta \n";

	if ( ($crtTime - $lastTime) > 60 )
	{
		# the last line written by was 60 sec ago.Its to late
		# restart the poloniex_get_data script
		 print "kill poloniex_get_data becuase distance to the last time is $delta seconds \n";
		 my $pid = `ps -ef | grep poloniex_get_data.pl | grep -v grep | awk '{print \$2}'`;
		 print "pid to kill is $pid \n";
		 `kill -9 $pid`;
	}
	sleep $sleep_intv;
}
sub timestamp {
   my $t = localtime;
   return sprintf( "%04d-%02d-%02d_%02d-%02d-%02d",
                  $t->year, $t->mon, $t->mday,
                  $t->hour, $t->min, $t->sec );
}