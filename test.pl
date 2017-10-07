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

use Selenium::Chrome;
use Selenium::Remote::WebElement;
use Selenium::Remote::WDKeys;
#my $url = "https://www.investing.com/currencies/btc-usd-technical";
#my $content = get($url);

#print Dumper $content;

my $driver = Selenium::Chrome->new;

$driver->get('https://www.investing.com/currencies/btc-usd-technical');
$driver->send_keys_to_active_element(KEYS->{'escape'});
#print $driver->get_body();
#print Dumper $driver->get_alert_text;


my $element =  $driver->find_element_by_link_text("5 Hours");
$element->click();
print $driver->get_body();
 #print $driver->get_page_source();

#element = $driver->find_element_by_id("techinalContent");
#rint Dumper $element->getElementText();
#rint $element->get_text();
#print Dumper $element;
#$element->click();
$driver->pause(100000);  # 10 second delay
# when you're done
$driver->shutdown_binary;