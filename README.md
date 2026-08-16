# Horyx

游戏合集，随时开局的掌上游戏厅。基于 Flutter 构建的 Android 应用。

## 功能特性

- **单词PK**：多人轮流拼写单词对战，支持自定义人数与回合顺序，本地万词表校验
- **五子棋**：双人对战，点选落子、确认与悔棋，自动判定五连胜负
- **围棋**：支持 9/13/19 路规格，内置提子、打劫（禁全同）、终局数子（中国规则）完整规则
- **计分器**：自定义局数与场分的比分记录工具，支持撤销误操作
- **对局存档**：各游戏中途保存退出后可继续上次对局，存档管理页集中查看与删除
- **主题定制**：深浅色模式与主题色选择（预设色板、自定义颜色），偏好自动保存

## 技术栈

- [Flutter](https://flutter.dev)（Dart）+ Material 3
- 状态管理：页面级 State 集中持有（无额外状态管理框架）
- 持久化：SharedPreferences 单键 JSON 原子写入，读取容错，模型带 version 字段备迁移
- SVG 渲染：flutter_svg（关于页 Logo 动态着色）
- 应用图标：flutter_launcher_icons（源图见 `assets/icon/`，配置位于 pubspec.yaml）

## 项目结构

```
lib/
├── main.dart               # 应用入口：预加载词表、恢复主题
├── data/                   # 静态数据源（游戏列表）
├── models/                 # 数据模型与存档模型（含序列化）
├── pages/                  # 页面层（骨架、各游戏页、设置、关于等）
├── services/               # 业务逻辑（规则引擎、校验、存档读写）
├── theme/                  # 主题系统（调色板、控制器、持久化）
└── widgets/                # 复用组件（顶栏、棋盘、选项块、弹窗等）
test/                       # 单元测试（存档服务、单词校验）
assets/
├── icon/                   # Logo 源文件与图标生成源图
└── words/                  # 单词PK 本地词表（google-10000）
```

## 开发指南

### 环境要求

- Flutter SDK（Dart ^3.13.0）
- Android 设备或模拟器

### 常用命令

```bash
flutter pub get                  # 安装依赖
flutter run                      # 运行（debug 模式，连接设备）
flutter analyze                  # 静态分析
flutter test                     # 运行单元测试
flutter pub run flutter_launcher_icons   # 重新生成应用图标（修改源图后执行）
flutter build apk --release      # 构建 release 包
```

### 约定

- **变更记录**：用户可感知的变化需更新 [CHANGELOG.md](CHANGELOG.md)，遵循 Keep a Changelog 1.1.0 规范与语义化版本
- **提交信息**：`type: 中文描述`，type 取值 `feat / ui / fix / refactor / init / style / docs / chore / perf / release / test / build / ci / revert`
- **UI 规范**：统一使用品牌纯色（默认 #7C5CFF），图标使用 Material Icons
