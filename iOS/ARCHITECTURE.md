# iPhone 版模块边界

iPhone 版按 0.20.4 数据结构和功能目录组织。Xcode 保持单 target；目录表达职责边界，避免为了拆分而引入额外 Package 维护成本。

| 目录 | 职责 |
| --- | --- |
| `Sources/App` | 应用入口、标签导航、动态森林色板 |
| `Sources/Core/Domain` | 装备、打包条目等基础值 |
| `Sources/Core/Application` | 可观察库存状态、派生数据与写入协调 |
| `Sources/Core/Data` | 本机 JSON 仓储协议及文件实现 |
| `Sources/Features/Gear` | 装备列表、编辑、软删除及装备写入规则 |
| `Sources/Features/Packing` | 库存校验、数量与价值统计、借用条目和装包页面 |
| `Sources/Features/Routes` | 路线目录、路线地图以及天气服务和页面状态 |
| `Sources/Features/History` | 徒步记录列表与历史装备快照查看 |
| `Sources/Features/Photos` | 装备照片文件保存 |
| `Sources/Features/Settings` | 本机资料库名称、所有者及外观选项 |
| `Sources/Features/ImportExport` | JSON/ZIP 备份、附件迁移及文件交互 |
| `Sources/Shared` | 多功能共同使用的玻璃卡片外观 |

## 数据流

- 页面只通过 `GearLibrary` 发起本机业务操作；打包校验放在 `PackingOperations`，文件写入放在 `InventoryRepository`。
- `GearLibrary` 保存原始 JSON 字典，装备编辑和数量修改只改对应字段，尽量保留 iPhone 当前未展示的 Mac 字段。
- 外部天气由 `TripWeatherProviding` 抽象，网络请求实现与页面状态分开。
- JSON 导入会整体替换本机资料，因此 UI 会先显示确认；完整 ZIP 导入先校验路径、CRC 与库存 JSON，再复制附件并替换资料。ZIP 备份使用无压缩条目，避免引入运行时依赖。
- GPX/KML 解析、路线在线搜索/轨迹下载和天气请求各自位于 Routes 的数据服务；页面通过动作对象和服务协议触发，避免将解析与网络逻辑塞进视图。

## 当前移植进度

已覆盖：概览、装备基础资料编辑与照片选择、软删除/回收站、打包数量/库存约束/重量/价值、从另一份 JSON 装备库挑选同行装备、路线目录和在线搜索、GPX/KML 轨迹导入、路线地图、出发时间和最长 16 日天气、徒步记录及当次装备查看、本机外观设置、JSON 导入导出及含附件的完整 ZIP 备份恢复。

仍未完成 0.20.4 的功能：完整逐小时天气与海拔图、餐食计划及食品识别、多用户资料库切换和跨用户附件复制、历史记录编辑、白底产品照片处理、Excel/CSV 迁移。目录索引中的路线只包含轻量元数据；导入的 GPX/KML 和在线搜索路线会保留完整轨迹。
