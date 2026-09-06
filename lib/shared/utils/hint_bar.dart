import 'package:flutter/material.dart';

/// 手动关闭式提示（SnackBar）的统一工具
///
/// 项目惯例：错误/引导提示不自动消失（超长 duration + 「知道了」按钮），
/// 避免玩家漏看。此前该逻辑在四个游戏页各内联一份，此处收敛为唯一实现，
/// 「messenger 生命周期」的经验注释也只在此维护一份。
///
/// 注意：SnackBar 挂在应用级 ScaffoldMessenger 上，不随页面销毁——
/// 退出页面前必须调用 [exitPageClean] 清理，否则提示会残留到下一页。
/// 工具函数无法感知调用方的 mounted 状态，异步回调场景由调用方自行检查。

/// 展示不自动消失的提示（需点「知道了」手动关闭）
///
/// 捕获 messenger state 而非在回调里依赖页面 context：
/// 提示可能比页面存活更久，引用已销毁 context 会导致「知道了」失效
void showPersistentHint(BuildContext context, String message) {
  final messenger = ScaffoldMessenger.of(context);
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(days: 1),
        behavior: SnackBarBehavior.floating,
        action: SnackBarAction(
          label: '知道了',
          onPressed: () => messenger.hideCurrentSnackBar(),
        ),
      ),
    );
}

/// 隐藏当前提示（合法操作生效后清除遗留的错误提示，避免信息干扰）
void hideHint(BuildContext context) {
  ScaffoldMessenger.of(context).hideCurrentSnackBar();
}

/// 立即移除当前提示（无退出动画）
///
/// 用于离开页面前的清理：必须 remove 而非 hide——页面销毁后提示的
/// 「知道了」回调引用已失效，将无法关闭；当前无提示时为无害空操作
void clearHint(BuildContext context) {
  ScaffoldMessenger.of(context).removeCurrentSnackBar();
}

/// 清理残留提示并退出当前页面
///
/// 先弹掉页面之上的全部弹窗覆盖层再退出页面，不能只 pop 一次：
/// 本端确认弹窗/提示弹窗开着时对局可能被对端终止（联机终局弹窗会
/// 压在其上），单次 pop 只弹掉栈顶弹窗，表现为「点了返回/退出
/// 却停留在对局页」。被弹掉的弹窗其 await 以 null 完成，调用方
/// 按未确认处理（有 mounted/result 判断，不会误执行确认分支）。
/// 页面自身即栈顶时行为与单次 pop 等价
void exitPageClean(BuildContext context) {
  final pageRoute = ModalRoute.of(context);
  if (pageRoute != null) {
    Navigator.of(context).popUntil((route) => route == pageRoute);
  }
  clearHint(context);
  Navigator.of(context).pop();
}
