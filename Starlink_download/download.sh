#!/bin/bash
# 在Starlink_download路径下用git bash运行,文件保存中的:替换为合法字符_

# 定义一个函数，在捕获到 SIGINT 信号时执行
cleanup() {
    echo ""
    echo "捕获到 CTRL+C (SIGINT)"
    if [ -n "$current_standby_timeout" ] && [ -n "$current_hibernate_timeout" ]; then
        powercfg -change standby-timeout-ac $current_standby_timeout
        powercfg -change hibernate-timeout-ac $current_hibernate_timeout
        echo "将睡眠时间调回$current_standby_timeout 分钟,将休眠时间调回$current_hibernate_timeout 分钟"
        echo "请手动运行check.sh检查"
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
        DIR="../${UTC:0:4}${UTC:5:2}"
        FILE="${DIR}/${LINK//:/_}"

        # 如果下载错误，耗时小于5s，暂停300s，重置cookies
        # if ((count > 0)) && ((time_serials[count] - time_serials[count - 1] < 5)); then
        #     sleep 300
        #     curl -c cookies.txt -b cookies.txt https://www.space-track.org/ajaxauth/login -d 'identity=trliu@pmo.ac.cn&password=123456789abcdef' >/dev/null
        #     time_serials[count]=$(date +%s)
        # fi

        # 下载开始时间
        # time_beg=$(date +%s)
        # echo $(date -d @${time_beg}) downloading $LINK

        UTC=${LINK%UTC*}
        UTC=${UTC:0-10}
        # 记录下载时刻
        time_serials[count]=$(date +%s)
        # 如果15分钟内下载超过10个文件，暂停等过15分钟，重置cookies
        if ((count > 8)); then
            elapsed_time=$((time_serials[count] - time_serials[count - 9]))
            if ((elapsed_time < 900)); then
                sleep $((900 - elapsed_time))
                curl -c cookies.txt -b cookies.txt https://www.space-track.org/ajaxauth/login -d 'identity=trliu@pmo.ac.cn&password=123456789abcdef' >/dev/null
                time_serials[count]=$(date +%s)
            fi
        fi
        echo $(date -d @${time_serials[count]}) downloading $LINK
        # 最大下载时间20分钟 --max-time 1200
        curl --cookie cookies.txt -A "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/127.0.0.0 Safari/537.36" --max-time 1200 https://www.space-track.org/publicfiles/query/class/download?name=$LINK --output $FILE
        # 下载超时删除
        if [ $? -ne 0 ]; then
            rm -f $FILE
        fi
        count+=1

        # 下载结束时间
        # time_end=$(date +%s)
        # 如如果下载错误，耗时小于10s，暂停600s
        # if ((time_end - time_beg < 10)); then
        #     sleep 600
        # fi

        # 下载并将:改为_,最大超时时间600s,超时后重试3次，自动断点续传
        # curl --cookie cookies.txt --retry 3 --retry-delay 2 --max-time 600 -C - -A "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/127.0.0.0 Safari/537.36" https://www.space-track.org/publicfiles/query/class/download?name=$LINK --output ../${UTC:0:4}${UTC:5:2}/${LINK//:/_}

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
    # 如果在windows系统，插入电源下载时不睡眠和休眠
    if uname -s | grep -q 'MINGW\|MSYS' || [ "$OS" = "Windows_NT" ] || [[ "$OSTYPE" == "msys"* || "$OSTYPE" == "mingw"* ]]; then
        current_standby_timeout=$(($(powercfg -query SCHEME_CURRENT SUB_SLEEP STANDBYIDLE | grep "当前交流电源设置索引" | awk -F ': ' '{print $2}' | tr -d ' ') / 60))
        current_hibernate_timeout=$(($(powercfg -query SCHEME_CURRENT SUB_SLEEP HIBERNATEIDLE | grep "当前交流电源设置索引" | awk -F ': ' '{print $2}' | tr -d ' ') / 60))
        if [ -n "$current_standby_timeout" ] && [ -n "$current_hibernate_timeout" ]; then
            # 修改显示器关闭时间和休眠时间为 0（禁用）
            powercfg -change standby-timeout-ac 0
            powercfg -change hibernate-timeout-ac 0
            echo "检测到Windows系统, 当前设置："
            echo "睡眠时间：$current_standby_timeout 分钟 -> 0 分钟"
            echo "休眠时间：$current_hibernate_timeout 分钟 -> 0 分钟"
        else
            echo "无法检测到当前电源设置索引，请检查系统配置。"
        fi
    fi
    echo $(date) >>log/filelist.txt
    echo $fl >>log/filelist.txt
    # 截取NASAJSC_ReadMe_23643_ReadMe_2023-10-23UTC15:49:52_1.zip格式
    dl=$(echo $fl | grep -o \"[^],[]*\")
    dl=$(echo $dl | grep -o "[^\"]*zip")
    # 如果文件夹存在，排除已下载，否则创建文件夹
    updated_dl=""
    declare -A dir_cache
    for LINK in $dl; do
        UTC=${LINK%UTC*}
        UTC=${UTC:0-10}
        DIR="../${UTC:0:4}${UTC:5:2}"
        FILE="${DIR}/${LINK//:/_}"
        # 缓存目录检查结果
        if [ -z "${dir_cache[$DIR]}" ]; then
            mkdir -p "$DIR"
            dir_cache[$DIR]=1
        fi
        # 检查文件是否存在
        if [ ! -f "$FILE" ]; then
            updated_dl+="$LINK"$'\n'
        fi
    done
    dl=$(sed '$d' <<<$updated_dl)

    # 不用循环，改为子进程的写法，注意子进程的变量修改不会反映到主进程，所以要用这种写法
    # updated_dl=""
    # updated_dl=echo "$dl" | while read -r LINK; do
    #     UTC=${LINK%UTC*}
    #     UTC=${UTC:0-10}
    #     DIR="../${UTC:0:4}${UTC:5:2}"
    #     FILE="${DIR}/${LINK//:/_}"
    #     if [ -d "$DIR" ]; then
    #         if [ ! -f "$FILE" ]; then
    #             echo $LINK
    #         fi
    #     else
    #         mkdir -p "$DIR"
    #         echo $LINK
    #     fi
    # done
    # dl=$updated_dl

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

    again=10
    # 第几次下载
    declare -i count=0
    # 下载时刻序列
    time_serials=()
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
                if unzip -t ../$dir/${LINK//:/_} >/dev/null 2>&1; then
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

        # 如果dl为空，下载完成
        # if [ -z "$dl" ]; then again=0; fi

        # echo 'Download again? if yes input 0, else input 1'
        # read -t 60 again
    done
    echo ---end---
    # 将睡眠和休眠时间调回15分钟
    if [ -n "$current_standby_timeout" ] && [ -n "$current_hibernate_timeout" ]; then
        powercfg -change standby-timeout-ac $current_standby_timeout
        powercfg -change hibernate-timeout-ac $current_hibernate_timeout
        echo "将休眠时间调回$current_standby_timeout 分钟,将休眠时间调回$current_hibernate_timeout 分钟"
    fi
else
    echo false
fi
