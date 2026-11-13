import 'package:flutter_test/flutter_test.dart';
import 'package:rezak/services/sniffer.dart';

void main() {
  group('Sniffer', () {
    late Sniffer sniffer;

    setUp(() => sniffer = Sniffer());
    tearDown(() => sniffer.dispose());

    test('ловит master.m3u8 и определяет тип HLS', () {
      expect(sniffer.inspect('https://cdn.example/hls/master.m3u8'), isTrue);
      expect(sniffer.found.single.kind, StreamKind.hls);
      expect(sniffer.found.single.kindLabel, 'HLS');
    });

    test('ловит DASH-манифест', () {
      expect(
          sniffer.inspect('https://cdn.example/dash/manifest.mpd?t=1'), isTrue);
      expect(sniffer.found.single.kind, StreamKind.dash);
    });

    test('ловит прямой mp4', () {
      expect(sniffer.inspect('https://cdn.example/movie/720.mp4'), isTrue);
      expect(sniffer.found.single.kind, StreamKind.file);
    });

    test('игнорирует сегменты .ts и .m4s', () {
      expect(sniffer.inspect('https://cdn.example/hls/seg1.ts'), isFalse);
      expect(sniffer.inspect('https://cdn.example/hls/seg1.m4s'), isFalse);
      expect(sniffer.found, isEmpty);
    });

    test('игнорирует не-потоки (картинки, скрипты, html)', () {
      expect(sniffer.inspect('https://cdn.example/logo.png'), isFalse);
      expect(sniffer.inspect('https://cdn.example/app.js'), isFalse);
      expect(sniffer.inspect('about:blank'), isFalse);
      expect(sniffer.found, isEmpty);
    });

    test('не дублирует одну и ту же ссылку', () {
      const url = 'https://cdn.example/master.m3u8';
      expect(sniffer.inspect(url), isTrue);
      expect(sniffer.inspect(url), isFalse);
      expect(sniffer.found.length, 1);
    });

    test('помечает вероятную аудиодорожку', () {
      sniffer.inspect('https://cdn.example/audio/ru.m3u8');
      expect(sniffer.found.single.looksLikeAudio, isTrue);
    });

    test('отдаёт события подписчикам', () async {
      final received = <SniffedStream>[];
      final sub = sniffer.stream.listen(received.add);

      sniffer.inspect('https://cdn.example/master.m3u8');
      sniffer.inspect('https://cdn.example/manifest.mpd');
      await Future<void>.delayed(Duration.zero);

      expect(received.length, 2);
      await sub.cancel();
    });

    test('clear() очищает накопленный список', () {
      sniffer.inspect('https://cdn.example/master.m3u8');
      sniffer.clear();
      expect(sniffer.found, isEmpty);
      // после очистки та же ссылка снова принимается
      expect(sniffer.inspect('https://cdn.example/master.m3u8'), isTrue);
    });

    test('shortUrl не ломается на длинном пути', () {
      sniffer.inspect(
        'https://cdn.example/${'a' * 80}/master.m3u8',
      );
      final item = sniffer.found.single;
      expect(item.shortUrl.length, lessThan(80));
      expect(item.shortUrl, contains('cdn.example'));
    });
  });
}
