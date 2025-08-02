#!/bin/bash
cd "$(dirname "$0")"

# ------- Configuration -------
BASE_DIR="../eph"  # 默认下载根路径
LOG_DIR="./logs"    # 日志目录
MANIFEST_URL="https://api.starlink.com/public-files/ephemerides/MANIFEST.txt"
CYCLE_HOURS=8
THROTTLE_LIMIT=50  # 同时下载的最大文件数
USER_AGENT="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36"

# Parse command line arguments
MANIFEST_PATH_INPUT=""
while [[ $# -gt 0 ]]; do
    case $1 in
        -m|--manifest)
            MANIFEST_PATH_INPUT="$2"
            shift 2
        ;;
        -h|--help)
            echo "Usage: $0 [-m|--manifest <path>]"
            echo "  -m, --manifest    Optional: User-provided manifest file path"
            exit 0
        ;;
        *)
            echo "Unknown option: $1"
            exit 1
        ;;
    esac
done

# 确保日志目录存在
mkdir -p "$LOG_DIR"

# ------- Global Variables -------
declare -A DOWNLOADED_FILES
declare -a BACKGROUND_PIDS=()
COMPLETED_COUNT=0
TOTAL_FILES=0
START_TIME=""

# ------- Cleanup and Progress Functions -------
cleanup_jobs() {
    echo -e "\n[$(date '+%H:%M:%S')] Cleaning up background jobs..."
    local job_count=0
    
    for pid in "${BACKGROUND_PIDS[@]}"; do
        if kill -0 "$pid" 2>/dev/null; then
            kill "$pid" 2>/dev/null
            ((job_count++))
        fi
    done
    
    if [[ $job_count -gt 0 ]]; then
        echo "Terminated $job_count running jobs."
        sleep 1
        # Force kill any remaining jobs
        for pid in "${BACKGROUND_PIDS[@]}"; do
            kill -9 "$pid" 2>/dev/null
        done
    else
        echo "No jobs to cleanup."
    fi
    
    BACKGROUND_PIDS=()
    
    if [ -n "$current_standby_timeout" ] && [ -n "$current_hibernate_timeout" ]; then
        powercfg -change standby-timeout-ac $current_standby_timeout
        powercfg -change hibernate-timeout-ac $current_hibernate_timeout
        echo "将睡眠时间调回$current_standby_timeout 分钟,将休眠时间调回$current_hibernate_timeout 分钟"
    fi
}

show_progress() {
    local total=$1
    local batch_completed=$2
    local completed=$3
    local batch_start_time=$4
    local start_time=$5
    
    local current_time=$(date +%s)
    local batch_elapsed=$((current_time - batch_start_time))
    local elapsed=$((current_time - start_time))
    local percent_complete=0
    
    if [[ $total -gt 0 ]]; then
        percent_complete=$((completed * 100 / total))
    fi
    
    # Progress bar
    local num_equals=$((percent_complete / 5))
    [[ $num_equals -gt 20 ]] && num_equals=20
    local num_spaces=$((20 - num_equals))
    [[ $num_spaces -lt 0 ]] && num_spaces=0
    
    local progress_bar=$(printf "%-${num_equals}s" | tr ' ' '=')
    local spaces=$(printf "%-${num_spaces}s")
    
    printf "\r\033[K[${progress_bar}>${spaces}] ${percent_complete}%% (${completed}/${total})"
    
    # Speed information
    if [[ $batch_elapsed -gt 1 ]]; then
        speed=$((batch_completed * 10 / batch_elapsed)) # files per 10 seconds
        printf " Speed: %d.%d files/s" $((speed/10)) $((speed%10))
    fi
    
    # Elapsed time
    if [[ $elapsed -ge 3600 ]]; then
        printf " Elapsed: %d:%02d:%02d" $((elapsed/3600)) $(((elapsed%3600)/60)) $((elapsed%60))
    else
        printf " Elapsed: %02d:%02d" $((elapsed/60)) $((elapsed%60))
    fi
    
    # Remaining time
    if [[ batch_completed -gt 0 ]]; then
        local remaining_files=$((total - completed))
        local estimated_seconds=$((remaining_files * batch_elapsed / batch_completed))
        local remaining_time=""
        
        if [[ $estimated_seconds -ge 3600 ]]; then
            remaining_time=$(printf "%d:%02d:%02d" $((estimated_seconds/3600)) $(((estimated_seconds%3600)/60)) $((estimated_seconds%60)))
        else
            remaining_time=$(printf "%02d:%02d" $((estimated_seconds/60)) $((estimated_seconds%60)))
        fi
        
        if [[ -n "$remaining_time" ]]; then
            printf " Remaining: %s" "$remaining_time"
        fi
    fi
}

add_downloaded_file() {
    local dirs=("$@")  # 所有参数作为目录路径数组
    local dir
    local file
    local existing_count=0
    
    for dir in "${dirs[@]}"; do
        if [[ -d "$dir" ]]; then
            # 清理临时文件
            find "$dir" -name "*.tmp" -delete 2>/dev/null
            
            # 检查已存在的非 tmp 文件
            while IFS= read -r -d '' file || [[ -n $file ]]; do
                local filename="${file##*/}"
                if [[ ! -v DOWNLOADED_FILES["$filename"] ]]; then
                    DOWNLOADED_FILES["$filename"]=1
                    ((existing_count++))
                fi
            done < <(find "$dir" -type f ! -name "*.tmp" -print0 2>/dev/null)
        fi
    done
    [[ $existing_count -gt 0 ]] && echo "Found $existing_count existing completed files."
}

# Signal handlers
trap 'echo -e "\n\nInterrupt signal detected, safely exiting..."; cleanup_jobs; exit 1' INT TERM

# ------- Main Script Logic -------
main() {
    local script_start_time=$(date +%s)
    local manifest_path=""
    local cycle_tag=""
    local ym_tag=""
    
    if [[ -n "$MANIFEST_PATH_INPUT" ]]; then
        manifest_path="$MANIFEST_PATH_INPUT"
        if [[ -f "$manifest_path" ]]; then
            echo -e "\nUsing provided manifest file: $manifest_path"
            # MANIFEST_2025-07-30UTC13_21_00.txt提取2025-07-30UTC13_21_00
            cycle_tag=${manifest_path#*MANIFEST_}
            cycle_tag=${cycle_tag%.txt}
            # 验证日期格式是否正确
            if ! [[ $cycle_tag =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}UTC[0-9]{2}_[0-9]{2}_[0-9]{2}$ ]]; then
                echo "Error: Invalid manifest file format. Expected format: MANIFEST_YYYY-MM-DDUTCHH_MM_SS.txt" >&2
                exit 1
            fi
        else
            echo "Error: Provided manifest path does not exist: $manifest_path" >&2
            exit 1
        fi
    else
        cycle_tag=$(date -u +"%Y-%m-%dUTC%H_%M_%S")
        manifest_path="$LOG_DIR/MANIFEST_$cycle_tag.txt"
        echo -e "\nDownloading MANIFEST.txt..."
        # Create directory if it doesn't exist
        mkdir -p "$(dirname "$manifest_path")"
        # Download the manifest file
        curl -A "$USER_AGENT" -o "$manifest_path" "$MANIFEST_URL"
        if [[ $? -ne 0 ]]; then
            echo "Error: Failed to download manifest file from $MANIFEST_URL" >&2
            exit 1
        else
            echo "Manifest file downloaded successfully to: $manifest_path"
        fi
    fi
    
    # 和上一次的manifest对比，避免重建download_dir
    local pre_manifest_path=""
    local last_tag=""
    local last_ym_tag=""
    local last_download_dir=""
    local manifest_files=($(ls $LOG_DIR/MANIFEST_* 2>/dev/null))
    
    if [[ ${#manifest_files[@]} -gt 0 ]]; then
        # 定位到当前manifest文件在数组中的位置
        for(( i=${#manifest_files[@]}-1; i>=0; i-- )); do
            if [[ "${manifest_files[i]##*/}" == "${manifest_path##*/}" ]]; then
                if [[ $i -gt 0 ]]; then
                    # 获取上一个周期的 manifest 路径
                    pre_manifest_path="${manifest_files[i-1]}"
                    # 如果两个 manifest 内容一致，则复用旧文件并删除当前
                    if cmp -s "$manifest_path" "$pre_manifest_path"; then
                        echo "Manifest file is identical to previous. Removing ${manifest_path##*/}"
                        rm -f "$manifest_path"
                        # 替换当前 manifest 为上一个周期的（内容相同），并更新 cycle_tag
                        manifest_path="$pre_manifest_path"
                        # 提取周期标签
                        cycle_tag=${manifest_path#*MANIFEST_}
                        cycle_tag=${cycle_tag%.txt}
                        if [[ $i -gt 1 ]]; then
                            pre_manifest_path="${manifest_files[i-2]}"
                        else
                            pre_manifest_path=""
                        fi
                    fi
                    break
                fi
            fi
        done
    fi
    
    echo "now manifest: ${manifest_path##*/}, previous manifest: ${pre_manifest_path##*/}"
    
    # ------- Directory and File Names -------
    if [ -n "$pre_manifest_path" ]; then
        last_tag=${pre_manifest_path#*MANIFEST_}
        last_tag=${last_tag%.txt}
        last_ym_tag=${last_tag:0:7} # 提取年月部分
        last_ym_tag=${last_ym_tag//-} # 去掉划线如202507
        last_download_dir="$BASE_DIR/$last_ym_tag/SpaceX_Ephemeris_552_SpaceX_$last_tag"
    fi
    ym_tag=${cycle_tag:0:7} # 提取年月部分
    ym_tag=${ym_tag//-} # 去掉划线如202507
    local download_dir="$BASE_DIR/$ym_tag/SpaceX_Ephemeris_552_SpaceX_$cycle_tag"
    
    add_downloaded_file "$last_download_dir" "$download_dir"
    
    # ------- Core Download Logic -------
    local -a manifest_lines=()
    while IFS= read -r line || [[ -n "$line" ]]; do
        [[ -n "$line" ]] && manifest_lines+=("$line")
    done < "$manifest_path"
    
    local -a new_files=()
    for file in "${manifest_lines[@]}"; do
        [[ ! -v DOWNLOADED_FILES["$file"] ]] && new_files+=("$file")
    done
    
    echo "Total files in manifest: ${#manifest_lines[@]}"
    # echo "Already downloaded files: ${#DOWNLOADED_FILES[@]}"
    
    if [[ ${#new_files[@]} -gt 0 ]]; then
        
        echo "New files to download: ${#new_files[@]}"
        echo -e "\nStarting high-performance parallel download, max concurrent: $THROTTLE_LIMIT"
        echo "Current cycle: $cycle_tag"
        echo "Download directory: $download_dir"
        
        local download_start_time=$(date +%s)
        TOTAL_FILES=${#new_files[@]}
        
        mkdir -p "$download_dir"
        
        # ------- Download Files in Batches -------
        for ((i = 0; i < ${#new_files[@]}; i += THROTTLE_LIMIT)); do
            local batch_end=$((i + THROTTLE_LIMIT - 1))
            [[ $batch_end -ge ${#new_files[@]} ]] && batch_end=$((${#new_files[@]} - 1))
            
            # 批次开始时间
            local batch_start_time=$(date +%s)
            
            # 记录批次进程
            local -a batch_pids=()
            
            for ((j = i; j <= batch_end; j++)); do
                local file="${new_files[j]}"
                download_file "$file" "$download_dir" &
                local pid=$!
                batch_pids+=("$pid")
                BACKGROUND_PIDS+=("$pid")
            done
            
            local batch_completed_count=0
            # Wait for batch completion
            for pid in "${batch_pids[@]}"; do
                wait "$pid"
                # 统计当前批次下载成功的文件数量
                [[ $? -eq 0 ]] && ((batch_completed_count++))
            done
            
            # Clean up batch PIDs from global array
            for pid in "${batch_pids[@]}"; do
                for idx in "${!BACKGROUND_PIDS[@]}"; do
                    if [[ "${BACKGROUND_PIDS[idx]}" == "$pid" ]]; then
                        unset 'BACKGROUND_PIDS[idx]'
                        break
                    fi
                done
            done
            
            # 统计成功下载的文件总数量
            let COMPLETED_COUNT+=batch_completed_count
            show_progress "$TOTAL_FILES" "$batch_completed_count" "$COMPLETED_COUNT" "$batch_start_time" "$download_start_time"
        done
        
        echo ""
    fi
    
    # ------- Execution Summary -------
    local script_end_time=$(date +%s)
    local total_duration=$((script_end_time - script_start_time))
    echo -e "\n[$(date '+%Y-%m-%d %H:%M:%S')] Script execution completed"
    
    local failed_count=$(($TOTAL_FILES - $COMPLETED_COUNT))
    if [[ $TOTAL_FILES -gt 0 ]]; then
        if [[ $failed_count -gt 0 ]]; then
            echo "Download completed: Success $COMPLETED_COUNT, Failed $failed_count"
        else
            echo "Download completed: All $COMPLETED_COUNT files downloaded successfully"
        fi
        
        if [[ $total_duration -gt 0 ]]; then
            local avg_speed=$((COMPLETED_COUNT * 100 / total_duration))
            echo "Average download speed: $((avg_speed/100)).$((avg_speed%100)) files/second"
        fi
    else
        echo "No files were downloaded."
    fi
    
    # echo "Total duration: $total_duration seconds"
    if [[ $total_duration -ge 3600 ]]; then
        echo "Total duration: $((total_duration/3600)) hours $(((total_duration%3600)/60)) minutes $((total_duration%60)) seconds"
    else
        echo "Total duration: $((total_duration/60)) minutes $((total_duration%60)) seconds"
    fi
    
    echo "Exit code: 0"
}

# ------- Download Function -------
download_file() {
    local file="$1"
    local download_path="$2"
    local url="https://api.starlink.com/public-files/ephemerides/$file"
    local target_path="$download_path/$file"
    local temp_path="$target_path.tmp"
    
    # Performance optimized: Single attempt with longer timeout
    # [[ -f "$temp_path" ]] && rm -f "$temp_path"
    
    # Optimized curl options for performance
    if curl -f -L --ssl-no-revoke --connect-timeout 15 --max-time 45 \
    --retry 2 --retry-delay 1 --retry-max-time 60 \
    --compressed --tcp-nodelay \
    -A "$USER_AGENT" -o "$temp_path" "$url" 2>/dev/null; then
        if [[ -s "$temp_path" ]]; then
            mv "$temp_path" "$target_path" && return 0
        fi
    fi
    
    [[ -f "$temp_path" ]] && rm -f "$temp_path"
    return 1
}

# ------- Script Entry Point -------
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    # Check dependencies
    command -v curl >/dev/null 2>&1 || { echo "Error: curl is required but not installed." >&2; exit 1; }
    command -v date >/dev/null 2>&1 || { echo "Error: date command is required but not available." >&2; exit 1; }
    
    # 如果在windows系统，插入电源下载时不睡眠和休眠
    if uname -s | grep -q 'MINGW\|MSYS' || [ "$OS" = "Windows_NT" ] || [[ "$OSTYPE" == "msys"* || "$OSTYPE" == "mingw"* ]]; then
        current_standby_timeout=$(($(powercfg -query SCHEME_CURRENT SUB_SLEEP STANDBYIDLE | findstr "当前交流电源设置索引" | awk -F ': ' '{print $2}' | tr -d ' ') / 60))
        current_hibernate_timeout=$(($(powercfg -query SCHEME_CURRENT SUB_SLEEP HIBERNATEIDLE | findstr "当前交流电源设置索引" | awk -F ': ' '{print $2}' | tr -d ' ') / 60))
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
    
    # 执行主函数
    main "$@"
    
    # while true; do
    #     main "$@"
    #     sleep 14400  # 4 小时 = 4 × 60 × 60 = 14400 秒
    # done
    
    # 清理临时文件和后台进程
    cleanup_jobs
    echo "Resource cleanup completed."
fi