#!/bin/sh -x

while [ 1 ]
do
	PID_OUT=`ps -ef | grep poloniex_get_data.pl | grep -v grep`
	# echo ${PID_OUT}
	if [ $? -eq 0 ]
	then
		#found one
		PID=`echo ${PID_OUT} | awk '{print $2}'`
		echo "poloniex_trade_macd is ${PID}"
	else
		./poloniex_get_data.pl
		
	fi
	sleep 5s
done
