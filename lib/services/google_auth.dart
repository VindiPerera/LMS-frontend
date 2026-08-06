import 'package:google_sign_in/google_sign_in.dart';
import '../config/env.dart';

/// Thin wrapper around google_sign_in for "Continue with Google": runs the
/// Google Identity Services flow and returns the ID token to send to the
/// backend's POST /api/auth/google.
class GoogleAuth {
  static GoogleSignIn? _instance;

  static GoogleSignIn get _signIn {
    return _instance ??= GoogleSignIn(
      clientId: Env.googleClientId.isEmpty ? null : Env.googleClientId,
      scopes: const ['email', 'profile'],
    );
  }

  /// Runs the sign-in flow. Returns the ID token, or null if the user
  /// cancelled the Google account picker.
  ///
  /// Throws if [Env.isGoogleSignInConfigured] is false — callers should
  /// check that first and show a friendlier message.
  static Future<String?> signInIdToken() async {
    if (!Env.isGoogleSignInConfigured) {
      throw StateError(
        'Google Sign-In is not configured. Set GOOGLE_CLIENT_ID (see lib/config/env.dart).',
      );
    }

    final account = await _signIn.signIn();
    if (account == null) return null; // user dismissed the picker

    final auth = await account.authentication;
    if (auth.idToken == null) {
      throw StateError('Google did not return an ID token for this sign-in.');
    }
    return auth.idToken;
  }
}
