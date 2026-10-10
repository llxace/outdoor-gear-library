$ErrorActionPreference = 'Stop'
$project = Join-Path $PSScriptRoot 'src\OutdoorGear.Wpf\OutdoorGear.Wpf.csproj'
$publish = Join-Path $PSScriptRoot 'dist\publish\win-x64'
$output = Join-Path $PSScriptRoot 'dist\户外装备库-0.20.4-Windows-x64.msi'

Push-Location $PSScriptRoot
try {
    dotnet publish $project -c Release -r win-x64 --self-contained true -p:EnableWindowsTargeting=true -o $publish
    if ($LASTEXITCODE -ne 0) { throw 'Windows x64 发布失败。' }
    Remove-Item (Join-Path $publish 'x86') -Recurse -Force -ErrorAction SilentlyContinue
    Get-ChildItem $publish -Filter '*.pdb' -File | Remove-Item -Force
    Get-ChildItem $publish -Filter '*.lib' -Recurse -File | Remove-Item -Force
    dotnet tool restore
    if ($LASTEXITCODE -ne 0) { throw 'WiX 工具还原失败。' }
    dotnet tool run wix build (Join-Path $PSScriptRoot 'installer\Package.wxs') -out $output -arch x64 -bindpath "Publish=$publish"
    if ($LASTEXITCODE -ne 0) { throw 'MSI 生成失败。' }
    Write-Host "MSI 已生成：$output"
}
finally { Pop-Location }
