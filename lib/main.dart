import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';

import 'app.dart';

/// 入口：仅做初始化 + runApp（设计文档 §2；平台分支只允许出现在本文件与 platform/）。
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  runApp(const ProviderScope(child: AiwliApp()));
}
