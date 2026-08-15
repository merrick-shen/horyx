import 'package:flutter_test/flutter_test.dart';

import 'package:horyx/main.dart';

void main() {
  testWidgets('主页静态 UI 冒烟测试', (tester) async {
    await tester.pumpWidget(const MyApp());

    // 导航栏与页脚均展示品牌名
    expect(find.text('Horyx'), findsWidgets);
    // 游戏列表已渲染出占位卡片
    expect(find.text('开发中'), findsWidgets);
    // 底部导航栏包含首页与设置入口
    expect(find.text('首页'), findsOneWidget);
    expect(find.text('设置'), findsOneWidget);
  });
}
