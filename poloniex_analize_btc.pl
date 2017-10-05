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


my $basename = basename($0,".pl");

my $crt_iteration = 0;

my $filename_status= $basename."_status.ctrl";
my $filename_status_h;

my $sleep_interval = 10; # sleep interval in seconds , the default
my $hours_back = 6 ; # nr of hours back for btc samples

sub get_json;
sub timestamp;
sub trim;
sub get_samples_btc;
sub update_samples_btc;
sub trim_list;
sub print_number;


sub get_tstmp_btc;
sub get_last_btc;

my @btc_samples_list;




my $database="poloniex";
my $hostname="localhost";
my $user="ciprian";

#clean the db from old samples 
`./clean_db.pl`;

# Connect to the database.
my $dbh = DBI->connect("DBI:mysql:database=$database;host=$hostname","ciprian", "ciprian", {'RaiseError' => 1});
# now retrieve data from the table.
my $sth;


# watchdog
my $filename_wdg = basename($0,".pl")."_wdg.txt";
open(my $fh_wdg, '>', $filename_wdg) or die "Could not open file '$filename_wdg' $!";
print $fh_wdg "start\n";
close $fh_wdg;		

#get the time now
my $script_start_time = timestamp();
my $start_crtTime =   Time::Piece->strptime($script_start_time,'%Y-%m-%d_%H-%M-%S');	

print "=========  initialize samples ".timestamp()." \n";	
get_samples_btc($start_crtTime,$hours_back,\@btc_samples_list);
print "=========  end initialize samples ".timestamp()." \n";	


# set lists to a specific maximum size
trim_list(\@btc_samples_list,$hours_back);

while (1)
{
	my $execute_crt_tstmp = timestamp();
	my $crtTime =   Time::Piece->strptime($execute_crt_tstmp,'%Y-%m-%d_%H-%M-%S');	
	my $latest_sampleTime = Time::Piece->strptime(get_tstmp_btc($btc_samples_list[0]),'%Y-%m-%d_%H-%M-%S');	

	print "============================= ".basename($0,".pl")." $execute_crt_tstmp  $$  $crt_iteration  ======================\n";		
	$crt_iteration++;

	# watchdog
	open(my $fh_wdg, '>', $filename_wdg) or die "Could not open file '$filename_wdg' $!";
	print $fh_wdg "$execute_crt_tstmp\n";
	close $fh_wdg;		
	
	update_samples_btc($crtTime,$latest_sampleTime,\@btc_samples_list);
	# print Dumper \@btc_samples_list;
	
	my $array_size = @btc_samples_list;
	$latest_sampleTime = Time::Piece->strptime(get_tstmp_btc($btc_samples_list[0]),'%Y-%m-%d_%H-%M-%S');	
	my $oldest_sampleTime = Time::Piece->strptime(get_tstmp_btc($btc_samples_list[$array_size -1]),'%Y-%m-%d_%H-%M-%S');	
	my $start_tstmp = $latest_sampleTime->strftime('%Y-%m-%d_%H-%M-%S');
	my $end_tstmp = $oldest_sampleTime->strftime('%Y-%m-%d_%H-%M-%S');
	my $start_price = get_last_btc($btc_samples_list[0]);	
	my $end_price = get_last_btc($btc_samples_list[$array_size -1]);		
	
	my $max = 0;
	my $min = 10000;	
	for (my $i = 0 ;$i < $array_size ; $i++)
	{
		if  ( $max < get_last_btc($btc_samples_list[$i]))
		{
			$max = get_last_btc($btc_samples_list[$i]);
		}
	}
	for (my $i = 0 ;$i < $array_size ; $i++)
	{
		if  ( $min > get_last_btc($btc_samples_list[$i]))
		{
			$min = get_last_btc($btc_samples_list[$i]);
		}
	}
	
	my $delta = 0;
	if ( $max > $start_price )
	{
		$delta = (($max - $start_price)*100) / $start_price;
		$delta *= (-1);
	}
	else
	{
		#the current price is the highest in the window
		# calculate the diference between the current and the lowest
		# print "$start_price $min \n";
		$delta = (( $start_price - $min ) *100) / $min;
	}
	
	my $delta_tstmp  = $crtTime - $oldest_sampleTime;
	print "$array_size $start_tstmp - $end_tstmp  [".$delta_tstmp->pretty."] -----  $start_price - $end_price  - $max - $min - delta [".print_number($delta)."%]\n";
	
	sleep $sleep_interval;
}

# Disconnect from the database.
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




sub get_tstmp_btc
{
	my $param = shift;
	if ( $param =~ /(\S*?)\s+\S*?\s+.*/ )
	{
		return $1;
	}
}


sub get_last_btc
{
	my $param = shift;
	if ( $param =~ /\S*?\s+(\S*?)\s+.*/ )
	{
		return $1;
	}
}


sub get_samples_btc()
{
	my $sample_tstmpTime = shift;
	my $hours_back = shift;
	my $output_hash = shift;
	my $found_tstmp = 0;
	my $sample_tstmp = 0;
	my $minim_TfTime = 0;
	my $minim_sample_tstmp = 0;
	
	$sample_tstmp = $sample_tstmpTime->strftime('%Y-%m-%d_%H-%M-%S');
	# search only between the end of the TF and 60 seconds before
	$minim_TfTime = $sample_tstmpTime - $hours_back*60*60;
	$minim_sample_tstmp = $minim_TfTime->strftime('%Y-%m-%d_%H-%M-%S');
	# print "select * from BTCUSD where tstmp < '$sample_tstmp' and tstmp > '$minim_sample_tstmp' order by tstmp desc limit 1 \n";
	$sth = $dbh->prepare("select * from BTCUSD where tstmp < '$sample_tstmp' and tstmp > '$minim_sample_tstmp' order by tstmp desc");
	$sth->execute();
	while (my $ref = $sth->fetchrow_hashref()) {
		# print "BTCUSD $ref->{'tstmp'} $ref->{'last'} \n";
		my $temp_tstmp =  $ref->{'tstmp'};
		$temp_tstmp =~ s/ /_/g;
		$temp_tstmp =~ s/:/-/g;
		push @{$output_hash} ,"$temp_tstmp $ref->{'last'} ";
	}
	$sth->finish();				
}

sub update_samples_btc()
{
	my $sample_tstmpTime = shift;
	my $sample_endTime = shift;
	my $output_hash = shift;
	my $found_tstmp = 0;
	my $sample_tstmp = 0;
	my $minim_TfTime = 0;
	my $minim_sample_tstmp = 0;
	
	$sample_tstmp = $sample_tstmpTime->strftime('%Y-%m-%d_%H-%M-%S');
	# search only between until the last element that we have
	$minim_TfTime = $sample_endTime;
	$minim_sample_tstmp = $minim_TfTime->strftime('%Y-%m-%d_%H-%M-%S');
	# print "select * from BTCUSD where tstmp < '$sample_tstmp' and tstmp > '$minim_sample_tstmp' order by tstmp asc \n";
	$sth = $dbh->prepare("select * from BTCUSD where tstmp < '$sample_tstmp' and tstmp > '$minim_sample_tstmp' order by tstmp asc");
	$sth->execute();
	while (my $ref = $sth->fetchrow_hashref()) {
		# print "BTCUSD $ref->{'tstmp'} $ref->{'last'} \n";
		my $temp_tstmp =  $ref->{'tstmp'};
		$temp_tstmp =~ s/ /_/g;
		$temp_tstmp =~ s/:/-/g;		
		if ( $temp_tstmp ne get_tstmp_btc($output_hash->[0]) )
		{
			unshift @{$output_hash} ,"$temp_tstmp $ref->{'last'} ";
		}
	}
	$sth->finish();		


	trim_list(\@btc_samples_list,$hours_back);	

}


sub trim_list()
{
	my $output_hash = shift;
	my $hours_back = shift;

	#remove the old btcusd samples
	my $diff_time = 0;
	do
	{
		my $output_hash_size = @{$output_hash};
		my $start_tstmp = get_tstmp_btc($output_hash->[0]);
		my $end_tstmp = get_tstmp_btc($output_hash->[$output_hash_size - 1]);
		my $startTime = Time::Piece->strptime($start_tstmp,'%Y-%m-%d_%H-%M-%S');	
		my $endTime = Time::Piece->strptime($end_tstmp,'%Y-%m-%d_%H-%M-%S');	
		$diff_time =  $startTime - $endTime ;
		if  ( $diff_time > (($hours_back+1)*60*60) )
		{
			#we have more then $hourse_back + 1h samples
			#delete the old samples
			pop @{$output_hash};
		}
	} while ( $diff_time > (($hours_back+1)*60*60) )	
	
}



sub print_number()
{
	my $number = shift;
	
	return sprintf("%0.8f",$number);
}



