import 'package:flutter/material.dart';
import '../../models/user.dart';
import '../../services/api_client.dart';
import '../../services/auth_service.dart';
import '../../services/google_auth.dart';
import '../../theme/app_colors.dart';
import '../../widgets/app_logo.dart';
import '../../widgets/auth_widgets.dart';
import '../main_shell.dart';
import 'forgot_password_screen.dart';
import 'signup_screen.dart';
import 'create_profile_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;
  bool _loading = false;
  bool _googleLoading = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message), backgroundColor: AppColors.badgeRed));
  }

  /// Routes to the right next screen after a successful login/sign-in:
  /// straight into the app if the profile is already set up, otherwise the
  /// profile-creation step (matching the original signup flow).
  void _enterApp(AppUser user) {
    if (!mounted) return;
    if (user.profileCompleted) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const MainShell()),
        (route) => false,
      );
    } else {
      final role = user.role == 'teacher' ? FaceTalkRole.teacher : FaceTalkRole.student;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => CreateProfileScreen(role: role)),
      );
    }
  }

  Future<void> _continue() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    if (email.isEmpty || password.isEmpty) {
      _showError('Enter your email and password.');
      return;
    }

    setState(() => _loading = true);
    try {
      final user = await AuthService.instance.login(email: email, password: password);
      _enterApp(user);
    } on ApiException catch (e) {
      _showError(e.message);
    } catch (_) {
      _showError('Could not reach the server. Is the backend running?');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _continueWithGoogle() async {
    setState(() => _googleLoading = true);
    try {
      final idToken = await GoogleAuth.signInIdToken();
      if (idToken == null) return; // user cancelled the account picker

      final result = await AuthService.instance.loginWithGoogle(idToken: idToken);
      _enterApp(result.user);
    } on ApiException catch (e) {
      _showError(e.message);
    } on StateError catch (e) {
      _showError(e.message);
    } catch (_) {
      _showError('Google sign-in failed. Please try again.');
    } finally {
      if (mounted) setState(() => _googleLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Center(child: AppLogo(height: 110)),
              const SizedBox(height: 4),
              const Text(
                'Welcome back',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: AppColors.textPrimary),
              ),
              const SizedBox(height: 8),
              const Text(
                'Log in to keep talking and learning with\nstudents and teachers worldwide.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13.5, height: 1.4, color: AppColors.textSecondary),
              ),
              const SizedBox(height: 30),
              AuthTextField(
                label: 'Email',
                hint: 'you@example.com',
                icon: Icons.mail_outline_rounded,
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
              ),
              const SizedBox(height: 16),
              AuthTextField(
                label: 'Password',
                hint: 'Enter your password',
                icon: Icons.lock_outline_rounded,
                controller: _passwordController,
                obscureText: _obscurePassword,
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscurePassword ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                    size: 19,
                    color: AppColors.textTertiary,
                  ),
                  onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                ),
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const ForgotPasswordScreen()),
                  ),
                  style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(0, 0)),
                  child: const Text('Forgot password?', style: TextStyle(color: AppColors.primaryPurple, fontSize: 12.5, fontWeight: FontWeight.w600)),
                ),
              ),
              const SizedBox(height: 12),
              AuthPrimaryButton(label: 'Log In', onPressed: _continue, loading: _loading),
              const SizedBox(height: 18),
              const AuthOrDivider(),
              const SizedBox(height: 18),
              GoogleAuthButton(onPressed: _continueWithGoogle, loading: _googleLoading),
              const SizedBox(height: 28),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text("Don't have an account?", style: TextStyle(color: AppColors.textSecondary, fontSize: 13.5)),
                  TextButton(
                    onPressed: () => Navigator.of(context).pushReplacement(
                      MaterialPageRoute(builder: (_) => const SignupScreen()),
                    ),
                    child: const Text('Sign Up', style: TextStyle(color: AppColors.primaryPurple, fontWeight: FontWeight.w700, fontSize: 13.5)),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
