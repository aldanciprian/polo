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



my $decoded_json;
my $hashref_temp = 0;
my $Basename = basename($0,".pl");
my $sleep_interval = 15;




sub get_json;
sub get_json_curl;
sub timestamp;
sub trim;


#db
sub add_data;
sub tstmp2db;

my $database="poloniex";
my $hostname="localhost";
my $user="ciprian";

# Connect to the database.
my $dbh = DBI->connect("DBI:mysql:database=$database;host=$hostname","ciprian", "ciprian", {'RaiseError' => 1});




while (1)
{
	my $execute_crt_tstmp = timestamp();
	print "============================= ".basename($0,".pl")." $execute_crt_tstmp  $$ ======================\n";	
	# watchdog
	my $filename_wdg = $Basename."_wdg_get_btc.txt";
	open(my $fh_wdg, '>', $filename_wdg) or die "Could not open file '$filename_wdg' $!";
	print $fh_wdg "$execute_crt_tstmp\n";
	close $fh_wdg;	
	
	$decoded_json=get_json("https://www.bitstamp.net/api/v2/ticker/BTCUSD/");
	
	# print Dumper $decoded_json;
	add_data("BTCUSD","'$execute_crt_tstmp' , '$decoded_json->{'last'}'");

	sleep $sleep_interval;
}

# Disconnect from the database.
$dbh->disconnect();


sub trim {
	my $input = shift;
	$input =~ s/^\s+|\s+$//g;
	return $input;
}

#gets url returns result object in json decoded  
sub get_json
{
	my $json;
	my $decode_json;
	my $url = shift;
	# 'get' is exported by LWP::Simple; install LWP from CPAN unless you have it.
	# You need it or something similar (HTTP::Tiny, maybe?) to get web pages.
	$json = get( $url );
	#sleep 250ms
	select(undef, undef, undef, 0.25);
	#print "curl --silent $url \n" ;
	#$json = `curl --silent $url`;
	warn "Could not get $url  !" unless defined $json;
	# print $json;

	# Decode the entire JSON
	$decode_json = decode_json( $json );
	return $decode_json

#	print Dumper $decoded_json;	
}


 sub get_json_curl
 {
     my $json;
     my $decoded_json;
     my $url = shift;
     # 'get' is exported by LWP::Simple; install LWP from CPAN unless you have it.
     # You need it or something similar (HTTP::Tiny, maybe?) to get web pages.
     #$json = get( $url );
     # print "curl --silent $url\n";
     $json = `curl  --silent $url `;
     warn "Could not get $url  !" unless defined $json;
     #print $json;
 
 
     # Decode the entire JSON
     #print "$json\n";
     $decoded_json = decode_json( $json );
     return $decoded_json
 
 #   print Dumper $decoded_json; 
 }


sub timestamp {
   my $t = localtime;
   return sprintf( "%04d-%02d-%02d_%02d-%02d-%02d",
                  $t->year, $t->mon, $t->mday,
                  $t->hour, $t->min, $t->sec );
	# %Y-%m-%d_%H-%M-%S				  
	# return localtime;
}

sub add_data()
{
	my $table = shift;
	my $data = shift;
  # Drop table 'foo'. This may fail, if 'foo' doesn't exist
  # Thus we put an eval around it.
   # eval { $dbh->do("DROP TABLE foo") };
   # print "Dropping foo failed: $@\n" if $@;

  # Create a new table 'foo'. This must not fail, thus we don't
  # catch errors.
	# print "CREATE TABLE IF NOT EXISTS $table (tstmp TIMESTAMP, last VARCHAR(30)) \n";
  $dbh->do("CREATE TABLE IF NOT EXISTS $table (tstmp TIMESTAMP, last VARCHAR(30))");

  # INSERT some data into 'foo'. We are using $dbh->quote() for
  # quoting the name.
	print "INSERT INTO $table VALUES ($data)\n";
  $dbh->do("INSERT INTO $table VALUES ($data)");

  # same thing, but using placeholders (recommended!)
  # $dbh->do("INSERT INTO foo VALUES (?, ?)", undef, 2, "Jochen");

}

sub tstmp2db()
{
	my $data = shift;
	
	$data =~ s/_/T/g;
	return $data;
}