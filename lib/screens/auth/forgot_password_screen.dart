import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../../services/auth_service.dart';
import '../../theme/app_colors.dart';
import '../../widgets/app_logo.dart';
import '../../widgets/auth_widgets.dart';

/// "Forgot password?": asks Firebase Auth to email a reset link
/// (sendPasswordResetEmail). Unlike the old Laravel-backed flow, there's no
/// in-app code-entry step — Firebase's email links to its own hosted reset
/// page, so this screen is the whole flow.
class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _emailController = TextEditingController();
  bool _loading = false;
  bool _sent = false;

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(message), backgroundColor: AppColors.badgeRed),
      );
  }

  Future<void> _sendResetEmail() async {
    final email = _emailController.text.trim();
    if (email.isEmpty) {
      _showError('Enter your email.');
      return;
    }

    setState(() => _loading = true);
    try {
      await AuthService.instance.forgotPassword(email: email);
      if (!mounted) return;
      setState(() => _sent = true);
    } on FirebaseAuthException catch (e) {
      _showError(e.message ?? 'Could not send the reset email.');
    } catch (_) {
      _showError(
        'Could not reach Firebase. Check your connection and try again.',
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text(
          'Forgot Password',
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Center(child: AppLogo(height: 90)),
              const SizedBox(height: 20),
              if (_sent) ...[
                const Icon(
                  Icons.mark_email_read_outlined,
                  size: 48,
                  color: AppColors.primaryPurple,
                ),
                const SizedBox(height: 16),
                Text(
                  "We've sent a password reset link to ${_emailController.text.trim()}. "
                  "Open it to choose a new password, then come back and log in.",
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 13.5,
                    height: 1.4,
                    color: AppColors.textSecondary,
                  ),
                ),
              ] else ...[
                const Text(
                  "Enter the email on your account and we'll send you a password reset link.",
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13.5,
                    height: 1.4,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 24),
                AuthTextField(
                  label: 'Email',
                  hint: 'you@example.com',
                  icon: Icons.mail_outline_rounded,
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                ),
                const SizedBox(height: 22),
                AuthPrimaryButton(
                  label: 'Send Reset Link',
                  onPressed: _sendResetEmail,
                  loading: _loading,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
