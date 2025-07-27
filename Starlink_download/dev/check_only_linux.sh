# 默认检查download.txt中的列表
#!/bin/bash
if [ -z $1 ]; then
    dl='download.txt'
else
    dl=$1
fi
for LINK in $(cat $dl); do
    if [ -f ../$(date +"%Y%m")/$LINK ]; then
        if unzip -t ../$(date +"%Y%m")/$LINK >/dev/null; then
            echo ../$(date +"%Y%m")/$LINK good
            dl=$(echo "$dl" | grep -v $LINK)
        else
            echo ../$(date +"%Y%m")/$LINK bad downloaded
            rm ../$(date +"%Y%m")/$LINK
        fi
    else
        echo ../$(date +"%Y%m")/$LINK not downloaded
    fi
done
