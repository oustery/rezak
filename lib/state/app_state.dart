import 'package:flutter/foundation.dart';

import '../services/download_service.dart';

/// Хранилище списка загрузок без внешних state-менеджеров.
/// Наследуется от [ChangeNotifier], поэтому экраны слушают его через
/// `ListenableBuilder`.
class AppState extends ChangeNotifier {
  AppState();

  /// Глобальный экземпляр для продакшена.
  static final AppState instance = AppState();

  final List<DownloadJob> _jobs = <DownloadJob>[];

  List<DownloadJob> get jobs => List.unmodifiable(_jobs);

  int get activeCount => _jobs.where((j) => j.isActive).length;

  int get doneCount =>
      _jobs.where((j) => j.status == DownloadStatus.done).length;

  /// Добавляет задачу или обновляет существующую (ключ — путь к файлу).
  void upsert(DownloadJob job) {
    final index = _jobs.indexWhere((j) => j.outputPath == job.outputPath);
    if (index == -1) {
      _jobs.insert(0, job);
    } else {
      _jobs[index] = job;
    }
    notifyListeners();
  }

  void remove(DownloadJob job) {
    _jobs.removeWhere((j) => j.outputPath == job.outputPath);
    notifyListeners();
  }

  void clearFinished() {
    _jobs.removeWhere((j) =>
        j.status == DownloadStatus.done ||
        j.status == DownloadStatus.cancelled ||
        j.status == DownloadStatus.failed);
    notifyListeners();
  }

  void clearAll() {
    _jobs.clear();
    notifyListeners();
  }
}
