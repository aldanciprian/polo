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
use Poloniex;


#poloniuex
my $apikey = $ENV{'POLONIEX_APIKEY'};
my $sign = $ENV{'POLONIEX_SIGN'};

my $decoded_json;
my $hashref_temp = 0;

my $previous_price = 0;
my $has_pending_order = 0; # bit to see if there is a pending order ot not
my $crt_order_number = 0; # in case there is a pending order, this should express the order number
my $crt_pair = 0; # the current pair in the order
my $crt_tstmp = 0; # the tstmp of the current order
my $crt_price = 0; # the current price in the order
my $crt_ammount = 0; # the current ammount in the order
my $current_spike = 0; # the current number of buy/sell 
my $btc_balance = 0.0007; # the ammount in BTC
my @queue_pairs_lists; # list with all samplings
my $queue_pairs_lists_size = 30; # size of the list with all samplings
my $wining_procent = 1.1; # the procent where we sell
my $wining_procent_divided = $wining_procent / 100; # the procent where we sell
my $down_delta_procent_threshold =  0.19; # the procent from max win down
my $basename = basename($0,".pl");
my $sample_minutes = 5; # number of minutes between each sample
my $max_distance =  ($sample_minutes*60)+ 60; # maximum distance between 2 samples in seconds
my $min_distance =  ($sample_minutes*60) - 60; # minimum distance between 2 samples in seconds


my $filename_status= $basename."_status.ctrl";
my $filename_status_h;

my $filename_selling= $basename."_selling.ctrl";
my $filename_selling_h;

my $filename_macd= $basename."_macd.ctrl";
my $filename_macd_h;


my $sleep_interval = 10; # sleep interval in seconds , the default
my $step_wait_execute = 10; # number of seconds to wait until verify if the order is executed
my $step_wait_selling = 10;
my $step_wait_sell_execute = 30;
my $step_sampling = 10; # number of seconds between samples when deciding to buy
my $step_sampling_ctr = 0; # counter for macd samplings
my $step_sampling_ctr_size = (280 / $step_sampling); # counter for macd samplings

my $loosingProcent = 20; #the loss limit
my $volumeRef = 70; # only pairs with more then x coin volume

my $buy_timeout = 0; #if it doesn't buy...cancel the order

my $incline_treshold = 15; # procent where macd goes over signal and up


# BUYING 1
# BOUGHT 2
# SELLING 3
# SOLD 4


my $sample_space = $ARGV[0]; #minutes between samples
my $first_ema = $ARGV[1]; #1ema size
my $second_ema = $ARGV[2]; #2ema size
my $signal = $ARGV[3]; #signal size



sub get_json;
sub timestamp;
sub trim;
sub get_state_machine;
sub get_pair_list;
sub get_next_buy_ticker;
sub long_trend;
sub update_samples;
sub db2tstmp;
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
	push @symbols_list , $ref->{'Tables_in_poloniex'};
}
$sth->finish();		



my @potential_inclines = ( 
	{
		delta => "1.1", #c=1159 n=3 p=1156
		time => "397"
	},
	{
		delta => "0.6", #c=958 n=0 p=958
		time => "1243"
	},
	{
		delta => "1.0", #c=916 n=2 p=914
		time => "200"
	},	
	{
		delta => "2.1", #c=885 n=0 p=885
		time => "1599"
	},
);

my $window_size = 2200; # size of the window in seconds

my $script_start_time = timestamp();
my $start_crtTime =   Time::Piece->strptime($script_start_time,'%Y-%m-%d_%H-%M-%S');	

my $endTime = $start_crtTime - $window_size;
my $end_tstmp = $endTime->strftime('%Y-%m-%d_%H-%M-%S');

foreach (sort @symbols_list)
{
	my $key = $_;	
	
	$sth = $dbh->prepare("select * from $key where tstmp < '$script_start_time' and tstmp > '$end_tstmp' order by tstmp asc");
	$sth->execute();
	while (my $ref = $sth->fetchrow_hashref()) {
		# print "$ticker $ref->{'tstmp'} $ref->{'last'} \n";
		my $temp_tstmp =  $ref->{'tstmp'};
		# $temp_tstmp = db2tstmp($temp_tstmp);
		$temp_tstmp =~ s/ /_/g;
		$temp_tstmp =~ s/:/-/g;
		my %elem;
		$elem{'tstmp'} = $temp_tstmp;
		$elem{'percentChange'} = $ref->{'percentChange'};
		$elem{'low24hr'} = $ref->{'low24hr'};
		$elem{'last'} = $ref->{'last'};
		$elem{'high24hr'} = $ref->{'high24hr'};
		$elem{'lowestAsk'} = $ref->{'lowestAsk'};
		$elem{'quoteVolume'} = $ref->{'quoteVolume'};
		$elem{'baseVolume'} = $ref->{'baseVolume'};
		$elem{'id'} = $ref->{'id'};
		$elem{'highestBid'} = $ref->{'highestBid'};
		$elem{'isFrozen'} = $ref->{'isFrozen'};		
		push @{$delta_generic_list{$key}} , \%elem;
		# print "$key $temp_tstmp $ref->{'percentChange'} $ref->{'low24hr'} $ref->{'last'} $ref->{'high24hr'} $ref->{'lowestAsk'} $ref->{'quoteVolume'} $ref->{'baseVolume'} $ref->{'id'} $ref->{'highestBid'} $ref->{'isFrozen'} \n";
	}
	$sth->finish();				
}



my $polo_wrapper = Poloniex->new($apikey,$sign);



while (1)
{
	my $buy_next = "WRONG";
	my $execute_crt_tstmp = timestamp();

	print "============================= ".basename($0,".pl")." $execute_crt_tstmp  $$ ======================\n";		

	
	# watchdog
	my $filename_wdg = basename($0,".pl")."_wdg.txt";
	open(my $fh_wdg, '>', $filename_wdg) or die "Could not open file '$filename_wdg' $!";
	print $fh_wdg "$execute_crt_tstmp\n";
	close $fh_wdg;		
	
	
	my $crtTime =   Time::Piece->strptime($execute_crt_tstmp,'%Y-%m-%d_%H-%M-%S');	


	
	foreach (sort @symbols_list)
	{
		my $key = $_;		
		update_samples($key,$crtTime);
		
		my $filename = "inertial/".$key."_samples_generic.txt";
		open(my $fh, '>', $filename) or die "Could not open file '$filename' $!";
		if ( @{$delta_generic_list{$key}} > 1 )
		{
			foreach (@{$delta_generic_list{$key}})
			{
				my $elem = $_;
				print $fh "$elem->{'tstmp'} $elem->{'percentChange'} $elem->{'low24hr'} $elem->{'last'} $elem->{'high24hr'} $elem->{'lowestAsk'} $elem->{'quoteVolume'} $elem->{'baseVolume'} $elem->{'id'} $elem->{'highestBid'} $elem->{'isFrozen'} \n";
			}
		}
		close $fh;	
		
		if ( @{$delta_generic_list{$key}} <= 1 )
		{
			#this symbol has not enough data
			next;
		}
		
		my $long_trend_array = long_trend($key,$crtTime);
		if ( @{$long_trend_array} >=2 ) 
		{
			# print "trend $delta_generic_list{$key}[-1]->{'tstmp'} $delta_generic_list{$key}[-1]->{'last'} $long_trend_array->[0]->{'tstmp'} $long_trend_array->[0]->{'last'} $long_trend_array->[1]->{'tstmp'} $long_trend_array->[1]->{'last'} ";
			if ( ($delta_generic_list{$key}[-1]->{'last'} < $long_trend_array->[0]->{'last'} ) or ($long_trend_array->[0]->{'last'} < $long_trend_array->[1]->{'last'}) )  
			{
				# the trend is down
				# print " DOWN \n";
				next;
			}
			# else
			# {
				# print " UP \n";			
			# }
		}
		
		my $array_size = @{$delta_generic_list{$key}};		
		my $window_array_size = $array_size;

		my $min_price = 1000;
		my $min_price_indx = 0;
		my $max_price = 0;
		my $max_price_indx = 0;
		my $delta_price = 0;
		my $max_increase = 0;

		for (my $k = 0 ; $k < $window_array_size ; $k++)
		{
			# print "$key $min_price  $delta_generic_list{$key}[$k]->{'last'} \n";
			if ( $min_price > $delta_generic_list{$key}[$k]->{'last'} )
			{
				$min_price = $delta_generic_list{$key}[$k]->{'last'};
				$min_price_indx = $k;
			}
		}

		for (my $k = $min_price_indx ; $k < $window_array_size ; $k++)
		{
			if ( $max_price < $delta_generic_list{$key}[$k]->{'last'} )
			{
				$max_price = $delta_generic_list{$key}[$k]->{'last'};
				$max_price_indx = $k;
			}
		}

		if ($min_price != 0 )
		{
			$delta_price = ((($max_price - $min_price) * 100)) / $min_price;			
		}

		my $min_tstmp = $delta_generic_list{$key}[$min_price_indx]->{'tstmp'};
		my $minTime = Time::Piece->strptime($min_tstmp,'%Y-%m-%d_%H-%M-%S');
		my $max_tstmp = $delta_generic_list{$key}[$max_price_indx]->{'tstmp'};
		my $maxTime = Time::Piece->strptime($max_tstmp,'%Y-%m-%d_%H-%M-%S');

		my $delta_tstmp_max_min = $maxTime - $minTime;

		# print "$key delta $delta_price $delta_tstmp_max_min \n";
		foreach ( @potential_inclines )
		{
			my $delta =  $_->{'delta'};
			my $time =  $_->{'time'};
			if ( (($delta_price >= $delta) and ($delta_price < ($delta + 0.1) ) ) )
			{
				if ( (($delta_tstmp_max_min >= $time) and ($delta_tstmp_max_min < ($time+50) ) ) )
				{
					# This is a good ticker to buy
					print "Buy this ticker $key $delta_tstmp_max_min s $delta_price % current_price $delta_generic_list{$key}[-1]->{'last'} $delta_generic_list{$key}[-1]->{'tstmp'} \n";
					$buy_next = $key;
					last;
				}
			}			
		} # foreach potential incline
	} # foreach symbol
	
	# sleep $sleep_interval;	
	# next;
	
	
	my %current_list;
	#do the sampling
	%current_list = get_pair_list();
	
	# print Dumper %current_list;
	# print "TEST ".get_last($current_list{'VTC'})." \n";
	
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
						# print Dumper $polo_wrapper->get_open_orders("all");						
						$decoded_json = $polo_wrapper->get_open_orders("all");
						# print "ref is ".ref($decoded_json)." \n";
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
							$sleep_interval = $step_wait_execute;
							
							#clear the selling file
							open(my $filename_selling_h, '>', $filename_selling) or warn "Could not open file '$filename_selling' $!";
							close $filename_selling_h;								
							
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
							#after 15 cycles cancel the order
							if ( $buy_timeout == 15 )
							{
								# cancel the order and go back to buying
								$polo_wrapper->cancel_order($crt_pair,$crt_order_number);
								#delete the last line from the status file
								open($filename_status_h,"+<$filename_status") or die;
									while (<$filename_status_h>) {
											if (eof($filename_status_h)) {
												 seek($filename_status_h,-(length($_)),2) or die;
												 truncate($filename_status_h,tell($filename_status_h)) or die;
											}
									}
								close $filename_status_h;
								
								#wait 20 seconds to cancel the order
								sleep 20;
							}
						}
					}
					else
					{
						# there is no order
						# print "there is no order \n";
						my $buy_ticker = $buy_next;
						if ( "BTC_$buy_ticker" == $crt_pair )
						{
							print "The last cycle was with $crt_pair , and the new one cannot be BTC_$buy_ticker.Wait for the next! \n";
							last;
						}
						if ( $buy_ticker ne "WRONG" )
						{
							print "buy now \n";
							# buy now
							# write status file - last line
							my $price = 0;
							$price = get_last($current_list{$buy_ticker});

							if ( $price > 0.00001000 )
							{
								$price = $price - 0.00000010;								
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
							my $buy_ammount = $btc_balance / $price ;
							# $buy_ammount = $buy_ammount - ($buy_ammount * 0.0015);
							$current_spike++;
							print "amount to buy $buy_ticker $buy_ammount $btc_balance ".print_number($price)." \n";
							$buy_timeout = 0;
							$decoded_json = $polo_wrapper->buy("BTC_$buy_ticker",$price,$buy_ammount);
							# $buy_ammount = $buy_ammount - ($buy_ammount * 0.0015);
							 # print Dumper $polo_wrapper->buy("BTC_$buy_ticker",$price,$buy_ammount);
							# print "Buying \n";
							# print Dumper $decoded_json;
							$crt_order_number = $decoded_json->{'orderNumber'};
							print "$current_spike $execute_crt_tstmp BUYING BTC_$buy_ticker ".sprintf("%0.8f",$price)." $buy_ammount $crt_order_number $btc_balance \n";
							open(my $filename_status_h, '>>', $filename_status) or warn "Could not open file '$filename_status' $!";
							print $filename_status_h  "$current_spike $execute_crt_tstmp BUYING BTC_$buy_ticker ".sprintf("%0.8f",$price)." $buy_ammount $crt_order_number $btc_balance \n";
							close $filename_status_h;
							$sleep_interval = $step_wait_selling;
						}
						else
						{
						$sleep_interval = $step_sampling;
						}
					}
			}
	case 2 { 
					print "BOUGHT \n"; 

					# check if the current price is higher then bought price
					my %pairs_list = get_pair_list();

					my $sell_ticker = $crt_pair;
					$sell_ticker =~ s/BTC_(.*)/$1/g ;
					# print Dumper $pairs_list{$sell_ticker};					
					my $latest_price = get_last($pairs_list{$sell_ticker});
					# print "latest_price $latest_price\n";

					if ($latest_price > $crt_price )
					{
						my $delta = $latest_price - $crt_price;
						my $procent = (100 * $delta) / $crt_price;
						print "$sell_ticker $latest_price ".get_tstmp($pairs_list{$sell_ticker})." delta_procent $procent $wining_procent\n";
						if ( $procent >= $wining_procent )
						{
							open(my $filename_selling_h, '<', $filename_selling) or warn "Could not open file '$filename_selling' $!";
							my $last_line;
							$last_line = $_,while (<$filename_selling_h>);
							close $filename_selling_h;
							chomp($last_line);
							
							if ( $last_line =~ /^$/ )
							{
								print "$filename_selling is empty !!\n";						
								$previous_price = $latest_price;
							}
							else
							{
								$previous_price = $last_line;
							}
							
							if ( $previous_price > $latest_price )
							{
								# we went over the top and going down
								my $down_delta = $previous_price - $latest_price;
								my $down_delta_procent =  ( $down_delta * 100 ) / $previous_price ;
								
								if ( $down_delta_procent >= $down_delta_procent_threshold )
								{
									# we went down to much
									#it is time to sell
									if ( $latest_price > 0.00001000 )
									{

										$latest_price = $latest_price + 0.00000010;								
									}
									else
									{
										# just decrease with the small resolution
										$latest_price = $latest_price + 0.00000001;							
									}

									$decoded_json = $polo_wrapper->sell("BTC_$sell_ticker",$latest_price,$crt_ammount);
									$crt_order_number = $decoded_json->{'orderNumber'};
									# print Dumper $decoded_json;
									my $btc_after_sell = $latest_price * $crt_ammount;
									$btc_after_sell = $btc_after_sell - ( $btc_after_sell * 0.0015 );
									print "$current_spike $execute_crt_tstmp SELLING BTC_$sell_ticker ".sprintf("%0.8f",$latest_price)." $crt_ammount $crt_order_number $btc_after_sell $procent % \n";
									open(my $filename_status_h, '>>', $filename_status) or warn "Could not open file '$filename_status' $!";
									print $filename_status_h "$current_spike $execute_crt_tstmp SELLING BTC_$sell_ticker ".sprintf("%0.8f",$latest_price)." $crt_ammount $crt_order_number $btc_after_sell \n";
									close $filename_status_h;					
									$sleep_interval = $step_wait_execute;									
								}
								else
								{
									print "let it go down $sell_ticker $latest_price $procent % $down_delta_procent %\n";
								}
							}
							else
							{
								print "let it raise  $sell_ticker $latest_price $procent %\n";
								open(my $filename_selling_h, '>', $filename_selling) or warn "Could not open file '$filename_selling' $!";
								print $filename_selling_h "$latest_price\n";
								close $filename_selling_h;									
							}
							$sleep_interval = $step_wait_selling;						
						}
						else
						{
							print "Not reached the wining procent $sell_ticker $latest_price  $crt_price $procent %\n";
						}
					}
					else
					{
						my $delta = $crt_price - $latest_price;
						my $procent = (100 * $delta) / $crt_price;
						print "price smaller then bought price $sell_ticker $latest_price  $crt_price -$procent % \n";						
						$sleep_interval = $step_wait_selling;		
						# force the sell 
						if ( $procent > 15 )
						{
							print "WE FORCE THE SELL because procent is -$procent % !!\n";

							if ( $latest_price > 0.00001000 )
							{

								$latest_price = $latest_price + 0.00000010;								
							}
							else
							{
								# just decrease with the small resolution
								$latest_price = $latest_price + 0.00000001;							
							}

							$decoded_json = $polo_wrapper->sell("BTC_$sell_ticker",$latest_price,$crt_ammount);
							$crt_order_number = $decoded_json->{'orderNumber'};
							# print Dumper $decoded_json;
							my $btc_after_sell = $latest_price * $crt_ammount;
							$btc_after_sell = $btc_after_sell - ( $btc_after_sell * 0.0015 );
							print "$current_spike $execute_crt_tstmp SELLING BTC_$sell_ticker ".sprintf("%0.8f",$latest_price)." $crt_ammount $crt_order_number $btc_after_sell \n";
							open(my $filename_status_h, '>>', $filename_status) or warn "Could not open file '$filename_status' $!";
							print $filename_status_h "$current_spike $execute_crt_tstmp SELLING BTC_$sell_ticker ".sprintf("%0.8f",$latest_price)." $crt_ammount $crt_order_number $btc_after_sell \n";
							close $filename_status_h;					
						}
						
						$sleep_interval = $step_wait_execute;		
					}
					
					#case 2
					#make a price higher with 1.5 %
					#sell with that price and wait for the execution
					# my $latest_price = $crt_price + ( $crt_price * $wining_procent);
					# $decoded_json = $polo_wrapper->sell("BTC_$sell_ticker",$latest_price,$crt_ammount);
					# $crt_order_number = $decoded_json->{'orderNumber'};
					# # print Dumper $decoded_json;
					# my $btc_after_sell = $latest_price * $crt_ammount;
					# $btc_after_sell = $btc_after_sell - ( $btc_after_sell * 0.0015 );
					# print "$current_spike $execute_crt_tstmp SELLING BTC_$sell_ticker ".sprintf("%0.8f",$latest_price)." $crt_ammount $crt_order_number $btc_after_sell \n";
					# open(my $filename_status_h, '>>', $filename_status) or warn "Could not open file '$filename_status' $!";
					# print $filename_status_h "$current_spike $execute_crt_tstmp SELLING BTC_$sell_ticker ".sprintf("%0.8f",$latest_price)." $crt_ammount $crt_order_number $btc_after_sell \n";
					# close $filename_status_h;					
					# $sleep_interval = $step_wait_selling;
		    }	
	case 3 { 
					print "SELLING \n";
					my $sell_ticker = $crt_pair;
					my $order_is_not_complete = 0;
					$sell_ticker =~ s/BTC_(.*)/$1/g ;
					my %current_list = 	get_pair_list();
					# print Dumper $current_list{$sell_ticker};
					my $ticker_status = $current_list{$sell_ticker};
					$ticker_status =~ s/\S*?\s+\S*?\s+\S*?\s+(\S*?)\s+.*/$1/g;
					
					$decoded_json = $polo_wrapper->get_open_orders("all");
					# print "ref is ".ref($decoded_json)." \n";
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
						$sleep_interval = $step_wait_execute;
						print "$current_spike $crt_tstmp SOLD $crt_pair ".sprintf("%0.8f",$crt_price)." ".sprintf("%0.8f",$sell_ammount)." $crt_order_number ".sprintf("%0.8f",$total_btc)." \n";						
						open(my $filename_status_h, '>>', $filename_status) or warn "Could not open file '$filename_status' $!";
						print $filename_status_h "$current_spike $crt_tstmp SOLD $crt_pair ".sprintf("%0.8f",$crt_price)." ".sprintf("%0.8f",$sell_ammount)." $crt_order_number ".sprintf("%0.8f",$total_btc)." \n";												
						close $filename_status_h;	
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
						print "$execute_crt_tstmp Order is not completed ! delta is $delta_procent %  $crt_price  $ticker_status \n";	
						$sleep_interval = $step_wait_sell_execute;							
					}					
			}
	case 4 { 
					print "SOLD \n"; 
					print "$current_spike $crt_tstmp BUYING $crt_pair 0 0 0 $btc_balance \n";
					open(my $filename_status_h, '>>', $filename_status) or warn "Could not open file '$filename_status' $!";
					print $filename_status_h "$current_spike $crt_tstmp BUYING $crt_pair 0 0 0 $btc_balance \n";
					close $filename_status_h;				
					$sleep_interval = $step_sampling;
			}	
	else { print "State is not recognised ! \n"; } 
	}
	sleep $sleep_interval;
}

# Disconnect from the database.
$dbh->disconnect();
	
# print " the minimum is  $hashref_temp->{'percentChange'} $hashref_temp->{'name'} \n";

# $decoded_json=get_json("https://poloniex.com/tradingApi ");
# print Dumper $decoded_json;



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
	# $decoded_json=get_json("https://api.nicehash.com/api?method=orders.set.price&id=$apiid&key=$apikey&location=0&algo=$algo&order=$local_specific_order->{'id'}&price=$increase_price");
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
						$current_list{$coinName} = "$tstmp $percentChange $low24hr $last $high24hr $lowestAsk $quoteVolume $baseVolume $id $highestBid $isFrozen ";
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


sub db2tstmp()
{
	my $data = shift;
	
	$data =~ s/ /_/g;
	return $data;
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
			# $temp_tstmp = db2tstmp($temp_tstmp);
			$temp_tstmp =~ s/ /_/g;
			$temp_tstmp =~ s/:/-/g;
			push @{$output_hash->{$ticker}} ,"$temp_tstmp $ref->{'percentChange'} $ref->{'low24hr'} $ref->{'last'} $ref->{'high24hr'} $ref->{'lowestAsk'} $ref->{'quoteVolume'} $ref->{'baseVolume'} $ref->{'id'} $ref->{'highestBid'} $ref->{'isFrozen'} ";
			my $array_size = @{$output_hash->{$ticker}};
			if ( $array_size > 400 )
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
		$sample_tstmpTime	= $sample_tstmpTime - ($delta*60);
	
	
	} while ($found_tstmp == 1)
	
}

sub update_samples()
{
	my $key = shift;
	my $sample_tstmpTime = shift;

	my $sample_tstmp = 0;
	my $minim_TfTime = 0;
	my $minim_sample_tstmp = 0;
	

	$sample_tstmp = $sample_tstmpTime->strftime('%Y-%m-%d_%H-%M-%S');
	# search only between the end of the TF and 60 seconds before
	$minim_TfTime = $sample_tstmpTime - 30;	
	$minim_sample_tstmp = $minim_TfTime->strftime('%Y-%m-%d_%H-%M-%S');	
	
	$sth = $dbh->prepare("select * from $key where tstmp < '$sample_tstmp' and tstmp > '$minim_sample_tstmp' order by tstmp asc");
	$sth->execute();
	while (my $ref = $sth->fetchrow_hashref()) {
		my $temp_tstmp =  $ref->{'tstmp'};
		# $temp_tstmp = db2tstmp($temp_tstmp);
		$temp_tstmp =~ s/ /_/g;
		$temp_tstmp =~ s/:/-/g;
		my %elem;
		$elem{'tstmp'} = $temp_tstmp;
		$elem{'percentChange'} = $ref->{'percentChange'};
		$elem{'low24hr'} = $ref->{'low24hr'};
		$elem{'last'} = $ref->{'last'};
		$elem{'high24hr'} = $ref->{'high24hr'};
		$elem{'lowestAsk'} = $ref->{'lowestAsk'};
		$elem{'quoteVolume'} = $ref->{'quoteVolume'};
		$elem{'baseVolume'} = $ref->{'baseVolume'};
		$elem{'id'} = $ref->{'id'};
		$elem{'highestBid'} = $ref->{'highestBid'};
		$elem{'isFrozen'} = $ref->{'isFrozen'};		
		if ( $temp_tstmp ne $delta_generic_list{$key}[-1]->{'tstmp'} )
		{		
			push @{$delta_generic_list{$key}} , \%elem;
		}
	}
	$sth->finish();	
	
	my $firstTime = 0;
	my $lastTime = 0;
	$firstTime =  Time::Piece->strptime($delta_generic_list{$key}[0]->{'tstmp'},'%Y-%m-%d_%H-%M-%S');	
	$lastTime =  Time::Piece->strptime($delta_generic_list{$key}[-1]->{'tstmp'},'%Y-%m-%d_%H-%M-%S');		
	
	while ( ($lastTime - $firstTime) > $window_size )	
	{
		# print "$key eliminate one record \n";
		shift @{$delta_generic_list{$key}} ;	
		$firstTime =  Time::Piece->strptime($delta_generic_list{$key}[0]->{'tstmp'},'%Y-%m-%d_%H-%M-%S');	
		$lastTime =  Time::Piece->strptime($delta_generic_list{$key}[-1]->{'tstmp'},'%Y-%m-%d_%H-%M-%S');		
	}

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

sub print_number()
{
	my $number = shift;
	
	return sprintf("%0.8f",$number);
}


sub long_trend()
{
	my $key = shift;
	my $sample_tstmpTime = shift;
	my @trend_array = ();
	
	for (my $i = 0 ; $i < 2; $i++ )
	{
		$sample_tstmpTime = $sample_tstmpTime - 60*60*24*1;
		my $tstmp_to_compare = $sample_tstmpTime->strftime('%Y-%m-%d_%H-%M-%S');	
		# print "$key long trend $tstmp_to_compare \n";
		$sth = $dbh->prepare("select * from $key where tstmp < '$tstmp_to_compare' order by tstmp desc limit 1");
		$sth->execute();
		while (my $ref = $sth->fetchrow_hashref()) {
			# print "$ticker $ref->{'tstmp'} $ref->{'last'} \n";
			my $temp_tstmp =  $ref->{'tstmp'};
			# $temp_tstmp = db2tstmp($temp_tstmp);
			$temp_tstmp =~ s/ /_/g;
			$temp_tstmp =~ s/:/-/g;
			my %elem;
			$elem{'tstmp'} = $temp_tstmp;
			$elem{'percentChange'} = $ref->{'percentChange'};
			$elem{'low24hr'} = $ref->{'low24hr'};
			$elem{'last'} = $ref->{'last'};
			$elem{'high24hr'} = $ref->{'high24hr'};
			$elem{'lowestAsk'} = $ref->{'lowestAsk'};
			$elem{'quoteVolume'} = $ref->{'quoteVolume'};
			$elem{'baseVolume'} = $ref->{'baseVolume'};
			$elem{'id'} = $ref->{'id'};
			$elem{'highestBid'} = $ref->{'highestBid'};
			$elem{'isFrozen'} = $ref->{'isFrozen'};		
			push @trend_array , \%elem;
			# print "$key $temp_tstmp $ref->{'percentChange'} $ref->{'low24hr'} $ref->{'last'} $ref->{'high24hr'} $ref->{'lowestAsk'} $ref->{'quoteVolume'} $ref->{'baseVolume'} $ref->{'id'} $ref->{'highestBid'} $ref->{'isFrozen'} \n";
		}
		$sth->finish();	
	}
	return \@trend_array;
}