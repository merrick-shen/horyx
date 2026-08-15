import 'package:flutter/material.dart';

import 'pages/app_shell.dart';
import 'services/word_validator.dart';
import 'theme/app_theme.dart';

/// 应用入口
Future<void> main() async {
  // 词表加载依赖 rootBundle，需先初始化绑定
  WidgetsFlutterBinding.ensureInitialized();
  await WordValidator.load();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Horyx',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      home: const AppShell(),
    );
  }
}
