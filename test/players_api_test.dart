import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rezak/services/players_api.dart';

/// Подменяет транспорт Dio: сеть не нужна, ответ задаётся в тесте.
class _StubAdapter implements HttpClientAdapter {
  _StubAdapter(this.body, {this.statusCode = 200});

  final Object body; // String или Map — как будто пришло от сервера
  final int statusCode;
  RequestOptions? lastRequest;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    lastRequest = options;
    final payload = body is String ? body as String : jsonEncode(body);
    return ResponseBody.fromString(
      payload,
      statusCode,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

PlayersApi _api(Object body, {int statusCode = 200, _StubAdapter? adapter}) {
  final stub = adapter ?? _StubAdapter(body, statusCode: statusCode);
  final dio = Dio(BaseOptions(baseUrl: 'https://fbphdplay.top'));
  dio.httpClientAdapter = stub;
  return PlayersApi(dio: dio);
}

void main() {
  const sampleResponse = {
    'data': [
      {
        'type': 'Veoveo',
        'iframeUrl': 'https://player.example/balancer?movie_id=1',
        'translations': [
          {
            'name': 'Русский',
            'quality': null,
            'iframeUrl': 'https://player.example/v'
          },
        ],
      },
      {
        'type': 'Turbo',
        'iframeUrl': 'https://turbo.example/embed/x',
        'translations': <String, dynamic>{},
      },
      {
        'type': 'Alloha',
        'iframeUrl': 'https://alloha.example/?token=1',
        'translations': [
          {
            'name': 'Русский',
            'quality': 'WEBRip',
            'iframeUrl': 'https://alloha.example/?t=1'
          },
          {
            'name': 'Оригинал',
            'quality': 'WEB-DL',
            'iframeUrl': 'https://alloha.example/?t=2'
          },
        ],
      },
      // битый элемент: без ссылки — должен быть отброшен
      {'type': 'Broken', 'iframeUrl': '', 'translations': []},
    ],
  };

  group('PlayersApi.fetchByKinopoiskId', () {
    test('парсит data[], отбрасывает записи без ссылки', () async {
      final players = await _api(sampleResponse).fetchByKinopoiskId('4640303');
      expect(players.length, 3);
      expect(players.any((p) => p.type == 'Broken'), isFalse);
    });

    test('сортирует источники в порядке сайта (Turbo первым)', () async {
      final players = await _api(sampleResponse).fetchByKinopoiskId('4640303');
      expect(players.first.type, 'Turbo');
      expect(players.map((p) => p.type), ['Turbo', 'Alloha', 'Veoveo']);
    });

    test('разбирает переводы', () async {
      final players = await _api(sampleResponse).fetchByKinopoiskId('4640303');
      final alloha = players.firstWhere((p) => p.type == 'Alloha');
      expect(alloha.translations.length, 2);
      expect(alloha.translations.first.label, contains('Русский'));
      expect(alloha.translations.first.label, contains('WEBRip'));
    });

    test('передаёт kinopoisk в query-параметрах', () async {
      final adapter = _StubAdapter(sampleResponse);
      await _api(sampleResponse, adapter: adapter).fetchByKinopoiskId('777');
      expect(adapter.lastRequest?.queryParameters['kinopoisk'], '777');
      expect(adapter.lastRequest?.path, '/api/players');
    });

    test('понимает ответ-массив без обёртки data', () async {
      final players = await _api([
        {'type': 'Kodik', 'iframeUrl': 'https://kodik.example/x'},
      ]).fetchByKinopoiskId('1');
      expect(players.single.displayName, contains('Kodik'));
    });

    test('выбрасывает PlayersApiException на неожиданном формате', () async {
      expect(
        () => _api({'unexpected': true}).fetchByKinopoiskId('1'),
        throwsA(isA<PlayersApiException>()),
      );
    });

    test('пробрасывает сетевую ошибку', () async {
      expect(
        () => _api('oops', statusCode: 500).fetchByKinopoiskId('1'),
        throwsA(isA<DioException>()),
      );
    });
  });

  group('displayName и host', () {
    test('маскирует источники в «Плеер N · Источник»', () async {
      final players = await _api(sampleResponse).fetchByKinopoiskId('1');
      final turbo = players.firstWhere((p) => p.type == 'Turbo');
      expect(turbo.displayName, 'Плеер 1 · Turbo');
      expect(turbo.host, 'turbo.example');
    });

    test('неизвестный источник отдаётся как есть', () async {
      final players = await _api([
        {'type': 'Custom', 'iframeUrl': 'https://c.example/x'},
      ]).fetchByKinopoiskId('1');
      expect(players.single.displayName, 'Custom');
    });
  });
}
