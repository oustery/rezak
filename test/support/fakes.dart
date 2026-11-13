import 'dart:async';
import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:rezak/core/app_dependencies.dart';
import 'package:rezak/models/player_source.dart';
import 'package:rezak/services/download_service.dart';
import 'package:rezak/services/players_api.dart';
import 'package:rezak/state/app_state.dart';
import 'package:rezak/ui/player_web_view.dart';

/// API-заглушка: не ходит в сеть, отдаёт заранее заданные плееры.
class FakePlayersRepository implements PlayersRepository {
  FakePlayersRepository({List<PlayerSource>? players, this.error, this.gate})
      : players = players ??
            const [
              PlayerSource(
                type: 'Turbo',
                iframeUrl: 'https://turbo.example/embed/1',
                translations: [],
              ),
              PlayerSource(
                type: 'Alloha',
                iframeUrl: 'https://alloha.example/?token=abc',
                translations: [
                  Translation(
                    name: 'Русский',
                    quality: 'WEBRip',
                    iframeUrl: 'https://alloha.example/?translation=82',
                  ),
                  Translation(
                    name: 'Оригинал',
                    quality: 'WEB-DL',
                    iframeUrl: 'https://alloha.example/?translation=209',
                  ),
                ],
              ),
            ];

  final List<PlayerSource> players;
  final Object? error;
  final List<String> requestedIds = [];

  /// Если задано, ответ ждёт [Completer] — так тест видит состояние «идёт поиск».
  final Completer<void>? gate;

  @override
  Future<List<PlayerSource>> fetchByKinopoiskId(String kinopoiskId) async {
    requestedIds.add(kinopoiskId);
    final gate = this.gate;
    if (gate != null) await gate.future;
    if (error != null) throw error!;
    return players;
  }
}

/// Движок загрузки-заглушка: пишет файл на диск и «отдаёт» готовую задачу.
class FakeDownloadEngine implements DownloadEngine {
  FakeDownloadEngine({
    required this.dir,
    this.fail = false,
    this.probeOutput = 'audio,aac\nvideo,h264',
    this.onStart,
  });

  final Directory dir;
  final bool fail;
  final String probeOutput;
  final void Function(DownloadJob job)? onStart;

  final List<List<String>> builtArguments = [];
  final List<DownloadJob> started = [];
  final List<String> probed = [];
  final List<DownloadJob> cancelled = [];

  @override
  Future<Directory> outputDir() async => dir;

  @override
  List<String> buildFfmpegArguments({
    required String url,
    required String outputPath,
    String? audioUrl,
  }) {
    final args = ['-i', url];
    if (audioUrl != null) args.addAll(['-i', audioUrl, '-map', '1:a:0?']);
    args.addAll(['-map', '0:v:0?', '-c', 'copy', outputPath]);
    builtArguments.add(args);
    return args;
  }

  @override
  Future<DownloadJob> start({
    required String url,
    required String fileName,
    String? audioUrl,
    String? title,
    void Function(DownloadJob job)? onUpdate,
  }) async {
    final job = DownloadJob(
      url: url,
      audioUrl: audioUrl,
      title: title,
      outputPath: '${dir.path}/$fileName',
      status: DownloadStatus.running,
    );
    started.add(job);
    onUpdate?.call(job);
    onStart?.call(job);

    if (fail) {
      final failed = job.copyWith(
        status: DownloadStatus.failed,
        log: 'boom: HTTP 403',
      );
      onUpdate?.call(failed);
      return failed;
    }

    File(job.outputPath).writeAsBytesSync(List<int>.filled(2048, 0));
    final done = job.copyWith(status: DownloadStatus.done, progress: 1);
    onUpdate?.call(done);
    return done;
  }

  @override
  Future<String> probeAudio(String path) async {
    probed.add(path);
    return probeOutput;
  }

  @override
  List<String> buildProbeArguments(String path) => [
        '-hide_banner',
        '-i',
        path,
        '-show_entries',
        'stream=codec_type,codec_name',
        '-of',
        'csv=p=0',
      ];

  @override
  Future<bool> cancel(DownloadJob job) async {
    cancelled.add(job);
    return true;
  }
}

/// WebView-заглушка: рисовать ничего не нужно, тест сам «эмулирует» сеть,
/// вызывая [emitResource].
class FakePlayerWebView implements PlayerWebView {
  FakePlayerWebView();

  ValueChanged<String>? _onResource;
  VoidCallback? _onLoadStart;
  VoidCallback? _onLoadStop;

  void emitResource(String url) => _onResource?.call(url);
  void finishLoading() => _onLoadStop?.call();
  void startLoading() => _onLoadStart?.call();

  @override
  Widget build({
    required String url,
    required ValueChanged<String> onResource,
    required VoidCallback onLoadStart,
    required VoidCallback onLoadStop,
    required ValueChanged<PlayerWebViewHandle> onReady,
  }) {
    _onResource = onResource;
    _onLoadStart = onLoadStart;
    _onLoadStop = onLoadStop;
    onReady(PlayerWebViewHandle.none);
    return const SizedBox.shrink();
  }
}

/// Собирает зависимости, указывающие на временную папку и фейки.
AppDependencies buildTestDependencies({
  Directory? dir,
  FakePlayersRepository? api,
  FakeDownloadEngine? engine,
  AppState? state,
  PlayerWebView? webView,
}) {
  final tmp = dir ?? Directory.systemTemp.createTempSync('rezak_test');
  return AppDependencies(
    playersApi: api ?? FakePlayersRepository(),
    downloadService: engine ?? FakeDownloadEngine(dir: tmp),
    appState: state ?? AppState(),
    outputDirProvider: () async => tmp,
    webView: webView,
  );
}
