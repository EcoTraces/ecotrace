import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

import 'api_config.dart';

class ApiException implements Exception {
  const ApiException(this.statusCode, this.message, {this.code});

  final int statusCode;
  final String message;
  final String? code;

  @override
  String toString() => 'ApiException($statusCode, $code): $message';
}

class ApiClient {
  ApiClient({String? baseUrl, FirebaseAuth? auth, http.Client? httpClient})
    : _baseUrl = (baseUrl ?? ApiConfig.baseUrl).replaceAll(RegExp(r'/+$'), ''),
      _auth = auth ?? FirebaseAuth.instance,
      _http = httpClient ?? http.Client();

  static final instance = ApiClient();

  final String _baseUrl;
  final FirebaseAuth _auth;
  final http.Client _http;

  Uri _uri(String path, [Map<String, String>? query]) {
    if (_baseUrl.isEmpty) {
      throw StateError('API_BASE_URL is not configured.');
    }
    final normalized = path.startsWith('/') ? path : '/$path';
    return Uri.parse('$_baseUrl$normalized').replace(queryParameters: query);
  }

  Future<Map<String, String>> _headers({
    required bool authenticated,
    bool forceRefresh = false,
  }) async {
    final headers = <String, String>{
      'accept': 'application/json',
      'content-type': 'application/json',
    };
    if (authenticated) {
      final token = await _auth.currentUser?.getIdToken(forceRefresh);
      if (token == null) throw const ApiException(401, 'Sign in is required.');
      headers['authorization'] = 'Bearer $token';
    }
    return headers;
  }

  Future<List<Map<String, dynamic>>> getList(
    String path, {
    bool authenticated = true,
    Map<String, String>? query,
  }) async {
    var response = await _http.get(
      _uri(path, query),
      headers: await _headers(authenticated: authenticated),
    );
    if (authenticated && response.statusCode == 401) {
      response = await _http.get(
        _uri(path, query),
        headers: await _headers(authenticated: true, forceRefresh: true),
      );
    }
    await _invalidateExpiredSession(response, authenticated: authenticated);
    final body = _decode(response);
    final data = body['data'];
    if (data is! List) throw const FormatException('API data is not a list.');
    return data.map((item) => Map<String, dynamic>.from(item as Map)).toList();
  }

  Future<Map<String, dynamic>> get(
    String path, {
    bool authenticated = true,
    Map<String, String>? query,
  }) async {
    var response = await _http.get(
      _uri(path, query),
      headers: await _headers(authenticated: authenticated),
    );
    if (authenticated && response.statusCode == 401) {
      response = await _http.get(
        _uri(path, query),
        headers: await _headers(authenticated: true, forceRefresh: true),
      );
    }
    await _invalidateExpiredSession(response, authenticated: authenticated);
    final body = _decode(response);
    return Map<String, dynamic>.from(body['data'] as Map? ?? const {});
  }

  Future<Map<String, dynamic>> post(
    String path,
    Map<String, dynamic> payload,
  ) async {
    var response = await _http.post(
      _uri(path),
      headers: await _headers(authenticated: true),
      body: jsonEncode(payload),
    );
    if (response.statusCode == 401) {
      response = await _http.post(
        _uri(path),
        headers: await _headers(authenticated: true, forceRefresh: true),
        body: jsonEncode(payload),
      );
    }
    await _invalidateExpiredSession(response);
    final body = _decode(response);
    return Map<String, dynamic>.from(body['data'] as Map? ?? const {});
  }

  Future<Map<String, dynamic>> patch(
    String path,
    Map<String, dynamic> payload,
  ) async {
    var response = await _http.patch(
      _uri(path),
      headers: await _headers(authenticated: true),
      body: jsonEncode(payload),
    );
    if (response.statusCode == 401) {
      response = await _http.patch(
        _uri(path),
        headers: await _headers(authenticated: true, forceRefresh: true),
        body: jsonEncode(payload),
      );
    }
    await _invalidateExpiredSession(response);
    final body = _decode(response);
    return Map<String, dynamic>.from(body['data'] as Map? ?? const {});
  }

  Future<void> delete(String path, {Map<String, dynamic>? payload}) async {
    var response = await _deleteRequest(path, payload: payload);
    if (response.statusCode == 401) {
      response = await _deleteRequest(
        path,
        payload: payload,
        forceRefresh: true,
      );
    }
    await _invalidateExpiredSession(response);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      _decode(response);
    }
  }

  Future<void> _invalidateExpiredSession(
    http.Response response, {
    bool authenticated = true,
  }) async {
    if (authenticated &&
        response.statusCode == 401 &&
        _auth.currentUser != null) {
      await _auth.signOut();
    }
  }

  Future<http.Response> _deleteRequest(
    String path, {
    Map<String, dynamic>? payload,
    bool forceRefresh = false,
  }) async {
    final request = http.Request('DELETE', _uri(path));
    request.headers.addAll(
      await _headers(authenticated: true, forceRefresh: forceRefresh),
    );
    if (payload != null) request.body = jsonEncode(payload);
    return http.Response.fromStream(await _http.send(request));
  }

  Map<String, dynamic> _decode(http.Response response) {
    final body = response.body.isEmpty
        ? <String, dynamic>{}
        : Map<String, dynamic>.from(jsonDecode(response.body) as Map);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final error = body['error'] as Map?;
      throw ApiException(
        response.statusCode,
        error?['message']?.toString() ?? 'The API request failed.',
        code: error?['code']?.toString(),
      );
    }
    return body;
  }
}
