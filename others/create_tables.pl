#!/usr/bin/perl 


use LWP::Simple;                # From CPAN
use JSON qw( decode_json );     # From CPAN
use Data::Dumper;               # Perl core module
use strict;                     # Good practice
use warnings;                   # Good practice
use Time::localtime;
use Time::Piece;
use LWP::UserAgent;
use Digest::SHA qw(hmac_sha512_hex);
use Switch;
use File::Basename;
use DBI;


sub timestamp;

#poloniuex
my $apikey = $ENV{'POLONIEX_APIKEY'};
my $sign = $ENV{'POLONIEX_SIGN'};

my @symbols_list;




my $database="poloniex";
my $hostname="localhost";
my $user="ciprian";


# Connect to the database.
my $dbh = DBI->connect("DBI:mysql:database=$database;host=$hostname","ciprian", "ciprian", {'RaiseError' => 1});
# now retrieve data from the table.
my $sth = $dbh->prepare("show tables");
$sth->execute();
while (my $ref = $sth->fetchrow_hashref()) {
	# print Dumper $ref;
	# print "Found a row: id = $ref->{'Tables_in_poloniex'}\n";
	if ( ( $ref->{'Tables_in_poloniex'} ne "ACTIVE_PAIRS" ))
	{
	push @symbols_list , $ref->{'Tables_in_poloniex'};	
	}
}
$sth->finish();		


#get the time now
my $script_start_time = timestamp();
my $start_crtTime =   Time::Piece->strptime($script_start_time,'%Y-%m-%d_%H-%M-%S');	
my $end_crtTime = $start_crtTime - 60*60*24;
my $end_crt_tstmp = $end_crtTime->strftime('%Y-%m-%d_%H-%M-%S');




foreach (@symbols_list)
{
	my $symbol =  $_;
	my $filename_status= "temp/".$symbol."_status.ctrl";

	# watchdog
	open(my $filename_status_h, '>', $filename_status) or die "Could not open file '$filename_status' $!";
	
	$sth = $dbh->prepare("select tstmp,last from $symbol where tstmp > '$end_crt_tstmp' ");
	$sth->execute();
	while (my $ref = $sth->fetchrow_hashref()) {
			my $temp_tstmp =  $ref->{'tstmp'};

			$temp_tstmp =~ s/ /_/g;
			$temp_tstmp =~ s/:/-/g;	
			print $filename_status_h "$temp_tstmp $ref->{'last'} \n";
	}
	$sth->finish();			
	
	close $filename_status_h;		
}

# Disconnect from the database.
$dbh->disconnect();

sub timestamp {
   my $t = localtime;
   return sprintf( "%04d-%02d-%02d_%02d-%02d-%02d",
                  $t->year, $t->mon, $t->mday,
                  $t->hour, $t->min, $t->sec );
	# %Y-%m-%d_%H-%M-%S				  
	# return localtime;
}