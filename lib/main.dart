import 'package:flutter/material.dart';
import 'screens/main_shell.dart';
import 'theme/app_theme.dart';

void main() {
  runApp(const HelloTalkCloneApp());
}

class HelloTalkCloneApp extends StatelessWidget {
  const HelloTalkCloneApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'HelloTalk Clone UI',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      themeMode: ThemeMode.light,
      home: const MainShell(),
    );
  }
}
