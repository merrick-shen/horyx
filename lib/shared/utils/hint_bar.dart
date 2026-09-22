import 'package:flutter/material.dart';

/// 退出页面前清理覆盖层的统一工具
///
/// 「先弹掉页面之上的弹窗覆盖层、再退出页面」的约定单点收敛于此。
/// 提示类 UI 已统一走模态 showAlertDialog，SnackBar 提示机制已移除。

/// 清理残留覆盖层并退出当前页面
///
/// 先弹掉页面之上的全部弹窗覆盖层再退出页面，不能只 pop 一次：
/// 本端确认弹窗开着时对局可能被对端终止（联机终局弹窗会
/// 压在其上），单次 pop 只弹掉栈顶弹窗，表现为「点了返回/退出
/// 却停留在对局页」。被弹掉的弹窗其 await 以 null 完成，调用方
/// 按未确认处理（有 mounted/result 判断，不会误执行确认分支）。
/// 页面自身即栈顶时行为与单次 pop 等价
void exitPageClean(BuildContext context) {
  final pageRoute = ModalRoute.of(context);
  if (pageRoute != null) {
    Navigator.of(context).popUntil((route) => route == pageRoute);
  }
  Navigator.of(context).pop();
}
