$buildVersion = '7zip-zstd-2501'
$PLATFORM = "x64"
$SUBSYS = "5.02"

# 环境变量
$workDir = $PSScriptRoot
$buildDir = "$workDir\build"
$resDir = "$workDir\resources"
$srcDir = "$buildDir\$buildVersion"
$tempDir = "$buildDir\Temp"
$def_version = "7z2501"

# 检测build是否存在
if (Test-Path -Path $buildDir -PathType Container) {
}
else {
    try {
        New-Item -ItemType Directory -Path $buildDir -Force | Out-Null
    }
    catch {
        Write-Host "创建build目录失败"
        exit 1
    }
}

# 检测build是否存在
# 复制src源代码
if (Test-Path -Path $srcDir -PathType Container) {
    Remove-Item -Path $srcDir -Recurse -Force
}

Copy-Item -Path "$workDir\src" -Destination $srcDir -Recurse -Force

# 资源替换

# 拷贝图标
Copy-Item -Force -Recurse -Path "$resDir\FileIcons\*.ico" -Destination "$srcDir\CPP\7zip\Archive\Icons"

# 拷贝资源文件
Copy-Item -Force -Path "$resDir\Format7zF.rc" -Destination "$srcDir\CPP\7zip\Bundles\Format7zF\resource.rc"
Copy-Item -Force -Path "$resDir\Fm.rc" -Destination "$srcDir\CPP\7zip\Bundles\Fm\resource.rc"

# 拷贝UI图
Copy-Item -Force -Path "$resDir\ToolBarIcons\*.bmp" -Destination "$srcDir\CPP\7zip\UI\FileManager"

# 构建部分
if (-not (Test-Path $tempDir)) {
    New-Item -ItemType Directory -Path $tempDir
}

# 下载7zR
if (-not (Test-Path "$tempDir\7zr.exe")) {
    Invoke-WebRequest -Uri "https://www.7-zip.org/a/7zr.exe" -OutFile "$tempDir\7zr.exe"
}

# 下载并解压VsWhere
if (-not (Test-Path "$tempDir\VsWhere")) {
    if (-not (Test-Path "$tempDir\vswhere.zip")) {
        Invoke-WebRequest -Uri "https://www.nuget.org/api/v2/package/vswhere" -OutFile "$tempDir\vswhere.zip"
    }
    Expand-Archive -Path "$tempDir\vswhere.zip" -DestinationPath "$tempDir\VsWhere"
}

# 查找编译环境
$vsInstallPath = & "$tempDir\VsWhere\tools\vswhere.exe" -latest -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
Import-Module "$vsInstallPath\Common7\Tools\Microsoft.VisualStudio.DevShell.dll"
Enter-VsDevShell -VsInstallPath $vsInstallPath -DevCmdArguments "-arch=$PLATFORM -host_arch=amd64" -SkipAutomaticLocation


function Build-Copy {
    param (
        [string]$RelativePath,
        [string]$OutputFile
    )
    Push-Location "$ROOT\$RelativePath"
    nmake
    if ($LASTEXITCODE -ne 0) { exit 1 }
    Copy-Item "$PLATFORM\$OutputFile" "$OUTDIR\$OutputFile" -Force
    Pop-Location
}


# 设置变量 这个构建其实可以多搞几个架构的 但是没什么必要 我反正用的x64
$WDIR = $srcDir
$env:PLATFORM = "x64"
$env:SUBSYS = "5.02"
$ROOT = Join-Path $WDIR "CPP\7zip"
$OUTDIR = Join-Path $WDIR "build\bin-$PLATFORM"
$env:LFLAGS = "/SUBSYSTEM:WINDOWS,$SUBSYS"

Write-Host "********"
Write-Host "Working Dir: $WDIR"
Write-Host "Platform:    $PLATFORM"
Write-Host "SUBSYS:      $SUBSYS"

New-Item -Path $OUTDIR -ItemType Directory -Force | Out-Null

# 开始构建每个模块
Build-Copy "Bundles\Format7zExtract" "7zxa.dll"
Build-Copy "Bundles\Format7z"        "7za.dll"
Build-Copy "Bundles\Format7zF"       "7z.dll"
Build-Copy "UI\FileManager"          "7zFM.exe"
Build-Copy "UI\GUI"                  "7zG.exe"
Build-Copy "UI\Explorer"             "7-zip.dll"
Build-Copy "Bundles\SFXWin"          "7z.sfx"
Build-Copy "Bundles\Codec_brotli"    "brotli.dll"
Build-Copy "Bundles\Codec_lizard"    "lizard.dll"
Build-Copy "Bundles\Codec_lz4"       "lz4.dll"
Build-Copy "Bundles\Codec_lz5"       "lz5.dll"
Build-Copy "Bundles\Codec_zstd"      "zstd.dll"
Build-Copy "Bundles\Codec_flzma2"    "flzma2.dll"

# 特殊路径
Push-Location "$ROOT\..\..\C\Util\7zipInstall"
nmake
if ($LASTEXITCODE -ne 0) { exit 1 }
Copy-Item "$PLATFORM\7zipInstall.exe" "$OUTDIR\Install.exe" -Force
Pop-Location

Push-Location "$ROOT\..\..\C\Util\7zipUninstall"
nmake
if ($LASTEXITCODE -ne 0) { exit 1 }
Copy-Item "$PLATFORM\7zipUninstall.exe" "$OUTDIR\Uninstall.exe" -Force
Pop-Location

# 控制台程序（切换子系统为 Console）
$env:LFLAGS = "/SUBSYSTEM:CONSOLE,$SUBSYS"
Build-Copy "UI\Console" "7z.exe"
Build-Copy "Bundles\SFXCon" "7zCon.sfx"
Build-Copy "Bundles\Alone"  "7za.exe"

# 特殊x86构建
$env:PLATFORM = "x86"
$env:SUBSYS = "5.01"
Enter-VsDevShell -VsInstallPath $vsInstallPath -DevCmdArguments "-arch=x86 -host_arch=amd64" -SkipAutomaticLocation
Push-Location "$ROOT\UI\Explorer"
nmake
if ($LASTEXITCODE -ne 0) { exit 1 }
Copy-Item "x86\7-zip.dll" "$OUTDIR\7-zip32.dll" -Force
Pop-Location

# 回归
Set-Location $workDir

$packDir = "$buildDir\Pack"
$preDir = "$buildDir\Pre"

if (-not (Test-Path $packDir)) {
    New-Item -ItemType Directory -Path $packDir
}

# 拷贝文件
Copy-Item -Path "$OUTDIR\*" -Destination $packDir -Recurse -Force

# 下载并解压预编译包
if (-not (Test-Path "$tempDir\$def_version-pre.7z")) {
    Invoke-WebRequest -Uri "https://7-zip.org/a/$def_version-x64.exe" -OutFile "$tempDir\$def_version-pre.7z"
    & "$OUTDIR\7z.exe" x "$tempDir\$def_version-pre.7z" -o"$preDir"
}

# 拷贝预编译文件
Copy-Item -Destination $packDir -Path "$preDir\History.txt"
Copy-Item -Destination $packDir -Path "$preDir\License.txt"
Copy-Item -Destination $packDir -Path "$preDir\readme.txt"
Copy-Item -Destination $packDir -Path "$preDir\7-zip.chm"
Copy-Item -Destination $packDir -Path "$preDir\descript.ion"
if (-not (Test-Path "$packDir\Lang")) {
    New-Item -ItemType Directory -Path "$packDir\Lang"
}
Copy-Item -Recurse -Force -Destination "$packDir\Lang" -Path "$preDir\Lang\*"

# 拷贝打包工具
Copy-Item -Destination "$packDir\7z.sfx" -Path "$OUTDIR\Install.exe"
Copy-Item -Destination "$packDir\7zCon.sfx" -Path "$OUTDIR\Install.exe"

# 打包
& "$packDir\7z.exe" a -sfx -t7z -mx=9 -m0=LZMA -r "$workDir\$BuildVersion.exe" "$packDir\*"

# 清理多余文件
Remove-Item -Path $preDir -Recurse -Force
Remove-Item -Path $packDir -Recurse -Force
Remove-Item -Path "$tempDir\$def_version-pre.7z" -Force

Write-Host "Done"