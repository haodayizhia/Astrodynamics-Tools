#!/bin/bash
# 在Starlink_download路径下用git bash运行,文件保存中的:替换为合法字符_

# 定义一个函数，在捕获到 SIGINT 信号时执行
cleanup() {
    echo ""
    echo "捕获到 CTRL+C (SIGINT)"
    if [ -n "$current_ac_timeout" ]; then
        powercfg -change standby-timeout-ac $current_ac_timeout
        echo "休眠时间调回$current_ac_timeout分钟,请手动运行check.sh检查"
    fi
    # bash check.sh -d
    exit
}

# 绑定 SIGINT 信号到 cleanup 函数
trap cleanup SIGINT
echo "开始执行脚本，按 CTRL+C 中断"

# 下载函数
download_fun() {
    for LINK in $(echo $1); do
        echo downloading $LINK
        UTC=${LINK%UTC*}
        UTC=${UTC:0-10}
        curl --cookie cookies.txt https://www.space-track.org/publicfiles/query/class/download?name=$LINK --output ../${UTC:0:4}${UTC:5:2}/${LINK//:/_}
        # 下载并将:改为_,最大超时时间600s,超时后重试3次，自动断点续传
        # curl --cookie cookies.txt --max-time 600 --retry 3 -C - https://www.space-track.org/publicfiles/query/class/download?name=$LINK --output ../$(date +"%Y%m")/${LINK//:/_}
        # if [ -f ../$(date +"%Y%m")/${LINK//:/_} ]; then
        #     mv ../$(date +"%Y%m")/${LINK//:/_} ../$(date +"%Y%m")/$LINK
        # fi
    done
}

echo ---begin---
bash check.sh -d >/dev/null 2>&1
curl -c cookies.txt -b cookies.txt https://www.space-track.org/ajaxauth/login -d 'identity=trliu@pmo.ac.cn&password=123456789abcdef' >/dev/null
# 访问文件列表并判断是否访问成功
if
    fl=$(curl --cookie cookies.txt https://www.space-track.org/publicfiles/query/class/files)
then
    # 如果在windows系统，插入电源下载时不休眠
    if uname -s | grep -q 'MINGW\|MSYS' || [ "$OS" = "Windows_NT" ] || [[ "$OSTYPE" == "msys"* || "$OSTYPE" == "mingw"* ]]; then
        current_ac_timeout=$(($(powercfg -query SCHEME_CURRENT SUB_SLEEP STANDBYIDLE | grep "当前交流电源设置索引" | awk -F ': ' '{print $2}' | tr -d ' ') / 60))
        if [ -n "$current_ac_timeout" ]; then
            powercfg -change standby-timeout-ac 0
            echo "检测到windows,插入电源下载时不休眠"
        fi
    fi
    echo $(date) >>log/filelist.txt
    echo $fl >>log/filelist.txt
    # 截取NASAJSC_ReadMe_23643_ReadMe_2023-10-23UTC15:49:52_1.zip格式
    dl=$(echo $fl | grep -o \"[^],[]*\")
    dl=$(echo $dl | grep -o "[^\"]*zip")
    # 如果文件夹存在，排除已下载，否则创建文件夹
    for LINK in $(echo $dl); do
        UTC=${LINK%UTC*}
        UTC=${UTC:0-10}
        if [ -d ../${UTC:0:4}${UTC:5:2} ]; then
            if [ -f ../${UTC:0:4}${UTC:5:2}/${LINK//:/_} ]; then
                dl=$(echo "$dl" | grep -v $LINK)
            fi
        else
            mkdir ../${UTC:0:4}${UTC:5:2}
        fi
    done
    echo ---downloading---
    # for i in $(ls ../$(date +"%Y%m")); do
    #     # 将文件名中的_替换回:字符
    #     i1=${i#*UTC}
    #     i1=${i1/_/:}
    #     i1=${i1/_/:}
    #     i=${i%UTC*}"UTC"$i1
    #     dl=$(echo "$dl" | grep -v $i)
    # done

    # for LINK in $(echo $dl); do
    #     echo downloading $LINK
    #     curl --cookie cookies.txt https://www.space-track.org/publicfiles/query/class/download?name=$LINK --output ../$(date +"%Y%m")/${LINK//:/_} # win文件名中:无法直接保存非法字符:
    #     if [ -f ../$(date +"%Y%m")/${LINK//:/_}]; then
    #         mv ../$(date +"%Y%m")/${LINK//:/_} ../$(date +"%Y%m")/$LINK
    #     fi
    # done
    again=3
    while [ "$again" != "0" ]; do
        # 保存本次下载列表备用
        echo "$dl" >log/download.txt
        download_fun "$dl"
        declare -i i=1
        # 检验本次下载的zip文件完整性,删除不完整下载,选择是否重新下载
        for LINK in $(echo $dl); do
            UTC=${LINK%UTC*}
            UTC=${UTC:0-10}
            dir=${UTC:0:4}${UTC:5:2}
            if [ -f ../$dir/${LINK//:/_} ]; then
                if unzip -t ../$dir/${LINK//:/_} >/dev/null; then
                    echo ../$dir/$LINK good
                    dl=$(echo "$dl" | grep -v $LINK)
                    awk -v i="$i" 'NR==i {$2="good"} 1' log/download.txt >log/downloadTemp.txt && mv log/downloadTemp.txt log/download.txt
                else
                    echo ../$dir/$LINK bad downloaded
                    rm ../$dir/${LINK//:/_}
                    awk -v i="$i" 'NR==i {$2="lack"} 1' log/download.txt >log/downloadTemp.txt && mv log/downloadTemp.txt log/download.txt
                fi
            else
                echo ../$dir/$LINK not downloaded
                awk -v i="$i" 'NR==i {$2="lack"} 1' log/download.txt >log/downloadTemp.txt && mv log/downloadTemp.txt log/download.txt
            fi
            i+=1
        done
        ((again--))
        if [ -z "$dl" ]; then again=0; fi
        # echo 'Download again? if yes input 0, else input 1'
        # read -t 60 again
    done
    echo ---end---
    # 将休眠时间调回15分钟
    if [ -n "$current_ac_timeout" ]; then
        powercfg -change standby-timeout-ac $current_ac_timeout
        echo "将休眠时间调回$current_ac_timeout分钟"
    fi
else
    echo false
fi