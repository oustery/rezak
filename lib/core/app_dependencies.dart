import 'dart:io';

import 'package:flutter/widgets.dart';

import '../services/download_service.dart';
import '../services/players_api.dart';
import '../state/app_state.dart';
import '../ui/player_web_view.dart';

/// Точка сборки зависимостей.
///
/// Всё, что ходит в сеть или на диск, передаётся сюда — поэтому экраны
/// и сервисы тестируются без реальных HTTP-запросов и без ffmpeg.
class AppDependencies {
  AppDependencies({
    PlayersRepository? playersApi,
    DownloadEngine? downloadService,
    AppState? appState,
    this.outputDirProvider,
    this.webView,
  })  : playersApi = playersApi ?? PlayersApi(),
        downloadService = downloadService ?? DownloadService(),
        appState = appState ?? AppState.instance;

  final PlayersRepository playersApi;
  final DownloadEngine downloadService;
  final AppState appState;

  /// Куда писать готовые файлы. В тестах подменяется временной папкой.
  final Future<Directory> Function()? outputDirProvider;

  /// Подмена WebView: в тестах вместо нативного InAppWebView.
  final PlayerWebView? webView;

  Future<Directory> resolveOutputDir() async {
    final custom = outputDirProvider;
    if (custom != null) return custom();
    return downloadService.outputDir();
  }

  static AppDependencies of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AppScope>();
    assert(scope != null, 'AppScope не найден в дереве виджетов');
    return scope!.dependencies;
  }
}

/// InheritedWidget-обёртка, раздающая [AppDependencies] вниз по дереву.
class AppScope extends InheritedWidget {
  const AppScope({
    super.key,
    required this.dependencies,
    required super.child,
  });

  final AppDependencies dependencies;

  @override
  bool updateShouldNotify(AppScope oldWidget) =>
      oldWidget.dependencies != dependencies;
}
