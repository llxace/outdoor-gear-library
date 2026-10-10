$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
$project = Join-Path $root 'src\OutdoorGear.Wpf\OutdoorGear.Wpf.csproj'
$publish = Join-Path $root 'dist\publish\win-x64'
$stage = Join-Path $root 'dist\户外装备库-0.20.4-Windows-x64'
$output = Join-Path $root 'dist\户外装备库-0.20.4-Windows-x64.zip'
$runtime = Join-Path $root '.tools\prerequisites\vc_redist.x64.exe'

Push-Location $root
try {
    if (-not (Test-Path $runtime)) {
        New-Item -ItemType Directory -Path (Split-Path $runtime) -Force | Out-Null
        Invoke-WebRequest 'https://aka.ms/vc14/vc_redist.x64.exe' -OutFile $runtime
    }
    dotnet publish $project -c Release -r win-x64 --self-contained true -p:EnableWindowsTargeting=true -o $publish
    if ($LASTEXITCODE -ne 0) { throw 'Windows x64 发布失败。' }
    Remove-Item (Join-Path $publish 'x86') -Recurse -Force -ErrorAction SilentlyContinue
    Get-ChildItem $publish -Filter '*.pdb' -File | Remove-Item -Force
    Get-ChildItem $publish -Filter '*.lib' -Recurse -File | Remove-Item -Force
    if (Test-Path $stage) { Remove-Item $stage -Recurse -Force }
    New-Item -ItemType Directory -Path $stage -Force | Out-Null
    Copy-Item $publish (Join-Path $stage 'app') -Recurse
    New-Item -ItemType Directory -Path (Join-Path $stage 'prerequisites') -Force | Out-Null
    Copy-Item $runtime (Join-Path $stage 'prerequisites\vc_redist.x64.exe')
    Copy-Item (Join-Path $root 'Install.cmd'), (Join-Path $root 'Setup.ps1'), (Join-Path $root 'README.md'), (Join-Path $root 'LICENSE'), (Join-Path $root 'THIRD-PARTY-NOTICES.md') -Destination $stage
    if (Test-Path $output) { Remove-Item $output -Force }
    Compress-Archive -Path (Join-Path $stage '*') -DestinationPath $output -CompressionLevel Optimal
    Write-Host "安装包已生成：$output"
}
finally { Pop-Location }
