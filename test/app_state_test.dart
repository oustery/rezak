import 'package:flutter_test/flutter_test.dart';
import 'package:rezak/services/download_service.dart';
import 'package:rezak/state/app_state.dart';

DownloadJob _job(String path, DownloadStatus status) => DownloadJob(
      url: 'https://cdn.example/x.m3u8',
      outputPath: path,
      status: status,
    );

void main() {
  group('AppState', () {
    late AppState state;
    var notifications = 0;

    setUp(() {
      state = AppState();
      notifications = 0;
      state.addListener(() => notifications++);
    });

    test('upsert добавляет новую задачу в начало списка', () {
      state.upsert(_job('/a.mp4', DownloadStatus.running));
      state.upsert(_job('/b.mp4', DownloadStatus.running));

      expect(state.jobs.length, 2);
      expect(state.jobs.first.outputPath, '/b.mp4');
      expect(notifications, 2);
    });

    test('upsert по тому же пути обновляет, а не дублирует', () {
      state.upsert(_job('/a.mp4', DownloadStatus.running));
      state.upsert(_job('/a.mp4', DownloadStatus.done));

      expect(state.jobs.length, 1);
      expect(state.jobs.single.status, DownloadStatus.done);
    });

    test('activeCount считает только активные', () {
      state.upsert(_job('/a.mp4', DownloadStatus.running));
      state.upsert(_job('/b.mp4', DownloadStatus.queued));
      state.upsert(_job('/c.mp4', DownloadStatus.done));
      state.upsert(_job('/d.mp4', DownloadStatus.failed));

      expect(state.activeCount, 2);
      expect(state.doneCount, 1);
    });

    test('clearFinished убирает завершённые/ошибочные, оставляет активные', () {
      state.upsert(_job('/a.mp4', DownloadStatus.running));
      state.upsert(_job('/b.mp4', DownloadStatus.done));
      state.upsert(_job('/c.mp4', DownloadStatus.failed));
      state.upsert(_job('/d.mp4', DownloadStatus.cancelled));

      state.clearFinished();

      expect(state.jobs.length, 1);
      expect(state.jobs.single.outputPath, '/a.mp4');
    });

    test('remove удаляет конкретную задачу', () {
      final job = _job('/a.mp4', DownloadStatus.done);
      state.upsert(job);
      state.remove(job);
      expect(state.jobs, isEmpty);
    });

    test('jobs защищён от внешней мутации', () {
      state.upsert(_job('/a.mp4', DownloadStatus.running));
      expect(
        () => state.jobs.add(_job('/b.mp4', DownloadStatus.done)),
        throwsUnsupportedError,
      );
    });

    test('clearAll очищает всё', () {
      state.upsert(_job('/a.mp4', DownloadStatus.running));
      state.clearAll();
      expect(state.jobs, isEmpty);
    });
  });
}
