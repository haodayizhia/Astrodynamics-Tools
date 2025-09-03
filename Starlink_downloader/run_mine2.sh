#!/bin/bash
export https_proxy=http://127.0.0.1:10808
LOGFILE="$HOME/Desktop/1.txt"
date >> $LOGFILE
/e/Starlink_downloader/mine2.sh | grep --line-buffered -E 'date|now|Script|Download completed' >> $LOGFILE 2>&1