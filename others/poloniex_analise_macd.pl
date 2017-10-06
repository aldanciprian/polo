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


sub timestamp;
sub print_number;
sub trim;

sub get_tstmp;
sub get_price;
sub get_1;
sub get_2;
sub get_macd;
sub get_signal; 

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



foreach (sort @symbols_list)
{
	my $key = $_;	
	my $filename = "macd/".$key."_macd_generic.txt";
	my $state = 0;
	open(my $fh, '<', $filename) or die "Could not open file '$filename' $!";	
	
	my %intersection;
	$intersection{'tstmp'} = 0;
	$intersection{'price'} = 0;
	$intersection{'1'} = 0;
	$intersection{'2'} = 0;
	$intersection{'macd'} = 0;
	$intersection{'signal'} = 0;		

	my %prev;
	$prev{'tstmp'} = 0;
	$prev{'price'} = 0;
	$prev{'1'} = 0;
	$prev{'2'} = 0;
	$prev{'macd'} = 0;
	$prev{'signal'} = 0;		

	my $delta_prev_price = 0;	
	
	while( my $line = <$fh>)  {   
    my %crt;
		$crt{'tstmp'} = get_tstmp($line);
		$crt{'price'} = get_price($line);
		$crt{'1'} = get_1($line);
		$crt{'2'} = get_2($line);
		$crt{'macd'} = get_macd($line);		
		$crt{'signal'} = get_signal($line);
		
		my $filename_multiple = "macd/".$key."_macd_generic_multiple.txt";
		my %multiple;
		$multiple{'tstmp'} = 0;
		$multiple{'price'} = 0;
		$multiple{'1'} = 0;
		$multiple{'2'} = 0;
		$multiple{'macd'} = 0;
		$multiple{'signal'} = 0;
		open(my $fh_multiple, '<', $filename_multiple) or die "Could not open file '$filename' $!";		
			while( my $line_multiple = <$fh_multiple>)  {   
					$multiple{'tstmp'} = get_tstmp($line_multiple);
					$multiple{'price'} = get_price($line_multiple);
					$multiple{'1'} = get_1($line_multiple);
					$multiple{'2'} = get_2($line_multiple);
					$multiple{'macd'} = get_macd($line_multiple);
					$multiple{'signal'} = get_signal($line_multiple);
					
					my $multipleTime =  Time::Piece->strptime($multiple{'tstmp'},'%Y-%m-%d_%H-%M-%S');
					my $crtTime = Time::Piece->strptime($crt{'tstmp'},'%Y-%m-%d_%H-%M-%S');
					if ($multipleTime > $crtTime)
					{
						last;
					}
			}
		close $fh_multiple;
		
		if ( $prev{'price'} != 0 )
		{
			$delta_prev_price = ( ($crt{'price'} - $prev{'price'} ) * 100) / $prev{'price'};		
		}

		$prev{'price'} = $crt{'price'};
		
			if ( $state == 0 )
			{
					if ( $crt{'macd'} < $crt{'signal'} )
					{
						$state = 1; # going to buy
					}
					else
					{
						$state = 2; # going to sell
					}
			}
	
			if ( $state == 1 )
			{
				if ( $crt{'macd'} > $crt{'signal'} )
				{
					# a cross
					$state = 2;
					
					print "CROSS buy\n";
					$intersection{'tstmp'} = $crt{'tstmp'};
					$intersection{'price'} = $crt{'price'};
					$intersection{'1'} = $crt{'1'};
					$intersection{'2'} = $crt{'2'};
					$intersection{'macd'} = $crt{'macd'};
					$intersection{'signal'} = $crt{'signal'};		
					my $delta_macd_signal = 0;
					if ( $crt{'signal'} != 0 )
					{
						$delta_macd_signal = ( ($crt{'macd'} - $crt{'signal'}) * 100 ) / $crt{'signal'} ;
					}			
					my $delta_multiple_macd_signal = 0;
					if ( $multiple{'signal'} != 0 )
					{
						$delta_multiple_macd_signal = ( ($multiple{'macd'} - $multiple{'signal'}) * 100 ) / $multiple{'signal'} ;
					}
					print "$key buy $intersection{'tstmp'} - $crt{'tstmp'} ".print_number($delta_macd_signal)." ".print_number($delta_multiple_macd_signal)." $multiple{'tstmp'} \n";
				}
			}

			if ( $state == 2 )
			{
				if ($intersection{'price'} !=  0 )
				{
					#compare to previous
					my $delta_macd_signal = 0;
					my $delta_signal = 0;
					my $delta_macd = 0;
					my $prev_delta_macd_signal = 0;
					
					my $delta_price = ( ($crt{'price'} - $intersection{'price'}) * 100 ) / $intersection{'price'} ;
					if ( $crt{'signal'} != 0 )
					{
						$delta_macd_signal = ( ($crt{'macd'} - $crt{'signal'}) * 100 ) / $crt{'signal'} ;
						# $delta_signal = ( ($intersection{'signal'} - $crt{'signal'}) * 100 ) / $crt{'signal'};						
					}
					if ( $intersection{'macd'} != 0 )
					{
						$prev_delta_macd_signal = ( ($crt{'signal'} - $intersection{'macd'}) * 100 ) / $intersection{'macd'} ;						
						# $delta_macd = ( ($crt{'macd'} - $intersection{'macd'}) * 100 ) / $intersection{'macd'};
					}
					
					my $rest_data = "";
					my $sth = $dbh->prepare("select * from $key where tstmp = '$crt{'tstmp'}' ;");
					$sth->execute();
					while (my $ref = $sth->fetchrow_hashref()) {
							my $temp_tstmp =  $ref->{'tstmp'};
							# $temp_tstmp = db2tstmp($temp_tstmp);
							$temp_tstmp =~ s/ /_/g;
							$temp_tstmp =~ s/:/-/g;					
							$rest_data = "$temp_tstmp $ref->{'percentChange'} $ref->{'low24hr'} $ref->{'last'} $ref->{'high24hr'} $ref->{'lowestAsk'} $ref->{'quoteVolume'} $ref->{'baseVolume'} $ref->{'id'} $ref->{'highestBid'} $ref->{'isFrozen'} \n";
						}
					$sth->finish();							
					
					
					print "$key $intersection{'tstmp'} - $crt{'tstmp'} P".print_number($delta_price)." ".print_number($delta_macd_signal)." ".print_number($delta_prev_price)." ".print_number($prev_delta_macd_signal)." ".print_number($delta_macd)." ".print_number($intersection{'signal'})." ".print_number($crt{'macd'})." ".print_number($crt{'signal'})." ".print_number($intersection{'price'})." ".print_number($crt{'price'})." $rest_data \n";
				}			
				if ( $crt{'signal'} > $crt{'macd'} )
				{
					# a cross
					$state = 1;
					print "CROSS sell\n";
					$intersection{'tstmp'} = $crt{'tstmp'};
					$intersection{'price'} = $crt{'price'};
					$intersection{'1'} = $crt{'1'};
					$intersection{'2'} = $crt{'2'};
					$intersection{'macd'} = $crt{'macd'};
					$intersection{'signal'} = $crt{'signal'};					
				}
			}
			
	}
	
	
	close $fh;
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
	if ( $param =~ /(\S*?)\s+\S*?\s+\S*?\s+\S*?\s+\S*?\s+\S*?\s+.*/ )
	{
		return $1;
	}
}

sub get_price
{
	my $param = shift;
	if ( $param =~ /\S*?\s+(\S*?)\s+\S*?\s+\S*?\s+\S*?\s+\S*?\s+.*/ )
	{
		return $1;
	}
}

sub get_1
{
	my $param = shift;
	if ( $param =~ /\S*?\s+\S*?\s+(\S*?)\s+\S*?\s+\S*?\s+\S*?\s+.*/ )
	{
		return $1;
	}
}

sub get_2
{
	my $param = shift;
	if ( $param =~ /\S*?\s+\S*?\s+\S*?\s+(\S*?)\s+\S*?\s+\S*?\s+.*/ )
	{
		return $1;
	}
}

sub get_macd
{
	my $param = shift;
	if ( $param =~ /\S*?\s+\S*?\s+\S*?\s+\S*?\s+(\S*?)\s+\S*?\s+.*/ )
	{
		return $1;
	}
}

sub get_signal
{
	my $param = shift;
	if ( $param =~ /\S*?\s+\S*?\s+\S*?\s+\S*?\s+\S*?\s+(\S*?)\s+.*/ )
	{
		return $1;
	}
}



sub print_number()
{
	my $number = shift;
	
	return sprintf("%0.8f",$number);
}

