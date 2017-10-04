#!/bin/sh

#. /home/ciprian/.bashrc
pid=0
startup=0

ctrl_c()
{
	echo "$0 Trapped CTRL-C"
	if [ $pid -ne 0 ]
	then 
		#send a trap first
		kill -10 $pid 2>/dev/null
		sleep 10
		echo "Killing $pid"
		kill -9 $pid 2>/dev/null
		pid=0
	fi
	exit 0
}

trap ctrl_c INT

while [ 1 ]
do
	echo "============GENESIS polo $0 $$============"
	date
	./manage_poloniex_trade_monoton.sh

	sleep 10s
done
