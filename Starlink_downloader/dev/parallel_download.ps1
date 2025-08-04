# PowerShell 7+ 脚本：并行下载 SpaceX Starlink 卫星数据
# ------- 配置 -------
$baseDir = "E:\Starlink"
$logDir = "$baseDir\logs"
$manifestUrl = "https://api.starlink.com/public-files/ephemerides/MANIFEST.txt"
$manifestPath = "$baseDir\MANIFEST.txt"
$cycleHours = 8
$checkCycleSeconds = 7200  # 2小时的检查周期

# ########## 优化点 A：设置并行下载的线程数 ##########
# 这个值决定了同时下载多少个文件。可以根据你的网络和CPU性能调整。
# 建议从 10 或 20 开始尝试。
$throttleLimit = 20

# 确保基础日志目录存在
New-Item -ItemType Directory -Force -Path $logDir | Out-Null

# ------- 主循环 -------
while ($true) {
    $loopStartTime = Get-Date

    # ------- 时间处理 (每次循环都重新计算) -------
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

    # ########## 优化点 B：使用并行下载替换原有的串行下载 ##########
    $successfullyDownloaded = @() # 用于收集成功下载的文件名
    if ($newFiles.Count -gt 0) {
        Write-Host "开始并行下载，最大并发数: $throttleLimit..."
        
        # 使用 ForEach-Object -Parallel 进行并行处理
        $successfullyDownloaded = $newFiles | ForEach-Object -Parallel {
            # 在并行脚本块中，使用 $using: 来引用外部作用域的变量
            $file = $_
            $url = "https://api.starlink.com/public-files/ephemerides/$file"
            $targetPath = "$($using:downloadDir)\$file"
            
            try {
                # 每个线程执行一次下载
                Invoke-WebRequest -Uri $url -OutFile $targetPath -UseBasicParsing -ErrorAction Stop
                
                # 如果下载成功，输出文件名，它将被收集到 $successfullyDownloaded 变量中
                Write-Output $file
            } catch {
                # 在并行任务中，错误信息需要用 Write-Warning 或 Write-Error 来显示
                Write-Warning "下载失败: $file - $($_.Exception.Message)"
            }
        } -ThrottleLimit $throttleLimit # 控制最大并行数

        # ########## 优化点 C：所有下载任务结束后，一次性写入记录文件 ##########
        if ($successfullyDownloaded.Count -gt 0) {
            # 将所有成功下载的文件名追加到记录文件中
            Add-Content -Path $using:recordFile -Value $successfullyDownloaded
            
            # 更新已下载列表，以便后续逻辑正确判断
            foreach($file in $successfullyDownloaded) {
                $using:downloaded[$file] = $true
            }
        }
    }
    
    $count = $successfullyDownloaded.Count

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