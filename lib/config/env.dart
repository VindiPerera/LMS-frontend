/// Build-time configuration, overridable with `--dart-define`.
class Env {
  /// Base URL of the Laravel API (hello-backend).
  /// Override for a different backend, e.g. a physical device or a deployed
  /// server: `flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8000/api`
  static const apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://localhost:8000/api',
  );

  /// Google OAuth "Web application" client ID used for "Continue with
  /// Google" (Google Identity Services). Create one at
  /// https://console.cloud.google.com/apis/credentials, add
  /// `http://localhost` (and the exact dev port Flutter serves on) as an
  /// authorized JavaScript origin, then run:
  ///   flutter run -d chrome --dart-define=GOOGLE_CLIENT_ID=xxxx.apps.googleusercontent.com
  ///
  /// hello-backend/.env's GOOGLE_CLIENT_ID must be set to the SAME value —
  /// the backend rejects any Google sign-in otherwise.
  static const googleClientId = String.fromEnvironment(
    'GOOGLE_CLIENT_ID',
    defaultValue: '',
  );

  static bool get isGoogleSignInConfigured => googleClientId.isNotEmpty;
}
