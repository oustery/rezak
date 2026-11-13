import 'dart:async';

/// «Сниффер»: копит найденные в WebView ссылки на потоки.
///
/// Плееры отдают видео адаптивно (HLS `.m3u8`, DASH `.mpd`, иногда прямой `.mp4`),
/// поэтому вручную искать плейлист в мобильном браузере неудобно. Здесь это
/// делает WebView: каждый сетевой запрос проверяется по расширению.
class Sniffer {
  final StreamController<SniffedStream> _controller =
      StreamController<SniffedStream>.broadcast();

  final Map<String, SniffedStream> _found = {};

  Stream<SniffedStream> get stream => _controller.stream;

  List<SniffedStream> get found => _found.values.toList(growable: false);

  static final RegExp _streamPattern = RegExp(
    r'\.(m3u8|mpd|mp4|m4s|ts)(\?|$)',
    caseSensitive: false,
  );

  static final RegExp _audioPattern = RegExp(
    r'(audio|rus|original|orig|voice|dub|_aac|_ac3)',
    caseSensitive: false,
  );

  /// Возвращает true, если ссылка похожа на поток и стоит её показать.
  bool inspect(String url) {
    if (!url.startsWith('http')) return false;
    if (!_streamPattern.hasMatch(url)) return false;
    // Сегменты (.ts/.m4s) не показываем — их будут сотни.
    if (RegExp(r'\.(ts|m4s)(\?|$)', caseSensitive: false).hasMatch(url)) {
      return false;
    }
    if (_found.containsKey(url)) return false;

    final item = SniffedStream(
      url: url,
      kind: RegExp(r'\.m3u8', caseSensitive: false).hasMatch(url)
          ? StreamKind.hls
          : RegExp(r'\.mpd', caseSensitive: false).hasMatch(url)
              ? StreamKind.dash
              : StreamKind.file,
      looksLikeAudio: _audioPattern.hasMatch(url),
    );
    _found[url] = item;
    _controller.emit(item);
    return true;
  }

  void clear() => _found.clear();

  void dispose() => _controller.close();
}

enum StreamKind { hls, dash, file }

class SniffedStream {
  const SniffedStream({
    required this.url,
    required this.kind,
    required this.looksLikeAudio,
  });

  final String url;
  final StreamKind kind;
  final bool looksLikeAudio;

  String get kindLabel {
    switch (kind) {
      case StreamKind.hls:
        return 'HLS';
      case StreamKind.dash:
        return 'DASH';
      case StreamKind.file:
        return 'MP4';
    }
  }

  String get shortUrl {
    final uri = Uri.tryParse(url);
    if (uri == null) return url;
    final path = uri.path.length > 46
        ? '…${uri.path.substring(uri.path.length - 46)}'
        : uri.path;
    return '${uri.host}$path';
  }
}

extension on StreamController<SniffedStream> {
  void emit(SniffedStream item) {
    if (!isClosed) add(item);
  }
}
