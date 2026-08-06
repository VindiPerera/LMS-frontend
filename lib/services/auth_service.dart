import 'package:shared_preferences/shared_preferences.dart';
import '../models/user.dart';
import 'api_client.dart';

/// Result of a successful register/login/Google sign-in.
class AuthResult {
  final AppUser user;
  final bool isNewUser;
  const AuthResult(this.user, {this.isNewUser = false});
}

/// Owns the current session: talks to the Laravel auth endpoints, keeps the
/// Sanctum token in [ApiClient], and persists it so the app can restore a
/// session on next launch.
class AuthService {
  AuthService._();
  static final AuthService instance = AuthService._();

  static const _tokenKey = 'facetalk_api_token';

  AppUser? _currentUser;
  AppUser? get currentUser => _currentUser;
  bool get isLoggedIn => _currentUser != null;

  /// Tries to resume a session from a token saved on a previous launch.
  /// Returns the user on success, or null if there was no token or it's no
  /// longer valid (in which case the stored token is cleared).
  Future<AppUser?> restoreSession() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString(_tokenKey);
    if (token == null) return null;

    ApiClient.instance.setToken(token);
    try {
      final res = await ApiClient.instance.get('/me');
      _currentUser = AppUser.fromJson(res['user'] as Map<String, dynamic>);
      return _currentUser;
    } catch (_) {
      await prefs.remove(_tokenKey);
      ApiClient.instance.setToken(null);
      return null;
    }
  }

  /// [name] is optional — signup_screen.dart no longer asks for a display
  /// name; the backend derives a placeholder from the email until the user
  /// sets a real one on create_profile_screen.dart.
  Future<AppUser> register({
    String? name,
    required String email,
    required String password,
    required String passwordConfirmation,
    required String role,
  }) async {
    final result = await _authenticate(() => ApiClient.instance.post('/register', {
          if (name != null && name.isNotEmpty) 'name': name,
          'email': email,
          'password': password,
          'password_confirmation': passwordConfirmation,
          'role': role,
        }));
    return result.user;
  }

  Future<AppUser> login({required String email, required String password}) async {
    final result = await _authenticate(() => ApiClient.instance.post('/login', {
          'email': email,
          'password': password,
        }));
    return result.user;
  }

  /// "Continue with Google". [idToken] is the Google ID token from
  /// GoogleAuth.signInIdToken(); [role] is only used the first time this
  /// Google account signs in (ignored for an existing account).
  Future<AuthResult> loginWithGoogle({required String idToken, String? role}) {
    return _authenticate(() => ApiClient.instance.post('/auth/google', {
          'id_token': idToken,
          if (role != null) 'role': role,
        }));
  }

  /// "Forgot password" step 1: asks the backend to email a reset code.
  Future<void> forgotPassword({required String email}) async {
    await ApiClient.instance.post('/forgot-password', {'email': email});
  }

  /// "Forgot password" step 2: exchanges the emailed code for a new password.
  Future<void> resetPassword({
    required String email,
    required String token,
    required String password,
    required String passwordConfirmation,
  }) async {
    await ApiClient.instance.post('/reset-password', {
      'email': email,
      'token': token,
      'password': password,
      'password_confirmation': passwordConfirmation,
    });
  }

  Future<AuthResult> _authenticate(Future<Map<String, dynamic>> Function() request) async {
    final res = await request();
    final token = res['token'] as String;
    final user = AppUser.fromJson(res['user'] as Map<String, dynamic>);

    ApiClient.instance.setToken(token);
    _currentUser = user;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_tokenKey, token);

    return AuthResult(user, isNewUser: res['isNewUser'] == true);
  }

  Future<void> logout() async {
    try {
      await ApiClient.instance.post('/logout');
    } catch (_) {
      // Best-effort — the local session is cleared below regardless.
    }
    ApiClient.instance.setToken(null);
    _currentUser = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey);
  }
}
