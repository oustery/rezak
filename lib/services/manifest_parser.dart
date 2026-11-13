/// Разбор HLS master-плейлиста (#EXT-X-MEDIA) и DASH-манифеста (MPD).
///
/// Задача модуля — понять ДО скачивания, лежит ли звук отдельной дорожкой,
/// чтобы потом собрать правильную команду ffmpeg и не получить немой файл.
library;

class HlsVariant {
  const HlsVariant({
    required this.url,
    this.resolution,
    this.bandwidth,
    this.audioGroup,
  });

  final String url;
  final String? resolution;
  final int? bandwidth;
  final String? audioGroup;

  String get label {
    final r = resolution ?? 'auto';
    final mbps =
        bandwidth == null ? null : (bandwidth! / 1000000).toStringAsFixed(1);
    return mbps == null ? r : '$r · $mbps Мбит/с';
  }
}

class HlsAudioTrack {
  const HlsAudioTrack({
    required this.name,
    required this.url,
    this.language,
    this.isDefault = false,
  });

  final String name;
  final String url;
  final String? language;
  final bool isDefault;
}

class StreamProbeResult {
  StreamProbeResult({
    required this.kind,
    required this.masterUrl,
    this.variants = const [],
    this.audioTracks = const [],
    this.separateAudioWarning = false,
    this.raw = '',
  });

  /// 'hls' | 'dash' | 'unknown'
  final String kind;
  final String masterUrl;
  final List<HlsVariant> variants;
  final List<HlsAudioTrack> audioTracks;

  /// true, когда в master-плейлисте нет #EXT-X-MEDIA, но есть варианты —
  /// звук может быть в отдельном плейлисте, который надо передать вручную.
  final bool separateAudioWarning;
  final String raw;

  bool get hasAudioGroup => audioTracks.isNotEmpty;

  bool get isHls => kind == 'hls';
  bool get isDash => kind == 'dash';

  String get summary {
    if (isDash) return 'DASH-манифест: видео и аудио в разных AdaptationSet';
    if (hasAudioGroup) {
      final names = audioTracks.map((t) => t.name).join(', ');
      return 'Аудиодорожек найдено: ${audioTracks.length} ($names)';
    }
    if (separateAudioWarning) {
      return 'Отдельной аудиогруппы нет — проверьте, есть ли звук в сегментах';
    }
    return 'Разбор не удался';
  }
}

class ManifestParser {
  /// Абсолютизирует относительные URI из плейлиста.
  static String _resolve(String base, String ref) {
    final baseUri = Uri.parse(base);
    return baseUri.resolve(ref).toString();
  }

  /// Разбирает текст master-плейлиста (.m3u8) или манифеста (.mpd).
  static StreamProbeResult parse(String text, String masterUrl) {
    if (text.contains('#EXTM3U')) {
      return _parseHls(text, masterUrl);
    }
    if (text.contains('<MPD')) {
      return StreamProbeResult(
        kind: 'dash',
        masterUrl: masterUrl,
        raw: text,
      );
    }
    return StreamProbeResult(kind: 'unknown', masterUrl: masterUrl, raw: text);
  }

  static StreamProbeResult _parseHls(String text, String masterUrl) {
    final lines = text
        .split(RegExp(r'\r?\n'))
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();

    final audioTracks = <HlsAudioTrack>[];
    final variants = <HlsVariant>[];

    String? pendingVariantAudioGroup;
    String? pendingResolution;
    int? pendingBandwidth;

    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];

      if (line.startsWith('#EXT-X-MEDIA:')) {
        final attrs = _parseAttributes(line.substring('#EXT-X-MEDIA:'.length));
        if ((attrs['TYPE'] ?? '').toUpperCase() == 'AUDIO') {
          final uri = attrs['URI'];
          if (uri != null && uri.isNotEmpty) {
            audioTracks.add(
              HlsAudioTrack(
                name: attrs['NAME'] ?? attrs['LANGUAGE'] ?? 'audio',
                url: _resolve(masterUrl, uri),
                language: attrs['LANGUAGE'],
                isDefault: (attrs['DEFAULT'] ?? '').toUpperCase() == 'YES',
              ),
            );
          }
        }
        continue;
      }

      if (line.startsWith('#EXT-X-STREAM-INF:')) {
        final attrs =
            _parseAttributes(line.substring('#EXT-X-STREAM-INF:'.length));
        pendingVariantAudioGroup = attrs['AUDIO'];
        pendingResolution = attrs['RESOLUTION'];
        pendingBandwidth = int.tryParse(attrs['BANDWIDTH'] ?? '');
        continue;
      }

      if (line.startsWith('#')) continue;

      // Строка без '#' после STREAM-INF — это URI варианта.
      if (pendingResolution != null ||
          pendingBandwidth != null ||
          pendingVariantAudioGroup != null) {
        variants.add(
          HlsVariant(
            url: _resolve(masterUrl, line),
            resolution: pendingResolution,
            bandwidth: pendingBandwidth,
            audioGroup: pendingVariantAudioGroup,
          ),
        );
        pendingResolution = null;
        pendingBandwidth = null;
        pendingVariantAudioGroup = null;
      }
    }

    final isMaster = variants.isNotEmpty;
    return StreamProbeResult(
      kind: 'hls',
      masterUrl: masterUrl,
      variants: variants,
      audioTracks: audioTracks,
      separateAudioWarning: isMaster && audioTracks.isEmpty,
      raw: text,
    );
  }

  /// Разбор строки вида `TYPE=AUDIO,GROUP-ID="aud",NAME="Русский",URI="a.m3u8"`.
  static Map<String, String> _parseAttributes(String input) {
    final result = <String, String>{};
    final regex = RegExp(r'([A-Z0-9-]+)=("[^"]*"|[^,]*)');
    for (final match in regex.allMatches(input)) {
      final key = match.group(1)!;
      var value = match.group(2) ?? '';
      if (value.startsWith('"') && value.endsWith('"') && value.length >= 2) {
        value = value.substring(1, value.length - 1);
      }
      result[key] = value;
    }
    return result;
  }
}
