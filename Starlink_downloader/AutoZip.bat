@echo off
setlocal

:: ====== WinRAR 路径 ======
set RAR="C:\Program Files\WinRAR\WinRAR.exe"

:: ====== 要处理的目录（改成你的路径） ======
set TARGET=E:\eph\202603

echo 开始处理目录: %TARGET%
echo.

if not exist "%TARGET%" (
    echo 目录不存在！
    pause
    exit /b
)

for /d %%D in ("%TARGET%\*") do (
    if exist "%TARGET%\%%~nxD.zip" (
        echo 跳过: %%~nxD.zip 已存在，无需重复压缩。
    ) else (
        echo 正在压缩 %%~nxD ...
        pushd "%%D"
        %RAR% a -afzip -r -ibck "%TARGET%\%%~nxD.zip" *
        popd
    )
)

echo.
echo 全部完成
pause