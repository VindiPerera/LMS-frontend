import 'package:flutter/material.dart';
import '../../services/auth_service.dart';
import '../../theme/app_colors.dart';
import '../../widgets/app_logo.dart';
import '../../widgets/auth_widgets.dart';
import '../main_shell.dart';
import 'login_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  bool _checkingSession = true;

  @override
  void initState() {
    super.initState();
    _tryResumeSession();
  }

  /// If a token from a previous login is still saved and still valid on the
  /// backend, skip straight past the auth screens into the app.
  Future<void> _tryResumeSession() async {
    final user = await AuthService.instance.restoreSession();
    if (!mounted) return;

    if (user != null) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const MainShell()),
        (route) => false,
      );
      return;
    }

    setState(() => _checkingSession = false);
  }

  void _goToLogin(BuildContext context) {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            children: [
              const Spacer(flex: 3),
              const AppLogo(height: 70),
              const SizedBox(height: 14),
              const Text(
                'Talk, learn and grow together',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 15,
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'A simple space for students and teachers to connect,\npractice conversations and share knowledge.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  height: 1.5,
                  color: AppColors.textTertiary,
                ),
              ),
              const Spacer(flex: 4),
              _checkingSession
                  ? const SizedBox(
                      height: 48,
                      child: Center(
                        child: SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2.4, color: AppColors.primaryPurple),
                        ),
                      ),
                    )
                  : AuthPrimaryButton(label: 'Next', onPressed: () => _goToLogin(context)),
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }
}
