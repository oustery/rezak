import 'dart:convert';

import 'package:dio/dio.dart';

import '../models/player_source.dart';

/// Клиент того же самого API, который использует сама страница iframe.cloud.
///
/// Важно: iframe.cloud не хранит видео — он лишь отдаёт список встраиваемых
/// плееров. Поэтому «скачивать из сервиса» = получить iframeUrl и уже внутри
/// плеера найти HLS/DASH-плейлист со звуком.
/// Контракт клиента API: позволяет подменить сеть в тестах.
abstract class PlayersRepository {
  Future<List<PlayerSource>> fetchByKinopoiskId(String kinopoiskId);
}

class PlayersApi implements PlayersRepository {
  PlayersApi({Dio? dio})
      : _dio = dio ??
            Dio(
              BaseOptions(
                baseUrl: 'https://fbphdplay.top',
                connectTimeout: const Duration(seconds: 15),
                receiveTimeout: const Duration(seconds: 20),
                headers: const {
                  'Accept': 'application/json',
                  // Тот же UA, что у мобильного браузера: часть источников
                  // отсекает «серверные» запросы по заголовкам.
                  'User-Agent':
                      'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 '
                          '(KHTML, like Gecko) Chrome/120.0 Mobile Safari/537.36',
                },
              ),
            );

  final Dio _dio;

  /// [kinopoiskId] — числовой ID фильма/сериала на Кинопоиске
  /// (он же последний сегмент ссылки вида https://iframe.cloud/see/{id}).
  @override
  Future<List<PlayerSource>> fetchByKinopoiskId(String kinopoiskId) async {
    final response = await _dio.get<dynamic>(
      '/api/players',
      queryParameters: {'kinopoisk': kinopoiskId},
    );

    final raw = response.data;
    final decoded = raw is String ? jsonDecode(raw) : raw;

    late final List<dynamic> list;
    if (decoded is List) {
      list = decoded;
    } else if (decoded is Map && decoded['data'] is List) {
      list = decoded['data'] as List;
    } else {
      throw PlayersApiException('Неожиданный формат ответа API');
    }

    // Имена источников для сортировки «как на сайте».
    const preferred = [
      'Turbo',
      'Collaps',
      'Alloha',
      'Videocdn',
      'Vibix',
      'Hdvb',
      'Kodik',
      'Veoveo',
    ];

    final players = <PlayerSource>[];
    for (final item in list) {
      if (item is! Map<String, dynamic>) continue;
      final player = PlayerSource.fromJson(item);
      if (!player.iframeUrl.startsWith('http')) continue;
      players.add(player);
    }

    int position(PlayerSource p) {
      final index = preferred.indexOf(p.type);
      return index == -1 ? preferred.length : index;
    }

    players.sort((a, b) => position(a).compareTo(position(b)));
    return players;
  }

  /// Достаёт ID из ссылки вида `https://iframe.cloud/see/4640303`
  /// или принимает «голый» числовой ID.
  static String? extractKinopoiskId(String input) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) return null;
    final direct = RegExp(r'^\d{3,}$');
    if (direct.hasMatch(trimmed)) return trimmed;

    final fromUrl = RegExp(r'/(\d{3,})/?$');
    final match = fromUrl.firstMatch(trimmed);
    if (match != null) return match.group(1);

    final digits = RegExp(r'\d{3,}').allMatches(trimmed).toList();
    if (digits.isEmpty) return null;
    return digits.last.group(0);
  }
}

class PlayersApiException implements Exception {
  PlayersApiException(this.message);

  final String message;

  @override
  String toString() => message;
}
