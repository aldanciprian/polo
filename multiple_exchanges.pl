#!/usr/bin/perl 


use LWP::Simple;                # From CPAN
use JSON qw( decode_json );     # From CPAN
use Data::Dumper;               # Perl core module
use strict;                     # Good practice
use warnings;                   # Good practice
use Time::localtime;
use Time::Piece;
use Time::Seconds;
use LWP::UserAgent;
use Digest::SHA qw(hmac_sha512_hex);
use Switch;
use File::Basename;
use DBI;
use Devel::StackTrace;
use Poloniex;


sub get_json;
sub get_json_curl;
sub timestamp;
sub trim;
sub get_btxchange_data;
sub print_number;
sub tstmp2db;




my $decoded_json;
#poloniuex
my $apikey = $ENV{'POLONIEX_APIKEY'};
my $sign = $ENV{'POLONIEX_SIGN'};

my $sleep_interval = 10;


my $database="multiple";
my $hostname="localhost";
my $user="ciprian";

# Connect to the database.
my $dbh = DBI->connect("DBI:mysql:database=$database;host=$hostname","ciprian", "ciprian", {'RaiseError' => 1});
my $multiple_eth = "MULTIPLE_EXCHANGES_ETH_BTC";

while (1)
{
	my %eth_btc_pair;
	my $execute_crt_tstmp = timestamp();
	print "============================= ".basename($0,".pl")." $execute_crt_tstmp  $$ ======================\n";	
	
	#BITSTAMP
	print "BITSTAMP \n";
	$decoded_json=get_json("https://www.bitstamp.net/api/v2/ticker/btcusd");
	print "BTCUSD ".$decoded_json->{'last'}."\n";
	# print Dumper $decoded_json;
	$decoded_json=get_json("https://www.bitstamp.net/api/v2/ticker/ethbtc");
	# print Dumper $decoded_json;
	print "ETHBTC ".$decoded_json->{'last'}." - ".print_number(1/$decoded_json->{'last'})."\n";
	$eth_btc_pair{'bitstamp'} = $decoded_json->{'last'};
	#btxchange
	# print "BTCXCHANGE \n";
	# get_btxchange_data();

	#kraken
	print "KRAKEN \n";
	$decoded_json=get_json("https://api.kraken.com/0/public/Ticker?pair=XBTUSD,ETHXBT");
	print "ETHBTC ".$decoded_json->{'result'}->{'XETHXXBT'}->{'c'}->[0]." - ".print_number(1/$decoded_json->{'result'}->{'XETHXXBT'}->{'c'}->[0])."\n";
	print "BTCUSD ".$decoded_json->{'result'}->{'XXBTZUSD'}->{'c'}->[0]."\n";
	$eth_btc_pair{'kraken'} = $decoded_json->{'result'}->{'XETHXXBT'}->{'c'}->[0];	
	# print Dumper $decoded_json;

	#poloniex
	print "POLONIEX \n";
	#get an object of the  Poloniex.pm class
	# my $polo_wrapper = Poloniex_new->new($apikey,$sign);
	# $decoded_json = $polo_wrapper->get_ticker("BTC_ETH");
	$decoded_json=get_json("https://poloniex.com/public?command=returnTicker");
	print "ETHBTC ".$decoded_json->{'BTC_ETH'}->{'last'}." - ".print_number(1/$decoded_json->{'BTC_ETH'}->{'last'})."\n";
	$eth_btc_pair{'poloniex'} = $decoded_json->{'BTC_ETH'}->{'last'};		
	
	my %min;
	$min{'value'} = 1000;
	$min{'exchange'} = "";
	my %max;
	$max{'value'} = 0;
	$max{'exchange'} = "";
	
	foreach (keys (%eth_btc_pair))
	{
		if ($eth_btc_pair{$_} < $min{'value'})
		{
			$min{'value'} = $eth_btc_pair{$_};
			$min{'exchange'} = $_;
		}
		if ($eth_btc_pair{$_} > $max{'value'})
		{
			$max{'value'} = $eth_btc_pair{$_};
			$max{'exchange'} = $_;
		}
	}
		
	print "max is $max{'exchange'} $max{'value'} \n";
	print "min is $min{'exchange'} $min{'value'} \n";
	my $delta = ($max{'value'} - $min{'value'})/$min{'value'};
	print "delta is $delta % \n";
	
  $dbh->do("CREATE TABLE IF NOT EXISTS $multiple_eth (tstmp TIMESTAMP, bitstamp VARCHAR(30), kraken VARCHAR(30), poloniex VARCHAR(30), min VARCHAR(30),max VARCHAR(30),delta VARCHAR(30))");
	my $db_data = "\'".tstmp2db($execute_crt_tstmp)."\', $eth_btc_pair{'bitstamp'},$eth_btc_pair{'kraken'},$eth_btc_pair{'poloniex'},$max{'exchange'},$min{'exchange'},$delta";
	# print $db_data."\n";
	$dbh->do("INSERT INTO $multiple_eth VALUES ($db_data)");	
	
	sleep $sleep_interval;
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
 
sub get_btxchange_data
{
		$decoded_json = get_json("http://api.fixer.io/latest?base=USD");
		# print Dumper $decoded_json;
		
		my @output = `lynx -connect_timeout=10 -dump https://www.btcxchange.ro/`;
		my $start_print = 0;
		my $counter = 0;
		my $counter2=0;
		foreach (@output)
		{
			chomp($_);
			if ( $_ =~ m/\.*What is bitcoin?.*/ )					
			{
				$start_print = 1;
				$counter = 0;
				$counter2=0;				
			}			
			if ( $start_print == 1)
			{		
					$counter ++;
					if  ($counter == 3 )
					{
						my $value = $_;
						if ( $counter2== 0 )
						{
							print "USD: ";
							$value =  $value * $decoded_json->{'rates'}->{'RON'};
						}
						if ( $counter2== 1 )
						{
							print "EUR: ";
						}
						if ( $counter2== 2 )
						{
							print "RON: ";
							$value =  $value / $decoded_json->{'rates'}->{'RON'};							
						}
						print trim($_)." ".print_number($value)."\n";						
						
						$counter = 0;
						$counter2 ++;
						if ( $counter2 == 3 )
						{
							$start_print = 0;
							last;
						}
					}
			}		

			
		}
		# print Dumper \@output;
}

sub trim {
	my $input = shift;
	$input =~ s/^\s+|\s+$//g;
	return $input;
}

sub print_number()
{
	my $number = shift;
	
	return sprintf("%0.8f",$number);
}

sub timestamp {
   my $t = localtime;
   return sprintf( "%04d-%02d-%02d_%02d-%02d-%02d",
                  $t->year, $t->mon, $t->mday,
                  $t->hour, $t->min, $t->sec );
	# %Y-%m-%d_%H-%M-%S				  
	# return localtime;
}
sub tstmp2db()
{
	my $data = shift;
	
	$data =~ s/_/T/g;
	return $data;
}