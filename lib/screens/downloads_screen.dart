import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:share_plus/share_plus.dart';

import '../core/app_dependencies.dart';
import '../services/download_service.dart';
import '../ui/theme.dart';
import '../ui/widgets/common.dart';

abstract final class DownloadsKeys {
  static const empty = Key('downloads-empty');
  static const clearButton = Key('downloads-clear');
}

/// Список загрузок: прогресс, шаринг, проверка звука.
class DownloadsScreen extends StatelessWidget {
  const DownloadsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = AppDependencies.of(context).appState;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Загрузки'),
        actions: [
          ListenableBuilder(
            listenable: state,
            builder: (context, _) => IconButton(
              key: DownloadsKeys.clearButton,
              tooltip: 'Очистить завершённые',
              icon: const Icon(Icons.cleaning_services_outlined),
              onPressed: state.jobs.isEmpty ? null : state.clearFinished,
            ),
          ),
        ],
      ),
      body: ListenableBuilder(
        listenable: state,
        builder: (context, _) {
          final jobs = state.jobs;
          if (jobs.isEmpty) {
            return const EmptyState(
              key: DownloadsKeys.empty,
              icon: Icons.download_for_offline_outlined,
              title: 'Пока пусто',
              message: 'Выберите ID → откройте плеер → нажмите play → '
                  '«Скачать» напротив найденного потока.',
            );
          }

          return ListView(
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 28),
            children: [
              _SummaryBar(jobs: jobs),
              const SizedBox(height: 14),
              ...jobs.map(
                (job) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: JobCard(job: job),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _SummaryBar extends StatelessWidget {
  const _SummaryBar({required this.jobs});

  final List<DownloadJob> jobs;

  @override
  Widget build(BuildContext context) {
    final active = jobs.where((j) => j.isActive).length;
    final done = jobs.where((j) => j.status == DownloadStatus.done).length;
    final failed = jobs.where((j) => j.status == DownloadStatus.failed).length;

    return GlassCard(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          _metric('$active', 'в работе', AppColors.primary),
          _divider(),
          _metric('$done', 'готово', AppColors.tertiary),
          _divider(),
          _metric('$failed', 'ошибок', AppColors.error),
        ],
      ),
    );
  }

  Widget _metric(String value, String label, Color color) {
    return Expanded(
      child: Column(
        children: [
          Text(
            value,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
          ),
        ],
      ),
    );
  }

  Widget _divider() => Container(
        width: 1,
        height: 26,
        color: AppColors.stroke,
      );
}

/// Карточка одной задачи.
class JobCard extends StatelessWidget {
  const JobCard({super.key, required this.job});

  final DownloadJob job;

  @override
  Widget build(BuildContext context) {
    final (color, label, icon) = switch (job.status) {
      DownloadStatus.queued => (
          AppColors.textMuted,
          'В очереди',
          Icons.hourglass_empty
        ),
      DownloadStatus.running => (
          AppColors.primary,
          'Скачивается',
          Icons.downloading
        ),
      DownloadStatus.done => (
          AppColors.tertiary,
          'Готово',
          Icons.check_circle_outline
        ),
      DownloadStatus.failed => (AppColors.error, 'Ошибка', Icons.error_outline),
      DownloadStatus.cancelled => (
          AppColors.warning,
          'Отменено',
          Icons.cancel_outlined
        ),
    };

    return GlassCard(
      key: Key('job-${job.fileName}'),
      accent: job.status == DownloadStatus.done
          ? AppColors.tertiary
          : job.status == DownloadStatus.failed
              ? AppColors.error
              : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 19),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  job.title ?? job.fileName,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13.5,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              StatusPill(label: label, color: color),
            ],
          ),
          if (job.status == DownloadStatus.running) ...[
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: job.progress <= 0 ? null : job.progress,
                minHeight: 6,
                backgroundColor: AppColors.stroke,
                valueColor: const AlwaysStoppedAnimation(AppColors.primary),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '${(job.progress * 100).clamp(0, 100).toStringAsFixed(0)} %',
              style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
            ),
          ],
          const SizedBox(height: 8),
          Text(
            job.url,
            style: const TextStyle(fontSize: 10.5, color: AppColors.textMuted),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          if (job.status == DownloadStatus.done) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                FilledButton.tonalIcon(
                  onPressed: () => Share.shareXFiles(
                    [XFile(job.outputPath)],
                    subject: job.fileName,
                  ),
                  icon: const Icon(Icons.ios_share, size: 16),
                  label: const Text('Поделиться'),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: () => showAudioCheck(context, job),
                  icon: const Icon(Icons.graphic_eq, size: 16),
                  label: const Text('Проверить звук'),
                ),
              ],
            ),
          ],
          if (job.status == DownloadStatus.failed) ...[
            const SizedBox(height: 10),
            // Material нужен, чтобы ink-эффекты ListTile не прятались
            // за полупрозрачной подложкой GlassCard.
            Material(
              color: Colors.transparent,
              child: Theme(
                data: Theme.of(context)
                    .copyWith(dividerColor: Colors.transparent),
                child: ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  childrenPadding: EdgeInsets.zero,
                  title: const Text('Лог ffmpeg',
                      style: TextStyle(fontSize: 12.5)),
                  children: [
                    MonoBlock(text: job.log, maxHeight: 180, dense: true)
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Проверка результата: ffprobe показывает, есть ли аудио.
  static Future<void> showAudioCheck(BuildContext context, DownloadJob job) {
    return showDialog<void>(
      context: context,
      builder: (_) => AudioCheckDialog(job: job),
    );
  }
}

/// Диалог проверки звука.
///
/// Отдельный виджет, а не функция «await ffprobe → показать результат»:
/// так пользователь сразу видит отклик, а тест может проверить оба состояния
/// (загрузка и результат) через [AudioCheckDialog.probeOverride].
class AudioCheckDialog extends StatefulWidget {
  const AudioCheckDialog({super.key, required this.job, this.probeOverride});

  final DownloadJob job;

  /// Подмена ffprobe для тестов: возвращает строку потоков.
  final Future<String> Function(String path)? probeOverride;

  static const Key loadingKey = Key('audio-check-loading');
  static const Key resultKey = Key('audio-check-result');

  @override
  State<AudioCheckDialog> createState() => _AudioCheckDialogState();
}

class _AudioCheckDialogState extends State<AudioCheckDialog> {
  bool _started = false;
  bool loading = true;
  bool fileMissing = false;
  String info = '';

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // InheritedWidget нельзя читать в initState — делаем это здесь.
    if (!_started) {
      _started = true;
      _probe(AppDependencies.of(context).downloadService);
    }
  }

  Future<void> _probe(DownloadEngine engine) async {
    final file = File(widget.job.outputPath);
    final exists = file.existsSync();
    if (!exists && widget.probeOverride == null) {
      if (!mounted) return;
      setState(() {
        fileMissing = true;
        loading = false;
      });
      return;
    }

    final result = await (widget.probeOverride ?? engine.probeAudio)(
      widget.job.outputPath,
    );

    if (!mounted) return;
    setState(() {
      info = result;
      loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final hasAudio = info.contains('audio');

    return AlertDialog(
      title: Text(
        loading
            ? 'Проверяю дорожки…'
            : fileMissing
                ? 'Файл не найден'
                : hasAudio
                    ? 'Аудиодорожка есть'
                    : 'Аудио не найдено',
      ),
      icon: loading
          ? const SizedBox(
              key: AudioCheckDialog.loadingKey,
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Icon(
              fileMissing
                  ? Icons.help_outline
                  : hasAudio
                      ? Icons.graphic_eq
                      : Icons.hearing_disabled,
              color: fileMissing
                  ? AppColors.warning
                  : hasAudio
                      ? AppColors.tertiary
                      : AppColors.error,
            ),
      content: loading
          ? null
          : MonoBlock(
              key: AudioCheckDialog.resultKey,
              text: fileMissing
                  ? 'Файл удалён или перемещён:\n${widget.job.outputPath}'
                  : info.isEmpty
                      ? 'ffprobe не вернул данные о потоках'
                      : info,
            ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Ок'),
        ),
      ],
    );
  }
}
