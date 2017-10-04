#!/usr/bin/perl 


use Data::Dumper;               # Perl core module
use strict;                     # Good practice
use warnings;                   # Good practice


my @array  = ();
my @tested  = ();

my $file = 'out_inertia2.txt';
open my $info, $file or die "Could not open $file: $!";

while( my $line = <$info>)  {   
    # print $line;    
    if ( $line =~ /key=(.*?) .*?D=(\S\.\S).*? I=(.*?) S=(.*?) .*(2017\S*?) .*/ )
		{
			# print "$1 $2 $3 $4 $5\n";
			my $key = $1;
			my $delta = $2;			
			my $raise = $3;			
			my $time = $4;			
			my %elem;
			$elem{'key'} = $key;
			$elem{'delta'} = $delta;			
			$elem{'raise'} = $raise;
			$elem{'time'} = $time;
			$elem{'tstmp'} = $5;
			push @array , \%elem;
		}
}

close $info;

foreach (@array)
{
	my $element = $_;
	my $count = 0;
	my $count_n = 0;	
	my $count_p = 0;	
	
	my @other_array = ();
	# print "$element->{'key'} $element->{'delta'}: \n";
	my $found = 0;
	
	foreach (@tested)
	{
		if ( "$element->{'delta'} $element->{'time'}" eq $_ )
		{
			$found = 1;
			last;
		}
	}
	
	if ( $found == 1 )
	{
		next;
	}

	push @tested , "$element->{'delta'} $element->{'time'}";	
	
	foreach (@array)
	{
		if ( ( $element->{'delta'} == $_->{'delta'} ) and ($element->{'time'} == $_->{'time'}) )
		{
			# print "$element->{'key'} $element->{'delta'}:  $_->{'key'} $_->{'delta'} $_->{'raise'} $_->{'time'} $count \n";
			if ( $_->{'raise'} < 0 )
			{
				$count_n++;
			}
			else
			{
				$count_p++;
			}
			$count++;
		}
		push @other_array ,$_;
	}
	
	
	if ( $count_p > $count_n )
	{
			if  ( ( $count_n <  10 ) and ($count_p > 100) )
			{
				if ( $element->{'raise'} > 2 )
				{
					print "k=$element->{'key'} d=$element->{'delta'} t=$element->{'time'} r=$element->{'raise'} : c=$count n=$count_n p=$count_p\n";				
				}
			}
			# foreach (@other_array )
			# {
				# # print "d=$_->{'delta'} t=$_->{'time'} r=$_->{'raise'} \n";
			# }
	}
	

}
