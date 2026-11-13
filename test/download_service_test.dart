import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:rezak/services/download_service.dart';

void main() {
  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('dl_test');
  });

  tearDown(() async {
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  group('buildFfmpegArguments', () {
    test('один вход: маппинг и видео, и аудио', () {
      final service = DownloadService(dirProvider: () async => tmp);
      final args = service.buildFfmpegArguments(
        url: 'https://cdn.example/master.m3u8',
        outputPath: '/tmp/out.mp4',
      );

      expect(args.where((a) => a == '-i').length, 1);
      expect(args, containsAllInOrder(['-map', '0:v:0?', '-map', '0:a:0?']));
      expect(args, containsAllInOrder(['-c', 'copy']));
      expect(args, contains('-shortest'));
      expect(args, containsAllInOrder(['-movflags', '+faststart']));
      expect(args.last, '/tmp/out.mp4');
    });

    test('два входа: аудио берётся из второго', () {
      final service = DownloadService(dirProvider: () async => tmp);
      final args = service.buildFfmpegArguments(
        url: 'https://cdn.example/video.m3u8',
        audioUrl: 'https://cdn.example/audio.m3u8',
        outputPath: '/tmp/out.mp4',
      );

      expect(args.where((a) => a == '-i').length, 2);
      expect(args, contains('1:a:0?'));
      expect(args, isNot(contains('0:a:0?')));
    });

    test('Referer и User-Agent прокидываются в оба входа', () {
      final service = DownloadService(dirProvider: () async => tmp);
      final args = service.buildFfmpegArguments(
        url: 'https://cdn.example/v.m3u8',
        audioUrl: 'https://cdn.example/a.m3u8',
        outputPath: '/tmp/out.mp4',
      );

      final referers = [
        for (var i = 0; i < args.length - 1; i++)
          if (args[i] == '-headers') args[i + 1],
      ];
      expect(referers.length, 2);
      expect(referers.every((r) => r.contains('iframe.cloud')), isTrue);

      final agents = [
        for (var i = 0; i < args.length - 1; i++)
          if (args[i] == '-user_agent') args[i + 1],
      ];
      expect(agents.length, 2);
      expect(agents.every((a) => a.contains('Mozilla')), isTrue);
    });

    test('пустая строка audioUrl не создаёт второй вход', () {
      final service = DownloadService(dirProvider: () async => tmp);
      final args = service.buildFfmpegArguments(
        url: 'https://cdn.example/v.m3u8',
        audioUrl: '',
        outputPath: '/tmp/out.mp4',
      );
      expect(args.where((a) => a == '-i').length, 1);
    });
  });

  group('start', () {
    test('успешный запуск: файл создан, статус done', () async {
      final service = DownloadService(
        dirProvider: () async => tmp,
        runner: (args) async {
          await File(args.last).writeAsBytes([1, 2, 3, 4]);
          return const FfmpegRunResult(success: true, output: 'ok');
        },
      );

      final updates = <DownloadStatus>[];
      final job = await service.start(
        url: 'https://cdn.example/master.m3u8',
        fileName: 'film.mp4',
        onUpdate: (j) => updates.add(j.status),
      );

      expect(job.status, DownloadStatus.done);
      expect(job.progress, 1);
      expect(await File(job.outputPath).exists(), isTrue);
      expect(updates.first, DownloadStatus.queued);
      expect(updates, contains(DownloadStatus.running));
      expect(updates.last, DownloadStatus.done);
    });

    test('ffmpeg упал: статус failed и понятное объяснение', () async {
      final service = DownloadService(
        dirProvider: () async => tmp,
        runner: (args) async => const FfmpegRunResult(
          success: false,
          output: 'HTTP error 403 Forbidden',
          exitCode: 1,
        ),
      );

      final job = await service.start(
        url: 'https://cdn.example/master.m3u8',
        fileName: 'film.mp4',
      );

      expect(job.status, DownloadStatus.failed);
      expect(job.log, contains('403'));
      expect(job.log, contains('регион'));
    });

    test('отмена отличается от ошибки', () async {
      final service = DownloadService(
        dirProvider: () async => tmp,
        runner: (args) async =>
            const FfmpegRunResult(success: false, output: '', cancelled: true),
      );

      final job = await service.start(
        url: 'https://cdn.example/master.m3u8',
        fileName: 'film.mp4',
      );
      expect(job.status, DownloadStatus.cancelled);
    });

    test('успех без файла считается ошибкой', () async {
      final service = DownloadService(
        dirProvider: () async => tmp,
        runner: (args) async =>
            const FfmpegRunResult(success: true, output: ''),
      );

      final job = await service.start(
        url: 'https://cdn.example/master.m3u8',
        fileName: 'film.mp4',
      );
      expect(job.status, DownloadStatus.failed);
      expect(job.log, contains('файла нет'));
    });

    test('имя файла очищается от запрещённых символов', () async {
      final service = DownloadService(
        dirProvider: () async => tmp,
        runner: (args) async {
          await File(args.last).writeAsBytes([1]);
          return const FfmpegRunResult(success: true, output: '');
        },
      );

      final job = await service.start(
        url: 'https://cdn.example/master.m3u8',
        fileName: 'a/b:c*?.mp4',
      );

      expect(job.fileName, 'a_b_c__.mp4');
    });

    test('ограничение параллельности: третья задача отклоняется', () async {
      final gate = <Function>[];
      final service = DownloadService(
        maxConcurrent: 1,
        dirProvider: () async => tmp,
        runner: (args) async {
          // Держим первый запуск «в полёте», пока не разрешим.
          await Future<void>.delayed(const Duration(milliseconds: 50));
          await File(args.last).writeAsBytes([1]);
          return const FfmpegRunResult(success: true, output: '');
        },
      );
      gate.clear();

      final first = service.start(
        url: 'https://cdn.example/1.m3u8',
        fileName: 'one.mp4',
      );
      final second = await service.start(
        url: 'https://cdn.example/2.m3u8',
        fileName: 'two.mp4',
      );

      expect(second.status, DownloadStatus.failed);
      expect(second.log, contains('одновременных'));
      expect((await first).status, DownloadStatus.done);
    });

    test('аргументы, переданные в раннер, совпадают с buildFfmpegArguments',
        () async {
      List<String>? captured;
      final service = DownloadService(
        dirProvider: () async => tmp,
        runner: (args) async {
          captured = args;
          await File(args.last).writeAsBytes([1]);
          return const FfmpegRunResult(success: true, output: '');
        },
      );

      final job = await service.start(
        url: 'https://cdn.example/v.m3u8',
        audioUrl: 'https://cdn.example/a.m3u8',
        fileName: 'film.mp4',
      );

      expect(captured, isNotNull);
      expect(captured, contains('1:a:0?'));
      expect(captured!.last, job.outputPath);
    });
  });

  group('probeAudio', () {
    test('возвращает вывод пробера', () async {
      final service = DownloadService(
        dirProvider: () async => tmp,
        probeRunner: (path) async => 'audio,aac',
      );
      expect(await service.probeAudio('/tmp/x.mp4'), 'audio,aac');
    });
  });

  group('DownloadJob', () {
    test('isActive только для queued/running', () {
      final job = DownloadJob(url: 'u', outputPath: '/a.mp4');
      expect(job.isActive, isTrue);
      expect(job.copyWith(status: DownloadStatus.done).isActive, isFalse);
      expect(job.copyWith(status: DownloadStatus.failed).isActive, isFalse);
    });

    test('copyWith сохраняет неизменяемые поля', () {
      final job = DownloadJob(
        url: 'https://x',
        audioUrl: 'https://a',
        outputPath: '/a.mp4',
        title: 'Фильм',
      );
      final copy = job.copyWith(status: DownloadStatus.running, progress: 0.5);
      expect(copy.url, job.url);
      expect(copy.audioUrl, job.audioUrl);
      expect(copy.title, 'Фильм');
      expect(copy.progress, 0.5);
    });
  });

  test('humanSize форматирует байты', () {
    expect(humanSize(512), '512.0 Б');
    expect(humanSize(2048), '2.0 КБ');
    expect(humanSize(5 * 1024 * 1024), '5.0 МБ');
  });

  group('buildProbeArguments', () {
    test('аргументы именно ffprobe: путь отдельным аргументом, без кавычек',
        () {
      final service = DownloadService(dirProvider: () async => tmp);
      final args = service.buildProbeArguments('/tmp/x.mp4');

      expect(args, containsAllInOrder(['-i', '/tmp/x.mp4']));
      expect(
        args,
        containsAllInOrder(['-show_entries', 'stream=codec_type,codec_name']),
      );
      expect(args, containsAllInOrder(['-of', 'csv=p=0']));
      // Путь не склеен с кавычками в одну строку — пробелы в имени файла
      // не сломают разбор аргументов.
      expect(args.where((a) => a.contains(' ')), isEmpty);
    });
  });

  group('cancel', () {
    test('без активной сессии отменять нечего', () async {
      final service = DownloadService(dirProvider: () async => tmp);
      final job = DownloadJob(url: 'u', outputPath: '/tmp/x.mp4');
      expect(await service.cancel(job), isFalse);
    });

    test('с подменённым раннером нативной сессии нет', () async {
      final service = DownloadService(
        dirProvider: () async => tmp,
        runner: (args) async =>
            const FfmpegRunResult(success: true, output: ''),
      );
      final job = DownloadJob(url: 'u', outputPath: '/tmp/x.mp4');
      expect(await service.cancel(job), isFalse);
    });
  });
}
