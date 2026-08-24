# Horyx

游戏合集，随时开局的掌上游戏厅。基于 Flutter 构建的 Android 应用。

## 功能特性

- **单词PK**：多人轮流拼写单词对战，支持自定义人数与回合顺序，本地万词表校验
- **五子棋**：双人对战，点选落子、确认与悔棋，自动判定五连胜负
- **计分器**：自定义 BO 赛制、每局胜利比分与领先规则（支持乒乓球式平分延长）的比分记录工具，支持撤销误操作
- **局域网联机**：同一 Wi-Fi 下自动发现房间，单词PK 多人轮流拼写、五子棋远程对战（落子实时同步、悔棋协商、认输），全程无需服务器
- **对局存档**：各游戏中途保存退出后可继续上次对局，存档管理页集中查看与删除
- **主题定制**：深浅色模式与主题色选择（预设色板、自定义颜色），偏好自动保存

## 技术栈

- [Flutter](https://flutter.dev)（Dart）+ Material 3
- 状态管理：页面级 State 集中持有（无额外状态管理框架）
- 游戏规则：各游戏独立规则引擎（纯静态逻辑，本地与联机共用同源判定）
- 局域网联机：dart:io TCP + UDP（NDJSON 分帧协议、房主权威模型、UDP 房间广播发现，零第三方网络依赖）
- 持久化：SharedPreferences 单键 JSON 原子写入，读取容错，模型带 version 字段备迁移
- SVG 渲染：flutter_svg（关于页 Logo 动态着色）
- 应用图标：flutter_launcher_icons（源图见 `assets/icon/`，配置位于 pubspec.yaml）

## 项目结构

按 feature-first 组织：一个游戏一个目录（pages / services / models / widgets），跨游戏复用的设施集中在 shared/，应用级页面在 app/。

```
lib/
├── main.dart               # 应用入口：预加载词表、恢复主题（含启动异常兜底）
├── app/                    # 应用层
│   ├── app_shell.dart      # 底部导航壳（首页/联机/更多，PageView 保活）
│   ├── pages/              # 应用级页面（主页、更多、设置：主题/存档管理/关于/更新日志）
│   └── widgets/            # 主页组件（游戏卡片、游戏网格）
├── games/                  # 游戏层（一游戏一目录，内分 pages/services/models/widgets）
│   ├── word_pk/            # 单词PK（页面、联机对局控制器、词表校验、存档）
│   ├── gomoku/             # 五子棋（规则引擎、联机对局控制器、存档）
│   ├── weiqi/              # 围棋（已下架待升级，代码保留）
│   └── scoreboard/         # 计分器（BO 赛制规则引擎、存档）
├── shared/                 # 共享层
│   ├── game/               # 游戏注册中心（统一游戏元数据与路由）
│   ├── network/            # 联机层（NDJSON 协议分帧、TCP 会话、房主/客户端/UDP 发现、房间列表与等待页）
│   ├── storage/            # 存档读写泛型基类、主题持久化
│   ├── theme/              # 主题系统（调色板、控制器）
│   ├── utils/              # 通用工具（页面提示条）
│   └── widgets/            # 通用组件（顶栏、对话框、设置项、面板、续玩卡片等）
test/                       # 单元与集成测试（按 games/、shared/ 与 lib 同构组织）
assets/
├── icon/                   # Logo 源文件与图标生成源图
└── words/                  # 单词PK 本地词表（google-10000）
```

## 开发指南

### 环境要求

- Flutter SDK（Dart ^3.13.0）
- Android 设备或模拟器；联机调试需双端（两台设备连同一 Wi-Fi，或 Android + Windows 桌面端 `flutter run -d windows`）
- 联机不通时优先排查路由器「AP 隔离」（同网络设备间禁止互访会导致 UDP/TCP 均失败）

### 常用命令

```bash
flutter pub get                  # 安装依赖
flutter run                      # 运行（debug 模式，连接设备）
flutter analyze                  # 静态分析
flutter test                     # 运行单元测试
dart run flutter_launcher_icons  # 重新生成应用图标（修改源图后执行）
flutter build apk --release      # 构建 release 包
```

### 约定

- **变更记录**：用户可感知的变化需更新 [CHANGELOG.md](CHANGELOG.md)，遵循 Keep a Changelog 1.1.0 规范与语义化版本
- **提交信息**：`type: 中文描述`，type 取值 `feat / ui / fix / refactor / init / style / docs / chore / perf / release / test / build / ci / revert`
- **UI 规范**：图标使用 Material Icons
- **导入规范**：统一使用 package 绝对导入（`package:horyx/...`），不使用相对导入
