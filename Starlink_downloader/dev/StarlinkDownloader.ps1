# ------- 配置 -------
$baseDir = "E:\Starlink"
$logDir = "$baseDir\logs"
$manifestUrl = "https://api.starlink.com/public-files/ephemerides/MANIFEST.txt"
$manifestPath = "$baseDir\MANIFEST.txt"
$cycleHours = 8
# ########## 修改点 A：这里的 7200 秒现在代表“检查周期的总时长” ##########
$checkCycleSeconds = 7200   # 2小时的检查周期

# 确保基础日志目录存在
New-Item -ItemType Directory -Force -Path $logDir | Out-Null

# ------- 主循环 -------
while ($true) {
    # ########## 修改点 B：在循环开始时记录“本轮任务的起始时间” ##########
    $loopStartTime = Get-Date

    # ------- 时间处理 (每次循环都重新计算) -------
    $now = [DateTime]::UtcNow
    # 定义当天和第二天的周期结束时间节点
    $today_T1 = $now.Date.AddHours(5).AddMinutes(21)   # 当天 05:21 UTC
    $today_T2 = $now.Date.AddHours(13).AddMinutes(21)  # 当天 13:21 UTC
    $today_T3 = $now.Date.AddHours(21).AddMinutes(21)  # 当天 21:21 UTC
    $tomorrow_T1 = $today_T1.AddDays(1)              # 第二天 05:21 UTC

    # 判断当前时间属于哪个周期，并获取该周期的结束时间
    # 例如，如果当前是 14:00，它大于 13:21 但小于等于 21:21，所以它的周期结束时间是 21:21
    if ($now -le $today_T1) {
        # 当前处于周期: (昨天 21:21) -> (今天 05:21]
        $cycleEnd = $today_T1
    } elseif ($now -le $today_T2) {
        # 当前处于周期: (今天 05:21) -> (今天 13:21]
        $cycleEnd = $today_T2
    } elseif ($now -le $today_T3) {
        # 当前处于周期: (今天 13:21) -> (今天 21:21]
        $cycleEnd = $today_T3
    } else {
        # 当前处于周期: (今天 21:21) -> (明天 05:21]
        $cycleEnd = $tomorrow_T1
    }

    # 获取年月标记（例如 202507）
    $ymTag = $cycleEnd.ToString("yyyyMM")
    # 使用周期的结束时间来生成标签
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

    $count = 0
    if ($newFiles.Count -gt 0) {
        foreach ($file in $newFiles) {
            $url = "https://api.starlink.com/public-files/ephemerides/$file"
            $targetPath = "$downloadDir\$file"
            try {
                Invoke-WebRequest -Uri $url -OutFile $targetPath -UseBasicParsing -ErrorAction Stop
                Add-Content -Path $recordFile -Value $file
                $downloaded[$file] = $true
                $count++
            } catch {
                Write-Warning "下载失败: $file - $($_.Exception.Message)"
            }
        }
    }

    if ($count -gt 0) {
        # 更新文件夹与记录文件名
        # $total = ($downloaded.Keys | Measure-Object).Count
        # $finalName = "SpaceX_Ephemeris_$total" + "_SpaceX_$cycleTag"
        # Rename-Item -Path $downloadDir -NewName $finalName -Force
        # Rename-Item -Path $recordFile -NewName "$baseDir\$finalName.txt" -Force
        # $downloadDir = "$baseDir\$finalName"
        # $recordFile = "$baseDir\$finalName.txt"

        # 获取当前周期记录文件中的总行数，即为当前周期的总下载文件数
        $totalInCycle = (Get-Content -Path $recordFile -ErrorAction SilentlyContinue).Count
        Write-Host "本轮下载完成：$count 个新文件。当前周期 ($cycleTag) 总计下载：$totalInCycle 个文件。"
    } else {
        Write-Host "无新增文件。"
    }

    # ########## 修改点 C：全新的智能休眠逻辑 ##########
    # --- 计算本轮任务总耗时 ---
    $loopEndTime = Get-Date
    $executionDuration = $loopEndTime - $loopStartTime

    Write-Host ("本轮任务总耗时: {0:N2} 秒" -f $executionDuration.TotalSeconds)

    # --- 根据耗时决定休眠时间 ---
    if ($executionDuration.TotalSeconds -ge $checkCycleSeconds) {
        # 如果执行时间已经超过或等于一个检查周期（2小时），则立即开始下一轮
        Write-Host "任务耗时已超过 $($checkCycleSeconds/3600) 小时，立即开始下一轮检查。"
        Start-Sleep -Seconds 1 # 短暂休眠1秒，防止CPU空转
    } else {
        # 如果执行时间小于检查周期，则计算剩余时间并休眠
        $sleepSeconds = $checkCycleSeconds - $executionDuration.TotalSeconds
        $nextCheckTime = (Get-Date).AddSeconds($sleepSeconds).ToString("u")
        Write-Host ("将在 {0:N2} 秒后 (大约在 $nextCheckTime) 开始下一轮检查。" -f $sleepSeconds)
        Start-Sleep -Seconds $sleepSeconds
    }
}