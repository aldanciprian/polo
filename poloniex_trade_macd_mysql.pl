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
my $down_delta_procent_threshold =  0.23; # the procent from max win down
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
sub get_samples;
sub get_samples_days;
sub update_samples;
sub db2tstmp;
sub calculate_macd_generic;
sub update_macd_generic;
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
my %macd_delta_generic_list;
my %delta_1d_list;


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


my $minute = 0;
my $reminder = 0;
my $endMinute	= 0;
my $endTfTimeGeneric= 0;

# watchdog
my $filename_wdg = basename($0,".pl")."_wdg.txt";
open(my $fh_wdg, '>', $filename_wdg) or die "Could not open file '$filename_wdg' $!";
print $fh_wdg timestamp()."\n";
close $fh_wdg;		

#get the time now
my $script_start_time = timestamp();
my $start_crtTime =   Time::Piece->strptime($script_start_time,'%Y-%m-%d_%H-%M-%S');	

{
	use integer;
	$minute = $start_crtTime->strftime("%M");
	$reminder = $minute % $sample_space;
	$minute = $minute - $reminder;

	$endMinute = sprintf("%02s",$minute);
	$endTfTimeGeneric = $start_crtTime->strftime("%Y-%m-%d_%H-$endMinute-00");
	$endTfTimeGeneric = Time::Piece->strptime($endTfTimeGeneric,'%Y-%m-%d_%H-%M-%S');
}

print "=========  initialize samples ".timestamp()." \n";	
foreach (@symbols_list)
{
	get_samples($_,$sample_space,$endTfTimeGeneric,\%delta_generic_list);	
}
print "=========  end initialize samples ".timestamp()." \n";	


# set lists to a specific maximum size
trim_list(\%delta_generic_list,400);

foreach (sort (keys(%delta_generic_list)) )
{
	my $key = $_;
	my $filename = "macd/".$key."_samples_generic_min.txt";
	open(my $fh, '>', $filename) or die "Could not open file '$filename' $!";

	foreach (@{$delta_generic_list{$key}})
	{
		print $fh "$_ \n";		
	}
	close $fh;		
}

foreach (sort (keys(%delta_generic_list)) )
{
		my $key = $_;
		my $size = @{$delta_generic_list{$key}};
		calculate_macd_generic(\@{$delta_generic_list{$key}},$size,\%macd_delta_generic_list,$key);
}

foreach ( sort (keys %macd_delta_generic_list))
{
	my $key = $_;
	# print ref ($macd_delta_generic_list{$key});
	my $filename = "macd/".$key."_macd_generic.txt";
	open(my $fh, '>', $filename) or die "Could not open file '$filename' $!";
	
	foreach (@{$macd_delta_generic_list{$key}})
	{
		my $elem = $_;
		foreach (keys %{$elem})
		{
			print $fh "$_ ".print_number($elem->{$_}{'price'})." ";
			print $fh print_number($elem->{$_}{'1'})." ";
			print $fh print_number($elem->{$_}{'2'})." ";
			print $fh print_number($elem->{$_}{'macd'})." ";
			print $fh print_number($elem->{$_}{'signal'})."\n";
		}
	}
	
	close $fh;
}


my $polo_wrapper = Poloniex->new($apikey,$sign);

my $runOnce = 0;

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

	#populate the generic distance list

	{
		use integer;
		$minute = $crtTime->strftime("%M");
		$reminder = $minute % $sample_space;
		$minute = $minute - $reminder;

		$endMinute = sprintf("%02s",$minute);
		$endTfTimeGeneric = $crtTime->strftime("%Y-%m-%d_%H-$endMinute-00");
		$endTfTimeGeneric = Time::Piece->strptime($endTfTimeGeneric,'%Y-%m-%d_%H-%M-%S');
	}	

	if  ( ( $crtTime - $endTfTimeGeneric ) < 60 )
	{
		if ( $runOnce == 0 )
		{
			print "update $sample_space min \n";
			$runOnce = 1;			
			foreach (sort @symbols_list)
			{
				my $key = $_;		
				my $good_ticker = 1;
				update_samples($_,$sample_space,$endTfTimeGeneric,\%delta_generic_list);
				
				{
				my $filename = "macd/".$key."_samples_generic_min.txt";
				open(my $fh, '>', $filename) or die "Could not open file '$filename' $!";

				foreach (@{$delta_generic_list{$key}})
				{
					print $fh "$_ \n";		
				}
				close $fh;					
				}
				
				
				#get a 1 day delta trend
				get_samples_days($_,1,$endTfTimeGeneric,\%delta_1d_list);							
				
				if ( defined $delta_generic_list{$key} )	
				{
					# print Dumper %delta_generic_list;
					my $size = @{$delta_generic_list{$key}};
					# print "$key sample list size is $size \n";
					if ( $size > $second_ema )
					{
						update_macd_generic(\@{$delta_generic_list{$key}},$size,\%macd_delta_generic_list,$key);		
					}
					else
					{
						if ( defined $macd_delta_generic_list{$key} )
						{
						#clear the array
						@{$macd_delta_generic_list{$key}}=(); 
						}
						calculate_macd_generic(\@{$delta_generic_list{$key}},$size,\%macd_delta_generic_list,$key);				
					}

					
					my $filename = "macd/".$key."_macd_generic.txt";
					open(my $fh, '>', $filename) or die "Could not open file '$filename' $!";

					#dump file
					foreach (@{$macd_delta_generic_list{$key}})
					{
						my $elem = $_;
						foreach (keys %{$elem})
						{
							print $fh "$_ ".print_number($elem->{$_}{'price'})." ";
							print $fh print_number($elem->{$_}{'1'})." ";
							print $fh print_number($elem->{$_}{'2'})." ";
							print $fh print_number($elem->{$_}{'macd'})." ";
							print $fh print_number($elem->{$_}{'signal'})."\n";
						}
					}
					close $fh;		

					# if ( defined $delta_1d_list{$key} )
					# {
						# my $previous_avg = 0;						
						# my $average_price = 0;
						# my $crt_counter = 0;
						# my $previous_date = "";
						# print "$key size of delta_1d_list is ".@{$delta_1d_list{$key}}." \n";
						# foreach (@{$delta_1d_list{$key}})
						# {
							# my $elem = $_;
							# my $temp_tp = get_tstmp($elem);
							# my $temp_price = get_last($elem);
							# # print "$key Before time [$temp_tp] \n";
							# my $tempTime = Time::Piece->strptime($temp_tp,'%Y-%m-%d_%H-%M-%S');								
							# # print "$key After strptime $temp_tp \n";
							# my $temp_date = $tempTime->strftime("%F");
							# # print "$key After time $temp_tp \n";
							# if ( $previous_date ne $temp_date )
							# {
								# my $old_previous = $previous_avg;
								# if ( $crt_counter != 0 )
								# {
									# $previous_avg  = $average_price % $crt_counter;								
								# }
								# else
								# {
									# $previous_avg = $average_price;
								# }
								# $previous_date = $temp_date;
								# print "$key Avarage trend old $old_previous new $previous_avg \n";
								# if ( $old_previous != 0)
								# {
									# if ( $old_previous < $previous_avg)
									# {
										# #this is not a good ticker
										# $good_ticker = 0;
										# last;
									# }
								# }

								# $average_price = 0;
								# $crt_counter = 0;
								
								
								# $average_price = $temp_price;
								# $crt_counter++;
							# }
							# else
							# {
								# $average_price += $temp_price;
								# $crt_counter++;
							# }
						# }
					# }
					
					# here we make the decision
					my $macd_size = @{$macd_delta_generic_list{$key}};
					if ( $macd_size > 60 )
					{
						if ( $good_ticker == 1 )
						{
							my ($previous_decision_key) = keys %{$macd_delta_generic_list{$key}[-2]};					
							my $previous_macd = $macd_delta_generic_list{$key}[-2]{$previous_decision_key}{'macd'};						
							my $previous_9ema = $macd_delta_generic_list{$key}[-2]{$previous_decision_key}{'signal'};												
							my ($current_decision_key) = keys %{$macd_delta_generic_list{$key}[-1]};					
							my $current_macd = $macd_delta_generic_list{$key}[-1]{$current_decision_key}{'macd'};						
							my $current_9ema = $macd_delta_generic_list{$key}[-1]{$current_decision_key}{'signal'};												
							
							if ( $previous_macd < $previous_9ema )
							{
								my $previous_delta = ($previous_9ema - $previous_macd) * 100 / $previous_macd;
								if ( $current_macd > $current_9ema )
								{
									# this is a good to buy ticker
									my $current_delta = ($current_macd - $current_9ema) * 100 / $current_9ema;
									if ( $current_delta >= $incline_treshold )
									{
										$buy_next =  $key;
										print "The ticker to buy is $key ".print_number($previous_delta)." ".print_number($current_delta)."macd size $macd_size \n";
									}
									# else
									# {
										# print "The ticker to buy is $key has a short incline ".print_number($previous_delta)." ".print_number($current_delta)." \n";
									# }
								}
								# else
								# {
									# print "Not a cross $key $previous_macd $previous_9ema $current_macd $current_9ema \n";
								# }
							}
						} # good ticker
						# else
						# {
							# print "No good trend for $key \n";
						# }					
					}
				}
			}
		}
	}
	else
	{
		$runOnce = 0;
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
						if ( $buy_ticker ne "WRONG" )
						{
							print "buy now \n";
							# buy now
							# write status file - last line
							my $price = get_last($current_list{$buy_ticker});

							if ( $price > 0.00001000 )
							{
								$price = $price - 0.00000010;								
							}
							else
							{
								# just increase with the small resolution
								$price = $price - 0.00000001;							
							}
							my $buy_ammount = $btc_balance / $price ;
							# $buy_ammount = $buy_ammount - ($buy_ammount * 0.0015);
							$current_spike++;
							print "amount to buy $buy_ammount $btc_balance ".print_number($price)." \n";
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
									print "$current_spike $execute_crt_tstmp SELLING BTC_$sell_ticker ".sprintf("%0.8f",$latest_price)." $crt_ammount $crt_order_number $btc_after_sell \n";
									open(my $filename_status_h, '>>', $filename_status) or warn "Could not open file '$filename_status' $!";
									print $filename_status_h "$current_spike $execute_crt_tstmp SELLING BTC_$sell_ticker ".sprintf("%0.8f",$latest_price)." $crt_ammount $crt_order_number $btc_after_sell \n";
									close $filename_status_h;					
									$sleep_interval = $step_wait_execute;									
								}
								else
								{
									print "let it go down $sell_ticker $latest_price $procent $down_delta_procent\n";
								}
							}
							else
							{
								print "let it raise  $sell_ticker $latest_price $procent \n";
								open(my $filename_selling_h, '>', $filename_selling) or warn "Could not open file '$filename_selling' $!";
								print $filename_selling_h "$latest_price\n";
								close $filename_selling_h;									
							}
							$sleep_interval = $step_wait_selling;						
						}
						else
						{
							print "Not reached the wining procent $sell_ticker $latest_price  $crt_price $procent \n";
						}
					}
					else
					{
						my $delta = $crt_price - $latest_price;
						my $procent = (100 * $delta) / $crt_price;
						print "price smaller then bought price $sell_ticker $latest_price  $crt_price -$procent  \n";						
						$sleep_interval = $step_wait_selling;		
						# force the sell 
						if ( $procent > 5 )
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
	open(my $filename_status_h, '<', $filename_status) or warn "Could not open file '$filename_status' $!";
	my $last_line;
	$last_line = $_,while (<$filename_status_h>);
	close $filename_status_h;
	chomp($last_line);
	
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
				if ( $baseVolume > $volumeRef)
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
	my $ticker = shift;
	my $delta = shift;
	my $sample_tstmpTime = shift;
	my $output_hash = shift;
	my $found_tstmp = 0;
	my $sample_tstmp = 0;
	my $minim_TfTime = 0;
	my $minim_sample_tstmp = 0;
	
	my $found = 0;
	
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
		$found = 1;
		if ( $temp_tstmp ne get_tstmp(${$output_hash->{$ticker}}[0]) )
		{
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
		my $array_size = @{$output_hash->{$ticker}};
		if  ( $array_size > 400 )
		{
			pop @{$output_hash->{$ticker}};
		}
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

sub calculate_macd_generic()
{
	my $array = shift;
	my $array_size =  shift;
	my $output_hash = shift;
	my $ticker = shift;
	
	my $ema_1 = 0;
	my $ema_2 = 0;
	my $macd = 0;	
	my $ema_signal = 0;	
	
	my $multiplier_2 = 2/($second_ema+1);
	my $multiplier_1 = 2/($first_ema+1);
	my $multiplier_signal = 2/($signal+1);		
	
	for (my $i = 0; $i < $array_size; $i++) 
	{
			my $crt_tstmp =  get_tstmp($array->[$array_size - 1 - $i]);
			my $last_price = get_last($array->[$array_size - 1 - $i]);
			if ( ($i >=0) && ($i < ($second_ema - 1) ) )
			{
				$ema_2 += $last_price;
			}
			if ( $i == ($second_ema - 1) )
			{
					$ema_2 +=$last_price;
					$ema_2 = $ema_2 / $second_ema;
			}
			if ( $i > ($second_ema - 1) )
			{
				$ema_2 = (($last_price - $ema_2) * $multiplier_2) + $ema_2;			
			}
			
			if ( ($i > ($first_ema - 1 )) && ($i < ($second_ema - 1)  ) )
			{
				$ema_1 += $last_price;
			}
			if ( $i == ($second_ema - 1) )
			{
					$ema_1 +=$last_price;
					$ema_1 = $ema_1 / $first_ema;
			}
			if ( $i > ($second_ema - 1) )
			{
				$ema_1 = (($last_price - $ema_1) * $multiplier_1) + $ema_1;			
			}
			
			if ( $i > ($second_ema - 2) )
			{
				$macd = $ema_1 - $ema_2;
			}
			
			if ( ( $i > ($second_ema - 2) ) && ( $i < ($second_ema - 2 + $signal) ) )
			{
				$ema_signal +=  $macd;
			}
			if ( $i == ($second_ema - 2 + $signal) )
			{
				$ema_signal +=  $macd;
				$ema_signal = $ema_signal / $signal;
			}
			if ( $i > ($second_ema - 2 + $signal) )
			{
				$ema_signal = (($macd - $ema_signal) * $multiplier_signal) + $ema_signal;			
			}
			
			my %crt_elem;
			$crt_elem{$crt_tstmp}{'price'} = $last_price;
			$crt_elem{$crt_tstmp}{'1'} = $ema_1;
			$crt_elem{$crt_tstmp}{'2'} = $ema_2;
			$crt_elem{$crt_tstmp}{'macd'} = $macd;
			$crt_elem{$crt_tstmp}{'signal'} = $ema_signal;
			# print "$crt_tstmp $ticker ".sprintf("%0.8f",$ema_2)." ".sprintf("%0.8f",$ema_1)." ".sprintf("%0.8f",$macd)." ".sprintf("%0.8f",$ema_signal)."  \n";
			push @{$output_hash->{$ticker}} , \%crt_elem;
	}			
}

sub update_macd_generic()
{
	my $array = shift;
	my $array_size =  shift;
	my $output_hash = shift;
	my $ticker = shift;
	
	my $output_array_size = @{$output_hash->{$ticker}};
	my ($key) = keys %{$output_hash->{$ticker}[$output_array_size - 1]};

	my $crt_tstmp =  get_tstmp($array->[0]);
	my $last_price = get_last($array->[0]);
	# print "crt tstmp and last price is $crt_tstmp $last_price \n";
	
	my $ema_1 = $output_hash->{$ticker}[$output_array_size - 1]{$key}{'1'};
	my $ema_2 = $output_hash->{$ticker}[$output_array_size - 1]{$key}{'2'};
	my $macd = 0;
	my $ema_signal = $output_hash->{$ticker}[$output_array_size - 1]{$key}{'signal'};
	
	my $multiplier_26 = 2/($second_ema+1);
	my $multiplier_12 = 2/($first_ema+1);
	my $multiplier_9 = 2/($signal+1);		
	
	$ema_2 = (($last_price - $ema_2) * $multiplier_26) + $ema_2;		
	$ema_1 = (($last_price - $ema_1) * $multiplier_12) + $ema_1;		
	$macd = $ema_1 - $ema_2;
	$ema_signal = (($macd - $ema_signal) * $multiplier_9) + $ema_signal;			
	

	my %crt_elem;
	$crt_elem{$crt_tstmp}{'price'} = $last_price;
	$crt_elem{$crt_tstmp}{'1'} = $ema_1;
	$crt_elem{$crt_tstmp}{'2'} = $ema_2;
	$crt_elem{$crt_tstmp}{'macd'} = $macd;
	$crt_elem{$crt_tstmp}{'signal'} = $ema_signal;	

	push @{$output_hash->{$ticker}} , \%crt_elem;
	
	#remove the oldest element;
	shift @{$output_hash->{$ticker}};
}

sub print_number()
{
	my $number = shift;
	
	return sprintf("%0.8f",$number);
}

sub get_samples_days()
{
	my $ticker = shift;
	my $delta = shift;
	my $sample_tstmpTime = shift;
	my $output_hash = shift;
	my $found_tstmp = 0;
	my $sample_tstmp = 0;
	my $minim_TfTime = 0;
	my $minim_sample_tstmp = 0;
	
	if ( defined $output_hash->{$ticker} )
	{
	#clear the array
	@{$output_hash->{$ticker}}=(); 
	}

	do
	{
		$found_tstmp = 0;	
		$sample_tstmp = $sample_tstmpTime->strftime('%Y-%m-%d_%H-%M-%S');
		# search only between the end of the TF and 60 seconds before
		$minim_TfTime = $sample_tstmpTime - 21600;
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
			if ( $array_size > 20 )
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
		$sample_tstmpTime	= $sample_tstmpTime - ($delta*43200);
	
	
	} while ($found_tstmp == 1)
}

