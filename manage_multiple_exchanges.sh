#!/bin/sh 

while [ 1 ]
do
	PID_OUT=`ps -ef | grep multiple_exchanges.pl | grep -v grep`
	# echo ${PID_OUT}
	if [ $? -eq 0 ]
	then
		#found one
		PID=`echo ${PID_OUT} | awk '{print $2}'`
		echo "multiple_exchanges.pl is ${PID}"
	else
		./multiple_exchanges.pl 20
		
	fi
	sleep 2s
done
