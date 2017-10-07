#!/bin/sh


gnome-terminal --show-menubar --maximize --tab-with-profile=Ciprian -e 'bash -c "source /home/ciprian/.bashrc ; /media/sf_shared/temp/polo/start_get_data.sh"' --tab-with-profile=Ciprian -e 'bash -c "source /home/ciprian/.bashrc ; sleep 5s ; /media/sf_shared/temp/polo/start_wdg_get_data.sh"' --tab-with-profile=Ciprian -e 'bash -c "source /home/ciprian/.bashrc ; /media/sf_shared/temp/polo/start_get_btc.sh"' --tab-with-profile=Ciprian -e 'bash -c "source /home/ciprian/.bashrc ; sleep 5s ; /media/sf_shared/temp/polo/start_wdg_get_btc.sh"' --tab-with-profile=Ciprian -e 'bash -c "source /home/ciprian/.bashrc ; /media/sf_shared/temp/polo/start_analize_btc.sh"' --tab-with-profile=Ciprian -e 'bash -c "source /home/ciprian/.bashrc ; sleep 5s ; /media/sf_shared/temp/polo/start_wdg_analize_btc.sh"' 

