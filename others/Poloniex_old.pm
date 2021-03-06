package Poloniex;
use Time::HiRes qw(time);
use POSIX qw(strftime);
use PHP::HTTPBuildQuery qw(http_build_query);
use Digest::SHA qw(hmac_sha512_hex);
use LWP::UserAgent;
use JSON::XS;
use WWW::Curl::Easy;
use Test::JSON;
use Data::Dumper;               # Perl core module
use Scalar::Util 'blessed';
use Devel::StackTrace;
use Time::localtime;
use Time::Piece;
use Time::Seconds;
use IPC::SysV qw(IPC_PRIVATE S_IRUSR S_IWUSR IPC_CREAT);
use IPC::Semaphore;



sub timestamp {
   my $t = localtime;
   return sprintf( "%04d-%02d-%02d_%02d-%02d-%02d",
                  $t->year, $t->mon, $t->mday,
                  $t->hour, $t->min, $t->sec );
	# %Y-%m-%d_%H-%M-%S				  
	# return localtime;
}

sub new {
 my $class = shift;
 my ( $api_key, $api_secret ) = @_;
 
 $self = bless {
  api_key => $api_key,
  api_secret => $api_secret,
  trading_url => "https://poloniex.com/tradingApi",
  public_url => "https://poloniex.com/public",
 }, $class;
 return $self;
}

sub query {
 my $self = shift;
 my %req = %{$_[0]};
	
 # sleep 250 miliseconds
 # select(undef, undef, undef, 0.25);
 # API unique settings
 my $key = $self->{api_key};
 my $secret = $self->{api_secret};

 # Generate a nonce to avoid problems with 32bit systems
 $req{'nonce'} = time() =~ s/\.//r;
 my $data = \%req;

 $req{'nonce'} += 6000000000;
 # Generate the POST data string
 my $post_data = http_build_query($data, '', '&');
 my $sign = hmac_sha512_hex($post_data, $secret);

 # Generate headers to prove settings
 my @headers = ("Key: $key", "Sign: $sign",);

 #Set up browser
 my $curl = WWW::Curl::Easy->new;
 $curl->setopt( CURLOPT_RETURNTRANSFER, 1 );
 $curl->setopt( CURLOPT_USERAGENT, 'Mozilla/4.0 (compatible; Poloniex Perl bot)' );
 $curl->setopt( CURLOPT_URL, $self->{trading_url} );
 $curl->setopt( CURLOPT_POSTFIELDS, $post_data );
 $curl->setopt( CURLOPT_HTTPHEADER, \@headers );
 $curl->setopt( CURLOPT_SSL_VERIFYPEER, 0 );
 my $response_body;
 $curl->setopt( CURLOPT_WRITEDATA, \$response_body );

 # Send request
 # print "SEND HTTP ".timestamp()." \n";
 my $retcode = $curl->perform;

 if ($retcode == 0) {
  # judge result and next action based on $response_code
  my $response_code = $curl->getinfo(CURLINFO_HTTP_CODE);
  if ($dec = JSON::XS::decode_json($response_body)) {
	  # print "in query \n";
		# print Dumper $dec;
		if (ref($dec) eq "HASH")
		{
			if ( exists($dec->{'error'} ) )
			{
				# print Devel::StackTrace->new()->as_string();			
				print "A logical error happened: $dec->{'error'}\n";
				if ( $dec->{'error'} eq "Order not found, or you are not the person who placed it." )
				{
					return 1;
				}
				return 0;
			}
		}
   if (ref($dec) eq "HASH") { return \%{  $dec  }; } else { return  \@{  $dec  }; }
  } else { return 0; }
 }
 # Error code, type of error, error message
 die "An error happened: $retcode ".$curl->strerror($retcode)." ".$curl->errbuf."\n";
 return 0;
}

sub retrieveJSON {
 $self = shift;
 my $URL = shift;
 my $ua = LWP::UserAgent->new(ssl_opts => { verify_hostname => 1 });
 my $res = $ua->get($URL);
 my $records = $res->decoded_content;
 my $json = JSON::XS::decode_json($records);
 return $json;
}

sub get_ticker {
 $self = shift; my $pair = shift;
 $prices = $self->retrieveJSON($self->{public_url} . '?command=returnTicker');
 if (!$pair || ($pair eq "ALL")) { return %{$prices}; } # Dereference the hash reference
 else {
  $pair = uc($pair);
  if ($prices->{$pair}) { return %{$prices->{$pair}}; } else { return {}; } # Dereference the hash reference or return empty anon hash
 }
}

sub get_trade_history {
 $self = shift; my $pair = shift;
 $trades = $self->retrieveJSON($self->{public_url} . '?command=returnTradeHistory&currencyPair=' . uc($pair));
 return @{$trades};
}


sub get_order_book {
 $self = shift; my $pair = shift;
 $orders = $self->retrieveJSON($self->{public_url} . '?command=returnOrderBook&currencyPair=' . uc($pair));
 return %{$orders};
}

sub get_volume() {
 $self = shift; my $volume = shift;
 $volume = $self->retrieveJSON($self->{public_url} . '?command=return24hVolume');
 return %{$volume};
}

sub get_trading_pairs() {
 $self = shift;
 $tickers = $self->retrieveJSON($self->{public_url} . '?command=returnTicker');
 return keys(%{$tickers});
}


sub get_balances() {
 $self = shift;
 return $self->query(
  {
   command => 'returnBalances'
  }
 );
}

sub get_order_trades() { # Returns the order trades
 $self = shift; $orderNumber= shift;
 my $ret = $self->query(
  {
   'command' => 'returnOrderTrades',
	 'orderNumber' => $orderNumber
  }
 ); 
 
	if  ( $ret == 0 )
	{
		print "RETRY get_order_trades \n"; 
		$ret = $self->query(
		{
		 'command' => 'returnOrderTrades',
		 'orderNumber' => $orderNumber
		}
  	);		
		
		if  ( $ret == 0 )
		{
			print "RETRY2 get_order_trades \n"; 
			$ret = $self->query(
			{
			 'command' => 'returnOrderTrades',
			 'orderNumber' => $orderNumber
			}
			);		
			 if ( $ret == 0 )
			 {
					die " get_order_trades twice failed \n";
			 }		
		}
	}
 return $ret;
}

sub get_open_orders() { # Returns array of open order hashes
 $self = shift; $pair = shift;
 my $ret = $self->query(
  {
   'command' => 'returnOpenOrders',
   'currencyPair' => uc($pair)
  }
 );
 if  ( $ret == 0 )
 {
  print "RETRY get_open_orders \n";
	$ret = $self->query(
		{
		 'command' => 'returnOpenOrders',
		 'currencyPair' => uc($pair)
		}
	 ); 
	 if ( $ret == 0 )
	 {
			print "RETRY2 get_open_orders \n";
			$ret = $self->query(
			{
			 'command' => 'returnOpenOrders',
			 'currencyPair' => uc($pair)
			}
		 ); 	 
			 if ( $ret == 0 )
			 {
				die " get_open_orders three times failed \n";
				}
	 }
 }
 return $ret;
}

sub get_my_trade_history() {
 $self = shift; $pair = shift;
  my $ret = $self->query(
  {
   'command' => 'returnTradeHistory',
   'currencyPair' => uc($pair)
  }
 );
 
	if  ( $ret == 0 )
	{
		print "RETRY get_my_trade_history \n";  
		$ret = $self->query(
			{
			 'command' => 'returnTradeHistory',
			 'currencyPair' => uc($pair)
			}
		 );	
		
		 if ( $ret == 0 )
		 {
				die " get_my_trade_history twice failed \n";
		 }		
	}
 
 return $ret;
}


sub buy() {
 # print "In buy \n";
 my $self = shift; my $pair = shift; my $rate = shift; my $amount = shift;
 my $ret = $self->query(
  {
   'command' => 'buy',
   'currencyPair' => uc($pair),
   'rate' => $rate,
   'amount' => $amount
  }
 );
 
	if  ( $ret == 0 )
	{
		print "RETRY buy \n"; 
		$ret = $self->query(
			{
			 'command' => 'buy',
			 'currencyPair' => uc($pair),
			 'rate' => $rate,
			 'amount' => $amount
			}
		 );		
	 if ( $ret == 0 )
	 {
			die " buy twice failed \n";
	 }
	}
 
 return $ret;
}

sub sell() {
 $self = shift; my $pair = shift; my $rate = shift; my $amount = shift;
   my $ret = $self->query(
  {
   'command' => 'sell',
   'currencyPair' => uc($pair),
   'rate' => $rate,
   'amount' => $amount
  }
 );
 
	if  ( $ret == 0 )
	{
		print "RETRY sell \n"; 
		
		$ret = $self->query(
			{
			 'command' => 'sell',
			 'currencyPair' => uc($pair),
			 'rate' => $rate,
			 'amount' => $amount
			}
		 );		
		
		 if ( $ret == 0 )
		 {
				die " sell  twice failed \n";
		 }			
		
	}
 
 return $ret;
}

sub cancel_order() {
 $self = shift; my $pair = shift; my $order_number = shift;
  my $ret = $self->query(
  {
   'command' => 'cancelOrder',
   'currencyPair' => uc($pair),
   'orderNumber' => $order_number
  }
 );
 
	if  ( $ret == 0 )
	{
		print "RETRY cancel_order \n"; 
		$ret = $self->query(
			{
			 'command' => 'cancelOrder',
			 'currencyPair' => uc($pair),
			 'orderNumber' => $order_number
			}
		 );	
		 if ( $ret == 0 )
		 {
			print "RETRY2 cancel_order \n"; 
			$ret = $self->query(
				{
				 'command' => 'cancelOrder',
				 'currencyPair' => uc($pair),
				 'orderNumber' => $order_number
				}
			 );	

				 if ( $ret == 0 )
				 {
				die " cancel_order twice failed \n";
				}
		 }		
	}
 
 return $ret;
}

sub withdraw() {
 $self = shift; my $currency = shift; my $amount = shift; my $address = shift;
 return $self->query(
  {
   'command' => 'withdraw',
   'currency' => uc($currency),
   'amount' => $amount,
   'address' => $address
  }
 );
}


sub public_url {
 my $self = shift;
 if (@_) {
  $self->{public_url} = shift;
 }
 return $self->{public_url};
}


1;
