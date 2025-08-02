#!/bin/bash

# 设置源目录和清单文件路径（将Windows路径转换为Linux路径格式）
SOURCE_DIR="/e/eph/202507/SpaceX_Ephemeris_552_SpaceX_2025-07-29UTC13_21_00"
MANIFEST_FILE="/e/eph/logs/MANIFEST_2025-07-29UTC13_21_00.txt"

# 检查源目录和清单文件是否存在
if [ ! -d "$SOURCE_DIR" ]; then
    echo "错误：源目录 $SOURCE_DIR 不存在"
    exit 1
fi

if [ ! -f "$MANIFEST_FILE" ]; then
    echo "错误：清单文件 $MANIFEST_FILE 不存在"
    exit 1
fi

# 遍历源目录中的所有文件
find "$SOURCE_DIR" -type f | while read -r file; do
    # 获取文件名（不包含路径）
    filename=$(basename "$file")
    
    # 检查文件是否在清单文件中
    if ! grep -Fx "$filename" "$MANIFEST_FILE" > /dev/null; then
        echo "删除文件：$file"
        rm -f "$file"
    fi
done

echo "完成：所有不在清单中的文件已删除"