# 户外装备库：模块与分层

本次从 0.19.9 (63) 整理为 0.20.0 (64)。保持现有界面、数据版本 9、资料目录和备份格式；尚未替换已安装 App。天气缺失值、借用损坏状态及修图原图备份作为验收发现的缺陷另行修复，详见验收记录。

## 目录导航

| 模块 | 负责内容 |
| --- | --- |
| `App` | 应用入口、窗口、菜单与主导航 |
| `Core` | Inventory 聚合、数据校验、迁移、保存与备份事务 |
| `Features/Gear` | 装备录入、分类、筛选、详情、标签与历史模板兼容 |
| `Features/Packing` | 装包数量、库存约束、借用装备与行前信息 |
| `Features/Meals` | 食品、热量、配餐、包装文字识别与相机 |
| `Features/History` | 徒步记录与当次装备快照 |
| `Features/Routes` | 路线搜索、轨迹导入、路线地图与海拔 |
| `Features/Weather` | 逐日天气、小时天气、远期趋势 |
| `Features/Profiles` | 本机用户切换、资料与头像、跨用户草稿附件复制 |
| `Features/ImportExport` | Excel、CSV、文件选择及导入确认 |
| `Features/Photos` | 产品照片处理与还原 |
| `Features/Settings` | 外观、设置与汇率 |
| `Features/Dashboard` | 总览与统计显示 |
| `Shared` | 复用界面组件、设计常量、文件及 HTTP 基础操作 |

功能模块按实际需要包含下列目录，不要求每个功能凑齐所有层：

- **Domain**：实体、值和与实体直接相关的派生属性；不读写文件、不调用网络、不引用 SwiftUI/AppKit。
- **Business**：计算、校验、修改规则及外部能力协议；输入输出是领域值。例如 `PackingOperations`、`GearOperations`、`FoodLabelParsing`。
- **Application**：用例协调，将业务结果交给统一保存入口，维护错误与提示；不弹出系统文件选择器。
- **Data**：JSON、文件、网络、XML/Excel、相机等外部能力的具体实现。
- **Presentation**：SwiftUI 视图、页面状态、系统面板、地图与图片显示适配。复杂异步流程由页面模型协调。

## 一次修改如何流动

```text
页面操作 → Application / 页面状态模型 → Business 规则 → 领域结果
                                              ↓
                                     GearStore.commit
                                              ↓
                                 InventoryRepository 协议
                                              ↓
                                  JSONInventoryRepository
```

`GearStore` 保留为统一可观察状态和保存入口；各功能通过所在模块的 extension 组织方法。写入成功后才替换公开的 inventory。恢复备份、导入 Excel 和跨用户附件复制分别保留原来的失败处理及备份时机。

网络页面通过 `RouteSearching`、`TripConditionsProviding` 协议取数。生产实现位于 Data，页面绑定与加载状态位于 Presentation。以后更换路线服务时，从协议和实现着手，不在视图里拼请求。

目前是**单一 Xcode target 下的逻辑模块**，并非独立 Swift Package，编译器尚不强制跨模块访问限制。保留单 target 可减少这个个人工具的构建维护成本；跨文件所需符号使用 internal，文件内助手保持 private。

## 维护规则

1. 新功能先找到所属业务模块，避免继续往通用 Store、Models 或 Views 文件堆代码。
2. 普通函数和初始化方法按 30 行上限整理；优先以职责拆分，不把多条语句压成一行。统计包含声明和括号，不计前后空白。
3. SwiftUI 的 `body`、视图片段和模型计算属性单独评审，不纳入普通函数行数统计；复杂页面提取命名片段或独立子视图。
4. JSON 字段名、默认值、单位、舍入、排序、错误提示和写入时机均属于兼容行为。修改这些内容时需要单独说明。
5. 不在 Domain/Business 加入文件、网络或平台界面调用。新外部服务需要替换实现时才引入协议。
6. 单个功能的改动优先局限于该功能目录。不要为了文件数量少把不同职责重新合并，也不要为了函数短建立没有意义的转发层。
7. 新增 Swift 文件后，在 Xcode 对应物理分组中添加并确认 OutdoorGear target membership。`work/refactor/project.py` 是本次迁移工具，依赖原始快照，不作为日常工程生成器。

## 构建与已有检查入口

在项目目录执行：

```sh
xcodebuild -project 户外装备库.xcodeproj -scheme OutdoorGear \
  -configuration Debug -derivedDataPath work/refactor/Build \
  CODE_SIGNING_ALLOWED=NO build
```

`Tests/` 的每个文件是独立的 `@main` 检查入口，不加入 App target。原有三个入口保留原内容，新增业务、异步流程、天气、借用生命周期及照片管线回归检查。使用 `python3 tools/run_checks.py` 运行；可指定入口名称，仅运行相关检查。Excel 入口依赖指定本地工作簿。使用 `python3 tools/check_structure.py` 检查生产函数长度。

## 本次交付边界

- 原始源码快照：同级 `RefactorBaseline-20261008-210200/`。
- 本次主要改动：物理目录及 Xcode 分组、业务规则与存储拆分、页面异步状态抽取、长方法拆分、统一格式。
- 未修改资源、已有检查入口和实际用户资料；具体静态核对结果见 `Docs/RefactorStatus.md`。
- 八组自动检查通过，完成部分实际页面验收。原生界面控制连接中断，剩余界面项目见 `Docs/RefactorStatus.md`；尚未替换已安装 App。
