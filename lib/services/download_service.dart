import 'dart:async';
import 'dart:io';

import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/ffprobe_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:path_provider/path_provider.dart';

/// Статус задачи на скачивание.
enum DownloadStatus { queued, running, done, failed, cancelled }

/// Одна задача скачивания. Мутабельная: ffmpeg-колбэк обновляет прогресс
/// несколько раз в секунду, пересоздавать объект на каждый тик дорого.
class DownloadJob {
  DownloadJob({
    required this.url,
    required this.outputPath,
    this.audioUrl,
    this.progress = 0,
    this.status = DownloadStatus.queued,
    this.log = '',
    this.title,
  });

  final String url;
  final String? audioUrl;
  final String outputPath;
  final String? title;

  double progress; // 0..1
  DownloadStatus status;
  String log;

  String get fileName => outputPath.split('/').last;

  bool get isActive =>
      status == DownloadStatus.running || status == DownloadStatus.queued;

  DownloadJob copyWith({
    double? progress,
    DownloadStatus? status,
    String? log,
  }) {
    return DownloadJob(
      url: url,
      audioUrl: audioUrl,
      outputPath: outputPath,
      title: title,
      progress: progress ?? this.progress,
      status: status ?? this.status,
      log: log ?? this.log,
    );
  }
}

/// Результат одного запуска ffmpeg — то, что нужно знать о завершении.
class FfmpegRunResult {
  const FfmpegRunResult({
    required this.success,
    required this.output,
    this.cancelled = false,
    this.exitCode,
  });

  final bool success;
  final bool cancelled;
  final String output;
  final int? exitCode;
}

/// Запуск ffmpeg с заданными аргументами. Вынесен в отдельный тип,
/// чтобы тесты подменяли реальный вызов без нативных библиотек.
typedef FfmpegRunner = Future<FfmpegRunResult> Function(List<String> args);

/// Контракт движка загрузки. Благодаря ему экраны можно тестировать
/// с фейковым движком — без ffmpeg и без сети.
abstract class DownloadEngine {
  Future<Directory> outputDir();

  List<String> buildFfmpegArguments({
    required String url,
    required String outputPath,
    String? audioUrl,
  });

  Future<DownloadJob> start({
    required String url,
    required String fileName,
    String? audioUrl,
    String? title,
    void Function(DownloadJob job)? onUpdate,
  });

  /// Пытается прервать активную задачу. Возвращает true, если отменить
  /// получилось (нативная сессия найдена); финальный статус `cancelled`
  /// всё равно придёт колбэком завершения ffmpeg.
  Future<bool> cancel(DownloadJob job);

  /// Аргументы проверки потока через ffprobe (см. [DownloadService]).
  List<String> buildProbeArguments(String path);

  Future<String> probeAudio(String path);
}

/// Реальная реализация поверх ffmpeg-kit.
class DownloadService implements DownloadEngine {
  DownloadService({
    this.maxConcurrent = 2,
    FfmpegRunner? runner,
    Future<Directory> Function()? dirProvider,
    Future<String> Function(String path)? probeRunner,
  })  : _runner = runner,
        _dirProvider = dirProvider,
        _probeRunner = probeRunner;

  static const String referer = 'https://iframe.cloud/';
  static const String userAgent =
      'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 (KHTML, like Gecko) '
      'Chrome/120.0 Mobile Safari/537.36';

  final int maxConcurrent;
  final FfmpegRunner? _runner;
  final Future<Directory> Function()? _dirProvider;
  final Future<String> Function(String path)? _probeRunner;

  int _running = 0;

  /// Идущие нативные сессии: outputPath → sessionId. Нужен для отмены:
  /// ffmpeg-kit отменяет только по id сессии.
  final Map<String, int> _sessions = {};

  @override
  Future<Directory> outputDir() async {
    final custom = _dirProvider;
    if (custom != null) return custom();
    // Внешняя память приложения: файл виден в файловом менеджере и его можно
    // отдать в «Поделиться». На Android 10+ разрешения не нужны.
    final base = await getExternalStorageDirectory() ??
        await getApplicationDocumentsDirectory();
    final dir = Directory('${base.path}/Rezak');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  /// Команда, из-за отсутствия которой обычно и получаются «немые» файлы:
  /// обязательны оба `-map` — видео и аудио.
  @override
  List<String> buildFfmpegArguments({
    required String url,
    required String outputPath,
    String? audioUrl,
  }) {
    const headers = 'Referer: $referer\r\n';
    final args = <String>[
      '-hide_banner',
      '-y',
      '-user_agent',
      userAgent,
      '-headers',
      headers,
      '-i',
      url,
    ];

    if (audioUrl != null && audioUrl.isNotEmpty) {
      args.addAll([
        '-user_agent',
        userAgent,
        '-headers',
        headers,
        '-i',
        audioUrl,
        '-map',
        '0:v:0?',
        '-map',
        '1:a:0?',
      ]);
    } else {
      args.addAll(['-map', '0:v:0?', '-map', '0:a:0?']);
    }

    args.addAll([
      '-c',
      'copy',
      '-shortest',
      '-movflags',
      '+faststart',
      outputPath,
    ]);
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
    final dir = await outputDir();
    final safeName = fileName.replaceAll(RegExp(r'[/\\:*?"<>|]'), '_');
    final outPath = '${dir.path}/$safeName';

    final job = DownloadJob(
      url: url,
      audioUrl: audioUrl,
      outputPath: outPath,
      title: title,
    );
    onUpdate?.call(job);

    if (_running >= maxConcurrent) {
      job.status = DownloadStatus.failed;
      job.log = 'Слишком много одновременных загрузок ($maxConcurrent). '
          'Дождитесь завершения текущих.';
      onUpdate?.call(job);
      return job;
    }

    _running++;
    job.status = DownloadStatus.running;
    onUpdate?.call(job);

    final args = buildFfmpegArguments(
      url: url,
      outputPath: outPath,
      audioUrl: audioUrl,
    );
    job.log = 'ffmpeg ${args.join(' ')}';

    late final FfmpegRunResult result;
    try {
      final runner = _runner;
      result = runner != null
          ? await runner(args)
          : await _runFfmpegNative(args, job, onUpdate);
    } finally {
      _running--;
    }

    final output = result.output;

    if (result.success) {
      final file = File(outPath);
      if (await file.exists()) {
        job.status = DownloadStatus.done;
        job.progress = 1;
        job.log = 'Готово: $outPath '
            '(${humanSize(await file.length())})\n$output';
      } else {
        job.status = DownloadStatus.failed;
        job.log = 'ffmpeg отчитался об успехе, но файла нет: $outPath';
      }
    } else if (result.cancelled) {
      job.status = DownloadStatus.cancelled;
      job.log = 'Отменено';
    } else {
      job.status = DownloadStatus.failed;
      job.log = _explainFailure(output, result.exitCode);
    }

    onUpdate?.call(job);
    return job;
  }

  Future<FfmpegRunResult> _runFfmpegNative(
    List<String> args,
    DownloadJob job,
    void Function(DownloadJob)? onUpdate,
  ) async {
    final completer = Completer<FfmpegRunResult>();

    // Колбэк статистики подписываем НА КОНКРЕТНУЮ сессию. Прежний глобальный
    // FFmpegKitConfig.enableStatisticsCallback был один на весь процесс:
    // при maxConcurrent > 1 параллельные задачи писали прогресс друг другу.
    final session = await FFmpegKit.executeWithArgumentsAsync(
      args,
      (doneSession) async {
        try {
          final returnCode = await doneSession.getReturnCode();
          final output = await doneSession.getAllLogsAsString() ?? '';
          completer.complete(FfmpegRunResult(
            success: ReturnCode.isSuccess(returnCode),
            cancelled: ReturnCode.isCancel(returnCode),
            output: output,
            exitCode: returnCode?.getValue(),
          ));
        } catch (error) {
          completer.completeError(error);
        }
      },
      null,
      (stats) {
        final timeMs = stats.getTime();
        if (timeMs > 0) {
          // Точную длительность без ffprobe не знаем — показываем оценочный рост.
          job.progress = (timeMs / (1000 * 60 * 120)).clamp(0.0, 0.99);
          onUpdate?.call(job);
        }
      },
    );

    final sessionId = session.getSessionId();
    if (sessionId != null) {
      _sessions[job.outputPath] = sessionId;
    }

    try {
      return await completer.future;
    } finally {
      _sessions.remove(job.outputPath);
    }
  }

  @override
  Future<bool> cancel(DownloadJob job) async {
    if (_runner != null) return false; // подменённый раннер сессий не создаёт
    final sessionId = _sessions[job.outputPath];
    if (sessionId == null) return false;
    await FFmpegKit.cancel(sessionId);
    return true;
  }

  /// Аргументы проверки потока. Ключевое: `-show_entries` и `-of` понимает
  /// только ffprobe — у ffmpeg таких флагов нет, и раньше эта команда
  /// отдавалась FFmpegKit.execute и всегда падала с «Unrecognized option».
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
  Future<String> probeAudio(String path) async {
    final custom = _probeRunner;
    if (custom != null) return custom(path);
    final session =
        await FFprobeKit.executeWithArguments(buildProbeArguments(path));
    final output = await session.getOutput();
    return (output ?? await session.getAllLogsAsString() ?? '').trim();
  }

  String _explainFailure(String log, int? code) {
    final lower = log.toLowerCase();
    if (lower.contains('403') || lower.contains('forbidden')) {
      return 'Источник ответил 403: ссылка привязана к IP/региону/Referer '
          'или токен уже протух. Переоткройте плеер и снимите ссылку заново.\n\n$log';
    }
    if (lower.contains('404')) {
      return '404: плейлист устарел. Ссылки живут недолго — снимите свежую.\n\n$log';
    }
    if (lower.contains('no such file') || lower.contains('invalid data')) {
      return 'Похоже, по ссылке не плейлист, а HTML/заглушка. '
          'Снимите ссылку именно с master.m3u8.\n\n$log';
    }
    return 'ffmpeg завершился с кодом $code.\n\n$log';
  }
}

/// Утилита для экранов: человеко-читаемый размер.
String humanSize(int bytes) {
  const units = ['Б', 'КБ', 'МБ', 'ГБ'];
  var size = bytes.toDouble();
  var unit = 0;
  while (size >= 1024 && unit < units.length - 1) {
    size /= 1024;
    unit++;
  }
  return '${size.toStringAsFixed(1)} ${units[unit]}';
}
