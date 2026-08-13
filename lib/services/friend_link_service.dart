/// Builds and parses the payload behind the "Add Friend via QR Code"
/// feature (my_qr_code_screen.dart / scan_qr_screen.dart).
///
/// NOTE ON DEEP LINKS: this deliberately does NOT use firebase_dynamic_links.
/// Google shut that service down in August 2025 — it can no longer create or
/// resolve links at all, so wiring it up would ship a feature that looks
/// real but silently does nothing. A real tap-to-open-app link (Android App
/// Links / iOS Universal Links) needs a domain this project controls plus
/// hosting `.well-known/assetlinks.json` / `apple-app-site-association`
/// there, neither of which exists yet. Until that infrastructure exists,
/// `facetalk.app` below is a placeholder — the link is real text you can
/// copy/share, but won't open the app if tapped outside it. The in-app flow
/// (share the QR code, or scan it with scan_qr_screen.dart) works today
/// without any of that. Swap the URL building below for real uriPrefix-based
/// link generation the day App/Universal Links are set up; every call site
/// already goes through this one class.
class FriendLinkService {
  FriendLinkService._();
  static final instance = FriendLinkService._();

  /// Generates this user's shareable "add me" link/QR payload.
  Future<String> generateFriendLink(String userId) async {
    return 'https://facetalk.app/add-friend?friendId=$userId&action=add_friend';
  }

  /// Extracts the friendId from a scanned QR payload. Only understands this
  /// app's own link format (see [generateFriendLink]) — an arbitrary QR code
  /// (a URL, a wifi config, a product barcode, ...) is correctly treated as
  /// "not a FaceTalk code" instead of being guessed at and passed through as
  /// if it were a real user id.
  String? extractFriendId(String rawValue) {
    final uri = Uri.tryParse(rawValue.trim());
    if (uri == null) return null;
    final friendId = uri.queryParameters['friendId'];
    if (friendId == null || friendId.isEmpty) return null;
    return friendId;
  }
}
