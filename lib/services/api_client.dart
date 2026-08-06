import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config/env.dart';

/// A backend error, with the human-readable message Laravel returned
/// (validation message, or a generic one) so screens can show it directly.
class ApiException implements Exception {
  final String message;
  final int? statusCode;

  ApiException(this.message, {this.statusCode});

  @override
  String toString() => message;
}

/// Small JSON/REST wrapper around the Laravel API. Holds the current
/// Sanctum bearer token in memory; AuthService is responsible for
/// persisting/restoring it.
class ApiClient {
  ApiClient._();
  static final ApiClient instance = ApiClient._();

  String? _token;

  void setToken(String? token) => _token = token;

  Uri _uri(String path, [Map<String, dynamic>? query]) {
    final full = '${Env.apiBaseUrl}$path';
    return Uri.parse(full).replace(
      queryParameters: query?.map((key, value) => MapEntry(key, '$value')),
    );
  }

  Map<String, String> get _headers => {
        'Accept': 'application/json',
        'Content-Type': 'application/json',
        if (_token != null) 'Authorization': 'Bearer $_token',
      };

  Future<Map<String, dynamic>> get(String path, {Map<String, dynamic>? query}) async {
    final res = await http.get(_uri(path, query), headers: _headers);
    return _decode(res);
  }

  Future<Map<String, dynamic>> post(String path, [Map<String, dynamic> body = const {}]) async {
    final res = await http.post(_uri(path), headers: _headers, body: jsonEncode(body));
    return _decode(res);
  }

  Future<Map<String, dynamic>> put(String path, Map<String, dynamic> body) async {
    final res = await http.put(_uri(path), headers: _headers, body: jsonEncode(body));
    return _decode(res);
  }

  Map<String, dynamic> _decode(http.Response res) {
    Map<String, dynamic> decoded = const {};
    if (res.body.isNotEmpty) {
      try {
        decoded = jsonDecode(res.body) as Map<String, dynamic>;
      } catch (_) {
        // Non-JSON body (e.g. an HTML error page) — fall through to the
        // generic status-code message below.
      }
    }

    if (res.statusCode >= 200 && res.statusCode < 300) return decoded;

    String message = decoded['message']?.toString() ?? 'Something went wrong (${res.statusCode}).';
    final errors = decoded['errors'];
    if (errors is Map && errors.isNotEmpty) {
      final firstField = errors.values.first;
      if (firstField is List && firstField.isNotEmpty) {
        message = firstField.first.toString();
      }
    }
    throw ApiException(message, statusCode: res.statusCode);
  }
}
