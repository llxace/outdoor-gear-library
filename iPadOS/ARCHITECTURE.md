# 户外装备库 iPadOS：模块与重构约定

本项目以 macOS 0.20.0 重构版为功能与数据行为基线，针对 iPadOS 17 使用原生 SwiftUI、UIKit、MapKit、Vision、AVFoundation 和系统文件面板重新实现界面及设备能力。iPad 使用独立应用沙盒；不得直接读写 Mac 资料目录。模块目前位于一个 Xcode target 中，并非独立 Swift Package。

## 模块职责

| 模块 | 职责 |
| --- | --- |
| `App` | 应用入口、iPad 侧边栏、导航和工作区 |
| `Core` | Inventory、领域校验、v9 数据迁移、统一保存与完整备份 |
| `Features/Gear` | 装备档案、分类、筛选、附件、复制、批量操作和回收站 |
| `Features/Packing` | 打包、库存约束、借用、行程及重量价值汇总 |
| `Features/Routes`、`Weather` | 路线目录和搜索、GPX/KML、地图、海拔、天气及远期趋势 |
| `Features/Meals` | 食物、配餐、热量、饮水、采购清单、包装 OCR 和相机 |
| `Features/History` | 徒步记录、路线天气和装备快照 |
| `Features/Photos` | 装备照片、白底/阴影处理、原图恢复及附件 |
| `Features/Profiles` | 多本地用户资料、头像、切换和跨用户复制 |
| `Features/ImportExport` | Excel 字段映射、CSV/TSV、完整备份和附件迁移 |
| `Features/Settings`、`Dashboard` | 设置、总览与统计 |
| `Shared` | 共享样式、系统文件对话框和跨模块 UI 组件 |

每个功能按实际需要使用 `Domain`、`Business`、`Application`、`Data`、`Presentation` 分层，不为目录齐全而增加空层：Domain 保存实体和值；Business 实现规则并声明外部能力协议；Application 协调用例和统一保存入口；Data 实现文件、JSON、网络、Excel、图片及相机访问；Presentation 负责 SwiftUI、页面状态和 iPad 系统界面。Domain/Business 不依赖 SwiftUI、UIKit、文件或网络。

## 功能对齐基线

| macOS 功能 | iPad 原生入口 |
| --- | --- |
| 仪表盘、统计与收藏 | 侧边栏「仪表盘」 |
| 装备详情、搜索、分类、照片附件、批量和回收站 | 「装备库」与详情页 |
| 打包、同行借用、路线、天气和海拔 | 「打包」工作区 |
| 徒步记录、筛选和装备快照 | 「个人专栏」 |
| 路餐、热量目标、饮水、OCR 和采购清单 | 打包工作区内「路餐与饮水」 |
| 多用户、主题、货币、库设置与整理工具 | 「设置」 |
| Excel/CSV/TSV 与完整备份 | 工具栏「资料迁移」及设置页 |

平台差异只允许出现在视图布局、系统能力适配、文件选择和相机/图片实现中。复用 macOS 的业务规则时，应保持结果相同；适配过程中不得删减功能入口或静默改变数据语义。

## 修改与兼容规则

1. 在所属功能目录修改，避免把业务堆入通用 Store、Models 或 Views。
2. 普通函数和初始化方法不超过 30 行；按职责提取，不通过压缩语句规避限制。检查包含声明和括号，不计前后空白。
3. SwiftUI `body`、视图片段和模型计算属性独立评审；复杂页面抽出有意义的命名视图片段或子视图。
4. JSON 字段、默认值、单位、舍入、排序、错误文本和保存时机均为兼容行为。修改需单独记录及说明。
5. `GearStore` 保持统一可观察状态和保存入口；写入成功后才更新公开 Inventory。业务规则先产出领域结果，再交由统一保存。
6. 新文件必须纳入 Xcode 项目和 `OutdoorGearPad` target membership。不要把 Mac 桌面系统面板直接复用为 iPad 页面。
7. 所有主要工作区和弹窗需适配 iPad 分屏宽度及横竖屏；不以 macOS 固定窗口最小宽高约束 iPad 内容。

## 验收与检查

- `python3 tools/check_structure.py`：普通函数和初始化方法行数。
- Xcode `OutdoorGearPad` scheme：iPad 模拟器构建。
- 模拟器验收：横竖屏主工作区、侧边栏入口、装备详情与编辑、路线搜索/导入/地图、路餐、历史、设置和资料迁移弹窗。
- 数据行为核对：以 macOS 重构版的 v9 JSON、计算结果和导入导出语义为参照；不得覆盖其他设备或用户的本地资料。
