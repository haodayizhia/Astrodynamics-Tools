#!/bin/bash

EPHEMERIS_DIR="/e/eph/202507/SpaceX_Ephemeris_552_SpaceX_2025-07-29UTC21_21_00"
MANIFEST_FILE="/e/eph/logs/MANIFEST_2025-07-29UTC21_21_00.txt"

# 检查文件和目录
if [ ! -f "$MANIFEST_FILE" ]; then
    echo "错误：MANIFEST文件不存在: $MANIFEST_FILE"
    exit 1
fi
if [ ! -d "$EPHEMERIS_DIR" ]; then
    echo "错误：目标目录不存在: $EPHEMERIS_DIR"
    exit 1
fi

# 统计行数（使用awk确保包含无换行符的最后一行）
manifest_lines=$(awk 'END {print NR}' "$MANIFEST_FILE")
dir_files=$(ls -1 "$EPHEMERIS_DIR" | wc -l)
echo "MANIFEST文件行数 (awk): $manifest_lines"
echo "目录中文件数: $dir_files"

# 检查文件末尾换行符
if [ -n "$(tail -c 1 "$MANIFEST_FILE")" ]; then
    echo "警告：MANIFEST文件最后一行没有换行符，可能导致wc -l少计一行"
    # 可选：自动添加换行符
    echo >> "$MANIFEST_FILE"
    echo "已为MANIFEST文件添加换行符"
    manifest_lines=$((manifest_lines + 1))
fi

# 检查缺失文件
echo "正在检查缺失文件..."
missing_count=0
while IFS= read -r file || [ -n "$file" ]; do
    # 跳过空行
    if [ -z "$file" ]; then
        echo "警告：检测到空行，跳过"
        continue
    fi
    full_path="$EPHEMERIS_DIR/$file"
    if [ ! -f "$full_path" ]; then
        echo "缺失文件: $full_path"
        ((missing_count++))
    fi
done < "$MANIFEST_FILE"

echo "检查完成。共找到 $missing_count 个缺失文件。"