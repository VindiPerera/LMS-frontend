import 'package:flutter/material.dart';
import '../../services/auth_service.dart';
import '../../theme/app_colors.dart';
import '../../widgets/app_logo.dart';
import '../main_shell.dart';
import 'create_profile_screen.dart';
import 'login_screen.dart';
import 'signup_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fade;
  late final Animation<double> _scale;

  static const _minSplashDuration = Duration(milliseconds: 1400);

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _fade = CurvedAnimation(parent: _controller, curve: Curves.easeOut);
    _scale = Tween<double>(begin: 0.82, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOutBack),
    );
    _controller.forward();
    _proceed();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Firebase Auth persists sign-in state itself — if it reports an
  /// existing user, skip straight past the auth screens into the app.
  /// The logo animation and session check run in parallel; navigation
  /// waits for whichever finishes last so the splash never flashes by.
  ///
  /// A signed-in Firebase Auth session doesn't mean the account finished
  /// signup — someone who closes the app between CreateProfileScreen and
  /// SelectInterestsScreen (or before either) still has a persisted
  /// session, so this resumes wherever they left off rather than always
  /// jumping to MainShell (matches LoginScreen._enterApp's logic).
  Future<void> _proceed() async {
    final userFuture = AuthService.instance.init();
    await Future.delayed(_minSplashDuration);
    final user = await userFuture;
    if (!mounted) return;

    Widget next;
    if (user == null) {
      next = const LoginScreen();
    } else if (!user.profileCompleted) {
      final role = user.role == 'teacher' ? FaceTalkRole.teacher : FaceTalkRole.student;
      next = CreateProfileScreen(role: role);
    } else {
      next = const MainShell();
    }

    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => next),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Center(
        child: FadeTransition(
          opacity: _fade,
          child: ScaleTransition(
            scale: _scale,
            child: const AppLogo(height: 140, isHorizontal: false),
          ),
        ),
      ),
    );
  }
}
