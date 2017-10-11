#!/bin/sh 

while [ 1 ]
do
	PID_OUT=`ps -ef | grep multiple_eth_base.pl | grep -v grep`
	# echo ${PID_OUT}
	if [ $? -eq 0 ]
	then
		#found one
		PID=`echo ${PID_OUT} | awk '{print $2}'`
		echo "multiple_eth_base.pl is ${PID}"
	else
		./multiple_eth_base.pl
		
	fi
	sleep 2s
done
