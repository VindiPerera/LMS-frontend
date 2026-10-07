import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:google_sign_in/google_sign_in.dart';
import '../models/user.dart';
import 'deep_link_service.dart';
import 'moment_service.dart';
import 'push_notification_service.dart';
import 'voice_room_service.dart';

/// Result of a successful register/login/Google sign-in.
class AuthResult {
  final AppUser user;
  final bool isNewUser;
  const AuthResult(this.user, {this.isNewUser = false});
}

/// Owns the current session. Firebase Auth persists the session itself (no
/// manual token storage needed, unlike the old Sanctum-based setup); this
/// just layers the app's `users/{uid}` Firestore profile on top of it.
class AuthService {
  AuthService._();
  static final AuthService instance = AuthService._();

  static final _users = FirebaseFirestore.instance.collection('users');

  // How often setOnlineStatus(true) re-fires on its own while the app stays
  // foregrounded, refreshing `lastSeenAt` so presence.dart's staleness
  // check never trips for a user who's actually still here. Comfortably
  // under presenceStaleAfter so a couple of missed beats (brief network
  // blip, app backgrounded briefly on some platforms) don't flip the dot.
  static const _heartbeatInterval = Duration(seconds: 30);
  Timer? _heartbeatTimer;

  AppUser? _currentUser;
  AppUser? get currentUser => _currentUser;
  bool get isLoggedIn => FirebaseAuth.instance.currentUser != null;

  /// Updates the cached user after a profile edit, so other screens reading
  /// [currentUser] see the change without another round-trip.
  void setCurrentUser(AppUser user) => _currentUser = user;

  /// Waits for Firebase Auth to report its (persisted) sign-in state, then
  /// loads the matching Firestore profile if there is one. Called once from
  /// splash_screen.dart on app start.
  Future<AppUser?> init() async {
    // FirebaseAuth.instance.currentUser is populated synchronously as soon
    // as Firebase.initializeApp() resolves (main.dart awaits that before
    // ever reaching this screen) — it reads straight from the native SDK's
    // already-restored persisted session. authStateChanges().first is less
    // reliable here: on some devices (slower storage I/O, heavy OEM skins
    // like MIUI/ColorOS that throttle cold-start work) its very first
    // emission can fire null before the native SDK has actually finished
    // restoring that session from disk — which is what made the splash
    // screen wrongly treat an already-signed-in user as logged out and
    // send them back to the login screen on every reopen. The stream is
    // now only a fallback for the one case where currentUser genuinely
    // isn't populated yet.
    final user = FirebaseAuth.instance.currentUser ??
        await FirebaseAuth.instance.authStateChanges().first;
    if (user == null) return null;
    // Resuming an existing session (the common case — most launches aren't
    // a fresh login) still needs a fresh FCM token registered, per the
    // Moments push-notification setup; register/login already do this via
    // _afterSignIn() for a brand-new sign-in.
    _afterSignIn();
    return refreshCurrentUser();
  }

  /// Re-fetches the current user's profile from Firestore — used by
  /// me_screen.dart so the Profile tab reflects the latest backend state.
  /// Falls back to the existing cached user if the request fails.
  Future<AppUser?> refreshCurrentUser() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return null;
    try {
      final doc = await _users.doc(uid).get();
      if (doc.exists) {
        _currentUser = AppUser.fromJson({...doc.data()!, 'id': doc.id});
      }
    } catch (_) {
      // Offline or Firestore down — keep showing whatever we already have.
    }
    return _currentUser;
  }

  /// [name] is optional — signup_screen.dart no longer asks for a display
  /// name; a placeholder derived from the email is used until the user sets
  /// a real one on create_profile_screen.dart.
  Future<AppUser> register({
    String? name,
    required String email,
    required String password,
    required String role,
  }) async {
    final credential = await FirebaseAuth.instance
        .createUserWithEmailAndPassword(email: email, password: password);
    final uid = credential.user!.uid;
    final displayName = (name != null && name.isNotEmpty)
        ? name
        : email.split('@').first;

    await _users.doc(uid).set({
      'name': displayName,
      'email': email,
      'role': role,
      'handle': await _generateUniqueHandle(displayName),
      'isOnline': false,
      'isVip': false,
      'tags': <String>[],
      'profileCompleted': false,
      'createdAt': FieldValue.serverTimestamp(),
    });

    _afterSignIn();
    // Always a brand-new account (unlike login()) — see DeepLinkService.
    // checkClipboardFallback's doc comment for why this only runs here and
    // in loginWithGoogle's isNewUser branch, never on an ordinary login.
    // ignore: discarded_futures
    DeepLinkService.instance.checkClipboardFallback();
    return (await refreshCurrentUser())!;
  }

  Future<AppUser> login({
    required String email,
    required String password,
  }) async {
    await FirebaseAuth.instance.signInWithEmailAndPassword(
      email: email,
      password: password,
    );
    _afterSignIn();
    final user = await refreshCurrentUser();
    if (user == null) {
      // Auth succeeded but there is no matching Firestore profile — the
      // account may have been created directly in the Firebase console or
      // the document was deleted. Sign out so the app doesn't end up in a
      // half-authenticated state, then surface a clear message.
      await FirebaseAuth.instance.signOut();
      throw FirebaseAuthException(
        code: 'user-not-found',
        message:
            'No profile found for this account. Please sign up to create one.',
      );
    }
    return user;
  }

  /// "Continue with Google". [role] is only used the first time this Google
  /// account signs in (ignored for an existing account). Returns null if
  /// the user dismissed the account picker/popup.
  Future<AuthResult?> loginWithGoogle({String? role}) async {
    final UserCredential credential;
    try {
      if (kIsWeb) {
        // Web: FirebaseAuth drives the OAuth popup directly — no separate
        // google_sign_in plumbing or client ID needed, just the Google
        // provider enabled in the Firebase console.
        credential = await FirebaseAuth.instance.signInWithPopup(
          GoogleAuthProvider(),
        );
      } else {
        final googleUser = await GoogleSignIn().signIn();
        if (googleUser == null) return null; // user cancelled
        final googleAuth = await googleUser.authentication;
        credential = await FirebaseAuth.instance.signInWithCredential(
          GoogleAuthProvider.credential(
            accessToken: googleAuth.accessToken,
            idToken: googleAuth.idToken,
          ),
        );
      }
    } on FirebaseAuthException catch (e) {
      if (e.code == 'popup-closed-by-user' ||
          e.code == 'cancelled-popup-request') {
        return null; // user cancelled — not a real error
      }
      rethrow;
    }

    final user = credential.user!;
    final doc = await _users.doc(user.uid).get();
    final isNewUser = !doc.exists;

    if (isNewUser) {
      final displayName =
          user.displayName ?? user.email?.split('@').first ?? 'user';
      await _users.doc(user.uid).set({
        'name': displayName,
        'email': user.email,
        'role': role ?? 'student',
        'handle': await _generateUniqueHandle(displayName),
        'avatarUrl': user.photoURL ?? '',
        'isOnline': false,
        'isVip': false,
        'tags': <String>[],
        'profileCompleted': false,
        'createdAt': FieldValue.serverTimestamp(),
      });
    }

    _afterSignIn();
    if (isNewUser) {
      // ignore: discarded_futures
      DeepLinkService.instance.checkClipboardFallback();
    }
    return AuthResult((await refreshCurrentUser())!, isNewUser: isNewUser);
  }

  /// "Forgot password": Firebase emails the user a reset link directly —
  /// there's no in-app code-entry step (unlike the old Laravel-backed flow),
  /// so there's no separate "confirm reset" method to call afterwards.
  Future<void> forgotPassword({required String email}) async {
    await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
  }

  /// Updates the signed-in user's own `users/{uid}` document (create/edit
  /// profile screens). Always marks the profile as completed — both screens
  /// that call this represent the user finishing/editing their profile.
  Future<AppUser> updateProfile(Map<String, dynamic> fields) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) throw StateError('Not signed in.');

    await _users.doc(uid).update({...fields, 'profileCompleted': true});
    final updated = (await refreshCurrentUser())!;

    // Old posts embed a snapshot of the author's name/avatar — keep it from
    // going stale. Fire-and-forget: shouldn't block returning the updated
    // profile, and it's non-critical if it fails (see
    // MomentService.updateAuthorInfoAcrossMoments's doc comment).
    if (fields.containsKey('name') || fields.containsKey('avatarUrl')) {
      // ignore: discarded_futures
      MomentService.updateAuthorInfoAcrossMoments(
        uid: uid,
        name: updated.name,
        avatarUrl: updated.avatarUrl,
      );
      // ignore: discarded_futures
      VoiceRoomService.updateHostInfoAcrossRooms(
        uid: uid,
        name: updated.name,
        avatarUrl: updated.avatarUrl,
      );
    }

    return updated;
  }

  /// Settings > Notifications toggle. Unlike [updateProfile], this never
  /// touches `profileCompleted` — flipping a notification preference isn't
  /// "finishing your profile".
  Future<AppUser> setVoiceRoomNotificationsEnabled(bool enabled) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) throw StateError('Not signed in.');

    await _users.doc(uid).update({'voiceRoomNotificationsEnabled': enabled});
    return (await refreshCurrentUser())!;
  }

  Future<void> logout() async {
    // Before signOut() clears FirebaseAuth.instance.currentUser — otherwise
    // setOnlineStatus has no uid left to write to.
    await setOnlineStatus(false);
    await FirebaseAuth.instance.signOut();
    try {
      await GoogleSignIn().signOut();
    } catch (_) {
      // Not signed in with Google, or unsupported on this platform — fine.
    }
    _currentUser = null;
  }

  /// Registers this device for push notifications, best-effort — a failure
  /// here (e.g. permission denied, no VAPID key configured yet) shouldn't
  /// block sign-in.
  void _afterSignIn() {
    // ignore: discarded_futures
    PushNotificationService.instance.initialize();
    // ignore: discarded_futures
    setOnlineStatus(true);
  }

  /// Marks the signed-in user online/offline — see main_shell.dart's
  /// WidgetsBindingObserver, which calls this on every app foreground/
  /// background transition, plus [_afterSignIn]/[logout] for sign-in/out.
  ///
  /// Firestore has no built-in "disconnect" detection (unlike Realtime
  /// Database's onDisconnect()), so an abrupt kill/crash — as opposed to a
  /// normal background/logout — would otherwise leave `isOnline: true`
  /// stuck forever. Two things close that gap: `online: true` (re)starts a
  /// heartbeat that keeps refreshing `lastSeenAt` every [_heartbeatInterval]
  /// while the app is actually foregrounded, and every reader of `isOnline`
  /// goes through presence.dart's isActuallyOnline, which treats the flag
  /// as stale — i.e. offline — once `lastSeenAt` is older than
  /// presenceStaleAfter. So a crash still self-corrects within that window
  /// even though nothing ever goes back and flips the stored field itself.
  Future<void> setOnlineStatus(bool online) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      await _users.doc(uid).update({
        'isOnline': online,
        'lastSeenAt': FieldValue.serverTimestamp(),
      });
    } catch (_) {
      // Offline, or the profile doc doesn't exist yet — non-critical, the
      // next successful call catches up.
    }

    _heartbeatTimer?.cancel();
    _heartbeatTimer = online
        ? Timer.periodic(_heartbeatInterval, (_) {
            // ignore: discarded_futures
            setOnlineStatus(true);
          })
        : null;
  }

  /// Build a unique @handle from a display name, e.g. "Vinuk Lakvindu" ->
  /// "vinuk_lakvindu" (mirrors the old backend's AuthController logic).
  Future<String> _generateUniqueHandle(String name) async {
    final base = name
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
    var handle = base.isEmpty ? 'user' : base;
    var suffix = 1;

    while ((await _users.where('handle', isEqualTo: handle).limit(1).get())
        .docs
        .isNotEmpty) {
      handle = '${base.isEmpty ? 'user' : base}_${suffix++}';
    }
    return handle;
  }
}
