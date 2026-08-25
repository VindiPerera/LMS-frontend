import 'package:http/http.dart' as http;
import 'dart:convert';
import '../config/api_config.dart';
import '../models/user.dart';

/// The result of resolving a scanned/tapped FaceTalk deep link — see
/// [FriendLinkService.resolveCode].
class ResolvedDeepLink {
  final String uid;
  final String? name;
  final String? handle;
  final String? avatarUrl;

  const ResolvedDeepLink({
    required this.uid,
    this.name,
    this.handle,
    this.avatarUrl,
  });
}

/// Builds and resolves the short links behind the "Add Friend via QR Code"
/// feature (my_qr_code_screen.dart / scan_qr_screen.dart) and the tap-to-
/// open-app flow (deep_link_service.dart).
///
/// hello-backend (Laravel) mints and resolves the short code — see
/// DeepLinkController there. This class deliberately does NOT use
/// firebase_dynamic_links: Google shut that service down in August 2025, so
/// it can no longer create or resolve links at all. The backend-minted
/// `https://hellotalk.jaan.lk/u/{code}` link below is a real tap-to-open
/// link once Android App Links / iOS Universal Links are verified for that
/// domain (see AndroidManifest.xml's intent-filter and
/// ios/Runner/Runner.entitlements) — every call site already goes through
/// this one class, so nothing else needs to change when that happens.
class FriendLinkService {
  FriendLinkService._();
  static final instance = FriendLinkService._();

  /// Generates (or reuses) this user's shareable "add me" link/QR payload.
  /// Idempotent per user — calling this again returns the same permanent
  /// link, just with a refreshed name/handle/avatar snapshot server-side,
  /// so an already-shared/printed QR code never breaks.
  Future<String> generateFriendLink(AppUser user) async {
    if (user.id.isEmpty) return '';
    try {
      final response = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/api/deep-links'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'type': 'add_friend',
          'uid': user.id,
          'name': user.name,
          'handle': user.handle,
          'avatar_url': user.avatarUrl,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final code = data['deepLink']?['code'] as String?;
        if (code != null && code.isNotEmpty) {
          return '${ApiConfig.baseUrl}/u/$code';
        }
      }
    } catch (_) {
      // Offline/backend down — fall through to the local fallback below.
    }

    // The backend is what makes this a real tap-to-open link (and gives it
    // a short code) — but if it's unreachable, still hand back *something*
    // scannable/shareable rather than an empty QR code. scan_qr_screen.dart
    // understands this shape too (see [resolveCode]).
    return '${ApiConfig.baseUrl}/add-friend?friendId=${user.id}';
  }

  /// Resolves a scanned/tapped QR/link back to the user it points at.
  /// Understands two shapes:
  ///  - `.../u/{code}` — the real short link, resolved via the backend.
  ///  - `.../add-friend?friendId=...` — the offline fallback above, which
  ///    already carries the uid and needs no network round trip.
  /// Anything else (an arbitrary URL, a wifi config, a product barcode, ...)
  /// correctly resolves to null instead of being guessed at and treated as
  /// if it were a real user id.
  Future<ResolvedDeepLink?> resolveCode(String rawValue) async {
    final uri = Uri.tryParse(rawValue.trim());
    if (uri == null) return null;

    final friendId = uri.queryParameters['friendId'];
    if (friendId != null && friendId.isNotEmpty) {
      return ResolvedDeepLink(uid: friendId);
    }

    final segments = uri.pathSegments;
    final uIndex = segments.indexOf('u');
    if (uIndex == -1 || uIndex + 1 >= segments.length) return null;
    final code = segments[uIndex + 1];
    if (code.isEmpty) return null;

    return resolveDeepLinkCode(code);
  }

  /// Resolves an already-extracted short code (no URL parsing) — used by
  /// deep_link_service.dart for App/Universal Link taps and Play Install
  /// Referrer, which both hand over the bare code directly.
  Future<ResolvedDeepLink?> resolveDeepLinkCode(String code) async {
    try {
      final response = await http.get(
        Uri.parse('${ApiConfig.baseUrl}/api/deep-links/$code'),
      );
      if (response.statusCode != 200) return null;

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final deepLink = data['deepLink'] as Map<String, dynamic>?;
      final uid = deepLink?['uid'] as String?;
      if (uid == null || uid.isEmpty) return null;

      final payload = deepLink?['payload'] as Map<String, dynamic>? ?? {};
      return ResolvedDeepLink(
        uid: uid,
        name: payload['name'] as String?,
        handle: payload['handle'] as String?,
        avatarUrl: payload['avatarUrl'] as String?,
      );
    } catch (_) {
      return null;
    }
  }
}
