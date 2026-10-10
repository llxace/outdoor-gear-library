# 户外装备库 Windows 原生版

WPF 桌面版本，基于 .NET 10，面向 Windows x64。程序数据默认保存在 `%LOCALAPPDATA%\OutdoorGearLibrary`，不联网同步。首次运行会创建空白资料库。

## 功能

- 装备档案、分类与品牌统计、搜索筛选、编辑、批量整理、回收站和装备照片/附件。
- 多个本机资料库及资料库间借用装备。
- 行前打包清单、数量约束、重量与价值合计。
- 徒步记录、路线搜索与地图、GPX/KML 导入、天气预报和趋势。
- 路餐规划、采购清单、营养标签识别。
- CSV/TSV 与 Excel 导入导出、完整 ZIP 备份与恢复。
- 本机照片整理工具：主体抠图、白底处理、裁剪与阴影。

天气、路线搜索、地图与汇率功能需要网络；库存和图片资料保存在本机。公开程序不内置个人装备清单、照片、头像或行程。

## 下载和安装

GitHub 发布页提供 Windows x64 安装 ZIP。下载解压后双击 `Install.cmd`，按提示完成安装。程序尚未使用 Windows 代码签名证书；Windows SmartScreen 可能显示未识别发布者提示。只从本仓库的发布页下载并核对 SHA-256 校验文件。

## 从源码构建

需要 Windows x64、.NET 10 SDK 和网络连接以恢复 NuGet 依赖。在 Visual Studio 或命令行打开 `OutdoorGearNative.slnx`。发布自包含程序：

```powershell
dotnet publish src/OutdoorGear.Wpf/OutdoorGear.Wpf.csproj -c Release -r win-x64 --self-contained true -p:EnableWindowsTargeting=true -o dist/publish/win-x64
```

默认源码包不含 U²-Net 权重文件（约 168 MB）。若需启用 AI 白底处理，从 GitHub Release 下载 Windows ZIP 后，将 `app/Resources/Models/u2net.onnx` 复制到 `models/u2net.onnx`，再发布。模型许可见 `models/LICENSE-u2net.txt`。中文和英文 OCR 语言数据及其许可随源码提供；照片处理模型另附在发布包中。

程序源码依 GNU AGPL-3.0；第三方组件、路线数据和模型的来源及许可见 [THIRD-PARTY-NOTICES.md](THIRD-PARTY-NOTICES.md)。
