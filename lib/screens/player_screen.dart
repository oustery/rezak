import 'dart:async';

import 'package:dio/dio.dart';
import 'package:material_ui/material_ui.dart';

import '../core/app_dependencies.dart';
import '../models/player_source.dart';
import '../services/download_service.dart';
import '../services/manifest_parser.dart';
import '../services/sniffer.dart';
import '../ui/player_web_view.dart';
import '../ui/theme.dart';
import '../ui/widgets/common.dart';
import 'downloads_screen.dart';

/// Ключи для виджет-тестов и семантики.
abstract final class PlayerKeys {
  static const webview = Key('player-webview');
  static const manualButton = Key('manual-url-button');
  static const emptySniffer = Key('sniffer-empty');
}

/// Экран плеера: WebView со сниффером + список найденных потоков
/// + кнопка запуска склейки видео со звуком.
class PlayerScreen extends StatefulWidget {
  const PlayerScreen({
    super.key,
    required this.player,
    required this.iframeUrl,
    required this.translationLabel,
    required this.kinopoiskId,
    this.sniffer,
    this.webView,
    this.probeDio,
  });

  final PlayerSource player;
  final String iframeUrl;
  final String translationLabel;
  final String kinopoiskId;

  /// Позволяет подсунуть предзаполненный сниффер в тестах.
  final Sniffer? sniffer;

  /// Позволяет подменить WebView в тестах.
  final PlayerWebView? webView;

  /// HTTP-клиент для чтения master-плейлиста (подменяется в тестах).
  final Dio? probeDio;

  @override
  State<PlayerScreen> createState() => PlayerScreenState();
}

class PlayerScreenState extends State<PlayerScreen> {
  late final Sniffer sniffer = widget.sniffer ?? Sniffer();
  StreamSubscription<SniffedStream>? _sub;

  PlayerWebViewHandle webViewHandle = PlayerWebViewHandle.none;
  final List<SniffedStream> streams = [];
  bool pageLoading = true;

  @override
  void initState() {
    super.initState();
    streams.addAll(sniffer.found);
    _sub = sniffer.stream.listen((item) {
      if (!mounted) return;
      setState(() => streams.insert(0, item));
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    if (widget.sniffer == null) sniffer.dispose();
    super.dispose();
  }

  void onResourceLoaded(String url) {
    if (sniffer.inspect(url)) {
      if (mounted) setState(() {});
    }
  }

  /// Запускает загрузку: файл пишется в папку приложения, прогресс уходит
  /// в общий [AppState].
  Future<void> startDownload(SniffedStream item, {String? audioUrl}) async {
    final deps = AppDependencies.of(context);
    final name = 'kp${widget.kinopoiskId}_${widget.player.type.toLowerCase()}_'
        '${DateTime.now().millisecondsSinceEpoch}.mp4';
    final dir = await deps.resolveOutputDir();

    final job = DownloadJob(
      url: item.url,
      audioUrl: audioUrl,
      outputPath: '${dir.path}/$name',
      title: '${widget.player.displayName} · ${widget.translationLabel}',
      status: DownloadStatus.running,
    );
    deps.appState.upsert(job);

    // Не блокируем UI: колбэк движка сам обновляет карточку в списке загрузок.
    unawaited(
      deps.downloadService
          .start(
            url: item.url,
            fileName: name,
            audioUrl: audioUrl,
            title: job.title,
            onUpdate: deps.appState.upsert,
          )
          .then((finished) => deps.appState.upsert(finished))
          .catchError((Object e) {
        deps.appState.upsert(
          job.copyWith(status: DownloadStatus.failed, log: '$e'),
        );
        return job;
      }),
    );
  }

  Future<void> confirmAndDownload(SniffedStream item,
      {String? audioUrl}) async {
    final proceed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => DownloadSheet(
        stream: item,
        audioUrl: audioUrl,
        dio: widget.probeDio,
        onStart: () => Navigator.of(context).pop(true),
      ),
    );

    if (proceed != true || !mounted) return;
    await startDownload(item, audioUrl: audioUrl);
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Загрузка пошла — прогресс в «Загрузки»'),
        action: SnackBarAction(
          label: 'Открыть',
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => const DownloadsScreen()),
          ),
        ),
      ),
    );
  }

  Future<void> openManualUrlDialog() async {
    final videoController = TextEditingController(
      text: streams.isEmpty ? '' : streams.first.url,
    );
    final audioController = TextEditingController();

    final result = await showDialog<List<String>>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Ссылки вручную'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              key: const Key('manual-video-input'),
              controller: videoController,
              decoration: const InputDecoration(
                labelText: 'master.m3u8 / manifest.mpd',
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              key: const Key('manual-audio-input'),
              controller: audioController,
              decoration: const InputDecoration(
                labelText: 'audio.m3u8 (если отдельно)',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop([
              videoController.text.trim(),
              audioController.text.trim(),
            ]),
            child: const Text('Дальше'),
          ),
        ],
      ),
    );

    videoController.dispose();
    audioController.dispose();

    if (result == null || result[0].isEmpty) return;
    await confirmAndDownload(
      SniffedStream(
        url: result[0],
        kind: result[0].contains('.mpd') ? StreamKind.dash : StreamKind.hls,
        looksLikeAudio: false,
      ),
      audioUrl: result[1].isEmpty ? null : result[1],
    );
  }

  @override
  Widget build(BuildContext context) {
    final videoHeight = MediaQuery.of(context).size.height * 0.40;

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.player.displayName,
                style: const TextStyle(fontSize: 15.5)),
            Text(
              widget.translationLabel,
              style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
            ),
          ],
        ),
        actions: [
          IconButton(
            key: PlayerKeys.manualButton,
            tooltip: 'Вставить ссылки вручную',
            icon: const Icon(Icons.link),
            onPressed: openManualUrlDialog,
          ),
          IconButton(
            tooltip: 'Загрузки',
            icon: const Icon(Icons.download_done_outlined),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const DownloadsScreen()),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 4, 14, 0),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.card),
              child: SizedBox(
                height: videoHeight,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Container(color: Colors.black),
                    (widget.webView ??
                            AppDependencies.of(context).webView ??
                            const RealPlayerWebView())
                        .build(
                      url: widget.iframeUrl,
                      onResource: onResourceLoaded,
                      onLoadStart: () {
                        if (mounted) setState(() => pageLoading = true);
                      },
                      onLoadStop: () {
                        if (mounted) setState(() => pageLoading = false);
                      },
                      onReady: (handle) => webViewHandle = handle,
                    ),
                    if (pageLoading)
                      const Align(
                        alignment: Alignment.topCenter,
                        child: LinearProgressIndicator(
                          minHeight: 2,
                          color: AppColors.primary,
                          backgroundColor: Colors.transparent,
                        ),
                      ),
                    Positioned(
                      top: 10,
                      right: 10,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(AppRadius.pill),
                        child: Container(
                          color: const Color(0xB3050A12),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 5,
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 7,
                                height: 7,
                                decoration: const BoxDecoration(
                                  color: AppColors.tertiary,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                'сниффер · ${streams.length}',
                                style: const TextStyle(
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 6),
            child: Row(
              children: [
                const Text(
                  'НАЙДЕННЫЕ ПОТОКИ',
                  style: TextStyle(
                    fontSize: 10.5,
                    letterSpacing: 1.4,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textMuted,
                  ),
                ),
                const Spacer(),
                TextButton.icon(
                  onPressed: () => webViewHandle.reload?.call(),
                  icon: const Icon(Icons.refresh, size: 16),
                  label:
                      const Text('Обновить', style: TextStyle(fontSize: 12.5)),
                ),
              ],
            ),
          ),
          Expanded(
            child: streams.isEmpty
                ? const EmptyState(
                    key: PlayerKeys.emptySniffer,
                    icon: Icons.radar,
                    title: 'Ждём поток',
                    message: 'Нажмите play в плеере выше — ссылка на '
                        'HLS/DASH-плейлист появится здесь автоматически.',
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(14, 4, 14, 24),
                    itemCount: streams.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, index) => StreamTile(
                      stream: streams[index],
                      index: index,
                      onDownload: () => confirmAndDownload(streams[index]),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

/// Карточка одного найденного потока.
class StreamTile extends StatelessWidget {
  const StreamTile({
    super.key,
    required this.stream,
    required this.onDownload,
    this.index = 0,
  });

  final SniffedStream stream;
  final VoidCallback onDownload;
  final int index;

  @override
  Widget build(BuildContext context) {
    final color = switch (stream.kind) {
      StreamKind.hls => AppColors.primary,
      StreamKind.dash => AppColors.warning,
      StreamKind.file => AppColors.tertiary,
    };

    return GlassCard(
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          StatusPill(label: stream.kindLabel, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  stream.shortUrl,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12, height: 1.35),
                ),
                const SizedBox(height: 2),
                Text(
                  stream.looksLikeAudio
                      ? 'похоже на аудиодорожку'
                      : 'видео / мастер-плейлист',
                  style: const TextStyle(
                    fontSize: 10.5,
                    color: AppColors.textMuted,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (!stream.looksLikeAudio)
            FilledButton(
              key: Key('download-stream-$index'),
              onPressed: onDownload,
              style: FilledButton.styleFrom(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              ),
              child: const Text('Скачать', style: TextStyle(fontSize: 12.5)),
            ),
        ],
      ),
    );
  }
}

/// Шторка подтверждения: разбирает плейлист и честно говорит, где звук.
class DownloadSheet extends StatefulWidget {
  const DownloadSheet({
    super.key,
    required this.stream,
    required this.onStart,
    this.audioUrl,
    this.dio,
  });

  final SniffedStream stream;
  final String? audioUrl;
  final VoidCallback onStart;

  /// Подменяемый HTTP-клиент для тестов.
  final Dio? dio;

  @override
  State<DownloadSheet> createState() => DownloadSheetState();
}

class DownloadSheetState extends State<DownloadSheet> {
  static const Key statusKey = Key('probe-status');
  static const Key startKey = Key('probe-start');

  late final Dio dio = widget.dio ??
      Dio(
        BaseOptions(
          connectTimeout: const Duration(seconds: 15),
          receiveTimeout: const Duration(seconds: 20),
        ),
      );

  bool loading = true;
  String? error;
  StreamProbeResult? probe;

  @override
  void initState() {
    super.initState();
    probeManifest();
  }

  Future<void> probeManifest() async {
    try {
      final result = await fetchManifest(widget.stream.url);
      if (!mounted) return;
      setState(() {
        probe = result;
        loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        error = 'Не удалось прочитать плейлист: $e\n'
            'Загрузку всё равно можно запустить — ffmpeg попробует сам.';
        loading = false;
      });
    }
  }

  Future<StreamProbeResult> fetchManifest(String url) async {
    final response = await dio.get<String>(
      url,
      options: Options(
        responseType: ResponseType.plain,
        headers: {
          'Referer': DownloadService.referer,
          'User-Agent': DownloadService.userAgent,
        },
        validateStatus: (_) => true,
      ),
    );
    if (response.statusCode != 200) {
      throw StateError('HTTP ${response.statusCode}');
    }
    return ManifestParser.parse(response.data ?? '', url);
  }

  @override
  Widget build(BuildContext context) {
    final result = probe;

    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
      padding: EdgeInsets.fromLTRB(
        18,
        12,
        18,
        18 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 42,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.stroke,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text('Параметры загрузки',
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            if (loading) const LinearProgressIndicator(minHeight: 2),
            if (result != null) ...[
              _InfoRow(
                icon: Icons.tag,
                title: 'Поток',
                value: result.isDash ? 'DASH (.mpd)' : 'HLS (.m3u8)',
              ),
              if (result.variants.isNotEmpty)
                _InfoRow(
                  icon: Icons.high_quality,
                  title: 'Качества',
                  value: result.variants.map((v) => v.label).join(', '),
                ),
              _InfoRow(
                key: statusKey,
                icon: result.hasAudioGroup
                    ? Icons.graphic_eq
                    : Icons.hearing_disabled,
                title: 'Аудио',
                value: result.hasAudioGroup
                    ? 'Отдельная дорожка: '
                        '${result.audioTracks.map((t) => t.name).join(', ')}'
                    : 'Аудиогруппа не найдена — склеим 0:a:0 из сегментов',
                valueColor: result.hasAudioGroup
                    ? AppColors.tertiary
                    : AppColors.warning,
              ),
              if (widget.audioUrl != null)
                _InfoRow(
                  icon: Icons.add_link,
                  title: 'Второй вход',
                  value: widget.audioUrl!,
                ),
            ],
            if (error != null) ...[
              const SizedBox(height: 6),
              MessageBanner(message: error!, severity: BannerSeverity.warning),
            ],
            const SizedBox(height: 12),
            const MonoBlock(
              text: 'ffmpeg -i <поток>\n'
                  '  -map 0:v:0 -map 0:a:0\n'
                  '  -c copy -shortest -movflags +faststart\n'
                  '  out.mp4',
              maxHeight: 104,
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    child: const Text('Отмена'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: FilledButton.icon(
                    key: startKey,
                    onPressed: widget.onStart,
                    icon: const Icon(Icons.download, size: 18),
                    label: const Text('Видео + звук'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    super.key,
    required this.icon,
    required this.title,
    required this.value,
    this.valueColor,
  });

  final IconData icon;
  final String title;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: AppColors.textMuted),
          const SizedBox(width: 8),
          SizedBox(
            width: 96,
            child: Text(
              title,
              style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 12,
                height: 1.35,
                color: valueColor ?? AppColors.text,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
