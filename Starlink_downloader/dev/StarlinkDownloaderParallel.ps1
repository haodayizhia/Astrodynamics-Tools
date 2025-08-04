# PowerShell 5.1 for Starlink Downloader - 高效批处理版
# 每次并发下载一批后统一处理结果，减少内存占用和作业数量
# 支持用户提供清单路径，自动生成周期标签
param(
    [string]$manifestPathInput  # 可选参数：用户提供的清单路径
)

# ------- 配置 -------
$baseDir = "E:\eph"
$logDir = "$baseDir\logs"
$manifestUrl = "https://api.starlink.com/public-files/ephemerides/MANIFEST.txt"
$cycleHours = 8
$throttleLimit = 20  # 并发数

# 确保基础日志目录存在
New-Item -ItemType Directory -Force -Path $logDir | Out-Null

# ------- 清理和进度显示函数 -------
function Clear-Jobs {
    Write-Host "`n[$(Get-Date -Format 'HH:mm:ss')] 正在清理后台作业..."
    $runningJobs = Get-Job | Where-Object { $_.State -eq 'Running' }
    if ($runningJobs) {
        Write-Host "发现 $($runningJobs.Count) 个运行中的作业，正在停止..."
        $runningJobs | Stop-Job -PassThru | Remove-Job -Force
    }
    
    $allJobs = Get-Job
    if ($allJobs) {
        $allJobs | Remove-Job -Force
        Write-Host "已清理 $($allJobs.Count) 个作业。"
    }
    else {
        Write-Host "无需清理作业。"
    }
}

function Show-Progress {
    param(
        [int]$Total,
        [int]$Completed,
        [datetime]$StartTime
    )
    
    $elapsed = (Get-Date) - $StartTime
    $percentComplete = if ($Total -gt 0) { [math]::Round(($Completed / $Total) * 100, 1) } else { 0 }
    
    # 使用整体吞吐量进行估算
    $remainingTime = [TimeSpan]::Zero
    if ($Completed -gt 10 -and $elapsed.TotalSeconds -gt 5) {
        $avgThroughput = $Completed / $elapsed.TotalSeconds
        if ($avgThroughput -gt 0) {
            $remainingFiles = $Total - $Completed
            $estimatedSeconds = $remainingFiles / $avgThroughput
            $remainingTime = [TimeSpan]::FromSeconds($estimatedSeconds)
        }
    }
    
    # 清除当前行并显示进度
    Write-Host "`r" -NoNewline
    
    # 进度条
    $numEquals = [math]::Floor($percentComplete / 5)
    if ($numEquals -gt 20) { $numEquals = 20 }
    $numSpaces = 19 - $numEquals
    if ($numSpaces -lt 0) { $numSpaces = 0 }
    $progressBar = "=" * $numEquals + ">" + " " * $numSpaces

    $progressText = "[$progressBar] $percentComplete% ($Completed/$Total)"
    
    # 显示速度信息
    if ($elapsed.TotalSeconds -gt 5 -and $Completed -gt 0) {
        $speed = [math]::Round($Completed / $elapsed.TotalSeconds, 1)
        $progressText += "速度: $speed files/s "
    }

    # 已用时间（支持完整格式）
    $elapsedFormat = if ($elapsed.TotalHours -ge 1) { "h\:mm\:ss" } else { "mm\:ss" }
    $progressText += "已用: $($elapsed.ToString($elapsedFormat)) "

    # 剩余时间（支持完整时间显示：小时、分钟、秒）
    if ($remainingTime.TotalSeconds -gt 1) {
        # 根据剩余时间长度选择格式：超过1小时则显示小时，否则只显示分秒
        $timeFormat = if ($remainingTime.TotalHours -ge 1) { "h\:mm\:ss" } else { "mm\:ss" }
        $progressText += "剩余: $($remainingTime.ToString($timeFormat)) "
    }
    Write-Host $progressText -NoNewline -ForegroundColor Cyan
}

# 注册退出事件处理
Register-EngineEvent -SourceIdentifier PowerShell.Exiting -Action { Clear-Jobs } | Out-Null

# 简化的 Ctrl+C 处理
trap {
    Write-Host "`n`n检测到中断信号，正在安全退出..." -ForegroundColor Red
    Clear-Jobs
    break
}

try {
    # ------- 单次执行逻辑 -------
    $scriptStartTime = Get-Date
    Write-Host "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] Starlink 下载脚本开始执行（高效批处理版）" -ForegroundColor Green

    # ------- 读取或下载清单 -------
    # 使用提供的路径或默认路径，并生成cycleTag
    if ($manifestPathInput) {
        $manifestPath = $manifestPathInput
        if (-not (Test-Path $manifestPath)) { Write-Error "提供的 manifestPath 不存在: $manifestPath"; exit 1 }
        Write-Host "`n使用提供的清单文件: $manifestPath"
    
        # 从文件名中提取cycleTag（格式：MANIFEST_yyyy-MM-ddUTCHH_mm_ss.txt）
        $fileName = [System.IO.Path]::GetFileName($manifestPath)
        $cycleTag = $fileName -replace '^MANIFEST_(.*)\.txt$', '$1'
    
        # 从cycleTag解析出cycleEnd时间
        # cycleTag格式: yyyy-MM-ddUTCHH_mm_ss
        if ($cycleTag -match '^(\d{4})-(\d{2})-(\d{2})UTC(\d{2})_(\d{2})_(\d{2})$') {
            $year = [int]$Matches[1]
            $month = [int]$Matches[2]
            $day = [int]$Matches[3]
            $hour = [int]$Matches[4]
            $minute = [int]$Matches[5]
            $second = [int]$Matches[6]
        
            try {
                $cycleEnd = [DateTime]::new($year, $month, $day, $hour, $minute, $second, [DateTimeKind]::Utc)
                Write-Host "解析得到周期结束时间: $($cycleEnd.ToString('yyyy-MM-dd HH:mm:ss')) UTC"
            }
            catch {
                Write-Error "无法解析清单文件名中的时间信息: $cycleTag"
                Write-Error "期望格式: MANIFEST_yyyy-MM-ddUTCHH_mm_ss.txt"
                exit 1
            }
        }
        else {
            Write-Error "清单文件名格式不正确: $fileName"
            Write-Error "期望格式: MANIFEST_yyyy-MM-ddUTCHH_mm_ss.txt"
            Write-Error "实际获得cycleTag: $cycleTag"
            exit 1
        }
    }
    else {
        # ------- 时间处理 -------
        $now = [DateTime]::UtcNow
        $today_T1 = $now.Date.AddHours(5).AddMinutes(21)
        $today_T2 = $now.Date.AddHours(13).AddMinutes(21)
        $today_T3 = $now.Date.AddHours(21).AddMinutes(21)
        $tomorrow_T1 = $today_T1.AddDays(1)

        if ($now -le $today_T1) {
            $cycleEnd = $today_T1
        }
        elseif ($now -le $today_T2) {
            $cycleEnd = $today_T2
        }
        elseif ($now -le $today_T3) {
            $cycleEnd = $today_T3
        }
        else {
            $cycleEnd = $tomorrow_T1
        }

        $cycleTag = $cycleEnd.ToString("yyyy-MM-dd\UTC") + $cycleEnd.ToString("HH_mm_00")
        $manifestPath = "$logDir\MANIFEST_$cycleTag.txt"
        Write-Host "`n正在获取 MANIFEST.txt..."
        
        $maxManifestRetries = 3
        $manifestRetryCount = 0
        $manifestDownloaded = $false
        
        do {
            try {
                Invoke-WebRequest -Uri $manifestUrl -OutFile $manifestPath -UseBasicParsing -ErrorAction Stop
                Write-Host "MANIFEST.txt 获取成功。"
                $manifestDownloaded = $true
            }
            catch {
                $manifestRetryCount++
                if ($manifestRetryCount -lt $maxManifestRetries) {
                    Write-Warning "MANIFEST.txt 下载失败（第 $manifestRetryCount 次尝试）：$($_.Exception.Message)"
                    Write-Host "将在 10 秒后重试..."
                    Start-Sleep -Seconds 10
                }
                else {
                    Write-Error "MANIFEST.txt 下载失败，已重试 $maxManifestRetries 次：$($_.Exception.Message)"
                    exit 1
                }
            }
        } while (-not $manifestDownloaded -and $manifestRetryCount -lt $maxManifestRetries)
    }

    # ------- 目录和文件名 -------
    $ymTag = $cycleEnd.ToString("yyyyMM")
    $downloadDir = "$baseDir\$ymTag\SpaceX_Ephemeris_552_SpaceX_$cycleTag"
    $recordFile = "$logDir\SpaceX_Ephemeris_552_SpaceX_$cycleTag.txt"
    New-Item -ItemType Directory -Force -Path $downloadDir | Out-Null

    Write-Host "当前周期: $cycleTag"
    Write-Host "下载目录: $downloadDir"
    Write-Host "最大并发数: $throttleLimit"

    # ------- 加载记录并检查已存在文件 -------
    $prevCycleEnd = $cycleEnd.AddHours(-$cycleHours)
    $prevTag = $prevCycleEnd.ToString("yyyy-MM-dd\UTC") + $prevCycleEnd.ToString("HH_mm_00")
    $prevRecord = "$logDir\SpaceX_Ephemeris_552_SpaceX_$prevTag.txt"

    $downloaded = @{}
    
    if (Test-Path $recordFile) {
        Get-Content $recordFile -ErrorAction SilentlyContinue | ForEach-Object { $downloaded[$_] = $true }
        Write-Host "从当前记录文件加载了 $($downloaded.Count) 个已下载文件记录"
    }
    if (Test-Path $prevRecord) {
        $prevCount = $downloaded.Count
        Get-Content $prevRecord -ErrorAction SilentlyContinue | ForEach-Object { $downloaded[$_] = $true }
        Write-Host "从上一周期记录文件加载了 $($downloaded.Count - $prevCount) 个已下载文件记录"
    }
    
    if (Test-Path $downloadDir) {
        $existingFiles = Get-ChildItem -Path $downloadDir -File | Where-Object { -not $_.Name.EndsWith('.tmp') } | Select-Object -ExpandProperty Name
        $existingCount = 0
        foreach ($existingFile in $existingFiles) {
            if (-not $downloaded.ContainsKey($existingFile)) {
                $filePath = Join-Path $downloadDir $existingFile
                $fileInfo = Get-Item $filePath -ErrorAction SilentlyContinue
                if ($fileInfo -and $fileInfo.Length -gt 0) {
                    $downloaded[$existingFile] = $true
                    $existingCount++
                    Add-Content -Path $recordFile -Value $existingFile -ErrorAction SilentlyContinue
                }
                else {
                    Write-Host "发现损坏文件，正在删除: $existingFile"
                    Remove-Item -Path $filePath -Force -ErrorAction SilentlyContinue
                }
            }
        }
        
        $tempFiles = Get-ChildItem -Path $downloadDir -File -Filter "*.tmp" -ErrorAction SilentlyContinue
        if ($tempFiles) {
            Write-Host "清理 $($tempFiles.Count) 个残留的临时文件..."
            $tempFiles | Remove-Item -Force -ErrorAction SilentlyContinue
        }
        
        if ($existingCount -gt 0) {
            Write-Host "发现 $existingCount 个已存在但未记录的完整文件，已补充记录。"
        }
    }

    # ------- 核心下载逻辑 -------

    $manifestFiles = Get-Content $manifestPath
    $newFiles = @()
    foreach ($file in $manifestFiles) {
        if (-not $downloaded.ContainsKey($file)) { $newFiles += $file }
    }

    Write-Host "清单文件总数: $($manifestFiles.Count)"
    Write-Host "已下载文件数: $($downloaded.Count)"
    Write-Host "发现新增文件: $($newFiles.Count) 个"

    # ------- 优化的并行下载（批处理模型）-------
    if ($newFiles.Count -gt 0) {
        Write-Host "`n开始并行下载，最大并发: $throttleLimit"
        
        $scriptBlock = {
            param($fileToDownload, $downloadPath)
            
            $url = "https://api.starlink.com/public-files/ephemerides/$fileToDownload"
            $targetPath = Join-Path $downloadPath $fileToDownload
            $tempPath = "$targetPath.tmp"
            $maxRetries = 3
            $retryCount = 0
            
            do {
                try {
                    if (Test-Path $tempPath) { Remove-Item -Path $tempPath -Force -ErrorAction SilentlyContinue }
                    
                    $webRequest = @{
                        Uri                = $url
                        OutFile            = $tempPath
                        UseBasicParsing    = $true
                        TimeoutSec         = 60
                        ErrorAction        = 'Stop'
                        UserAgent          = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36'
                        MaximumRedirection = 3
                    }
                    Invoke-WebRequest @webRequest
                    
                    $downloadedFile = Get-Item $tempPath -ErrorAction Stop
                    if ($downloadedFile.Length -eq 0) { throw "下载的文件为空" }
                    
                    Move-Item -Path $tempPath -Destination $targetPath -Force -ErrorAction Stop
                    
                    return @{ 
                        Success  = $true
                        FileName = $fileToDownload
                        Size     = $downloadedFile.Length
                        TempPath = $tempPath
                    }
                }
                catch {
                    if (Test-Path $tempPath) { Remove-Item -Path $tempPath -Force -ErrorAction SilentlyContinue }
                    $retryCount++
                    if ($retryCount -lt $maxRetries) {
                        Start-Sleep -Seconds ([Math]::Pow(2, $retryCount))
                    }
                    else {
                        return @{ 
                            Success  = $false
                            FileName = $fileToDownload
                            Error    = $_.Exception.Message
                        }
                    }
                }
            } while ($retryCount -lt $maxRetries)
        }
        
        $downloadStartTime = Get-Date
        $completedCount = 0
        
        # 批处理下载
        for ($i = 0; $i -lt $newFiles.Count; $i += $throttleLimit) {
            $batch = $newFiles[$i..[MATH]::Min($newFiles.Count, ($i + $throttleLimit - 1))]
            $jobs = @()
            
            # 启动批处理作业
            foreach ($file in $batch) {
                $jobs += Start-Job -ScriptBlock $scriptBlock -ArgumentList $file, $downloadDir
            }
            
            # 等待批处理完成
            $jobs | Wait-Job | Out-Null
            
            # 处理结果并记录
            $batchResults = $jobs | Receive-Job
            $recordLines = @()
            
            foreach ($result in $batchResults) {
                if ($result.Success) {
                    $recordLines += $result.FileName
                    $downloaded[$result.FileName] = $true
                }
                else {
                    Write-Warning "下载失败: $($result.FileName) - $($result.Error)"
                }

                $completedCount++
            }
            
            # 批量写入记录文件
            if ($recordLines.Count -gt 0) {
                $recordLines | Add-Content -Path $recordFile
            }
            
            # 清理作业
            $jobs | Remove-Job -Force
            
            # 更新进度
            Show-Progress -Total $newFiles.Count -Completed $completedCount -StartTime $downloadStartTime
        }

        Write-Host ""
        
        $failedCount = $newFiles.Count - $completedCount
        if ($failedCount -gt 0) {
            Write-Host "下载完成: 成功 $completedCount 个, 失败 $failedCount 个" -ForegroundColor Yellow
        }
        else {
            Write-Host "下载完成: 全部 $completedCount 个文件成功下载" -ForegroundColor Green
        }
    }
    else {
        Write-Host "无新增文件需要下载。"
    }

    # ------- 执行总结 -------
    $scriptEndTime = Get-Date
    $totalDuration = $scriptEndTime - $scriptStartTime
    Write-Host "`n[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] 脚本执行完成"
    Write-Host ("总耗时: {0:N1} 秒" -f $totalDuration.TotalSeconds)
    
    if ($newFiles.Count -gt 0 -and $totalDuration.TotalSeconds -gt 0) {
        $avgSpeed = [math]::Round($completedCount / $totalDuration.TotalSeconds, 2)
        Write-Host ("平均下载速度: $avgSpeed 文件/秒")
    }
    
    Write-Host "退出代码: 0"

}
catch {
    Write-Error "脚本执行时发生错误: $($_.Exception.Message)"
    Write-Error $_.ScriptStackTrace
    Write-Host "退出代码: 1"
    exit 1
}
finally {
    Clear-Jobs
    Write-Host "资源清理完成。"
}