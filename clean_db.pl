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
use Poloniex;


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
	if ( ( $ref->{'Tables_in_poloniex'} ne "ACTIVE_PAIRS" ) and ( $ref->{'Tables_in_poloniex'} ne "ACTIVE_PAIRS_HIGH_RISK" ) and ( $ref->{'Tables_in_poloniex'} ne "CONTROL_TABLE" ) )
	{
		push @symbols_list , $ref->{'Tables_in_poloniex'};
	}
}
$sth->finish();


my $days =3 ;

#delete records from all tables
foreach (sort @symbols_list)
{
print "delete from $_ where tstmp < TIMESTAMP(DATE_SUB(NOW(), INTERVAL $days DAY )) \n";
my $sth = $dbh->prepare("delete from $_ where tstmp < TIMESTAMP(DATE_SUB(NOW(), INTERVAL $days DAY ))");
$sth->execute();
$sth->finish();	
}

# Disconnect from the database.
$dbh->disconnect();
exit 0;

