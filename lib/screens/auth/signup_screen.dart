import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../../services/auth_service.dart';
import '../../theme/app_colors.dart';
import '../../widgets/app_logo.dart';
import '../../widgets/auth_widgets.dart';
import 'login_screen.dart';
import 'create_profile_screen.dart';

enum FaceTalkRole { student, teacher }

class SignupScreen extends StatefulWidget {
  const SignupScreen({super.key});

  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  bool _obscurePassword = true;
  bool _loading = false;
  bool _googleLoading = false;
  FaceTalkRole _role = FaceTalkRole.student;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(message), backgroundColor: AppColors.badgeRed),
      );
  }

  void _goToCreateProfile() {
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => CreateProfileScreen(role: _role)),
    );
  }

  Future<void> _continue() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    final confirm = _confirmController.text;

    if (email.isEmpty || password.isEmpty) {
      _showError('Fill in your email and password.');
      return;
    }
    if (password != confirm) {
      _showError('Passwords do not match.');
      return;
    }

    setState(() => _loading = true);
    try {
      await AuthService.instance.register(
        email: email,
        password: password,
        role: _role == FaceTalkRole.teacher ? 'teacher' : 'student',
      );
      _goToCreateProfile();
    } on FirebaseAuthException catch (e) {
      _showError(e.message ?? 'Could not create your account.');
    } catch (_) {
      _showError(
        'Could not reach Firebase. Check your connection and try again.',
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _continueWithGoogle() async {
    setState(() => _googleLoading = true);
    try {
      final result = await AuthService.instance.loginWithGoogle(
        role: _role == FaceTalkRole.teacher ? 'teacher' : 'student',
      );
      if (result == null) return; // user cancelled the account picker
      _goToCreateProfile();
    } on FirebaseAuthException catch (e) {
      _showError(e.message ?? 'Google sign-in failed. Please try again.');
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
          padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Center(child: AppLogo(height: 100)),
              const SizedBox(height: 4),
              const Text(
                'Create your account',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Join FaceTalk as a student or a teacher and\nstart real conversations today.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13.5,
                  height: 1.4,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                'I am joining as',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 10),
              _RoleSelector(
                role: _role,
                onChanged: (r) => setState(() => _role = r),
              ),
              const SizedBox(height: 20),
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
                hint: 'Create a password',
                icon: Icons.lock_outline_rounded,
                controller: _passwordController,
                obscureText: _obscurePassword,
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscurePassword
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                    size: 19,
                    color: AppColors.textTertiary,
                  ),
                  onPressed: () =>
                      setState(() => _obscurePassword = !_obscurePassword),
                ),
              ),
              const SizedBox(height: 16),
              AuthTextField(
                label: 'Confirm Password',
                hint: 'Re-enter your password',
                icon: Icons.lock_outline_rounded,
                controller: _confirmController,
                obscureText: _obscurePassword,
              ),
              const SizedBox(height: 22),
              AuthPrimaryButton(
                label: 'Sign Up',
                onPressed: _continue,
                loading: _loading,
              ),
              const SizedBox(height: 18),
              const AuthOrDivider(),
              const SizedBox(height: 18),
              GoogleAuthButton(
                onPressed: _continueWithGoogle,
                label: 'Sign up with Google',
                loading: _googleLoading,
              ),
              const SizedBox(height: 28),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text(
                    'Already have an account?',
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 13.5,
                    ),
                  ),
                  TextButton(
                    onPressed: () => Navigator.of(context).pushReplacement(
                      MaterialPageRoute(builder: (_) => const LoginScreen()),
                    ),
                    child: const Text(
                      'Log In',
                      style: TextStyle(
                        color: AppColors.primaryPurple,
                        fontWeight: FontWeight.w700,
                        fontSize: 13.5,
                      ),
                    ),
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

class _RoleSelector extends StatelessWidget {
  final FaceTalkRole role;
  final ValueChanged<FaceTalkRole> onChanged;

  const _RoleSelector({required this.role, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _RoleCard(
            label: 'Student',
            icon: Icons.school_outlined,
            selected: role == FaceTalkRole.student,
            onTap: () => onChanged(FaceTalkRole.student),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _RoleCard(
            label: 'Teacher',
            icon: Icons.menu_book_outlined,
            selected: role == FaceTalkRole.teacher,
            onTap: () => onChanged(FaceTalkRole.teacher),
          ),
        ),
      ],
    );
  }
}

class _RoleCard extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _RoleCard({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.primaryPurple.withValues(alpha: 0.1)
              : AppColors.surfaceLight,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? AppColors.primaryPurple : Colors.transparent,
            width: 1.4,
          ),
        ),
        child: Column(
          children: [
            Icon(
              icon,
              color: selected
                  ? AppColors.primaryPurple
                  : AppColors.textTertiary,
              size: 22,
            ),
            const SizedBox(height: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: selected
                    ? AppColors.primaryPurple
                    : AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
