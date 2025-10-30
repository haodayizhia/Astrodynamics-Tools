#!/bin/bash
# export https_proxy=http://127.0.0.1:10808
LOGFILE="$HOME/Desktop/1.txt"

echo "--- 任务开始 ---" >> $LOGFILE

# # --- 第一次执行 ---
# date >> $LOGFILE
# /e/Starlink_downloader/mine2.sh | grep --line-buffered -E 'date|now|Script|Download completed' >> $LOGFILE 2>&1

# # --- 暂停 20 分钟 ---
# echo "--- 暂停20分钟重复执行... ---" >> $LOGFILE
# sleep 1200

# # --- 第二次执行 ---
# date >> $LOGFILE
# /e/Starlink_downloader/mine2.sh | grep --line-buffered -E 'date|now|Script|Download completed' >> $LOGFILE 2>&1

# echo "--- 任务完成 ---" >> $LOGFILE
# echo "" >> $LOGFILE


# --- 循环执行直到成功 ---

result="Failed"
while [[ "$result" == *Failed* ]]; do
    echo "[$(date '+%Y-%m-%d %H:%M:%S')]" >> $LOGFILE
    # 主命令：输出到文件+管道
    result=$(/e/Starlink_downloader/mine2.sh | grep --line-buffered -E 'date|now|Script|Download completed' | tee -a "$LOGFILE")
    
    # 检查捕获的输出中是否包含 "Failed"
    if [[ "$result" == *Failed* ]]; then
        echo "检测到 'Failed'，任务将在5分钟后重试..." >> $LOGFILE
        sleep 300  # 暂停5分钟
    fi
done

echo "--- 任务完成 ---" >> $LOGFILE
echo "" >> $LOGFILE