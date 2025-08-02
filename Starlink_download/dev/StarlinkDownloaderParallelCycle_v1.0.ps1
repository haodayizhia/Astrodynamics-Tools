# PowerShell 5.1 for Starlink Downloader with Progress and Thread Cleanup
# ------- 配置 -------
$baseDir = "E:\eph"
$logDir = "$baseDir\logs"
$manifestUrl = "https://api.starlink.com/public-files/ephemerides/MANIFEST.txt"
$manifestPath = "$baseDir\MANIFEST.txt"
$cycleHours = 8
$checkCycleSeconds = 7200  # 2小时的检查周期
$throttleLimit = 15  # 降低并发数以提高稳定性

# 确保基础日志目录存在
New-Item -ItemType Directory -Force -Path $logDir | Out-Null

# ------- 清理和进度显示函数 -------
function Cleanup-Jobs {
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
    } else {
        Write-Host "无需清理作业。"
    }
}

function Show-Progress {
    param(
        [int]$Current,
        [int]$Total,
        [int]$Completed,
        [string]$CurrentFile = "",
        [datetime]$StartTime
    )
    
    $elapsed = (Get-Date) - $StartTime
    $percentComplete = if ($Total -gt 0) { [math]::Round(($Completed / $Total) * 100, 1) } else { 0 }
    
    # 估算剩余时间
    $remainingTime = if ($Completed -gt 0) {
        $avgTimePerFile = $elapsed.TotalSeconds / $Completed
        $remainingFiles = $Total - $Completed
        [TimeSpan]::FromSeconds($avgTimePerFile * $remainingFiles)
    } else {
        [TimeSpan]::Zero
    }
    
    # 清除当前行并显示进度
    Write-Host "`r" -NoNewline
    $progressBar = "=" * [math]::Floor($percentComplete / 5) + ">" + " " * (20 - [math]::Floor($percentComplete / 5))
    $progressText = "[$progressBar] $percentComplete% ($Completed/$Total) "
    
    if ($remainingTime.TotalMinutes -gt 0) {
        $progressText += "剩余: $($remainingTime.ToString('mm\:ss')) "
    }
    
    if ($CurrentFile) {
        $displayFile = if ($CurrentFile.Length -gt 33) { $CurrentFile.Substring(0, 33) + "..." } else { $CurrentFile }
        $progressText += "当前: $displayFile"
    }
    
    Write-Host $progressText -NoNewline
}

# 注册退出事件处理
Register-EngineEvent -SourceIdentifier PowerShell.Exiting -Action { Cleanup-Jobs } | Out-Null

# 简化的 Ctrl+C 处理 - 使用 trap 语句
trap {
    Write-Host "`n`n检测到中断信号，正在安全退出..."
    Cleanup-Jobs
    break
}

try {
    # ------- 主循环 -------
    while ($true) {
        $loopStartTime = Get-Date

        # ------- 时间处理 -------
        $now = [DateTime]::UtcNow
        $today_T1 = $now.Date.AddHours(5).AddMinutes(21)
        $today_T2 = $now.Date.AddHours(13).AddMinutes(21)
        $today_T3 = $now.Date.AddHours(21).AddMinutes(21)
        $tomorrow_T1 = $today_T1.AddDays(1)

        if ($now -le $today_T1) {
            $cycleEnd = $today_T1
        } elseif ($now -le $today_T2) {
            $cycleEnd = $today_T2
        } elseif ($now -le $today_T3) {
            $cycleEnd = $today_T3
        } else {
            $cycleEnd = $tomorrow_T1
        }

        $ymTag = $cycleEnd.ToString("yyyyMM")
        $cycleTag = $cycleEnd.ToString("yyyy-MM-dd\UTC") + $cycleEnd.ToString("HH_mm_00")

        # ------- 目录和文件名 -------
        $downloadDir = "$baseDir\$ymTag\SpaceX_Ephemeris_552_SpaceX_$cycleTag"
        $recordFile = "$logDir\SpaceX_Ephemeris_552_SpaceX_$cycleTag.txt"
        New-Item -ItemType Directory -Force -Path $downloadDir | Out-Null

        # ------- 加载记录并检查已存在文件 -------
        $prevCycleEnd = $cycleEnd.AddHours(-$cycleHours)
        $prevTag = $prevCycleEnd.ToString("yyyy-MM-dd\UTC") + $prevCycleEnd.ToString("HH_mm_00")
        $prevRecord = "$logDir\SpaceX_Ephemeris_552_SpaceX_$prevTag.txt"

        $downloaded = @{}
        
        # 从记录文件加载
        if (Test-Path $recordFile) {
            Get-Content $recordFile -ErrorAction SilentlyContinue | ForEach-Object { $downloaded[$_] = $true }
        }
        if (Test-Path $prevRecord) {
            Get-Content $prevRecord -ErrorAction SilentlyContinue | ForEach-Object { $downloaded[$_] = $true }
        }
        
        # 检查目录中已存在的文件（防止记录丢失导致重复下载）
        if (Test-Path $downloadDir) {
            $existingFiles = Get-ChildItem -Path $downloadDir -File | Select-Object -ExpandProperty Name
            $existingCount = 0
            foreach ($existingFile in $existingFiles) {
                if (-not $downloaded.ContainsKey($existingFile)) {
                    $downloaded[$existingFile] = $true
                    $existingCount++
                    # 补充记录到文件中
                    Add-Content -Path $recordFile -Value $existingFile -ErrorAction SilentlyContinue
                }
            }
            if ($existingCount -gt 0) {
                Write-Host "发现 $existingCount 个已存在但未记录的文件，已补充记录。"
            }
        }

        # ------- 核心下载逻辑 -------
        Write-Host "`n[$(Get-Date -Format 'HH:mm:ss')] 开始新一轮检查，当前周期: $cycleTag"
        Write-Host "正在获取 MANIFEST.txt..."
        
        try {
            Invoke-WebRequest -Uri $manifestUrl -OutFile $manifestPath -UseBasicParsing -ErrorAction Stop
            Write-Host "MANIFEST.txt 获取成功。"
        } catch {
            Write-Warning "MANIFEST.txt 下载失败：$($_.Exception.Message)"
            Write-Host "将在 60 秒后重试..."
            Start-Sleep -Seconds 60
            continue 
        }

        $manifestFiles = Get-Content $manifestPath
        $newFiles = @()
        foreach ($file in $manifestFiles) {
            if (-not $downloaded.ContainsKey($file)) { $newFiles += $file }
        }

        Write-Host "发现新增文件 $($newFiles.Count) 个。"

        # ------- 并行下载带进度显示 -------
        if ($newFiles.Count -gt 0) {
            Write-Host "开始并行下载，最大并发: $throttleLimit"
            $jobs = @()
            $successfullyDownloaded = @()
            $completedCount = 0
            $downloadStartTime = Get-Date
            
            # 显示初始进度
            Show-Progress -Current 0 -Total $newFiles.Count -Completed 0 -StartTime $downloadStartTime
            
            # 创建互斥锁文件用于实时记录同步
            $lockFile = "$recordFile.lock"
            
            foreach ($file in $newFiles) {
                # 下载脚本块（带重试机制和实时记录）
                $scriptBlock = {
                    param($fileToDownload, $downloadPath, $recordFilePath)
                    
                    $url = "https://api.starlink.com/public-files/ephemerides/$fileToDownload"
                    $targetPath = Join-Path $downloadPath $fileToDownload
                    $maxRetries = 3
                    $retryCount = 0
                    
                    do {
                        try {
                            Invoke-WebRequest -Uri $url -OutFile $targetPath -UseBasicParsing -TimeoutSec 30 -ErrorAction Stop
                            
                            # 立即记录成功下载的文件（带锁机制）
                            $lockFile = "$recordFilePath.lock"
                            $maxLockWait = 10 # 最多等待10秒获取锁
                            $lockWaitCount = 0
                            
                            # 等待获取文件锁
                            while ((Test-Path $lockFile) -and ($lockWaitCount -lt $maxLockWait)) {
                                Start-Sleep -Milliseconds 100
                                $lockWaitCount++
                            }
                            
                            try {
                                # 创建锁文件
                                New-Item -Path $lockFile -ItemType File -Force -ErrorAction SilentlyContinue | Out-Null
                                # 立即写入记录
                                Add-Content -Path $recordFilePath -Value $fileToDownload -ErrorAction SilentlyContinue
                            } finally {
                                # 释放锁
                                Remove-Item -Path $lockFile -Force -ErrorAction SilentlyContinue
                            }
                            
                            return @{
                                Success = $true
                                FileName = $fileToDownload
                                Size = (Get-Item $targetPath -ErrorAction SilentlyContinue).Length
                            }
                        } catch {
                            $retryCount++
                            if ($retryCount -lt $maxRetries) {
                                Start-Sleep -Seconds (2 * $retryCount)
                            }
                        }
                    } while ($retryCount -lt $maxRetries)
                    
                    return @{
                        Success = $false
                        FileName = $fileToDownload
                        Error = $_.Exception.Message
                    }
                }
                
                # 启动作业，传递记录文件路径
                $jobs += Start-Job -ScriptBlock $scriptBlock -ArgumentList $file, $downloadDir, $recordFile

                # 限流控制和进度更新
                if ($jobs.Count -ge $throttleLimit) {
                    $completedJob = Wait-Job -Job $jobs -Any
                    $result = Receive-Job -Job $completedJob
                    
                    if ($result.Success) {
                        $successfullyDownloaded += $result.FileName
                        # 更新内存中的下载记录，避免重复下载
                        $downloaded[$result.FileName] = $true
                    }
                    
                    $completedCount++
                    Show-Progress -Current $jobs.Count -Total $newFiles.Count -Completed $completedCount -CurrentFile $result.FileName -StartTime $downloadStartTime
                    
                    $jobs = $jobs | Where-Object { $_.Id -ne $completedJob.Id }
                    Remove-Job -Job $completedJob
                }
            }

            # 等待剩余作业完成
            while ($jobs.Count -gt 0) {
                $completedJob = Wait-Job -Job $jobs -Any
                $result = Receive-Job -Job $completedJob
                
                if ($result.Success) {
                    $successfullyDownloaded += $result.FileName
                    # 更新内存中的下载记录，避免重复下载
                    $downloaded[$result.FileName] = $true
                }
                
                $completedCount++
                Show-Progress -Current $jobs.Count -Total $newFiles.Count -Completed $completedCount -CurrentFile $result.FileName -StartTime $downloadStartTime
                
                $jobs = $jobs | Where-Object { $_.Id -ne $completedJob.Id }
                Remove-Job -Job $completedJob
            }
            
            Write-Host ""  # 换行
            
            # 清理可能残留的锁文件
            if (Test-Path $lockFile) {
                Remove-Item -Path $lockFile -Force -ErrorAction SilentlyContinue
            }
            
            $failedCount = $newFiles.Count - $successfullyDownloaded.Count
            Write-Host "下载完成: 成功 $($successfullyDownloaded.Count) 个"
            if ($failedCount -gt 0) {
                Write-Host "下载失败: $failedCount 个" -ForegroundColor Yellow
            }
        } else {
            Write-Host "无新增文件。"
        }

        # ------- 智能休眠逻辑 -------
        $loopEndTime = Get-Date
        $executionDuration = $loopEndTime - $loopStartTime
        Write-Host ("本轮任务耗时: {0:N1} 秒" -f $executionDuration.TotalSeconds)

        if ($executionDuration.TotalSeconds -ge $checkCycleSeconds) {
            Write-Host "任务耗时已超过检查周期，立即开始下一轮。"
            Start-Sleep -Seconds 1
        } else {
            $sleepSeconds = $checkCycleSeconds - $executionDuration.TotalSeconds
            $nextCheckTime = (Get-Date).AddSeconds($sleepSeconds).ToString("HH:mm:ss")
            Write-Host ("将在 {0:N0} 秒后 ($nextCheckTime) 开始下一轮检查。" -f $sleepSeconds)
            Start-Sleep -Seconds $sleepSeconds
        }
    }
} finally {
    # 确保清理所有资源
    Cleanup-Jobs
    Write-Host "程序已安全退出。"
}