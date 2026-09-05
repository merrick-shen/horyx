import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// 横屏沉浸模式生命周期 mixin（挂接在页面 State 上）：
/// 统一「横屏 + immersiveSticky / 竖屏 + edgeToEdge」的系统 UI 切换
/// （坦克本地/联机对局页与计分器计分阶段共用）。
/// 用法约定：
/// - 进入横屏的时机由页面决定（initState 或阶段切换/恢复存档），
///   显式调用 [enterLandscapeImmersive]；
/// - 「先还原再 pop」的退出路径（系统旋转与转场动画并行执行，退出无延迟）
///   在 pop 前显式调用 [restorePortrait]；
/// - dispose 自动还原兜底：覆盖未经页面退出流程的 pop 路径
///   （如系统返回直接弹出），防止横屏锁定/沉浸式泄漏到其他页面。
/// 非泛型裸 `on State` 会固化为 `State<StatefulWidget>`，与页面实际
/// 的 `State<页面类型>` 产生泛型接口冲突，故引入类型参数（由页面推断，
/// 无法推断时显式传入）
mixin LandscapeImmersiveMixin<T extends StatefulWidget> on State<T> {
  /// 进入横屏 + 沉浸式（隐藏状态栏/导航栏）
  void enterLandscapeImmersive() {
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  /// 还原竖屏与边到边系统 UI
  void restorePortrait() {
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  }

  @override
  void dispose() {
    // 还原兜底：正常退出路径已在 pop 前调用 restorePortrait，此处兜住
    // 其余 pop 路径（调用顺序与「先还原再 pop」的显式还原重复，无副作用）
    restorePortrait();
    super.dispose();
  }
}
