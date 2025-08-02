# PowerShell 5.1 for Starlink Downloader
# 用到锁，批量下载，但是每次记录一个，效率低
#
# 整合了高效的事件驱动下载循环与用户自定义的优化项
# 解决了进度条显示延迟和不更新的问题
#
# 使用自定义清单路径方法
# .\StarlinkDownloader.ps1 -manifestPathInput "E:\Starlink\custom_manifest.txt"
param(
    [string]$manifestPathInput  # 可选参数：用户提供的清单路径
)

# ------- 配置 -------
$baseDir = "E:\eph"
$logDir = "$baseDir\logs"
$manifestUrl = "https://api.starlink.com/public-files/ephemerides/MANIFEST.txt"
$cycleHours = 8
$throttleLimit = 25  # 并发数

# 使用提供的路径或默认路径
$manifestPath = if ($manifestPathInput) { $manifestPathInput } else { "$baseDir\MANIFEST.txt" }

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
    
    # 使用整体吞吐量进行估算
    $remainingTime = [TimeSpan]::Zero
    if ($Completed -gt 10 -and $elapsed.TotalSeconds -gt 5) { # 增加样本和时间阈值，让估算更稳定
        $avgThroughput = $Completed / $elapsed.TotalSeconds  # 每秒完成的文件数
        if ($avgThroughput -gt 0) {
            $remainingFiles = $Total - $Completed
            $estimatedSeconds = $remainingFiles / $avgThroughput
            $remainingTime = [TimeSpan]::FromSeconds($estimatedSeconds)
        }
    }
    
    # 清除当前行并显示进度
    Write-Host "`r" -NoNewline
    
    # 修正进度条在100%时可能超出1个字符的小问题
    $numEquals = [math]::Floor($percentComplete / 5)
    if ($numEquals -gt 20) { $numEquals = 20 }
    $numSpaces = 19 - $numEquals
    if ($numSpaces -lt 0) { $numSpaces = 0 }
    $progressBar = "=" * $numEquals + ">" + " " * $numSpaces

    $progressText = "[$progressBar] $percentComplete% ($Completed/$Total) "
    
    # 显示速度信息
    if ($elapsed.TotalSeconds -gt 5 -and $Completed -gt 0) {
        $speed = [math]::Round($Completed / $elapsed.TotalSeconds, 1)
        $progressText += "速度: $speed files/s "
    }
    
    # 只在有合理估算时显示剩余时间
    if ($remainingTime.TotalSeconds -gt 1) {
        if ($remainingTime.TotalHours -ge 1) {
            $progressText += "剩余: $($remainingTime.ToString('hh\:mm\:ss')) "
        } else {
            $progressText += "剩余: $($remainingTime.ToString('mm\:ss')) "
        }
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
    # ------- 单次执行逻辑 -------
    $scriptStartTime = Get-Date
    Write-Host "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] Starlink 下载脚本开始执行（最终优化版 - 已修复）"

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
                } else {
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

    # ------- 读取或下载清单 -------
    if ($manifestPathInput) {
        if (Test-Path $manifestPath) {
            Write-Host "`n使用提供的清单文件: $manifestPath"
        } else {
            Write-Error "提供的 manifestPath 不存在: $manifestPath"
            exit 1
        }
    } else {
        Write-Host "`n正在获取 MANIFEST.txt..."
        
        $maxManifestRetries = 3
        $manifestRetryCount = 0
        $manifestDownloaded = $false
        
        do {
            try {
                Invoke-WebRequest -Uri $manifestUrl -OutFile $manifestPath -UseBasicParsing -ErrorAction Stop
                Write-Host "MANIFEST.txt 获取成功。"
                $manifestDownloaded = $true
            } catch {
                $manifestRetryCount++
                if ($manifestRetryCount -lt $maxManifestRetries) {
                    Write-Warning "MANIFEST.txt 下载失败（第 $manifestRetryCount 次尝试）：$($_.Exception.Message)"
                    Write-Host "将在 10 秒后重试..."
                    Start-Sleep -Seconds 10
                } else {
                    Write-Error "MANIFEST.txt 下载失败，已重试 $maxManifestRetries 次：$($_.Exception.Message)"
                    exit 1
                }
            }
        } while (-not $manifestDownloaded -and $manifestRetryCount -lt $maxManifestRetries)
    }

    $manifestFiles = Get-Content $manifestPath
    $newFiles = @()
    foreach ($file in $manifestFiles) {
        if (-not $downloaded.ContainsKey($file)) { $newFiles += $file }
    }

    Write-Host "清单文件总数: $($manifestFiles.Count)"
    Write-Host "已下载文件数: $($downloaded.Count)"
    Write-Host "发现新增文件: $($newFiles.Count) 个"

    # ------- 优化的并行下载（事件驱动模型）-------
    if ($newFiles.Count -gt 0) {
        Write-Host "`n开始并行下载，最大并发: $throttleLimit"
        
        $scriptBlock = {
            param($fileToDownload, $downloadPath, $recordFilePath)
            
            $url = "https://api.starlink.com/public-files/ephemerides/$fileToDownload"
            $targetPath = Join-Path $downloadPath $fileToDownload
            $maxRetries = 3
            $retryCount = 0
            
            do {
                try {
                    $tempPath = "$targetPath.tmp"
                    if (Test-Path $tempPath) { Remove-Item -Path $tempPath -Force -ErrorAction SilentlyContinue }
                    
                    $webRequest = @{
                        Uri = $url
                        OutFile = $tempPath
                        UseBasicParsing = $true
                        TimeoutSec = 60
                        ErrorAction = 'Stop'
                        UserAgent = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36'
                        MaximumRedirection = 3
                    }
                    Invoke-WebRequest @webRequest
                    
                    $downloadedFile = Get-Item $tempPath -ErrorAction Stop
                    if ($downloadedFile.Length -eq 0) { throw "下载的文件为空" }
                    
                    Move-Item -Path $tempPath -Destination $targetPath -Force -ErrorAction Stop
                    
                    $success = $false
                    $lockAttempts = 0
                    while (-not $success -and $lockAttempts -lt 50) {
                        try {
                            Add-Content -Path $recordFilePath -Value $fileToDownload -ErrorAction Stop
                            $success = $true
                        } catch {
                            Start-Sleep -Milliseconds 20
                            $lockAttempts++
                        }
                    }
                    
                    return @{ Success = $true; FileName = $fileToDownload; Size = $downloadedFile.Length }
                } catch {
                    if (Test-Path $tempPath) { Remove-Item -Path $tempPath -Force -ErrorAction SilentlyContinue }
                    $retryCount++
                    if ($retryCount -lt $maxRetries) {
                        Start-Sleep -Seconds ([Math]::Pow(2, $retryCount))
                    }
                }
            } while ($retryCount -lt $maxRetries)
            
            return @{ Success = $false; FileName = $fileToDownload; Error = $_.Exception.Message }
        }
        
        $jobs = @()
        $successfullyDownloaded = @()
        $completedCount = 0
        $downloadStartTime = Get-Date
        
        # --- 核心修复 ---
        # 定义一个代码块来处理已完成的作业
        # 在块内使用 $script: 前缀来确保修改的是主脚本作用域的变量
        $processCompletedJob = {
            param($completedJob)

            $result = Receive-Job -Job $completedJob
            
            # 使用 $script: 来修改主脚本的变量
            $script:completedCount++
            if ($result.Success) {
                $script:successfullyDownloaded += $result.FileName
                $script:downloaded[$result.FileName] = $true
            }
            
            # 从主脚本的 $jobs 数组中移除该作业
            $script:jobs = $script:jobs | Where-Object { $_.Id -ne $completedJob.Id }
            
            # 现在可以安全地从系统中删除作业
            Remove-Job -Job $completedJob
            
            # 更新进度显示
            Show-Progress -Current $script:jobs.Count -Total $newFiles.Count -Completed $script:completedCount -CurrentFile $result.FileName -StartTime $downloadStartTime
        }

        foreach ($file in $newFiles) {
            $jobs += Start-Job -ScriptBlock $scriptBlock -ArgumentList $file, $downloadDir, $recordFile
            
            if ($jobs.Count -ge $throttleLimit) {
                $completedJob = Wait-Job -Job $jobs -Any
                & $processCompletedJob $completedJob
            }
        }

        while ($jobs.Count -gt 0) {
            $completedJob = Wait-Job -Job $jobs -Any
            & $processCompletedJob $completedJob
        }

        Write-Host ""
        
        $failedCount = $newFiles.Count - $successfullyDownloaded.Count
        Write-Host "下载完成: 成功 $($successfullyDownloaded.Count) 个"
        if ($failedCount -gt 0) {
            Write-Host "下载失败: $failedCount 个" -ForegroundColor Yellow
        }
    } else {
        Write-Host "无新增文件需要下载。"
    }

    # ------- 执行总结 -------
    $scriptEndTime = Get-Date
    $totalDuration = $scriptEndTime - $scriptStartTime
    Write-Host "`n[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] 脚本执行完成"
    Write-Host ("总耗时: {0:N1} 秒" -f $totalDuration.TotalSeconds)
    
    if ($newFiles.Count -gt 0 -and $totalDuration.TotalSeconds -gt 0) {
        $avgSpeed = [math]::Round($successfullyDownloaded.Count / $totalDuration.TotalSeconds, 2)
        Write-Host ("平均下载速度: $avgSpeed 文件/秒")
    }
    
    Write-Host "退出代码: 0"

} catch {
    Write-Error "脚本执行时发生错误: $($_.Exception.Message)"
    # 打印更详细的堆栈跟踪信息，方便调试
    Write-Error $_.ScriptStackTrace
    Write-Host "退出代码: 1"
    exit 1
} finally {
    # 确保清理所有资源
    Cleanup-Jobs
    Write-Host "资源清理完成。"
}