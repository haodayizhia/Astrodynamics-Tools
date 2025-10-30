#!/bin/bash

# 文件夹路径（注意使用正斜杠 /）
folder_path="/e/eph/202508/SpaceX_Ephemeris_552_SpaceX_2025-08-14UTC05_21_44/"

# 输出文件
output_file="$HOME/Desktop/111.txt"

# 清空输出文件
> "$output_file"

# 遍历所有 txt 文件
for file in "$folder_path"/*.txt; do
    # 提取文件名
    fname=$(basename "$file")

    # 使用正则匹配文件名中的数字部分
    # MEME_44714_STARLINK-1008_2251941_Operational_1439408520_UNCLASSIFIED.txt
    if [[ $fname =~ MEME_[0-9]+_STARLINK-[0-9]+_([0-9]+)_Operational_[0-9]+_UNCLASSIFIED\.txt ]]; then
        num_val=${BASH_REMATCH[1]}
        
        # 判断数字是否小于 2252121
        if (( num_val < 2252121 )); then
            echo "$fname" >> "$output_file"
        fi
    fi
done

echo "筛选完成，结果已保存到: $output_file"
