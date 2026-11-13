import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rezak/core/app_dependencies.dart';
import 'package:rezak/models/player_source.dart';
import 'package:rezak/screens/player_screen.dart';
import 'package:rezak/services/download_service.dart';
import 'package:rezak/ui/player_web_view.dart';
import 'package:rezak/ui/theme.dart';

import '../support/fakes.dart';

/// Заглушка транспорта Dio: отдаёт заданный текст плейлиста.
class _ManifestAdapter implements HttpClientAdapter {
  _ManifestAdapter(this.body, {this.statusCode = 200});

  final String body;
  final int statusCode;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    return ResponseBody.fromString(
      body,
      statusCode,
      headers: {
        Headers.contentTypeHeader: ['application/vnd.apple.mpegurl'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

Dio _dio(String body, {int statusCode = 200}) {
  final dio = Dio();
  dio.httpClientAdapter = _ManifestAdapter(body, statusCode: statusCode);
  return dio;
}

const _masterWithAudio = '''
#EXTM3U
#EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="aud",NAME="Русский",DEFAULT=YES,URI="audio/ru.m3u8"
#EXT-X-STREAM-INF:BANDWIDTH=5200000,RESOLUTION=1920x1080,AUDIO="aud"
video/1080/index.m3u8
''';

const _masterWithoutAudio = '''
#EXTM3U
#EXT-X-STREAM-INF:BANDWIDTH=1200000,RESOLUTION=854x480
480/index.m3u8
''';

const _player = PlayerSource(
  type: 'Turbo',
  iframeUrl: 'https://turbo.example/embed/1',
  translations: [],
);

Widget _wrap(AppDependencies deps, Widget child) => AppScope(
      dependencies: deps,
      child: MaterialApp(theme: AppTheme.dark(), home: child),
    );

PlayerScreen _screen({
  required AppDependencies deps,
  Dio? dio,
  PlayerWebView? webView,
}) {
  return PlayerScreen(
    webView: webView,
    player: _player,
    iframeUrl: 'https://turbo.example/embed/1',
    translationLabel: 'Русский',
    kinopoiskId: '4640303',
    probeDio: dio ?? _dio(_masterWithAudio),
  );
}

/// Качает несколько кадров вместо pumpAndSettle: в шторке есть
/// бесконечно анимирующийся LinearProgressIndicator, из-за которого
/// pumpAndSettle не может «успокоиться».
Future<void> pumpFrames(WidgetTester tester, {int frames = 8}) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 60));
  }
}

void main() {
  testWidgets('показывает пустое состояние, пока поток не найден',
      (tester) async {
    final webView = FakePlayerWebView();
    final deps = buildTestDependencies(webView: webView);

    await tester.pumpWidget(
      _wrap(deps, _screen(deps: deps, webView: webView)),
    );
    await tester.pump();

    expect(find.byKey(PlayerKeys.emptySniffer), findsOneWidget);
    expect(find.text('Ждём поток'), findsOneWidget);
  });

  testWidgets('сниффер добавляет найденный поток в список', (tester) async {
    final webView = FakePlayerWebView();
    final deps = buildTestDependencies(webView: webView);

    await tester.pumpWidget(
      _wrap(deps, _screen(deps: deps, webView: webView)),
    );
    await tester.pump();

    webView.emitResource('https://cdn.example/hls/master.m3u8');
    await tester.pump();
    webView.emitResource('https://cdn.example/hls/seg1.ts'); // сегмент — мимо
    await tester.pump();

    expect(find.text('HLS'), findsOneWidget);
    expect(find.textContaining('master.m3u8'), findsOneWidget);
    expect(find.byKey(const Key('download-stream-0')), findsOneWidget);
  });

  testWidgets('шторка сообщает, что аудио найдено отдельной дорожкой',
      (tester) async {
    final webView = FakePlayerWebView();
    final deps = buildTestDependencies(webView: webView);

    await tester.pumpWidget(
      _wrap(deps, _screen(deps: deps, webView: webView)),
    );
    await tester.pump();
    webView.emitResource('https://cdn.example/hls/master.m3u8');
    await tester.pump();

    await tester.tap(find.byKey(const Key('download-stream-0')));
    await pumpFrames(tester);

    expect(find.text('Параметры загрузки'), findsOneWidget);
    // «Русский» встречается дважды: в подзаголовке экрана и в самой шторке
    expect(
      find.textContaining('Отдельная дорожка: Русский'),
      findsOneWidget,
    );
    expect(find.byKey(DownloadSheetState.startKey), findsOneWidget);
  });

  testWidgets('шторка предупреждает, если аудиогруппы нет', (tester) async {
    final webView = FakePlayerWebView();
    final deps = buildTestDependencies(webView: webView);

    await tester.pumpWidget(
      _wrap(
        deps,
        _screen(
          deps: deps,
          dio: _dio(_masterWithoutAudio),
          webView: webView,
        ),
      ),
    );
    await tester.pump();
    webView.emitResource('https://cdn.example/hls/master.m3u8');
    await tester.pump();

    await tester.tap(find.byKey(const Key('download-stream-0')));
    await pumpFrames(tester);

    expect(find.textContaining('Аудиогруппа не найдена'), findsOneWidget);
  });

  testWidgets('ошибка чтения плейлиста не блокирует запуск', (tester) async {
    final webView = FakePlayerWebView();
    final deps = buildTestDependencies(webView: webView);

    await tester.pumpWidget(
      _wrap(
        deps,
        _screen(
            deps: deps, dio: _dio('nope', statusCode: 403), webView: webView),
      ),
    );
    await tester.pump();
    webView.emitResource('https://cdn.example/hls/master.m3u8');
    await tester.pump();

    await tester.tap(find.byKey(const Key('download-stream-0')));
    await pumpFrames(tester);

    expect(find.textContaining('HTTP 403'), findsOneWidget);
    expect(find.byKey(DownloadSheetState.startKey), findsOneWidget);
  });

  testWidgets(
      'подтверждение в шторке запускает движок и кладёт задачу в AppState',
      (tester) async {
    final webView = FakePlayerWebView();
    final engine = FakeDownloadEngine(
      dir: Directory.systemTemp.createTempSync('widget_dl'),
    );
    final deps = buildTestDependencies(webView: webView, engine: engine);

    await tester.pumpWidget(
      _wrap(deps, _screen(deps: deps, webView: webView)),
    );
    await tester.pump();
    webView.emitResource('https://cdn.example/hls/master.m3u8');
    await tester.pump();

    await tester.tap(find.byKey(const Key('download-stream-0')));
    await pumpFrames(tester);
    await tester.tap(find.byKey(DownloadSheetState.startKey));
    await pumpFrames(tester);

    expect(engine.started.length, 1);
    expect(engine.started.single.url, 'https://cdn.example/hls/master.m3u8');
    expect(deps.appState.jobs, isNotEmpty);
    expect(deps.appState.jobs.first.status, DownloadStatus.done);
  });

  testWidgets('ручной ввод ссылок открывает диалог', (tester) async {
    final webView = FakePlayerWebView();
    final deps = buildTestDependencies(webView: webView);

    await tester.pumpWidget(
      _wrap(deps, _screen(deps: deps, webView: webView)),
    );
    await tester.pump();

    await tester.tap(find.byKey(PlayerKeys.manualButton));
    await pumpFrames(tester);

    expect(find.text('Ссылки вручную'), findsOneWidget);
    expect(find.byKey(const Key('manual-video-input')), findsOneWidget);
    expect(find.byKey(const Key('manual-audio-input')), findsOneWidget);
  });
}
