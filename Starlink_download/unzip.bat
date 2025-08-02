@echo off
setlocal enabledelayedexpansion

rem 设置你自己的文件夹路径
set "folder_path=F:\202409"

rem 设置输出文件夹
set "out_path=E:\program\202409"

rem 遍历 zip 文件
for %%f in (%folder_path%\*.zip) do (
    set "filename=%%~nxf"

    rem 判断是否以 SpaceX 开头（不区分大小写）
    if /i "!filename:~0,6!" == "SpaceX" (
        set "datepart=!filename:~-28,10!"

        rem 如果需要根据日期范围筛选，取消下面 if 的注释
        rem if "!datepart!" geq "2024-09-01" if "!datepart!" leq "2024-09-05" (

            echo unzip: %%f

            set "foldername=%%~nf"
            set "target_path=%out_path%\!foldername!"

            if exist "%ProgramFiles%\WinRAR\WinRAR.exe" (
                "%ProgramFiles%\WinRAR\WinRAR.exe" x -o+ -ibck "%%f" "!target_path!\"
            ) else (
                powershell -Command "Expand-Archive -Path '%%f' -DestinationPath '!target_path!'"
            )
        rem )
    )
)

echo well done!
pause
