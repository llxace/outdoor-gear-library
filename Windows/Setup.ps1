$ErrorActionPreference = 'Stop'

if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) {
    throw '此安装程序只能在 Windows 上运行。'
}
if ([Environment]::Is64BitOperatingSystem -eq $false) {
    throw '此版本需要 64 位 Windows。'
}

$source = Join-Path $PSScriptRoot 'app'
$target = Join-Path $env:LOCALAPPDATA 'Programs\户外装备库'
$exe = Join-Path $target '户外装备库.exe'
$sourceExe = Join-Path $source '户外装备库.exe'
if (-not (Test-Path $sourceExe)) {
    throw '没有找到安装文件。请先解压完整安装包，再运行 Install.cmd。'
}

$runningApp = Get-Process -Name '户外装备库' -ErrorAction SilentlyContinue
if ($runningApp) {
    throw '户外装备库仍在运行。请先关闭程序，再重新运行安装程序。'
}

$runtimeKey = 'HKLM:\SOFTWARE\Microsoft\VisualStudio\14.0\VC\Runtimes\x64'
$runtimeInstalled = (Get-ItemProperty -Path $runtimeKey -Name Installed -ErrorAction SilentlyContinue).Installed -eq 1
if (-not $runtimeInstalled) {
    $runtimeInstaller = Join-Path $PSScriptRoot 'prerequisites\vc_redist.x64.exe'
    if (-not (Test-Path $runtimeInstaller)) { throw '缺少 Microsoft Visual C++ 运行库安装文件。请重新下载完整安装包。' }
    $runtimeProcess = Start-Process -FilePath $runtimeInstaller -ArgumentList '/install /quiet /norestart' -Verb RunAs -Wait -PassThru
    if ($runtimeProcess.ExitCode -notin @(0, 3010, 1638, 1641)) { throw "Visual C++ 运行库安装失败，退出码 $($runtimeProcess.ExitCode)。" }
}

$programs = Split-Path -Parent $target
$installId = [Guid]::NewGuid().ToString('N')
$staging = Join-Path $programs ".户外装备库.installing-$installId"
$backup = Join-Path $programs ".户外装备库.previous-$installId"
$previousMoved = $false
$newInstallMoved = $false

try {
    New-Item -ItemType Directory -Path $programs -Force | Out-Null
    New-Item -ItemType Directory -Path $staging -Force | Out-Null
    Get-ChildItem -LiteralPath $source -Force | Copy-Item -Destination $staging -Recurse -Force
    if (-not (Test-Path (Join-Path $staging '户外装备库.exe'))) {
        throw '复制后的安装文件不完整，已取消安装。'
    }

    if (Test-Path $target) {
        Move-Item -LiteralPath $target -Destination $backup
        $previousMoved = $true
    }
    Move-Item -LiteralPath $staging -Destination $target
    $newInstallMoved = $true

    $shortcutPath = Join-Path ([Environment]::GetFolderPath('Desktop')) '户外装备库.lnk'
    $shell = New-Object -ComObject WScript.Shell
    $shortcut = $shell.CreateShortcut($shortcutPath)
    $shortcut.TargetPath = $exe
    $shortcut.WorkingDirectory = $target
    $shortcut.Description = '户外装备库 Windows 原生版 0.20.4'
    $shortcut.Save()

    if ($previousMoved) {
        Remove-Item -LiteralPath $backup -Recurse -Force -ErrorAction SilentlyContinue
    }
}
catch {
    if ($newInstallMoved -and (Test-Path $target)) {
        Remove-Item -LiteralPath $target -Recurse -Force -ErrorAction SilentlyContinue
    }
    if ($previousMoved -and (Test-Path $backup) -and -not (Test-Path $target)) {
        Move-Item -LiteralPath $backup -Destination $target -ErrorAction SilentlyContinue
    }
    if (Test-Path $staging) {
        Remove-Item -LiteralPath $staging -Recurse -Force -ErrorAction SilentlyContinue
    }
    throw
}

Write-Host '安装完成。桌面已创建“户外装备库”快捷方式。'
Write-Host '首次启动会在本机创建一个空白资料库。'
Write-Host '资料只保存在本机；卸载程序时可自行选择是否保留 %LOCALAPPDATA%\OutdoorGearLibrary。'
Read-Host '按回车键关闭'
