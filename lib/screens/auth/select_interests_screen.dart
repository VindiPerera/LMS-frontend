import 'package:flutter/material.dart';
import '../../services/auth_service.dart';
import '../../theme/app_colors.dart';
import '../../widgets/auth_widgets.dart';
import '../main_shell.dart';

/// One-time step shown right after [CreateProfileScreen] finishes, the first
/// time a new account completes signup. Selected chips are saved onto
/// `AppUser.tags` (already rendered elsewhere — see
/// partner_profile_screen.dart / friend_profile_screen.dart / me_screen.dart)
/// so this is the only place that ever needs to populate that field.
///
/// Reached only once per account: by the time this screen's Continue button
/// runs, `profileCompleted` is already true (set by CreateProfileScreen), so
/// a relaunch goes straight into MainShell via splash_screen.dart rather than
/// looping back here.
class SelectInterestsScreen extends StatefulWidget {
  const SelectInterestsScreen({super.key});

  @override
  State<SelectInterestsScreen> createState() => _SelectInterestsScreenState();
}

class _SelectInterestsScreenState extends State<SelectInterestsScreen> {
  static const _allInterests = [
    'Free Talk',
    'Travel',
    'Food',
    'Music',
    'Movies & TV',
    'Reading',
    'Sports',
    'Fitness',
    'Photography',
    'Dancing',
    'Gardening',
    'Camping',
    'Fashion',
    'Art',
    'Technology',
    'Science',
    'Health',
    'Business',
    'Education',
    'Entertainment',
    'Media',
    'News',
    'Geo-politic',
  ];

  final Set<String> _selected = {};
  bool _loading = false;

  void _toggle(String interest) {
    setState(() {
      if (_selected.contains(interest)) {
        _selected.remove(interest);
      } else {
        _selected.add(interest);
      }
    });
  }

  Future<void> _finish() async {
    setState(() => _loading = true);
    try {
      await AuthService.instance.updateProfile({'tags': _selected.toList()});
    } catch (_) {
      // Offline/Firestore unreachable — still let the user into the app
      // rather than blocking them here; matches CreateProfileScreen._finish.
    }
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const MainShell()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Your interests',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                "Choose a few topics you're interested in — it helps us "
                'show you to the right people.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13.5,
                  height: 1.4,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 28),
              Wrap(
                spacing: 10,
                runSpacing: 12,
                children: _allInterests.map((interest) {
                  final selected = _selected.contains(interest);
                  return GestureDetector(
                    onTap: () => _toggle(interest),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: selected
                            ? AppColors.primaryPurple
                            : AppColors.surfaceLight,
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(
                          color: selected
                              ? AppColors.primaryPurple
                              : AppColors.divider,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (selected) ...[
                            const Icon(
                              Icons.check_rounded,
                              size: 16,
                              color: Colors.white,
                            ),
                            const SizedBox(width: 6),
                          ],
                          Text(
                            interest,
                            style: TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w600,
                              color: selected
                                  ? Colors.white
                                  : AppColors.textPrimary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 32),
              AuthPrimaryButton(
                label: _selected.isEmpty ? 'Skip for now' : 'Get Started',
                onPressed: _finish,
                loading: _loading,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
