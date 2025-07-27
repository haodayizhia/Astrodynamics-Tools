# 在linux上运行,文件名保留":"和官网一致,Starlink_download路径下运行
#!/bin/bash
download_fun() {
    for LINK in $(echo $1); do
        echo downloading $LINK
        curl --cookie cookies.txt https://www.space-track.org/publicfiles/query/class/download?name=$LINK --output ../$(date +"%Y%m")/$LINK
    done
}
echo ----begin---
curl -c cookies.txt -b cookies.txt https://www.space-track.org/ajaxauth/login -d 'identity=trliu@pmo.ac.cn&password=123456789abcdef'
# 访问文件列表并判断是否访问成功
if
    fl=$(curl --cookie cookies.txt https://www.space-track.org/publicfiles/query/class/files)
then
    echo $(date) >>filelist.txt
    echo $fl >>filelist.txt
    # 只保留如NASAJSC_ReadMe_23643_ReadMe_2023-10-23UTC15:49:52_1.zip格式
    dl=$(echo $fl | grep -o \"[^],[]*\")
    dl=$(echo $dl | grep -o "[^\"]*zip")
    # 如果文件夹存在，排除已下载，否则创建文件夹
    if [ -d ../$(date +"%Y%m") ]; then
        for i in $(ls ../$(date +"%Y%m")); do
            dl=$(echo "$dl" | grep -v $i)
        done
    else
        mkdir ../$(date +"%Y%m")
    fi
    echo ---downloading---
    # for LINK in $(echo $dl); do
    #     echo downloading $LINK
    #     curl --cookie cookies.txt https://www.space-track.org/publicfiles/query/class/download?name=$LINK --output ../$(date +"%Y%m")/${LINK//:/_} # win文件名中:无法直接保存非法字符:
    #     if [ -f ../$(date +"%Y%m")/${LINK//:/_}]; then
    #         mv ../$(date +"%Y%m")/${LINK//:/_} ../$(date +"%Y%m")/$LINK
    #     fi
    # done
    again=0
    while [ $again -eq 0 ]; do
        # 保存本次下载列表备用
        echo $dl >download.txt
        download_fun "$dl"
        # 检验本次下载的zip文件完整性,删除不完整下载,选择是否重新下载
        for LINK in $(echo $dl); do
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
        echo 'Download again? if yes input 0, else input 1'
        read again
    done
    echo ---end---
else
    echo false
fi
