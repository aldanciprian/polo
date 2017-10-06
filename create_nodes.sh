#!/bin/sh


if [ -z "$1" ]
then
	echo "How many nodes ?"
	return 1 
fi


NR_NODES=$1

for i in `seq 1 $NR_NODES` 
do
	mkdir -p ~/poloniex/polo${i}
 	ln -sf `realpath poloniex_trade_monoton.pl` ~/poloniex/polo${i}/poloniex_trade_monoton${i}.pl
 	ln -sf `realpath poloniex_trade_high_risk_monoton.pl` ~/poloniex/polo${i}/poloniex_trade_high_risk_monoton${i}.pl
#	cp `realpath poloniex_trade_monoton.pl` ~/poloniex/polo${i}/poloniex_trade_monoton${i}.pl
	ln -sf `realpath Poloniex.pm` ~/poloniex/polo${i}/Poloniex.pm
	ln -sf `realpath clean_db.pl` ~/poloniex/polo${i}/clean_db.pl

	cp ./manage_poloniex_trade_monoton.sh ~/poloniex/polo${i}/manage_poloniex_trade_monoton${i}.sh
	sed -i "s/monoton/monoton${i}/g" ~/poloniex/polo${i}/manage_poloniex_trade_monoton${i}.sh
	sed -i "s/BASE/#BASE/g" ~/poloniex/polo${i}/manage_poloniex_trade_monoton${i}.sh
	sed -i "s/cd /#cd /g" ~/poloniex/polo${i}/manage_poloniex_trade_monoton${i}.sh
	cp ./manage_poloniex_trade_high_risk_monoton.sh ~/poloniex/polo${i}/manage_poloniex_trade_high_risk_monoton${i}.sh
	sed -i "s/monoton/monoton${i}/g" ~/poloniex/polo${i}/manage_poloniex_trade_high_risk_monoton${i}.sh
	sed -i "s/BASE/#BASE/g" ~/poloniex/polo${i}/manage_poloniex_trade_high_risk_monoton${i}.sh
	sed -i "s/cd /#cd /g" ~/poloniex/polo${i}/manage_poloniex_trade_high_risk_monoton${i}.sh

	cp ./start_trade_monoton.sh ~/poloniex/polo${i}/start_trade_monoton${i}.sh
	sed -i "s/monoton/monoton${i}/g" ~/poloniex/polo${i}/start_trade_monoton${i}.sh
	sed -i "s/BASE/#BASE/g" ~/poloniex/polo${i}/start_trade_monoton${i}.sh
	sed -i "s/cd /#cd /g" ~/poloniex/polo${i}/start_trade_monoton${i}.sh
	cp ./start_trade_high_risk_monoton.sh ~/poloniex/polo${i}/start_trade_high_risk_monoton${i}.sh
	sed -i "s/monoton/monoton${i}/g" ~/poloniex/polo${i}/start_trade_high_risk_monoton${i}.sh
	sed -i "s/BASE/#BASE/g" ~/poloniex/polo${i}/start_trade_high_risk_monoton${i}.sh
	sed -i "s/cd /#cd /g" ~/poloniex/polo${i}/start_trade_high_risk_monoton${i}.sh

	cp ./wdg_trade_monoton.pl ~/poloniex/polo${i}/wdg_trade_monoton${i}.pl
	sed -i "s/monoton/monoton${i}/g" ~/poloniex/polo${i}/wdg_trade_monoton${i}.pl
	sed -i "s/BASE/#BASE/g" ~/poloniex/polo${i}/wdg_trade_monoton${i}.pl
	sed -i "s/cd /#cd /g" ~/poloniex/polo${i}/wdg_trade_monoton${i}.pl
	cp ./wdg_trade_high_risk_monoton.pl ~/poloniex/polo${i}/wdg_trade_high_risk_monoton${i}.pl
	sed -i "s/monoton/monoton${i}/g" ~/poloniex/polo${i}/wdg_trade_high_risk_monoton${i}.pl
	sed -i "s/BASE/#BASE/g" ~/poloniex/polo${i}/wdg_trade_high_risk_monoton${i}.pl
	sed -i "s/cd /#cd /g" ~/poloniex/polo${i}/wdg_trade_high_risk_monoton${i}.pl

	cp ./start_wdg_trade_monoton.sh ~/poloniex/polo${i}/start_wdg_trade_monoton${i}.sh
	sed -i "s/monoton/monoton${i}/g" ~/poloniex/polo${i}/start_wdg_trade_monoton${i}.sh
	sed -i "s/BASE/#BASE/g" ~/poloniex/polo${i}/start_wdg_trade_monoton${i}.sh
	sed -i "s/cd /#cd /g" ~/poloniex/polo${i}/start_wdg_trade_monoton${i}.sh
	cp ./start_wdg_trade_high_risk_monoton.sh ~/poloniex/polo${i}/start_wdg_trade_high_risk_monoton${i}.sh
	sed -i "s/monoton/monoton${i}/g" ~/poloniex/polo${i}/start_wdg_trade_high_risk_monoton${i}.sh
	sed -i "s/BASE/#BASE/g" ~/poloniex/polo${i}/start_wdg_trade_high_risk_monoton${i}.sh
	sed -i "s/cd /#cd /g" ~/poloniex/polo${i}/start_wdg_trade_high_risk_monoton${i}.sh

done
