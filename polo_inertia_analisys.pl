#!/usr/bin/perl 


use Data::Dumper;               # Perl core module
use strict;                     # Good practice
use warnings;                   # Good practice
use Time::localtime;
use Time::Piece;
use Time::Seconds;
use Switch;
use File::Basename;
use DBI;
use Math::Trig;


sub timestamp;
sub print_number;
sub trim;

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


my $script_start_time = timestamp();
my $start_crtTime =   Time::Piece->strptime($script_start_time,'%Y-%m-%d_%H-%M-%S');	

my $endTime = $start_crtTime - (60*60*24);
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


foreach (sort @symbols_list)
{
	my $key = $_;	
	my $window_size = 60*3; # size of the window in seconds
	my $window_step = 60*3; # seconds to increment the window size
	my $max_window_size = 60*60*2; # seconds where we search maximum  window size
	my $after_window_size = $window_size  * 2; # size after the window where we search for max

	do
	{
		my $array_size = @{$delta_generic_list{$key}};
		foreach (my $i = 0 ; $i < $array_size ; $i++)
		{
			my $temp_tstmp = $delta_generic_list{$key}[$i]->{'tstmp'};
			my $tempTime = Time::Piece->strptime($temp_tstmp,'%Y-%m-%d_%H-%M-%S');
			my $start_afterTime = 0;
			my @temp_array = ();
			my @temp_after_array = ();
			my $stop_array = 0;
			foreach (my $j = $i ; $j < $array_size ; $j++)
			{
				my $inner_temp_tstmp = $delta_generic_list{$key}[$j]->{'tstmp'};
				my $inner_tempTime = Time::Piece->strptime($inner_temp_tstmp,'%Y-%m-%d_%H-%M-%S');
				if ( $stop_array == 0 )
				{
					push @temp_array, $delta_generic_list{$key}[$j];				
					if (($inner_tempTime - $tempTime) >= $window_size)
					{
						# we found the limit of the window
						# get out of this for
						$stop_array = 1;
						$start_afterTime = $inner_tempTime;
						next;
					}
				}
				else
				{
					push @temp_after_array, $delta_generic_list{$key}[$j];
					if (($inner_tempTime - $start_afterTime) >= $after_window_size)
					{
						# we found the limit of the window
						# get out of this for
						last;
					}
				}
			} # end of foreach
			# foreach (@temp_array)
			# {
				# print "$key $_->{'tstmp'} $_->{'last'}\n";
			# }
			# print "$key $temp_tstmp $start_afterTime \n";
			
			my $window_array_size = @temp_array;
			my $after_window_array_size = @temp_after_array;
			my $min_price = 1000;
			my $min_price_indx = 0;
			my $max_price = 0;
			my $max_price_indx = 0;
			my $max_price_after = 0;
			my $max_price_indx_after = 0;
			my $delta_price = 0;
			my $max_increase = 0;
			
			for (my $k = 0 ; $k < $window_array_size ; $k++)
			{
				if ( $min_price > $temp_array[$k]->{'last'} )
				{
					$min_price = $temp_array[$k]->{'last'};
					$min_price_indx = $k;
				}
			}
			
			for (my $k = $min_price_indx ; $k < $window_array_size ; $k++)
			{
				if ( $max_price < $temp_array[$k]->{'last'} )
				{
					$max_price = $temp_array[$k]->{'last'};
					$max_price_indx = $k;
				}
			}
			for (my $k = 0 ; $k < $after_window_array_size ; $k++)
			{
				if ( $max_price_after < $temp_after_array[$k]->{'last'} )
				{
					$max_price_after = $temp_after_array[$k]->{'last'};
					$max_price_indx_after = $k;
				}
			}
			
			if ($min_price != 0 )
			{
				$delta_price = ((($max_price - $min_price) * 100)) / $min_price;			
			}
			
			if ($max_price !=0)
			{
				$max_increase = ((($max_price_after - $max_price) * 100)) / $max_price;			
			}
			

			my $min_tstmp = $temp_array[$min_price_indx]->{'tstmp'};
			my $minTime = Time::Piece->strptime($min_tstmp,'%Y-%m-%d_%H-%M-%S');
			my $max_tstmp = $temp_array[$max_price_indx]->{'tstmp'};
			my $maxTime = Time::Piece->strptime($max_tstmp,'%Y-%m-%d_%H-%M-%S');
			my $after_tstmp = $temp_after_array[$max_price_indx_after]->{'tstmp'};
			my $afterTime = Time::Piece->strptime($after_tstmp,'%Y-%m-%d_%H-%M-%S');
			
			my $delta_tstmp_max_min = $maxTime - $minTime;
			my $delta_tstmp_after_max = $afterTime - $maxTime;
			
			# my $angle=0;
			
			# if ( ($delta_tstmp_max_min != 0) and ($max_price != $min_price) )
			# {
				# $angle = 1 / (tan( ($max_price- $min_price ) / $delta_tstmp_max_min ));			
				# print "\n========= ".print_number($max_price- $min_price )." ".print_number(($max_price- $min_price ) / $delta_tstmp_max_min )." ".print_number(tan( ($max_price- $min_price ) / $delta_tstmp_max_min ))." ".print_number(1/(tan( ($max_price- $min_price ) / $delta_tstmp_max_min )))." \n\n";				
			# }


			print "key=$key $min_price $max_price $max_price_after - D=".print_number($delta_price)." I=".print_number($max_increase)." S=$delta_tstmp_max_min s A=$delta_tstmp_after_max s $min_tstmp $window_size s $after_window_size s $temp_array[$min_price_indx]->{'baseVolume'} $temp_array[$max_price_indx]->{'baseVolume'} ";
			print "$temp_after_array[$max_price_after]->{'baseVolume'} $temp_array[$min_price_indx]->{'quoteVolume'} $temp_array[$max_price_indx]->{'quoteVolume'} $temp_after_array[$max_price_after]->{'quoteVolume'} k $temp_array[$min_price_indx]->{'low24hr'} $temp_array[$max_price_indx]->{'low24hr'} $temp_after_array[$max_price_after]->{'low24hr'}  $temp_array[$min_price_indx]->{'high24hr'} $temp_array[$max_price_indx]->{'high24hr'} $temp_after_array[$max_price_after]->{'high24hr'} \n";
			# foreach (@temp_array)
			# {
				# print "$key $_->{'tstmp'} \n";
			# }
			# print "\nNew window $window_size\n";		
			# exit;
		}
	
		$window_size += $window_step;
		$after_window_size = $window_size  * 2;
		# print "\n\nNew window \n\n";	
		print "\n$key next window $window_size $after_window_size \n";
		# exit;		
	} while ($window_size < ($max_window_size));
}

$dbh->disconnect();

sub trim {
	my $input = shift;
	$input =~ s/^\s+|\s+$//g;
	return $input;
}


sub timestamp {
   my $t = localtime;
   return sprintf( "%04d-%02d-%02d_%02d-%02d-%02d",
                  $t->year, $t->mon, $t->mday,
                  $t->hour, $t->min, $t->sec );
	# %Y-%m-%d_%H-%M-%S				  
	# return localtime;
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




sub print_number()
{
	my $number = shift;
	
	return sprintf("%0.8f",$number);
}

