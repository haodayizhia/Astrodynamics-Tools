# powershell 5.1 for Starlink Downloader Parallel.ps1
# ------- 配置 -------
$baseDir = "E:\Starlink"
$logDir = "$baseDir\logs"
$manifestUrl = "https://api.starlink.com/public-files/ephemerides/MANIFEST.txt"
$manifestPath = "$baseDir\MANIFEST.txt"
$cycleHours = 8
$checkCycleSeconds = 7200  # 2小时的检查周期

# ########## 优化点 A：设置并行下载的作业数 ##########
# 这个值决定了同时在后台运行多少个下载作业。可以根据你的CPU性能调整。
# 建议从 10 或 20 开始尝试。
$throttleLimit = 20

# 确保基础日志目录存在
New-Item -ItemType Directory -Force -Path $logDir | Out-Null

# ------- 主循环 -------
while ($true) {
    $loopStartTime = Get-Date

    # ------- 时间处理 (每次循环都重新计算) -------
    # ... [这部分代码与您原来的一样，保持不变] ...
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

    # ------- 目录和文件名 (每次循环都重新计算) -------
    $downloadDir = "$baseDir\$ymTag\SpaceX_Ephemeris_552_SpaceX_$cycleTag"
    $recordFile = "$logDir\SpaceX_Ephemeris_552_SpaceX_$cycleTag.txt"
    New-Item -ItemType Directory -Force -Path $downloadDir | Out-Null

    # ------- 加载记录 -------
    # ... [这部分代码与您原来的一样，保持不变] ...
    $prevCycleEnd = $cycleEnd.AddHours(-$cycleHours)
    $prevTag = $prevCycleEnd.ToString("yyyy-MM-dd\UTC") + $prevCycleEnd.ToString("HH_mm_00")
    $prevRecord = "$logDir\SpaceX_Ephemeris_552_SpaceX_$prevTag.txt"

    $downloaded = @{}
    if (Test-Path $recordFile) {
        Get-Content $recordFile -ErrorAction SilentlyContinue | ForEach-Object { $downloaded[$_] = $true }
    }
    if (Test-Path $prevRecord) {
        Get-Content $prevRecord -ErrorAction SilentlyContinue | ForEach-Object { $downloaded[$_] = $true }
    }

    # ------- 核心下载逻辑 -------
    Write-Host "`n[$(Get-Date -Format u)] 开始新一轮检查，当前周期为: $cycleTag"
    Write-Host "开始访问 MANIFEST.txt..."
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

    # ########## 优化点 B：使用后台作业 (Start-Job) 进行并行下载 ##########
    $count = 0
    if ($newFiles.Count -gt 0) {
        Write-Host "开始并行下载，最大并发作业数: $throttleLimit..."
        $jobs = @() # 用于存放所有启动的作业
        $successfullyDownloaded = @() # 用于收集成功下载的文件名

        foreach ($file in $newFiles) {
            # 定义作业要执行的脚本块
            $scriptBlock = {
                param($fileToDownload, $downloadPath) # 接收从主脚本传来的参数
                
                $url = "https://api.starlink.com/public-files/ephemerides/$fileToDownload"
                $targetPath = Join-Path $downloadPath $fileToDownload
                
                try {
                    Invoke-WebRequest -Uri $url -OutFile $targetPath -UseBasicParsing -ErrorAction Stop
                    # 如果成功，输出文件名，以便 Receive-Job 接收
                    return $fileToDownload
                } catch {
                    # 如果出错，不返回任何内容
                    Write-Warning "下载失败: $fileToDownload - $($_.Exception.Message)"
                }
            }
            
            # 启动作业，并通过 -ArgumentList 传递参数
            $jobs += Start-Job -ScriptBlock $scriptBlock -ArgumentList $file, $downloadDir

            # 限流控制：如果正在运行的作业达到了上限，就等待其中任意一个完成后再继续
            if ($jobs.Count -ge $throttleLimit) {
                # 等待任意一个作业完成
                $jobFinished = Wait-Job -Job $jobs -Any
                # 收集已完成作业的结果
                $result = Receive-Job -Job $jobFinished
                if ($result) { $successfullyDownloaded += $result }
                # 从列表中移除已完成的作业
                $jobs = $jobs | Where-Object { $_.Id -ne $jobFinished.Id }
                # 清理作业对象，释放资源
                Remove-Job -Job $jobFinished
            }
        }

        # 等待所有剩余的作业完成
        Wait-Job -Job $jobs | Out-Null
        # 收集所有剩余作业的结果
        foreach ($job in $jobs) {
            $result = Receive-Job -Job $job
            if ($result) { $successfullyDownloaded += $result }
        }
        # 清理所有剩余的作业
        Remove-Job -Job $jobs

        # ########## 优化点 C：所有下载任务结束后，一次性写入记录文件 ##########
        if ($successfullyDownloaded.Count -gt 0) {
            Add-Content -Path $recordFile -Value $successfullyDownloaded
        }
        
        $count = $successfullyDownloaded.Count
    }
    
    if ($count -gt 0) {
        $totalInCycle = (Get-Content -Path $recordFile -ErrorAction SilentlyContinue).Count
        Write-Host "本轮下载完成：$count 个新文件。当前周期 ($cycleTag) 总计下载：$totalInCycle 个文件。"
    } else {
        Write-Host "无新增文件。"
    }

    # ########## 无需修改：智能休眠逻辑 ##########
    $loopEndTime = Get-Date
    $executionDuration = $loopEndTime - $loopStartTime
    Write-Host ("本轮任务总耗时: {0:N2} 秒" -f $executionDuration.TotalSeconds)

    if ($executionDuration.TotalSeconds -ge $checkCycleSeconds) {
        Write-Host "任务耗时已超过 $($checkCycleSeconds/3600) 小时，立即开始下一轮检查。"
        Start-Sleep -Seconds 1
    } else {
        $sleepSeconds = $checkCycleSeconds - $executionDuration.TotalSeconds
        $nextCheckTime = (Get-Date).AddSeconds($sleepSeconds).ToString("u")
        Write-Host ("将在 {0:N2} 秒后 (大约在 $nextCheckTime) 开始下一轮检查。" -f $sleepSeconds)
        Start-Sleep -Seconds $sleepSeconds
    }
}