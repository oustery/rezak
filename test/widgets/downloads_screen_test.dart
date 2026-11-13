import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rezak/core/app_dependencies.dart';
import 'package:rezak/screens/downloads_screen.dart';
import 'package:rezak/services/download_service.dart';
import 'package:rezak/state/app_state.dart';

import '../support/fakes.dart';

Widget _wrap(AppDependencies deps) => AppScope(
      dependencies: deps,
      child: const MaterialApp(home: DownloadsScreen()),
    );

DownloadJob _job(
  String path,
  DownloadStatus status, {
  String? title,
  double progress = 0,
}) =>
    DownloadJob(
      url: 'https://cdn.example/master.m3u8',
      outputPath: path,
      status: status,
      title: title,
      progress: progress,
    );

void main() {
  testWidgets('пустое состояние', (tester) async {
    final deps = buildTestDependencies();
    await tester.pumpWidget(_wrap(deps));

    expect(find.byKey(DownloadsKeys.empty), findsOneWidget);
    expect(find.text('Пока пусто'), findsOneWidget);
  });

  testWidgets('показывает сводку и карточки задач', (tester) async {
    final state = AppState();
    state.upsert(_job('/a.mp4', DownloadStatus.done, title: 'Фильм A'));
    state.upsert(_job('/b.mp4', DownloadStatus.failed, title: 'Фильм B'));
    state.upsert(_job('/c.mp4', DownloadStatus.running, title: 'Фильм C'));

    final deps = buildTestDependencies(state: state);
    await tester.pumpWidget(_wrap(deps));
    await tester.pump();

    expect(find.text('Фильм A'), findsOneWidget);
    expect(find.text('Фильм B'), findsOneWidget);
    expect(find.text('Фильм C'), findsOneWidget);
    expect(find.text('Готово'), findsOneWidget);
    expect(find.text('Ошибка'), findsOneWidget);
    expect(find.text('Скачивается'), findsOneWidget);
  });

  testWidgets('у активной задачи есть прогресс-бар', (tester) async {
    final state = AppState();
    state.upsert(
      _job('/a.mp4', DownloadStatus.running, title: 'Фильм', progress: 0.42),
    );

    await tester.pumpWidget(_wrap(buildTestDependencies(state: state)));
    await tester.pump();

    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(find.text('42 %'), findsOneWidget);
  });

  testWidgets('у готовой задачи есть шаринг и проверка звука', (tester) async {
    final dir = Directory.systemTemp.createTempSync('dl_widget');
    final file = File('${dir.path}/film.mp4')..writeAsBytesSync([1, 2, 3]);

    final state = AppState();
    state.upsert(
      DownloadJob(
        url: 'https://cdn.example/master.m3u8',
        outputPath: file.path,
        status: DownloadStatus.done,
        title: 'Фильм',
      ),
    );

    final engine = FakeDownloadEngine(dir: dir, probeOutput: 'audio,aac');
    await tester.pumpWidget(
      _wrap(buildTestDependencies(state: state, engine: engine, dir: dir)),
    );
    await tester.pump();

    expect(find.text('Поделиться'), findsOneWidget);
    expect(find.text('Проверить звук'), findsOneWidget);

    await tester.tap(find.text('Проверить звук'));
    await tester.pump(); // диалог создаётся
    await tester.pump(const Duration(milliseconds: 50)); // ffprobe ответил
    await tester.pump();

    expect(engine.probed.single, file.path);
    expect(find.text('Аудиодорожка есть'), findsOneWidget);
    expect(find.byKey(AudioCheckDialog.resultKey), findsOneWidget);
  });

  testWidgets('при отсутствии аудио диалог честно об этом сообщает',
      (tester) async {
    final dir = Directory.systemTemp.createTempSync('dl_widget2');
    final file = File('${dir.path}/mute.mp4')..writeAsBytesSync([1]);

    final state = AppState();
    state.upsert(
      DownloadJob(
        url: 'https://cdn.example/master.m3u8',
        outputPath: file.path,
        status: DownloadStatus.done,
      ),
    );

    final engine = FakeDownloadEngine(dir: dir, probeOutput: 'video,h264');
    await tester.pumpWidget(
      _wrap(buildTestDependencies(state: state, engine: engine, dir: dir)),
    );
    await tester.pump();

    await tester.tap(find.text('Проверить звук'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump();

    expect(find.text('Аудио не найдено'), findsOneWidget);
  });

  testWidgets('очистка завершённых работает через AppState', (tester) async {
    final state = AppState();
    state.upsert(_job('/done.mp4', DownloadStatus.done));
    state.upsert(_job('/run.mp4', DownloadStatus.running));

    await tester.pumpWidget(_wrap(buildTestDependencies(state: state)));
    await tester.pump();

    await tester.tap(find.byKey(DownloadsKeys.clearButton));
    await tester.pump();

    expect(state.jobs.length, 1);
    expect(state.jobs.single.outputPath, '/run.mp4');
  });

  testWidgets('у упавшей задачи раскрывается лог ffmpeg', (tester) async {
    final state = AppState();
    state.upsert(
      DownloadJob(
        url: 'https://cdn.example/master.m3u8',
        outputPath: '/fail.mp4',
        status: DownloadStatus.failed,
        log: 'HTTP error 403 Forbidden',
      ),
    );

    await tester.pumpWidget(_wrap(buildTestDependencies(state: state)));
    await tester.pump();

    expect(find.text('Лог ffmpeg'), findsOneWidget);
    await tester.tap(find.text('Лог ffmpeg'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.textContaining('403'), findsOneWidget);
  });
}
