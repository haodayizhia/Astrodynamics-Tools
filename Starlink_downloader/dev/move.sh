#!/bin/bash

# 源目录（注意 Git Bash 下路径写法）
src_dir="/e/eph/202508/SpaceX_Ephemeris_552_SpaceX_2025-08-14UTC05_21_44"

# 清单文件（完整路径）
manifest="/e/Starlink_downloader/logs/MANIFEST_2025-08-14UTC05_21_44.txt"

# 目标目录
dst_dir="/e/eph/202508/SpaceX_Ephemeris_552_SpaceX_2025-08-13UTC21_21_44"

# 创建目标目录（若不存在）
mkdir -p "$dst_dir"

# 把清单读入数组
mapfile -t manifest_files < "$manifest"

# 遍历源目录下的所有文件
for file in "$src_dir"/*; do
    fname=$(basename "$file")

    # 判断当前文件是否在清单中
    if [[ ! " ${manifest_files[@]} " =~ " $fname " ]]; then
        echo "移动: $fname"
        mv "$file" "$dst_dir/"
    fi
done

echo "操作完成，未在清单中的文件已移动到: $dst_dir"
