/// Модели данных, которые отдаёт публичный API плееров.
///
/// Пример ответа `GET https://fbphdplay.top/api/players?kinopoisk=4640303`:
/// ```json
/// {"data":[{"type":"Alloha",
///           "iframeUrl":"https://theatre.stravers.live/?token_movie=...",
///           "translations":[{"id":82,"name":"Не требуется","quality":"WEBRip",
///                            "iframeUrl":"https://theatre.stravers.live/?...&translation=82"}]}]}
/// ```
library;

class Translation {
  const Translation({
    required this.name,
    required this.quality,
    required this.iframeUrl,
  });

  final String? name;
  final String? quality;
  final String iframeUrl;

  factory Translation.fromJson(Map<String, dynamic> json) {
    return Translation(
      name: json['name'] as String?,
      quality: json['quality'] as String?,
      iframeUrl: (json['iframeUrl'] as String?) ?? '',
    );
  }

  String get label {
    final parts = <String>[
      if (name != null && name!.trim().isNotEmpty) name!.trim(),
      if (quality != null && quality!.trim().isNotEmpty) quality!.trim(),
    ];
    return parts.isEmpty ? 'Озвучка' : parts.join(' • ');
  }
}

class PlayerSource {
  const PlayerSource({
    required this.type,
    required this.iframeUrl,
    required this.translations,
  });

  /// Внутреннее имя источника: Turbo, Alloha, Collaps, Veoveo, Kodik, ...
  final String type;
  final String iframeUrl;
  final List<Translation> translations;

  factory PlayerSource.fromJson(Map<String, dynamic> json) {
    final rawTranslations = json['translations'];
    final translations = <Translation>[];
    if (rawTranslations is List) {
      for (final item in rawTranslations) {
        if (item is Map<String, dynamic>) {
          final t = Translation.fromJson(item);
          if (t.iframeUrl.isNotEmpty) translations.add(t);
        }
      }
    }
    return PlayerSource(
      type:
          (json['type'] as String?) ?? (json['source'] as String?) ?? 'NoName',
      iframeUrl: (json['iframeUrl'] as String?) ?? '',
      translations: translations,
    );
  }

  /// Человеческое имя источника — сервис маскирует их под «Плеер N»,
  /// но по типу проще понять, с чем имеешь дело.
  String get displayName {
    switch (type.toLowerCase()) {
      case 'turbo':
        return 'Плеер 1 · Turbo';
      case 'collaps':
        return 'Плеер 2 · Collaps';
      case 'alloha':
        return 'Плеер 3 · Alloha';
      case 'videocdn':
        return 'Плеер 4 · Videocdn';
      case 'vibix':
        return 'Плеер 5 · Vibix';
      case 'hdvb':
        return 'Плеер 6 · Hdvb';
      case 'kodik':
        return 'Плеер 7 · Kodik';
      case 'veoveo':
        return 'Плеер 8 · Veoveo';
      default:
        return type;
    }
  }

  String get host {
    final uri = Uri.tryParse(iframeUrl);
    return uri?.host ?? '—';
  }
}
