/// 境界: App Store Connect API(JSON:API形式)の薄いHTTPクライアント。
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'package:store_cli/asc/asc_jwt.dart';
import 'package:store_cli/asc/asc_models.dart';

/// App Store Connect API がエラーを返した。レスポンス本文の `errors[]` を
/// そのまま見せる(握り潰さない)。
final class AscApiException implements Exception {
  AscApiException({
    required this.method,
    required this.path,
    required this.status,
    required this.body,
  });

  final String method;
  final String path;
  final int status;
  final String body;

  @override
  String toString() {
    final details = <String>[];
    try {
      final errors = (jsonDecode(body) as Json)['errors'] as List<dynamic>?;
      for (final error in errors ?? const []) {
        final e = error as Json;
        details.add('  - ${e['code']}: ${e['title']} / ${e['detail']}');
      }
    } on FormatException {
      details.add('  $body');
    }
    return [
      'App Store Connect API がエラーを返しました: $method $path → $status',
      ...details,
    ].join('\n');
  }
}

final class AscClient {
  AscClient(
    this._credentials, {
    http.Client? httpClient,
    DateTime Function()? now,
  }) : _http = httpClient ?? http.Client(),
       _now = now ?? DateTime.now;

  static final _base = Uri.parse('https://api.appstoreconnect.apple.com/v1/');

  final AscCredentials _credentials;
  final http.Client _http;
  final DateTime Function() _now;

  String? _token;
  DateTime? _tokenIssuedAt;

  /// 有効期限の手前(残り2分)で作り直す。長いアップロードの途中で切れないようにする。
  String get _bearer {
    final now = _now();
    final issuedAt = _tokenIssuedAt;
    if (_token == null ||
        issuedAt == null ||
        now.difference(issuedAt) >
            ascTokenLifetime - const Duration(minutes: 2)) {
      _token = buildAscJwt(_credentials, now: now);
      _tokenIssuedAt = now;
    }
    return _token!;
  }

  Future<Json> get(String path, [Map<String, String>? query]) async =>
      (await _send(
        'GET',
        _base.resolve(path).replace(queryParameters: query),
      ))!;

  /// 一覧を `links.next` をたどって全件取得する。
  Future<List<AscResource>> getAll(
    String path, [
    Map<String, String>? query,
  ]) async {
    final items = <AscResource>[];
    // limit は付けない(上限がエンドポイントごとに違い、超えると400になる)。
    // 既定のページ幅のまま links.next をたどる。
    Uri? next = _base.resolve(path).replace(queryParameters: query);
    while (next != null) {
      final page = (await _send('GET', next))!;
      items.addAll([
        for (final data in page['data'] as List<dynamic>)
          AscResource.fromJson(data as Json),
      ]);
      final link = (page['links'] as Json?)?['next'] as String?;
      next = link == null ? null : Uri.parse(link);
    }
    return items;
  }

  Future<AscResource> post(String path, Json body) async =>
      AscResource.fromJson(
        (await _send('POST', _base.resolve(path), body))!['data'] as Json,
      );

  Future<void> patch(String path, Json body) =>
      _send('PATCH', _base.resolve(path), body);

  Future<void> delete(String path) => _send('DELETE', _base.resolve(path));

  /// スクリーンショットの実体を、予約時に返されたURLへ送る(ASCの認証ヘッダは付けない)。
  Future<void> upload(AscUploadOperation op, Uint8List bytes) async {
    final request = http.Request(op.method, Uri.parse(op.url))
      ..headers.addAll(op.requestHeaders)
      ..bodyBytes = Uint8List.sublistView(
        bytes,
        op.offset,
        op.offset + op.length,
      );
    final response = await http.Response.fromStream(await _http.send(request));
    if (response.statusCode >= 300) {
      throw AscApiException(
        method: op.method,
        path: '(アップロード先)',
        status: response.statusCode,
        body: response.body,
      );
    }
  }

  Future<Json?> _send(String method, Uri uri, [Json? body]) async {
    final request = http.Request(method, uri)
      ..headers['Authorization'] = 'Bearer $_bearer';
    if (body != null) {
      request
        ..headers['Content-Type'] = 'application/json'
        ..body = jsonEncode(body);
    }
    final response = await http.Response.fromStream(await _http.send(request));
    if (response.statusCode >= 300) {
      throw AscApiException(
        method: method,
        path: uri.path,
        status: response.statusCode,
        body: response.body,
      );
    }
    if (response.body.isEmpty) return null;
    return jsonDecode(utf8.decode(response.bodyBytes)) as Json;
  }

  void close() => _http.close();
}
