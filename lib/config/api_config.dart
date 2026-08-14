import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;

/// Global API configuration for connecting to `hello-backend` (Laravel).
class ApiConfig {
  static String? _customBaseUrl;

  /// Default port for hello-backend (port 8001 is dedicated to hello-backend).
  static int defaultPort = 8001;

  /// Candidate ports to try (8001 first, then 8000).
  static List<int> candidatePorts = [8001, 8000];

  /// Override base URL at runtime (e.g. for testing on physical devices with a local LAN IP).
  static void setBaseUrl(String url) {
    _customBaseUrl = url.endsWith('/') ? url.substring(0, url.length - 1) : url;
  }

  /// Automatically picks the correct host depending on whether the app is
  /// running in an Android emulator (10.0.2.2), iOS/web/desktop (127.0.0.1),
  /// or a custom configured host.
  static String get baseUrl {
    if (_customBaseUrl != null && _customBaseUrl!.isNotEmpty) {
      return _customBaseUrl!;
    }

    if (kIsWeb) {
      return 'http://127.0.0.1:$defaultPort';
    }

    if (Platform.isAndroid) {
      // 10.0.2.2 maps to the host machine's 127.0.0.1 from inside standard Android emulator
      return 'http://10.0.2.2:$defaultPort';
    }

    // iOS Simulator, macOS, Windows, Linux
    return 'http://127.0.0.1:$defaultPort';
  }

  /// Resolves any backend media URL so it matches the current platform host, port, and CORS endpoint.
  static String resolveUrl(String? rawUrl) {
    if (rawUrl == null || rawUrl.isEmpty) return '';
    if (!rawUrl.startsWith('http://') && !rawUrl.startsWith('https://')) return rawUrl;

    try {
      final uri = Uri.parse(rawUrl);
      if (candidatePorts.contains(uri.port) ||
          uri.path.startsWith('/storage') ||
          uri.path.startsWith('/media') ||
          uri.path.startsWith('/api/media')) {
        final currentBase = Uri.parse(baseUrl);
        var path = uri.path;
        if (path.startsWith('/storage/')) {
          path = '/media/file/${path.substring('/storage/'.length)}';
        }

        final resolvedUri = uri.replace(
          scheme: currentBase.scheme,
          host: currentBase.host,
          port: currentBase.port,
          path: path,
        );
        return resolvedUri.toString();
      }
    } catch (_) {}
    return rawUrl;
  }

  /// Gets candidate upload URLs to try in priority order (8001 first, then 8000).
  static List<String> get candidateUploadUrls {
    if (_customBaseUrl != null && _customBaseUrl!.isNotEmpty) {
      return ['$_customBaseUrl/api/media/upload'];
    }

    if (kIsWeb) {
      return [
        'http://127.0.0.1:8001/api/media/upload',
        'http://localhost:8001/api/media/upload',
        'http://127.0.0.1:8000/api/media/upload',
        'http://localhost:8000/api/media/upload',
      ];
    }

    final host = Platform.isAndroid ? '10.0.2.2' : '127.0.0.1';
    return candidatePorts.map((p) => 'http://$host:$p/api/media/upload').toList();
  }

  static String get mediaUploadUrl => '$baseUrl/api/media/upload';

  static String mediaStreamUrl(dynamic id) => '$baseUrl/api/media/$id';
}
