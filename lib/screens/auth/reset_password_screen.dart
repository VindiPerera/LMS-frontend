import 'package:flutter/material.dart';
import '../../services/api_client.dart';
import '../../services/auth_service.dart';
import '../../theme/app_colors.dart';
import '../../widgets/app_logo.dart';
import '../../widgets/auth_widgets.dart';
import 'login_screen.dart';

/// Step 2 of "Forgot password?": the user pastes the reset code emailed by
/// ForgotPasswordScreen (in dev, MAIL_MAILER=log means it's written to
/// hello-backend/storage/logs/laravel.log instead of a real inbox) and
/// picks a new password (POST /api/reset-password).
class ResetPasswordScreen extends StatefulWidget {
  final String email;

  const ResetPasswordScreen({super.key, required this.email});

  @override
  State<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends State<ResetPasswordScreen> {
  final _tokenController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  bool _obscurePassword = true;
  bool _loading = false;

  @override
  void dispose() {
    _tokenController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message), backgroundColor: AppColors.badgeRed));
  }

  Future<void> _resetPassword() async {
    final token = _tokenController.text.trim();
    final password = _passwordController.text;
    final confirm = _confirmController.text;

    if (token.isEmpty || password.isEmpty) {
      _showError('Enter the reset code and a new password.');
      return;
    }
    if (password != confirm) {
      _showError('Passwords do not match.');
      return;
    }

    setState(() => _loading = true);
    try {
      await AuthService.instance.resetPassword(
        email: widget.email,
        token: token,
        password: password,
        passwordConfirmation: confirm,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Password reset. Please log in.')),
      );
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
        (route) => false,
      );
    } on ApiException catch (e) {
      _showError(e.message);
    } catch (_) {
      _showError('Could not reach the server. Is the backend running?');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Reset Password', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18))),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Center(child: AppLogo(height: 90)),
              const SizedBox(height: 20),
              Text(
                'We sent a reset code to ${widget.email}. Enter it below along with your new password.',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 13.5, height: 1.4, color: AppColors.textSecondary),
              ),
              const SizedBox(height: 24),
              AuthTextField(
                label: 'Reset Code',
                hint: 'Paste the code from your email',
                icon: Icons.pin_outlined,
                controller: _tokenController,
              ),
              const SizedBox(height: 16),
              AuthTextField(
                label: 'New Password',
                hint: 'Create a new password',
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
              const SizedBox(height: 16),
              AuthTextField(
                label: 'Confirm New Password',
                hint: 'Re-enter your new password',
                icon: Icons.lock_outline_rounded,
                controller: _confirmController,
                obscureText: _obscurePassword,
              ),
              const SizedBox(height: 22),
              AuthPrimaryButton(label: 'Reset Password', onPressed: _resetPassword, loading: _loading),
            ],
          ),
        ),
      ),
    );
  }
}
