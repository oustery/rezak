import 'package:flutter_test/flutter_test.dart';
import 'package:rezak/services/manifest_parser.dart';
import 'package:rezak/services/players_api.dart';

void main() {
  group('PlayersApi.extractKinopoiskId', () {
    test('принимает голый ID', () {
      expect(PlayersApi.extractKinopoiskId('4640303'), '4640303');
    });

    test('достаёт ID из ссылки iframe.cloud', () {
      expect(
        PlayersApi.extractKinopoiskId('https://iframe.cloud/see/4640303'),
        '4640303',
      );
    });

    test('работает с query-параметрами и слэшем на конце', () {
      expect(
        PlayersApi.extractKinopoiskId('https://iframe.cloud/see/4640303/?x=1'),
        '4640303',
      );
    });

    test('достаёт последнее число из произвольной ссылки', () {
      expect(
        PlayersApi.extractKinopoiskId('https://www.kinopoisk.ru/film/4640303/'),
        '4640303',
      );
    });

    test('возвращает null на мусоре', () {
      expect(PlayersApi.extractKinopoiskId('привет'), isNull);
      expect(PlayersApi.extractKinopoiskId('   '), isNull);
      expect(PlayersApi.extractKinopoiskId('12'), isNull);
    });

    test('обрезает пробелы вокруг ID', () {
      expect(PlayersApi.extractKinopoiskId('  4640303  '), '4640303');
    });
  });

  group('ManifestParser: HLS', () {
    const masterWithAudio = '''
#EXTM3U
#EXT-X-VERSION:3
#EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="aud",NAME="Русский",LANGUAGE="ru",DEFAULT=YES,URI="audio/ru.m3u8"
#EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="aud",NAME="English",LANGUAGE="en",URI="audio/en.m3u8"
#EXT-X-STREAM-INF:BANDWIDTH=5200000,RESOLUTION=1920x1080,AUDIO="aud"
video/1080/index.m3u8
#EXT-X-STREAM-INF:BANDWIDTH=2400000,RESOLUTION=1280x720,AUDIO="aud"
video/720/index.m3u8
''';

    test('находит обе аудиодорожки и абсолютные ссылки на них', () {
      final result = ManifestParser.parse(
        masterWithAudio,
        'https://cdn.example/hls/master.m3u8',
      );

      expect(result.isHls, isTrue);
      expect(result.hasAudioGroup, isTrue);
      expect(result.audioTracks.length, 2);
      expect(result.audioTracks.first.name, 'Русский');
      expect(result.audioTracks.first.isDefault, isTrue);
      expect(result.audioTracks.first.url,
          'https://cdn.example/hls/audio/ru.m3u8');
      expect(
          result.audioTracks.last.url, 'https://cdn.example/hls/audio/en.m3u8');
      expect(result.summary, contains('Аудиодорожек найдено: 2'));
    });

    test('разбирает качества и битрейт', () {
      final result = ManifestParser.parse(
        masterWithAudio,
        'https://cdn.example/hls/master.m3u8',
      );

      expect(result.variants.length, 2);
      expect(result.variants.first.resolution, '1920x1080');
      expect(result.variants.first.bandwidth, 5200000);
      expect(result.variants.first.label, contains('1080'));
      expect(result.variants.last.url,
          'https://cdn.example/hls/video/720/index.m3u8');
    });

    test('предупреждает, если аудиогруппы в master нет', () {
      const master = '''
#EXTM3U
#EXT-X-STREAM-INF:BANDWIDTH=1200000,RESOLUTION=854x480
480/index.m3u8
''';
      final result = ManifestParser.parse(master, 'https://cdn.example/m.m3u8');
      expect(result.hasAudioGroup, isFalse);
      expect(result.separateAudioWarning, isTrue);
      expect(result.summary, contains('проверьте'));
    });

    test('не считает медиа-плейлист мастером', () {
      const media = '''
#EXTM3U
#EXT-X-TARGETDURATION:6
#EXTINF:6.0,
seg1.ts
#EXTINF:6.0,
seg2.ts
#EXT-X-ENDLIST
''';
      final result =
          ManifestParser.parse(media, 'https://cdn.example/v/720.m3u8');
      expect(result.variants, isEmpty);
      expect(result.separateAudioWarning, isFalse);
    });

    test('абсолютизирует относительные URI', () {
      const master = '''
#EXTM3U
#EXT-X-STREAM-INF:BANDWIDTH=800000,RESOLUTION=640x360
../v/360.m3u8
''';
      final result = ManifestParser.parse(
        master,
        'https://cdn.example/a/b/master.m3u8',
      );
      expect(result.variants.first.url, 'https://cdn.example/a/v/360.m3u8');
    });

    test('IGNORES не-AUDIO дорожки (например SUBTITLES)', () {
      const master = '''
#EXTM3U
#EXT-X-MEDIA:TYPE=SUBTITLES,GROUP-ID="subs",NAME="Русские",URI="subs/ru.m3u8"
#EXT-X-STREAM-INF:BANDWIDTH=900000,RESOLUTION=1280x720
720/index.m3u8
''';
      final result = ManifestParser.parse(master, 'https://cdn.example/m.m3u8');
      expect(result.audioTracks, isEmpty);
    });
  });

  group('ManifestParser: DASH и мусор', () {
    test('узнаёт DASH-манифест', () {
      const mpd =
          '<?xml version="1.0"?><MPD xmlns="urn:mpeg:dash:schema:mpd:2011"></MPD>';
      final result =
          ManifestParser.parse(mpd, 'https://cdn.example/manifest.mpd');
      expect(result.isDash, isTrue);
      expect(result.summary, contains('DASH'));
    });

    test('отдаёт unknown на HTML-заглушку', () {
      final result = ManifestParser.parse('<html>403</html>', 'https://x/y');
      expect(result.kind, 'unknown');
      expect(result.summary, contains('не удался'));
    });
  });
}
