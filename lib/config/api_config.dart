import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb, kReleaseMode;

/// Global API configuration for connecting to `hello-backend` (Laravel).
class ApiConfig {
  static String? _customBaseUrl;

  /// The live production server — swap this if the real domain ends up
  /// different from what was planned when this was written. Only used for
  /// `--release` builds (see [baseUrl]); local dev (`flutter run`) never
  /// hits this even by accident.
  static const String _prodBaseUrl = 'https://hellotalk.jaan.lk';

  /// Default port for hello-backend. Local dev only — production runs on
  /// standard HTTPS (443, implicit — see [_prodBaseUrl]).
  static int defaultPort = 8000;

  /// Candidate ports to try. Only 8000 is supported.
  static List<int> candidatePorts = [8000];

  /// Set via `--dart-define=API_HOST=192.168.x.x` at `flutter run`/`flutter
  /// build` time — the one piece [baseUrl] genuinely cannot infer on its
  /// own. `10.0.2.2` (the Android-emulator-only loopback alias) and
  /// `127.0.0.1` both only work when the Flutter process and the Laravel
  /// server share a loopback interface, which is true for every case
  /// [baseUrl] already handles automatically below EXCEPT a real physical
  /// phone/tablet — there, the backend is only reachable at the host PC's
  /// actual LAN IP (find it with `ipconfig` on Windows), and nothing at
  /// runtime can discover that IP for you. Without this, every request
  /// from a physical device silently fails to connect.
  static const String _dartDefineHost = String.fromEnvironment('API_HOST');

  /// Override base URL at runtime (e.g. for testing on physical devices with a local LAN IP).
  static void setBaseUrl(String url) {
    _customBaseUrl = url.endsWith('/') ? url.substring(0, url.length - 1) : url;
  }

  /// Automatically picks the correct host depending on whether the app is
  /// running in an Android emulator (10.0.2.2), iOS/web/desktop (127.0.0.1),
  /// a `--dart-define=API_HOST=...` override (needed for a real physical
  /// device — see [_dartDefineHost]), a `--release` build (the live
  /// server, [_prodBaseUrl]), or a custom configured host.
  ///
  /// Priority matters here: `setBaseUrl`/`API_HOST` win even in a release
  /// build (e.g. QA-testing a release APK against a staging backend), but
  /// absent either override, release always means production — there's no
  /// path from a `--release` build to a `10.0.2.2`/`127.0.0.1` dev address.
  static String get baseUrl {
    if (_customBaseUrl != null && _customBaseUrl!.isNotEmpty) {
      return _customBaseUrl!;
    }

    if (_dartDefineHost.isNotEmpty) {
      return 'http://$_dartDefineHost:$defaultPort';
    }

    if (kReleaseMode) {
      return _prodBaseUrl;
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

  /// Gets candidate upload URLs to try, in priority order. Only port 8000 is supported.
  static List<String> get candidateUploadUrls {
    if (_customBaseUrl != null && _customBaseUrl!.isNotEmpty) {
      return ['$_customBaseUrl/api/media/upload'];
    }

    if (_dartDefineHost.isNotEmpty) {
      return ['http://$_dartDefineHost:$defaultPort/api/media/upload'];
    }

    if (kReleaseMode) {
      return ['$_prodBaseUrl/api/media/upload'];
    }

    if (kIsWeb) {
      return [
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
