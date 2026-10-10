# Windows 原生版模块与分层

本工程以 macOS 原版 0.20.4 (68) 为行为基线，保留 schema 9、字段名、单位、备份结构和个人资料迁移语义。WPF 仅负责 Windows 桌面交互；跨平台核心规则不依赖 WPF。

## 目录职责

| 目录 | 职责 |
| --- | --- |
| `src/OutdoorGear.Core/Models` | schema 9 数据模型、字段兼容与验证 |
| `src/OutdoorGear.Core/Services` | 装备、打包、餐食、路线、历史、导入导出、资料库规则与事务 |
| `src/OutdoorGear.Core/Services/MapTileService.cs` | 标准/卫星地图瓦片来源、署名、下载和分图源缓存 |
| `src/OutdoorGear.Core/Features/Photos` | 图片处理用例和本地推理实现 |
| `src/OutdoorGear.Core/Features/Profiles/Business` | 用户头像裁剪输出与源图保护 |
| `src/OutdoorGear.Wpf/Features/*/Presentation` | 各功能的原生 WPF 页面、XAML、窗口和输入反馈 |
| `src/OutdoorGear.Wpf/Features/Weather/Presentation` | 周/月远期天气曲线、趋势明细与可选要素展示 |
| `src/OutdoorGear.Wpf/Features/Shared/Presentation` | 跨模块复用的轻量展示辅助组件 |
| `src/OutdoorGear.Wpf/ViewModels` | 页面协调、活动资料库状态及保存入口 |
| `src/OutdoorGear.Wpf/Resources` | 路线数据、署名、离线模型运行资源 |
| `tests/OutdoorGear.Regression` | 真实 schema 9 种子和本地文件服务的自动回归 |

## 依赖方向

```text
WPF 输入 → ViewModel / 功能用例 → Core 规则 → 资料库仓储
                                      ├→ 本地文件与备份
                                      └→ 明确抽象的网络/平台能力
```

- Core 不引用 WPF、控件、系统文件选择器或消息框。用户输入与确认由 Presentation 负责，页面只协调规则执行和结果显示。
- 业务计算与本机/网络 I/O 分开；数据写入沿用统一资料库保存入口，并保留备份与失败回滚语义。
- JSON 键、默认值、日期格式、单位、排序及未知字段保留均属兼容行为。迁移数据中的用户资料只作为首次初始化模板，不覆盖现有目录。
- 普通方法控制在 30 行以内，按职责拆分；不同功能不合并到通用“万能”窗口或文件。新增逻辑先归入所属功能目录。
- WPF 页面按功能模块存放；XAML 与代码后置同目录、同命名空间，避免把不同功能重新聚合到共享 `Views` 文件夹。
- 每项业务改动都补充行为级回归。Windows 窗口、摄像头/OCR、文件锁、升级与重启仍须在 Windows 设备验收；交叉编译成功不代表这些验收已通过。

## 当前照片管线

Photos 功能使用本地 U²-Net ONNX 模型和 SkiaSharp，断网可完成 1024×1024 PNG 输出、白底分割、主体定位/留白和柔和阴影。输入只读，处理结果生成独立文件；照片原图以 `修图原图` 附件保留，兼容旧版存放在 Photos 目录的记录。模型与许可证随安装包一同部署。
