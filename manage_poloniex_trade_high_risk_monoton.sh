#!/bin/sh 

while [ 1 ]
do
	PID_OUT=`ps -ef | grep poloniex_trade_high_risk_monoton.pl | grep -v grep`
	# echo ${PID_OUT}
	if [ $? -eq 0 ]
	then
		#found one
		PID=`echo ${PID_OUT} | awk '{print $2}'`
		echo "poloniex_trade_high_risk_monoton is ${PID}"
	else
		./poloniex_trade_high_risk_monoton.pl 20
		
	fi
	sleep 2s
done
