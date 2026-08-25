import 'dart:async';
import 'dart:io' show Platform;

import 'package:app_links/app_links.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show Clipboard;
import 'package:play_install_referrer/play_install_referrer.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'friend_link_service.dart';
import 'navigation_service.dart';

/// Owns the whole "QR code / link opens the right profile" flow described
/// in the project's deep link design doc:
///
///   Case A (app installed):    QR/link -> OS App/Universal Link -> this
///     service extracts the code -> FriendLinkService resolves it against
///     hello-backend -> NavigationService opens the profile.
///   Case B (app not installed): QR/link -> browser -> hello-backend's
///     web landing page (DeepLinkRedirectController) -> store -> install ->
///     first open -> this service reads the code back from the Play
///     Install Referrer (Android) or a same-format clipboard fallback
///     (iOS, best-effort) -> same resolve-and-navigate as Case A.
///
/// A code that arrives before anyone is signed in (cold start straight to
/// Login/Signup) is stashed in SharedPreferences and picked up later by
/// [consumePendingLink] — see main_shell.dart, the one screen every
/// sign-in/signup/session-resume path ends up on.
class DeepLinkService {
  DeepLinkService._();
  static final instance = DeepLinkService._();

  static const _pendingCodeKey = 'deep_link_pending_code';
  static const _referrerCheckedKey = 'deep_link_referrer_checked';
  static const _clipboardCheckedKey = 'deep_link_clipboard_checked';

  final AppLinks _appLinks = AppLinks();
  StreamSubscription<Uri>? _linkSub;
  bool _initialized = false;

  /// Starts listening for App/Universal Link taps and, on Android, checks
  /// the Play Install Referrer once. Call this exactly once, early in
  /// main.dart — before runApp, like Firebase — so a cold-start launch URI
  /// isn't missed.
  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    _linkSub = _appLinks.uriLinkStream.listen(
      _handleUri,
      onError: (Object e) => debugPrint('DeepLinkService stream error: $e'),
    );

    try {
      final initialUri = await _appLinks.getInitialLink();
      if (initialUri != null) await _handleUri(initialUri);
    } catch (e) {
      debugPrint('DeepLinkService.getInitialLink failed: $e');
    }

    if (!kIsWeb && Platform.isAndroid) {
      // Fire-and-forget: only matters on a fresh install (Case B), and
      // must never block startup for the far more common case (already
      // installed) where there's nothing to find.
      unawaited(_checkPlayInstallReferrer());
    }
  }

  void dispose() {
    _linkSub?.cancel();
  }

  Future<void> _handleUri(Uri uri) async {
    final code = _extractCode(uri);
    if (code == null) return;
    await _stashPendingCode(code);
    // Already signed in and running (the common case for a warm tap while
    // the app is alive) — resolve and navigate right away instead of
    // waiting for MainShell to next mount.
    await consumePendingLink();
  }

  /// Understands both `https://<domain>/u/{code}` (the real link — see
  /// FriendLinkService) and the `facetalk://u/{code}` custom-scheme backup
  /// registered alongside it in AndroidManifest.xml/Info.plist, handy for
  /// testing deep links (`adb shell am start -a android.intent.action.VIEW
  /// -d "facetalk://u/CODE"`) without a verified domain. The two put "u" in
  /// different places (a path segment vs. the URI's host, since
  /// `facetalk://u/CODE` parses with host "u"), so both are checked.
  String? _extractCode(Uri uri) {
    if (uri.scheme == 'facetalk' && uri.host == 'u') {
      final segments = uri.pathSegments;
      return segments.isNotEmpty && segments.first.isNotEmpty ? segments.first : null;
    }

    final segments = uri.pathSegments;
    final uIndex = segments.indexOf('u');
    if (uIndex == -1 || uIndex + 1 >= segments.length) return null;
    final code = segments[uIndex + 1];
    return code.isEmpty ? null : code;
  }

  Future<void> _stashPendingCode(String code) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_pendingCodeKey, code);
    } catch (e) {
      debugPrint('DeepLinkService: could not persist pending code: $e');
    }
  }

  /// Android only, and only once per install: recovers the code from the
  /// `&referrer=code%3D...` query param FriendLinkService/the web landing
  /// page put on the Play Store URL. This is what makes Case B resume
  /// without the user having to re-tap the link after installing.
  Future<void> _checkPlayInstallReferrer() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_referrerCheckedKey) == true) {
      return; // Already looked, on this or an earlier launch — a referrer
      // string describes the install itself, so re-reading it on every
      // later launch would keep resurrecting a long-redeemed invite.
    }
    await prefs.setBool(_referrerCheckedKey, true);

    try {
      final details = await PlayInstallReferrer.installReferrer;
      final referrer = details.installReferrer;
      if (referrer == null || referrer.isEmpty) return;

      // installReferrer is a raw query string, e.g. "code=AbC123".
      final params = Uri.splitQueryString(referrer);
      final code = params['code'];
      if (code != null && code.isNotEmpty) {
        await _stashPendingCode(code);
      }
    } catch (e) {
      // Not installed from Play (sideloaded/dev build), or the Play
      // services call failed — nothing to recover either way.
      debugPrint('DeepLinkService: install referrer unavailable: $e');
    }
  }

  /// iOS's best-effort stand-in for the Play Install Referrer above — there
  /// is no free equivalent on iOS to recover an install-time referrer, so
  /// this instead checks whether the system clipboard happens to hold one
  /// of *our own* deep links (the web landing page copies its link there
  /// when "Download on the App Store" is tapped — see deep-link.blade.php).
  /// Deliberately narrow: only ever acts on text that parses as our own
  /// `/u/{code}` shape, and only reads the clipboard once per fresh signup
  /// (see [_clipboardCheckedKey]) — never on every launch, since reading
  /// the clipboard surfaces iOS's "Pasted from Safari" banner and doing
  /// that repeatedly would just be noise for the vast majority of signups
  /// that have nothing to do with an invite.
  ///
  /// Call this once, right after a brand-new account finishes signing up
  /// (AuthService.register / the isNewUser branch of loginWithGoogle) —
  /// not on every login, where there's nothing to recover.
  Future<void> checkClipboardFallback() async {
    if (kIsWeb || !Platform.isIOS) return;

    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_clipboardCheckedKey) == true) return;
    await prefs.setBool(_clipboardCheckedKey, true);

    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      final text = data?.text?.trim();
      if (text == null || text.isEmpty) return;

      final uri = Uri.tryParse(text);
      if (uri == null || !uri.hasScheme) return;
      final code = _extractCode(uri);
      if (code == null) return;

      await _stashPendingCode(code);
      await consumePendingLink();
    } catch (e) {
      debugPrint('DeepLinkService: clipboard fallback unavailable: $e');
    }
  }

  /// Resolves and navigates to whatever deep link is pending, if any and if
  /// someone is actually signed in yet. Safe to call liberally — a no-op
  /// when there's nothing pending. Called from:
  ///  - here, right after a live App/Universal Link tap;
  ///  - main_shell.dart's initState, covering "the link arrived before
  ///    login/signup finished" and "the app was killed with a link still
  ///    pending".
  Future<void> consumePendingLink() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return; // Not signed in yet — leave it pending.

    String? code;
    try {
      final prefs = await SharedPreferences.getInstance();
      code = prefs.getString(_pendingCodeKey);
      if (code == null || code.isEmpty) return;
      await prefs.remove(_pendingCodeKey); // consume once, win or lose
    } catch (e) {
      debugPrint('DeepLinkService: could not read pending code: $e');
      return;
    }

    final resolved = await FriendLinkService.instance.resolveDeepLinkCode(code);
    if (resolved == null || resolved.uid.isEmpty || resolved.uid == uid) {
      return; // Expired/invalid code, or it's the signed-in user's own link.
    }

    NavigationService.openFriendProfile(resolved.uid, source: 'link');
  }
}
