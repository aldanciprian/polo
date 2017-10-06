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
use Poloniex_new;


#poloniuex
my $apikey = $ENV{'POLONIEX_APIKEY'};
my $sign = $ENV{'POLONIEX_SIGN'};

my $decoded_json;


my $has_pending_order = 0; # bit to see if there is a pending order ot not
my $crt_order_number = 0; # in case there is a pending order, this should express the order number
my $crt_pair = 0; # the current pair in the order
my $crt_tstmp = 0; # the tstmp of the current order
my $crt_price = 0; # the current price in the order
my $crt_ammount = 0; # the current ammount in the order
my $current_spike = 0; # the current number of buy/sell 
my $btc_balance = 0.00011; # the ammount in BTC
my $delta_procent_force_sell = -9; # the procent where we force the sell
my $max_average_deviation = 1.8; # the procent of maximum average deviation that we allow
my $max_dev_size = 0.5; # the maximum procent of deviation of the current price to the middle of the average
my $wining_procent = 0.012; # the procent where we sell - case 2


my $basename = basename($0,".pl");


my $nr_trend_samples = 3; # number of trend samples on the average array
my $crt_iteration = 0;

my $filename_status= $basename."_status.ctrl";
my $filename_status_h;


my $sleep_interval = 10; # sleep interval in seconds , the default

my $buy_timeout = 0; #if it doesn't buy...cancel the order


# BUYING 1
# BOUGHT 2
# SELLING 3
# SOLD 4

my $max_average_size =  35; # size of average elements
my $max_sample_size = 135; # size of sample elements
my $sample_space = $ARGV[0]; #seconds between samples
# my $first_ema = $ARGV[1]; #1ema size
# my $second_ema = $ARGV[2]; #2ema size
# my $signal = $ARGV[3]; #signal size



sub get_json;
sub timestamp;
sub trim;
sub get_state_machine;
sub get_pair_list;
sub get_samples;
sub update_samples;
sub calculate_average;
sub update_average;
sub trim_list;
sub print_number;

sub get_tstmp;
sub get_percentChange;
sub get_low24hr;
sub get_last;
sub get_high24hr;
sub get_lowestAsk; 
sub get_quoteVolume;
sub get_baseVolume;
sub get_id; 
sub get_highestBid;
sub get_isFrozen;

my %delta_generic_list;
my %average_delta_generic_list;
my @symbols_list;

#sleep a random of seconds so that is desyncroinsed from other instances
my @range = ( 1 .. 60 );
my $random_number = $range[rand(@range)];
print basename($0,".pl")." Sleep $random_number seconds \n";
sleep ($random_number);


my $database="poloniex";
my $hostname="localhost";
my $user="ciprian";

#clean the db from old samples 
`./clean_db.pl`;

# Connect to the database.
my $dbh = DBI->connect("DBI:mysql:database=$database;host=$hostname","ciprian", "ciprian", {'RaiseError' => 1});
# now retrieve data from the table.
my $sth = $dbh->prepare("show tables");
$sth->execute();
while (my $ref = $sth->fetchrow_hashref()) {
	# print Dumper $ref;
	# print "Found a row: id = $ref->{'Tables_in_poloniex'}\n";
	if ( $ref->{'Tables_in_poloniex'} ne "ACTIVE_PAIRS" )
	{
	push @symbols_list , $ref->{'Tables_in_poloniex'};	
	}
}
$sth->finish();		


# watchdog
my $filename_wdg = basename($0,".pl")."_wdg.txt";
open(my $fh_wdg, '>', $filename_wdg) or die "Could not open file '$filename_wdg' $!";
print $fh_wdg "start\n";
close $fh_wdg;		

#get the time now
my $script_start_time = timestamp();
my $start_crtTime =   Time::Piece->strptime($script_start_time,'%Y-%m-%d_%H-%M-%S');	

print "=========  initialize samples ".timestamp()." \n";	
foreach (@symbols_list)
{
	get_samples($_,$sample_space,$start_crtTime,\%delta_generic_list);	
}
print "=========  end initialize samples ".timestamp()." \n";	


# set lists to a specific maximum size
trim_list(\%delta_generic_list,$max_sample_size);

foreach (sort (keys(%delta_generic_list)) )
{
		my $key = $_;
		my $size = @{$delta_generic_list{$key}};
		calculate_average(\@{$delta_generic_list{$key}},$size,\%average_delta_generic_list,$key,1);
}


#get an object of the  Poloniex.pm class
my $polo_wrapper = Poloniex_new->new($apikey,$sign);


while (1)
{
	my $buy_next = "WRONG";
	my $execute_crt_tstmp = timestamp();

	print "============================= ".basename($0,".pl")." $execute_crt_tstmp  $$  $crt_iteration ======================\n";		
	$crt_iteration++;

	
	# watchdog
	my $filename_wdg = basename($0,".pl")."_wdg.txt";
	open(my $fh_wdg, '>', $filename_wdg) or die "Could not open file '$filename_wdg' $!";
	print $fh_wdg "$execute_crt_tstmp\n";
	close $fh_wdg;		
	
	
	my $crtTime =   Time::Piece->strptime($execute_crt_tstmp,'%Y-%m-%d_%H-%M-%S');	

	print "update $sample_space sec \n";

	my @potential_buyers = ();
	foreach (sort @symbols_list)
	{
		my $key = $_;		

		if ( update_samples($_,$sample_space,$crtTime,\%delta_generic_list) == 1)
		{
			if ( defined $delta_generic_list{$key} )	
			{
				# print Dumper %delta_generic_list;
				my $size = @{$delta_generic_list{$key}};
				# print "$key sample list size is $size \n";
				calculate_average(\@{$delta_generic_list{$key}},$size,\%average_delta_generic_list,$key,0);								
			}
		}
	}
	foreach (sort @symbols_list)
	{
		# here we make the decision
		my $key = $_;		
		my $good_ticker = 1;
		
		my $average_size = @{$average_delta_generic_list{$key}};
		# print "$key average size $average_size \n";
		if ( $average_size > ($max_average_size - 1 ) )
		{
			# print print_number(get_baseVolume($delta_generic_list{$key}[0]))." $key \n";
			if ( get_baseVolume($delta_generic_list{$key}[0]) < 100 )
			{
				#the volume is to low
				$good_ticker = 0;
			}				
			if ( $good_ticker == 1 )
			{
				#calculcate the average of all the averages
				my $sum = 0;
				# print "good ticker $key \n";
				for (my $i = 0; $i < $average_size; $i++) 
				{
							my $last_price = $average_delta_generic_list{$key}[$i];
							# print "$key $last_price $average_size \n";
							$sum += $last_price;
				}			
				
				#average 
				$sum = $sum / $average_size;	
		
				# there should not be a very big deviation
				my $big_deviation = 0;
				for (my $i = 0; $i < $average_size; $i++) 
				{
					my $delta = 0;
					my $last_average = $average_delta_generic_list{$key}[$i];
					if ( $last_average >= $sum )
					{
						$delta = ( ( $last_average - $sum ) * 100 ) / $sum;
					}
					else
					{
						$delta = ( ( $sum - $last_average ) * 100 ) / $last_average;								
					}
					
					# print "$key $delta $average_size\n";
					if (!(($delta >= 0) && ($delta <= $max_average_deviation)))
					{
						#delta is not in limit
						$big_deviation = 1;
						last;
					}
				}
				
				if ( $big_deviation == 1 )
				{
					# it has deviated to much
					# skip this ticker
					# print "deviation is to big $key $big_deviation \n";
					next;
				}
				
				
				my $current_price = get_last($delta_generic_list{$key}[0]);
				my $current_deviation = 0;
				# print "$key $current_price ".print_number($sum)." \n";
				if ( $current_price > $sum )
				{
					#the price is above average
					next;
				}
				
				$current_deviation = ( ( $sum - $current_price ) * 100 )  / $current_price;
				
				my %elem_potential;
				$elem_potential{'ticker'} = $key;
				$elem_potential{'deviation'} = $current_deviation;
				# print "Potential deviation $elem_potential{'ticker'} $elem_potential{'deviation'} % $current_price $sum\n";
				push @potential_buyers , \%elem_potential;
			} # good ticker
		}
	} # foreach symbol

	my %max_dev_elem;
	my $max_dev = 0;
	foreach (@potential_buyers)
	{
		if ( $max_dev > $_->{'deviation'} )
		{
			$max_dev = $_->{'deviation'};
			$max_dev_elem{'deviation'} = $_->{'deviation'};
			$max_dev_elem{'ticker'} = $_->{'ticker'};
		}
	}
	
	if ( $max_dev_elem{'ticker'} )
	{
		print "$max_dev_elem{'ticker'} [ $max_dev_elem{'deviation'} ] % \n";
		if ( $max_dev < $max_dev_size )
		{
			my $found_pair = 0;
			$dbh->do("CREATE TABLE IF NOT EXISTS ACTIVE_PAIRS (pair VARCHAR(40) UNIQUE)");
			my $sth = $dbh->prepare("select * from ACTIVE_PAIRS");
			$sth->execute();
			# print "ACTIVE_PAIRS table : \n";
			while (my $ref = $sth->fetchrow_hashref()) {
				# print "$ref->{'pair'} \n";
			 if ( "BTC_$max_dev_elem{'ticker'}" eq $ref->{'pair'} )
			 {
				$found_pair = 1;
				last;
			 }
			} 
			$sth->finish();	
		
			if  ( $found_pair == 0 )
			{
				# we have found another pair active
				# we can use this one
				print "The ticker to buy next is $max_dev_elem{'ticker'} - $max_dev_elem{'deviation'} % \n";
				$buy_next = $max_dev_elem{'ticker'};
				
				# { #print the average list
				# my $average_size = @{$average_delta_generic_list{$max_dev_elem{'ticker'}}};			
					# for (my $i = 0; $i < $average_size; $i++) 
					# {
						# print print_number($average_delta_generic_list{$max_dev_elem{'ticker'}}[$i])." ";
						# use integer;
						# if ( ( $i % 10 ) == 0 )
						# {
							# print "\n";
						# }
					# }
					# print "\n";
				# }
				
			}
			else
			{
				print "This ticker is allready active $max_dev_elem{'ticker'} $max_dev_elem{'deviation'} %\n";
			}
		}
	}

	
	# sleep $sleep_interval;	
	# next;
	
	
	my %current_list;
	#do the sampling
	%current_list = get_pair_list();
	
	# get the state machine
	# my $execute_crt_tstmp = timestamp();
	# print "============================= poloniex trade $execute_crt_tstmp  $$ ======================\n";		
	my $state = get_state_machine();
	
	#switch for each state
	switch ($state) {
	case 1 { 
					print "BUYING $crt_pair \n";
					my $order_is_not_complete = 0;
					if ( $has_pending_order == 1 )
					{
						print "Order $crt_order_number is pending.Wait for finalization.\n";
						
						$decoded_json = $polo_wrapper->get_open_orders("all");
						if ( $decoded_json->{'returnValue'} > 0 )
						{
							$decoded_json = $decoded_json->{'returnJson'};
						}
						else
						{
							#repeat the iteration
							last;
						}
						
						# print Dumper $decoded_json;
						foreach (@{$decoded_json->{$crt_pair}})
						{
							if ( $_->{'orderNumber'} == $crt_order_number )
							{
									#we found the order in the pending list
									#order is not complete;
									$order_is_not_complete = 1;
							}
						}
						if ( $order_is_not_complete == 0 )
						{
							print "Order is completed ! \n";
							
							$decoded_json = $polo_wrapper->get_my_trade_history($crt_pair);
							print Dumper $decoded_json;
							if ( $decoded_json->{'returnValue'} > 0 )
							{
								$decoded_json = $decoded_json->{'returnJson'};
							}
							else
							{
								#repeat the iteration
								last;
							}
							
							my $total_btc = 0;
							my $buy_ammount = 0;
							foreach (@{$decoded_json})
							{
								if ( $crt_order_number == $_->{'orderNumber'} )
								{
									my $applied_fee = $_->{'amount'} - ( $_->{'amount'} * $_->{'fee'});
									$total_btc += $_->{'total'};
									$buy_ammount += $applied_fee;
								}
							}
							
							#clear the selling file
							# open(my $filename_selling_h, '>', $filename_selling) or warn "Could not open file '$filename_selling' $!";
							# close $filename_selling_h;								
							
							# store the bought event
							print "$current_spike $crt_tstmp BOUGHT $crt_pair ".sprintf("%0.8f",$crt_price)." ".sprintf("%0.8f",$buy_ammount)." $crt_order_number ".sprintf("%0.8f",$total_btc)." \n";						
							open(my $filename_status_h, '>>', $filename_status) or warn "Could not open file '$filename_status' $!";
							print $filename_status_h "$current_spike $crt_tstmp BOUGHT $crt_pair ".sprintf("%0.8f",$crt_price)." ".sprintf("%0.8f",$buy_ammount)." $crt_order_number ".sprintf("%0.8f",$total_btc)." \n";												
							close $filename_status_h;			
						}
						else
						{
							print "Order is not completed ! \n";			
							$buy_timeout++;
							
							#after 20 cycles cancel the order
							if ( $buy_timeout == 20 )
							{
								# cancel the order and go back to buying
								print "Timeout on the order cancel the order and go back to buying ! \n";
							
								$decoded_json = $polo_wrapper->get_order_trades($crt_order_number);
								print Dumper $decoded_json;
								if ( $decoded_json->{'returnValue'} > 0 )
								{
									$decoded_json = $decoded_json->{'returnJson'};
								}
								else
								{
									#repeat the iteration
									last;
								}							
							
								$polo_wrapper->cancel_order($crt_pair,$crt_order_number);
								if ( $decoded_json->{'returnValue'} <= 0 )
								{
									#repeat the iteration
									last;									
								}
								print "delete from  ACTIVE_PAIRS where pair = '$crt_pair' \n";
								$dbh->do("delete from  ACTIVE_PAIRS where pair = '$crt_pair' ");

								
								#delete the last line from the status file
								open($filename_status_h,"+<$filename_status") or die;
									while (<$filename_status_h>) {
											if (eof($filename_status_h)) {
												 seek($filename_status_h,-(length($_)),2) or die;
												 truncate($filename_status_h,tell($filename_status_h)) or die;
											}
									}
								close $filename_status_h;
								
								if ( $decoded_json->{'returnValue'} != 1 )
								{
									print "We have to sell the partial BUY $crt_pair !\n";
									# we have partial buy
									# we need to sell that
									my $total_btc = 0;
									my $buy_ammount = 0;								
									foreach (@{$decoded_json->{'returnJson'}})
									{
										my $applied_fee = $_->{'amount'} - ( $_->{'amount'} * $_->{'fee'});
										$total_btc += $_->{'total'};
										$buy_ammount += $applied_fee;
										$crt_price = $_->{'rate'};
									}	
									
									# store the bought event
									print "$current_spike $crt_tstmp BOUGHT $crt_pair ".sprintf("%0.8f",$crt_price)." ".sprintf("%0.8f",$buy_ammount)." $crt_order_number ".sprintf("%0.8f",$total_btc)." \n";						
									open(my $filename_status_h, '>>', $filename_status) or warn "Could not open file '$filename_status' $!";
									print $filename_status_h "$current_spike $crt_tstmp BOUGHT $crt_pair ".sprintf("%0.8f",$crt_price)." ".sprintf("%0.8f",$buy_ammount)." $crt_order_number ".sprintf("%0.8f",$total_btc)." \n";												
									close $filename_status_h;	
								}
							}
						}
					}
					else
					{
						# there is no order
						# print "there is no order \n";
						# print "delete from  ACTIVE_PAIRS where pair = '$crt_pair' \n";
						# $dbh->do("delete from  ACTIVE_PAIRS where pair = '$crt_pair' ");						
						my $buy_ticker = $buy_next;
						if ( "BTC_$buy_ticker" eq $crt_pair )
						{
							print "The last cycle was with $crt_pair , and the new one cannot be BTC_$buy_ticker.Wait for the next! \n";
							last;
						}						
						if ( $buy_ticker ne "WRONG" )
						{
							print "buy now \n";
							# buy now
							# write status file - last line
							my $price = get_last($current_list{$buy_ticker});

							if ( $price > 0.00001000 )
							{
								$price = $price - 0.00000005;								
							}
							else
							{
								# just increase with the small resolution
								$price = $price - 0.00000001;							
							}
							if ( $price <= 0 )
							{
								print "Something is wrong with the price $buy_ticker $price !!!!\n";
								last;
							}
							print "INSERT INTO ACTIVE_PAIRS (pair) VALUES ('BTC_$buy_ticker') \n";
							$dbh->do("INSERT INTO ACTIVE_PAIRS (pair) VALUES ('BTC_$buy_ticker')");
							
							my $buy_ammount = $btc_balance / $price ;
							# $buy_ammount = $buy_ammount - ($buy_ammount * 0.0015);
							$current_spike++;
							print "amount to buy $buy_ticker ".print_number($buy_ammount)." $btc_balance ".print_number($price)." \n";
							
							$buy_timeout = 0;
							$decoded_json = $polo_wrapper->buy("BTC_$buy_ticker",$price,$buy_ammount);
							# print Dumper $decoded_json;
							if ( $decoded_json->{'returnValue'} > 0 )
							{
								$decoded_json = $decoded_json->{'returnJson'};
							}
							else
							{
								#repeat the iteration
								print "delete from  ACTIVE_PAIRS where pair = 'BTC_$buy_ticker' \n";
								$dbh->do("delete from  ACTIVE_PAIRS where pair = 'BTC_$buy_ticker' ");								
								last;
							}											
							$crt_order_number = $decoded_json->{'orderNumber'};
							print "$current_spike $execute_crt_tstmp BUYING BTC_$buy_ticker ".sprintf("%0.8f",$price)." $buy_ammount $crt_order_number $btc_balance \n";
							open(my $filename_status_h, '>>', $filename_status) or warn "Could not open file '$filename_status' $!";
							print $filename_status_h  "$current_spike $execute_crt_tstmp BUYING BTC_$buy_ticker ".sprintf("%0.8f",$price)." $buy_ammount $crt_order_number $btc_balance \n";
							close $filename_status_h;
						}
					}
			}
	case 2 { 
					print "BOUGHT \n"; 

					# check if the current price is higher then bought price
					my %pairs_list = get_pair_list();

					my $sell_ticker = $crt_pair;
					$sell_ticker =~ s/BTC_(.*)/$1/g ;
					
					#case 2
					#make a price higher with 1.5 %
					#sell with that price and wait for the execution
					my $latest_price = $crt_price + ( $crt_price * $wining_procent);
					$decoded_json = $polo_wrapper->sell("BTC_$sell_ticker",$latest_price,$crt_ammount);
					if ( $decoded_json->{'returnValue'} > 0 )
					{
						$decoded_json = $decoded_json->{'returnJson'};
					}
					else
					{
						#repeat the iteration
						last;
					}										
					$crt_order_number = $decoded_json->{'orderNumber'};
					# print Dumper $decoded_json;
					my $btc_after_sell = $latest_price * $crt_ammount;
					$btc_after_sell = $btc_after_sell - ( $btc_after_sell * 0.0015 );
					print "$current_spike $execute_crt_tstmp SELLING BTC_$sell_ticker ".sprintf("%0.8f",$latest_price)." $crt_ammount $crt_order_number $btc_after_sell \n";
					open(my $filename_status_h, '>>', $filename_status) or warn "Could not open file '$filename_status' $!";
					print $filename_status_h "$current_spike $execute_crt_tstmp SELLING BTC_$sell_ticker ".sprintf("%0.8f",$latest_price)." $crt_ammount $crt_order_number $btc_after_sell \n";
					close $filename_status_h;					
		    }	
	case 3 { 
					print "SELLING $crt_pair\n";
					my $sell_ticker = $crt_pair;
					my $order_is_not_complete = 0;
					$sell_ticker =~ s/BTC_(.*)/$1/g ;
					my %current_list = 	get_pair_list();
					# print Dumper $current_list{$sell_ticker};
					my $ticker_status = $current_list{$sell_ticker};
					$ticker_status =~ s/\S*?\s+\S*?\s+\S*?\s+(\S*?)\s+.*/$1/g;
					
					# $decoded_json = $polo_wrapper->get_open_orders($crt_pair);
					$decoded_json = $polo_wrapper->get_open_orders('all');
					# print Dumper $decoded_json;					
					if ( $decoded_json->{'returnValue'} > 0 )
					{
						$decoded_json = $decoded_json->{'returnJson'};
					}
					else
					{
						#repeat the iteration
						last;
					}							
					foreach (@{$decoded_json->{$crt_pair}})
					{
						if ( $_->{'orderNumber'} == $crt_order_number )
						{
								#we found the order in the pending list
								#order is not complete;
								$order_is_not_complete = 1;
						}
					}					
					
					if ( $order_is_not_complete == 0 )
					{
						print "Order is completed !  $crt_order_number \n";
						
						$decoded_json = $polo_wrapper->get_my_trade_history($crt_pair);
						if ( $decoded_json->{'returnValue'} > 0 )
						{
							$decoded_json = $decoded_json->{'returnJson'};
						}
						else
						{
							#repeat the iteration
							last;
						}								
						print Dumper $decoded_json;
						my $total_btc = 0;
						my $sell_ammount = 0;
						foreach (@{$decoded_json})
						{
							if ( $crt_order_number == $_->{'orderNumber'} )
							{
								my $applied_fee = $_->{'total'} - ( $_->{'total'} * $_->{'fee'} );
								$total_btc += $applied_fee;
								$sell_ammount += $_->{'amount'};
							}
						}						
						print "$current_spike $crt_tstmp SOLD $crt_pair ".sprintf("%0.8f",$crt_price)." ".sprintf("%0.8f",$sell_ammount)." $crt_order_number ".sprintf("%0.8f",$total_btc)." \n";						
						open(my $filename_status_h, '>>', $filename_status) or warn "Could not open file '$filename_status' $!";
						print $filename_status_h "$current_spike $crt_tstmp SOLD $crt_pair ".sprintf("%0.8f",$crt_price)." ".sprintf("%0.8f",$sell_ammount)." $crt_order_number ".sprintf("%0.8f",$total_btc)." \n";												
						close $filename_status_h;	
						print "delete from  ACTIVE_PAIRS where pair = '$crt_pair' \n";
						$dbh->do("delete from  ACTIVE_PAIRS where pair = '$crt_pair' ");
					}
					else
					{
						my $delta_procent = 0;
						# my $bought_price = $crt_price - (
						if  ( $crt_price > $ticker_status )
						{
						$delta_procent = $crt_price - $ticker_status;
						$delta_procent = ( $delta_procent * 100 ) / $crt_price; 
						$delta_procent = $delta_procent * (-1) ;						
						}
						else
						{
						$delta_procent = $ticker_status - $crt_price;
						$delta_procent = ( $delta_procent * 100 ) / $crt_price; 
						}
						print "$execute_crt_tstmp Order is not completed ! $crt_order_number delta is $delta_procent %  $crt_price  $ticker_status \n";	
						if ( $delta_procent < $delta_procent_force_sell )						
						{
							# Cancel sell order
							print "loosing procent higher then $delta_procent_force_sell we need to force a selll $delta_procent ! \n";
							print "Cancel order $crt_order_number \n";
							$polo_wrapper->cancel_order($crt_pair,$crt_order_number);
							if ( $decoded_json->{'returnValue'} > 0 )
							{
								$decoded_json = $decoded_json->{'returnJson'};
							}
							else
							{
								#repeat the iteration
								last;
							}										

							# FORCE a sell							
							my $latest_price = $ticker_status + 0.00000001;
							$decoded_json = $polo_wrapper->sell("BTC_$sell_ticker",$latest_price,$crt_ammount);
							if ( $decoded_json->{'returnValue'} > 0 )
							{
								$decoded_json = $decoded_json->{'returnJson'};
							}
							else
							{
								#repeat the iteration
								last;
							}									
							$crt_order_number = $decoded_json->{'orderNumber'};
							# print Dumper $decoded_json;
							my $btc_after_sell = $latest_price * $crt_ammount;
							$btc_after_sell = $btc_after_sell - ( $btc_after_sell * 0.0015 );
							print "$current_spike $execute_crt_tstmp SELLING BTC_$sell_ticker ".sprintf("%0.8f",$latest_price)." $crt_ammount $crt_order_number $btc_after_sell \n";
							open(my $filename_status_h, '>>', $filename_status) or warn "Could not open file '$filename_status' $!";
							print $filename_status_h "$current_spike $execute_crt_tstmp SELLING BTC_$sell_ticker ".sprintf("%0.8f",$latest_price)." $crt_ammount $crt_order_number $btc_after_sell \n";
							close $filename_status_h;							
						}
					}					
			}
	case 4 { 
					print "SOLD \n"; 
					print "$current_spike $crt_tstmp BUYING $crt_pair 0 0 0 $btc_balance \n";
					open(my $filename_status_h, '>>', $filename_status) or warn "Could not open file '$filename_status' $!";
					print $filename_status_h "$current_spike $crt_tstmp BUYING $crt_pair 0 0 0 $btc_balance \n";
					close $filename_status_h;				

			}	
	else { print "State is not recognised ! \n"; } 
	}
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

sub timestamp {
   my $t = localtime;
   return sprintf( "%04d-%02d-%02d_%02d-%02d-%02d",
                  $t->year, $t->mon, $t->mday,
                  $t->hour, $t->min, $t->sec );
	# %Y-%m-%d_%H-%M-%S				  
	# return localtime;
}

sub get_state_machine {
	my $previous_state = 0;
	#read status file - last line
	
	unless(-e $filename_status) {
			#Create the file if it doesn't exist
			open my $fc, ">", $filename_status;
			close $fc;
	}
	my $last_line="";	
	if ( -s $filename_status )
	{
		open(my $filename_status_h, '<', $filename_status) or warn "Could not open file '$filename_status' $!";
		$last_line = $_,while (<$filename_status_h>);
		close $filename_status_h;
		chomp($last_line);
	}	
	
	
	if ( $last_line =~ /^$/ )
	{
		print "$filename_status is empty !!\n";
		$previous_state = "BUYING";
		$has_pending_order = 0;		
		$current_spike = 0;
		$crt_order_number = 0;
		$crt_pair = 0;
		$crt_price = 0;
		$crt_ammount = 0;
		$crt_tstmp = 0;
	}
	else
	{
		# extract state   crt tstmp state pair price ammount ordernumber btc_balance
		if ( $last_line =~ /\s*?(\S*?)\s+(\S*?)\s+(\S*?)\s+(\S*?)\s+(\S*?)\s+(\S*?)\s+(\S*?)\s+(\S*?)\s/ )
		{

			$current_spike = $1;
			$crt_tstmp = $2;
			$previous_state = $3;
			$crt_order_number = $7;
			$crt_pair = $4;
			$crt_price = $5;
			$crt_ammount = $6;
			$btc_balance = $8;

			if  ($crt_order_number == 0 )
			{
				$has_pending_order = 0;
			}
			else
			{
				$has_pending_order = 1;
			}
			# if ( ( $crt_order_number == 0 )&& ($crt_price == 0) )
			# {
				# # this is the end of a cycle
				# #force the deletion of the last used pair
				# print "force the deletion : delete from  ACTIVE_PAIRS where pair = '$crt_pair' \n";
				# $dbh->do("delete from  ACTIVE_PAIRS where pair = '$crt_pair' ");
			# }
		}
	}
	#get state machine
	
	switch ($previous_state) {
	case "BUYING"		{ return 1; }
	case "BOUGHT"	{ return 2; }
	case "SELLING"	{ return 3; }
	case "SOLD"	{ return 4; }
	else		{ print "Case not detected !! \n" ; return 0; }
    }	
}

sub get_pair_list {
	my %current_list;
	my $tstmp = timestamp();
	$decoded_json=get_json("https://poloniex.com/public?command=returnTicker");
	# print Dumper $decoded_json;

	# open(my $filename_samplings_all_h, '>>', $filename_samplings_all) or warn "Could not open file $filename_samplings_all $!";

	foreach (sort (keys (%{$decoded_json})))
	{
		# 'percentChange' => '0.03412950',
		# 'low24hr' => '0.00036400',
		# 'last' => '0.00038057',
		# 'high24hr' => '0.00038800',
		# 'lowestAsk' => '0.00038055',
		# 'quoteVolume' => '91871.69002694',
		# 'baseVolume' => '34.51963175',
		# 'id' => 170,
		# 'highestBid' => '0.00037520',
		# 'isFrozen' => '0'
		
		if ( $_ =~ /BTC_(.*)/ )
		{
			# only trade against BTC
			my $coinName = $1;
			
			my $percentChange   = ${decoded_json}->{$_}->{'percentChange'};
			my $low24hr   = ${decoded_json}->{$_}->{'low24hr'};
			my $last   = ${decoded_json}->{$_}->{'last'};
			my $high24hr   = ${decoded_json}->{$_}->{'high24hr'};
			my $lowestAsk   = ${decoded_json}->{$_}->{'lowestAsk'};
			my $quoteVolume   = ${decoded_json}->{$_}->{'quoteVolume'};
			my $baseVolume   = ${decoded_json}->{$_}->{'baseVolume'};
			my $id   = ${decoded_json}->{$_}->{'id'};
			my $highestBid   = ${decoded_json}->{$_}->{'highestBid'};
			my $isFrozen   = ${decoded_json}->{$_}->{'isFrozen'};		
			
			if ( $isFrozen == 0 )
			{
				#only unfrozen pairs					
				# if ( $baseVolume > $volumeRef)
				{
					# only higher then a threshold
					if ( $last > 0.00001000 )
					{

						# push @elem $tstmp;
						# push @elem $coinName;
						# push @elem $percentChange;
						# push @elem $low24hr;
						# push @elem $last;
						# push @elem $high24hr;
						# push @elem $lowestAsk;
						# push @elem $quoteVolume;
						# push @elem $baseVolume;
						# push @elem $id;
						# push @elem $highestBid;
						# push @elem $isFrozen;
						$current_list{$coinName} = "$tstmp $percentChange $low24hr $last $high24hr $lowestAsk $quoteVolume $baseVolume $id $highestBid $isFrozen";
						# print $filename_samplings_all_h "$tstmp $coinName $percentChange $low24hr $last $high24hr $lowestAsk $quoteVolume $baseVolume $id $highestBid $isFrozen \n";
						# push @current_list, %elem_hash;				
					}
				}
			}
		}
	}
	# close $filename_samplings_all_h;				
				# push @current_list, @elem;	
	return %current_list;
}


sub get_tstmp
{
	my $param = shift;
	if ( $param =~ /(\S*?)\s+\S*?\s+\S*?\s+\S*?\s+\S*?\s+\S*?\s+\S*?\s+\S*?\s+\S*?\s+\S*?\s+\S*?.*/ )
	{
		return $1;
	}
}

sub get_percentChange
{
	my $param = shift;
	if ( $param =~ /\S*?\s+(\S*?)\s+\S*?\s+\S*?\s+\S*?\s+\S*?\s+\S*?\s+\S*?\s+\S*?\s+\S*?\s+\S*?.*/ )
	{
		return $1;
	}
}
sub get_low24hr
{
	my $param = shift;
	if ( $param =~ /\S*?\s+\S*?\s+(\S*?)\s+\S*?\s+\S*?\s+\S*?\s+\S*?\s+\S*?\s+\S*?\s+\S*?\s+\S*?.*/ )
	{
		return $1;
	}
}
sub get_last
{
	my $param = shift;
	if ( $param =~ /\S*?\s+\S*?\s+\S*?\s+(\S*?)\s+\S*?\s+\S*?\s+\S*?\s+\S*?\s+\S*?\s+\S*?\s+\S*?.*/ )
	{
		return $1;
	}
}
sub get_high24hr
{
	my $param = shift;
	if ( $param =~ /\S*?\s+\S*?\s+\S*?\s+\S*?\s+(\S*?)\s+\S*?\s+\S*?\s+\S*?\s+\S*?\s+\S*?\s+\S*?.*/ )
	{
		return $1;
	}
}
sub get_lowestAsk
{
	my $param = shift;
	if ( $param =~ /\S*?\s+\S*?\s+\S*?\s+\S*?\s+\S*?\s+(\S*?)\s+\S*?\s+\S*?\s+\S*?\s+\S*?\s+\S*?.*/ )
	{
		return $1;
	}
}
sub get_quoteVolume
{
	my $param = shift;
	if ( $param =~ /\S*?\s+\S*?\s+\S*?\s+\S*?\s+\S*?\s+\S*?\s+(\S*?)\s+\S*?\s+\S*?\s+\S*?\s+\S*?.*/ )
	{
		return $1;
	}
}
sub get_baseVolume
{
	my $param = shift;
	if ( $param =~ /\S*?\s+\S*?\s+\S*?\s+\S*?\s+\S*?\s+\S*?\s+\S*?\s+(\S*?)\s+\S*?\s+\S*?\s+\S*?.*/ )
	{
		return $1;
	}
}
sub get_id
{
	my $param = shift;
	if ( $param =~ /\S*?\s+\S*?\s+\S*?\s+\S*?\s+\S*?\s+\S*?\s+\S*?\s+\S*?\s+(\S*?)\s+\S*?\s+\S*?.*/ )
	{
		return $1;
	}
}
sub get_highestBid
{
	my $param = shift;
	if ( $param =~ /\S*?\s+\S*?\s+\S*?\s+\S*?\s+\S*?\s+\S*?\s+\S*?\s+\S*?\s+\S*?\s+(\S*?)\s+\S*?.*/ )
	{
		return $1;
	}
}
sub get_isFrozen
{
	my $param = shift;
	if ( $param =~ /\S*?\s+\S*?\s+\S*?\s+\S*?\s+\S*?\s+\S*?\s+\S*?\s+\S*?\s+\S*?\s+\S*?\s+(\S*?).*/ )
	{
		return $1;
	}
}

sub get_samples()
{
	my $ticker = shift;
	my $delta = shift;
	my $sample_tstmpTime = shift;
	my $output_hash = shift;
	my $found_tstmp = 0;
	my $sample_tstmp = 0;
	my $minim_TfTime = 0;
	my $minim_sample_tstmp = 0;
	do
	{
		$found_tstmp = 0;	
		$sample_tstmp = $sample_tstmpTime->strftime('%Y-%m-%d_%H-%M-%S');
		# search only between the end of the TF and 60 seconds before
		$minim_TfTime = $sample_tstmpTime - 60;
		$minim_sample_tstmp = $minim_TfTime->strftime('%Y-%m-%d_%H-%M-%S');
		# print "select * from $ticker where tstmp < '$sample_tstmp' and tstmp > '$minim_sample_tstmp' order by tstmp desc limit 1 \n";
		$sth = $dbh->prepare("select * from $ticker where tstmp < '$sample_tstmp' and tstmp > '$minim_sample_tstmp' order by tstmp desc limit 1");
		$sth->execute();
		while (my $ref = $sth->fetchrow_hashref()) {
			# print "$ticker $ref->{'tstmp'} $ref->{'last'} \n";
			my $temp_tstmp =  $ref->{'tstmp'};

			$temp_tstmp =~ s/ /_/g;
			$temp_tstmp =~ s/:/-/g;
			push @{$output_hash->{$ticker}} ,"$temp_tstmp $ref->{'percentChange'} $ref->{'low24hr'} $ref->{'last'} $ref->{'high24hr'} $ref->{'lowestAsk'} $ref->{'quoteVolume'} $ref->{'baseVolume'} $ref->{'id'} $ref->{'highestBid'} $ref->{'isFrozen'} ";
			my $array_size = @{$output_hash->{$ticker}};
			if ( $array_size > $max_sample_size )
			{
				# we have read enough
				$found_tstmp = 0;				
				last;
			}
			else
			{
				#read more
				$found_tstmp = 1;
			}

		}
		$sth->finish();				
		$sample_tstmpTime	= $sample_tstmpTime - $delta;
	
	
	} while ($found_tstmp == 1)
	
}

sub update_samples()
{
	my $ticker = shift;
	my $delta = shift;
	my $sample_tstmpTime = shift;
	my $output_hash = shift;
	my $found_tstmp = 0;
	my $sample_tstmp = 0;
	my $minim_TfTime = 0;
	my $minim_sample_tstmp = 0;
	
	
	my $found = 0;
	my $added = 0;
	
	$sample_tstmp = $sample_tstmpTime->strftime('%Y-%m-%d_%H-%M-%S');
	# search only between the end of the TF and 60 seconds before
	$minim_TfTime = $sample_tstmpTime - 60;
	$minim_sample_tstmp = $minim_TfTime->strftime('%Y-%m-%d_%H-%M-%S');
	# print "select * from $ticker where tstmp < '$sample_tstmp' and tstmp > '$minim_sample_tstmp' order by tstmp desc limit 1 \n";
	$sth = $dbh->prepare("select * from $ticker where tstmp < '$sample_tstmp' and tstmp > '$minim_sample_tstmp' order by tstmp desc limit 1");
	$sth->execute();
	while (my $ref = $sth->fetchrow_hashref()) {
		# print "$ticker $ref->{'tstmp'} $ref->{'last'} \n";
		my $temp_tstmp =  $ref->{'tstmp'};
		$temp_tstmp =~ s/ /_/g;
		$temp_tstmp =~ s/:/-/g;		
		$found = 1;
		if ( $temp_tstmp ne get_tstmp(${$output_hash->{$ticker}}[0]) )
		{
			$added = 1;
			unshift @{$output_hash->{$ticker}} ,"$temp_tstmp $ref->{'percentChange'} $ref->{'low24hr'} $ref->{'last'} $ref->{'high24hr'} $ref->{'lowestAsk'} $ref->{'quoteVolume'} $ref->{'baseVolume'} $ref->{'id'} $ref->{'highestBid'} $ref->{'isFrozen'} ";
		}
	}
	$sth->finish();		

	if ($found == 0 )
	{
		# we haven't found the element
		# we have to restart the calculation all over
		# we have to clean the entire array;
		print "NO element found for $ticker  ! \n";
		if ( defined $output_hash->{$ticker} )
		{
		#clear the array
		@{$output_hash->{$ticker}}=(); 
		}
	}
	else
	{
		#remove the old samples
		if ( $added == 1 )
		{
			my $array_size = @{$output_hash->{$ticker}};
			if  ( $array_size > $max_sample_size )
			{
				pop @{$output_hash->{$ticker}};
			}
		}
	}
	
	return $added;
}


sub trim_list()
{
	my $sample_hash = shift;
	my $max_size = shift;
	foreach (sort (keys(%{$sample_hash})) )
	{
		my $key = $_;

		# my $ticker_list = @#{$sample_hash{$key}};
		my $ticker_list_size = @{$sample_hash->{$key}};
		# if ($ticker_list_size > $max_size )
		# {
			# # print "list size is higher then $max_size, removing the old samples \n";
			# print " ";
		# }
		for (my $j = 1 ; $j <= ( $ticker_list_size - $max_size ) ; $j++ )
		{
			pop @{$sample_hash->{$key}};
		}
	}
}

sub calculate_average()
{
	my $array = shift;
	my $array_size =  shift;
	my $output_hash = shift;
	my $ticker = shift;
	my $init = shift;
	
	my $ema_1 = 0;
	my $ema_2 = 0;
	my $average = 0;	
	my $ema_signal = 0;	
	
	if ( $init == 1 )
	{
		# print "$ticker calculate average at init $array_size\n";
		if ( $array_size > $max_average_size )
		{
			for (my $j = 0; $j < $max_average_size; $j++) 		
			{
				my $sum = 0;

				for (my $i = $j; $i < (($array_size - $max_average_size)+$j); $i++) 
				{
							# print " i is $ticker $i \n";				
							my $last_price = get_last($array->[$i]);
							# print "$ticker $last_price ".get_tstmp($array->[$i])." \n";
							$sum += $last_price;
				}			
				
				#average 
				if ($array_size == $max_average_size)
				{
					#just let update samples gather more data
					return;
				}					
				$sum = $sum / (($array_size - $max_average_size));
				
				push @{$output_hash->{$ticker}} , $sum;	
				
				my $output_size = @{$output_hash->{$ticker}};
				if  ( $output_size > $max_average_size )
				{
					#remove the oldest element;
					shift @{$output_hash->{$ticker}};
				}						
			}
		}
		else
		{
			my $sum = 0;
			for (my $i = 0; $i < ($array_size - $max_average_size); $i++) 
			{
						my $last_price = get_last($array->[$i]);
						# print "$ticker $last_price ".get_tstmp($array->[$i])." \n";
						$sum += $last_price;
			}			
			
			#average 
			if ($array_size == $max_average_size)
			{
				#just let update samples gather more data
				return;
			}
			$sum = $sum / ($array_size - $max_average_size);
			
			push @{$output_hash->{$ticker}} , $sum;	
			
			my $output_size = @{$output_hash->{$ticker}};
			if  ( $output_size > $max_average_size )
			{
				#remove the oldest element;
				shift @{$output_hash->{$ticker}};
			}			
		}
	}
	else
	{
		my $sum = 0;
		for (my $i = 0; $i < ($array_size - $max_average_size); $i++) 
		{
			my $last_price = get_last($array->[$i]);
			# print "$ticker $last_price ".get_tstmp($array->[$i])." \n";
			$sum += $last_price;
		}			
		
		#average 
		#average 
		if ($array_size == $max_average_size)
		{
			#just let update samples gather more data
			return;
		}		
		$sum = $sum / ($array_size - $max_average_size);
		
		push @{$output_hash->{$ticker}} , $sum;	
		
		my $output_size = @{$output_hash->{$ticker}};
		if  ( $output_size > $max_average_size )
		{
			#remove the oldest element;
			shift @{$output_hash->{$ticker}};
		}		
	}
}

sub update_average()
{
	my $array = shift;
	my $array_size =  shift;
	my $output_hash = shift;
	my $ticker = shift;

	my $sum = 0;
	for (my $i = 0; $i < ($array_size - $max_average_size); $i++) 
	{
				my $last_price = get_last($array->[$i]);
				$sum += $last_price;
	}			
	
	#average 
	
	$sum = $sum / $array_size;	

	push @{$output_hash->{$ticker}} , $sum;
	
	
	my $output_size = @{$output_hash->{$ticker}};
	if  ( $output_size > $max_average_size )
	{
		#remove the oldest element;
		shift @{$output_hash->{$ticker}};
	}	
}

sub print_number()
{
	my $number = shift;
	
	return sprintf("%0.8f",$number);
}



