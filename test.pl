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

#use Selenium::Chrome;
use Selenium::Remote::Driver;
use Selenium::Remote::WebElement;
use Selenium::Remote::WDKeys;
#my $url = "https://www.investing.com/currencies/btc-usd-technical";
#my $content = get($url);

#print Dumper $content;

my $driver = new Selenium::Remote::Driver('browser_name'       => 'chrome','platform'           => 'LINUX');

#print Dumper $driver;

#my $driver = new Selenium::Remote::Driver();

$driver->get('https://www.investing.com/currencies/btc-usd-technical');

sleep(2);
$driver->send_keys_to_active_element(KEYS->{'escape'});
#print $driver->get_body();
#print Dumper $driver->get_alert_text;

my $element =  $driver->find_element_by_link_text("5 Hours");
$element->click();
#print $driver->get_body();
 #print $driver->get_page_source();

sleep(2);

$element = $driver->find_element_by_id("techinalContent");

my $element_table = $driver->find_child_element($element,"//table[\@class='genTbl closedTbl technicalIndicatorsTbl smallTbl float_lang_base_1']");

print $element_table->get_text();

print "found table\n";
my $element_trs = $driver->find_child_elements($element_table,"//tbody");
#print "found tbody\n";
#print "tbody : \n".$element_tbody->get_text()."\n";
#my $childs = $driver->find_child_elements($element_tbody,"//tr");
#print "found trs\n";
print "size of childs ".@{$element_trs}." \n";
#foreach (@{$childs})
#{
#	print $_->get_text()."\n\n\n";
#	my $child = $driver->find_child_element($_,"//td[\@class='first left symbol']");
#	print  $child->get_text()." ";
#	$child = $driver->find_child_element($_,"//td[\@class='left textNum bold']");
#	print  $child->get_text()."\n";	
#	#sleep(1);
#}

#print $element->get_text();
#print $element->get_value();
#print $element->get_tag_name();
# my $childs = $driver->find_child_elements($element, "//td[\@class='first left symbol']");
# my $size = @{$childs};
# print "size is $size \n";
#print Dumper $childs;
#print $childs->[1]->get_value();
#print $childs->[1]->get_text();
#foreach (@{$childs})
#{
#	#print $_->get_value()."\n";
#	print  $_->get_text()."\n";
#	#sleep(1);
#}
#rint Dumper $element->getElementText();
#rint $element->get_text();
#print Dumper $element;
#$element->click();
$driver->pause(10000);  # 10 second delay
# when you're done
$driver->close();

$driver->quit();

