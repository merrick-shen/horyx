# Horyx

## 技术栈

- [Flutter](https://flutter.dev)（Dart）+ Material 3
- 状态管理：页面级 State 集中持有（无额外状态管理框架）
- 游戏规则：各游戏独立规则引擎（纯静态逻辑，本地与联机共用同源判定）
- 游戏引擎：Flame（坦克动荡实时战场：迷宫、坦克、子弹的循环与渲染）
- 音效：flutter_soloud（Soloud 引擎，预解码进内存的低延迟游戏音效）
- 局域网联机：dart:io TCP（NDJSON 分帧协议、房主权威模型，零第三方网络依赖）
- 持久化：SharedPreferences 单键 JSON 原子写入，读取容错，模型带 version 字段备迁移
- SVG 渲染：flutter_svg（关于页 Logo 动态着色）
- 版本信息：package_info_plus（关于页读取并展示应用版本号）
- 应用图标：flutter_launcher_icons（源图见 `assets/icon/`，配置位于 pubspec.yaml）

## 项目结构

按 feature-first 组织：一个游戏一个目录（pages / services / models / widgets），跨游戏复用的设施集中在 shared/，应用级页面在 app/。

```
lib/
├── main.dart               # 应用入口：恢复主题（含启动异常兜底）
├── app/                    # 应用层
│   ├── app_shell.dart      # 底部导航壳（首页/联机/更多，PageView 保活；挂载时预热单词PK词表）
│   ├── game_data.dart      # 游戏注册中心（全部游戏元数据与路由的组合根）
│   ├── pages/              # 应用级页面（主页、更多）
│   │   └── settings/       # 设置页（主题/存档管理/关于/更新日志）
│   └── widgets/            # 主页组件（游戏卡片、游戏网格）
├── games/                  # 游戏层（一游戏一目录，内分 pages/services/models/widgets）
│   ├── word_pk/            # 单词PK（页面、联机对局控制器、词表校验、存档）
│   ├── gomoku/             # 五子棋（规则引擎、联机对局控制器、存档）
│   ├── tank/               # 坦克动荡（Flame 战场：随机迷宫、原版摇杆驾驶、坦克与子弹碰撞、回合计分；内分 engine/ 实体逻辑、特效与音效；联机为房主权威快照广播 + 客户端影子战场）
│   ├── chess/              # 中国象棋（CustomPainter 绘制棋盘与棋子、规则引擎、联机对局控制器、存档）
│   └── scoreboard/         # 计分器（BO 赛制规则引擎、存档）
├── shared/                 # 共享层
│   ├── game/               # 游戏元数据模型（GameInfo，注册组合根位于 app/game_data.dart）
│   ├── network/            # 联机层（NDJSON 协议分帧、TCP 会话、房主/客户端、对局控制器基类）
│   ├── pages/              # 联机通用页面（房间等待页、局域网加入房间页）
│   ├── storage/            # 存档读写泛型基类、主题持久化
│   ├── theme/              # 主题系统（调色板、控制器）
│   ├── utils/              # 通用工具（页面提示条、资产图片解码缓存、横屏沉浸式 mixin）
│   └── widgets/            # 通用组件（顶栏、对话框、设置项、面板、续玩卡片等）
test/                       # 单元与集成测试（按 games/、shared/ 与 lib 同构组织）
assets/
├── icon/                   # Logo 源文件与图标生成源图
├── tank/                   # 坦克动荡白模素材（提取自原版 APK 图集，运行时按玩家色染色）
│   └── audio/              # 坦克动荡音效（OGG，提取自原版 APK 音频）
└── words/                  # 单词PK 本地词表（约 37 万词）
```

## 开发指南

### 环境要求

- Flutter SDK（Dart ^3.13.0）

### 常用命令

```bash
flutter pub get                  # 安装依赖
flutter run                      # 运行（debug 模式，连接设备）
flutter analyze                  # 静态分析
flutter test                     # 运行单元测试
dart run flutter_launcher_icons  # 重新生成应用图标（修改源图后执行）
flutter build apk --release      # 构建 release 包
```
