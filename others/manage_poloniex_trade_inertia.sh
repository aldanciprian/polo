#!/bin/sh 

while [ 1 ]
do
	PID_OUT=`ps -ef | grep poloniex_trade_inertia.pl | grep -v grep`
	# echo ${PID_OUT}
	if [ $? -eq 0 ]
	then
		#found one
		PID=`echo ${PID_OUT} | awk '{print $2}'`
		echo "poloniex_trade_inertia is ${PID}"
	else
		./poloniex_trade_inertia.pl
		
	fi
	sleep 2s
done
