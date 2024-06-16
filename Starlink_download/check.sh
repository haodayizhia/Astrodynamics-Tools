#!/bin/bash
# 或手动检查已下载文件完整性 bash check.sh -d "dir1 dir2 ..."参数可选删除错误下载

echo -n >log/badlist.txt # 清空错误列表
dl='log/download.txt'    # 默认检查download.txt列表
delete=1                 # 默认不删除错误下载
for arg in "$@"; do
    if [ "$arg" == "-d" ]; then
        delete=0
    else
        dl=$arg
    fi
done
if [ "$dl" == "log/download.txt" ]; then
    declare -i i=1
    while IFS= read -r line; do
        LINK=$(echo $line | awk '{print $1}')
        if [ -n "$LINK" -a -z "$(echo $line | awk '{print $2}')" ]; then
            UTC=${LINK%UTC*}
            UTC=${UTC:0-10}
            dir=${UTC:0:4}${UTC:5:2}
            if [ -f ../$dir/${LINK//:/_} ]; then
                if unzip -t ../$dir/${LINK//:/_} >/dev/null; then
                    echo ../$dir/$LINK good
                    awk -v i="$i" 'NR==i {$2="good"} 1' $dl >log/downloadTemp.txt && mv log/downloadTemp.txt $dl
                else
                    echo ../$dir/$LINK bad
                    awk -v i="$i" 'NR==i {$2="bad"} 1' $dl >log/downloadTemp.txt && mv log/downloadTemp.txt $dl
                    echo ../$dir/${LINK//:/_} >>log/badlist.txt
                    if [ "$delete" == "0" ]; then
                        rm ../$dir/${LINK//:/_}
                    fi
                fi
            else
                echo ../$dir/$LINK lack
                awk -v i="$i" 'NR==i {$2="lack"} 1' $dl >log/downloadTemp.txt && mv log/downloadTemp.txt $dl
            fi
        fi
        i+=1
    done <$dl
else
    for item in $(echo $dl); do
        if [ ${item:(-1)} == / ]; then
            for LINK in $(ls $item); do
                if unzip -t $item$LINK >/dev/null; then
                    echo $item$LINK good
                else
                    echo $item$LINK bad downloaded
                    echo $item$LINK >>log/badlist.txt
                    if [ $delete == 0 ]; then
                        rm $item$LINK
                    fi
                fi
            done
        else
            for LINK in $(ls $item); do
                if unzip -t $item/$LINK >/dev/null; then
                    echo $item/$LINK good
                else
                    echo $item/$LINK bad downloaded
                    echo $item/$LINK >>log/badlist.txt
                    if [ $delete == 0 ]; then
                        rm $item/$LINK
                    fi
                fi
            done
        fi
    done
fi
