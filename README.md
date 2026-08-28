# Horyx

## 技术栈

- [Flutter](https://flutter.dev)（Dart）+ Material 3
- 状态管理：页面级 State 集中持有（无额外状态管理框架）
- 游戏规则：各游戏独立规则引擎（纯静态逻辑，本地与联机共用同源判定）
- 局域网联机：dart:io TCP（NDJSON 分帧协议、房主权威模型，零第三方网络依赖）
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
│   ├── network/            # 联机层（NDJSON 协议分帧、TCP 会话、房主/客户端、房间等待页与联机加入）
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

### 常用命令

```bash
flutter pub get                  # 安装依赖
flutter run                      # 运行（debug 模式，连接设备）
flutter analyze                  # 静态分析
flutter test                     # 运行单元测试
dart run flutter_launcher_icons  # 重新生成应用图标（修改源图后执行）
flutter build apk --release      # 构建 release 包
```
