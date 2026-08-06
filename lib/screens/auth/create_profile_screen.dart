import 'package:flutter/material.dart';
import '../../services/api_client.dart';
import '../../theme/app_colors.dart';
import '../../widgets/app_avatar.dart';
import '../../widgets/auth_widgets.dart';
import '../main_shell.dart';
import 'signup_screen.dart';

class CreateProfileScreen extends StatefulWidget {
  final FaceTalkRole role;

  const CreateProfileScreen({super.key, this.role = FaceTalkRole.student});

  @override
  State<CreateProfileScreen> createState() => _CreateProfileScreenState();
}

class _CreateProfileScreenState extends State<CreateProfileScreen> {
  final _nameController = TextEditingController();
  final _bioController = TextEditingController();
  final _detailController = TextEditingController();
  String _nativeLang = 'English';
  String _learningLang = 'Spanish';
  bool _loading = false;

  static const _languages = ['English', 'Spanish', 'Sinhala', 'Japanese', 'French', 'German', 'Chinese'];

  @override
  void dispose() {
    _nameController.dispose();
    _bioController.dispose();
    _detailController.dispose();
    super.dispose();
  }

  bool get _isTeacher => widget.role == FaceTalkRole.teacher;

  Future<void> _finish() async {
    setState(() => _loading = true);
    try {
      // Persists profile_completed = true server-side, so a restored
      // session (see splash_screen.dart) goes straight into the app next
      // time instead of looping back here.
      await ApiClient.instance.put('/profile', {
        if (_nameController.text.trim().isNotEmpty) 'name': _nameController.text.trim(),
        'bio': _bioController.text.trim(),
        'detail': _detailController.text.trim(),
        'native_lang': _nativeLang,
        'learning_lang': _learningLang,
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(e.message), backgroundColor: AppColors.badgeRed));
      return;
    } catch (_) {
      // Backend unreachable — still let the user into the app locally
      // rather than blocking them; profile just won't be saved yet.
    }

    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const MainShell()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final displayName = _nameController.text.trim().isEmpty ? '?' : _nameController.text.trim();

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Create Profile', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18))),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    AppAvatar(seed: displayName, size: 92),
                    Positioned(
                      right: -2,
                      bottom: -2,
                      child: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: AppColors.primaryPurple,
                          shape: BoxShape.circle,
                          border: Border.all(color: AppColors.background, width: 2.5),
                        ),
                        child: const Icon(Icons.camera_alt_rounded, size: 15, color: Colors.white),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(color: AppColors.surfaceLight, borderRadius: BorderRadius.circular(12)),
                  child: Text(
                    _isTeacher ? '🧑‍🏫  Teacher' : '🎓  Student',
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.textSecondary),
                  ),
                ),
              ),
              const SizedBox(height: 22),
              AuthTextField(
                label: 'Display Name',
                hint: 'How should we call you?',
                icon: Icons.badge_outlined,
                controller: _nameController,
              ),
              const SizedBox(height: 16),
              AuthTextField(
                label: 'Short Bio',
                hint: _isTeacher ? 'Tell students about your teaching style' : 'Tell others what you want to learn',
                icon: Icons.edit_note_rounded,
                controller: _bioController,
              ),
              // Teachers still list their subject; students no longer have
              // an "Interests / Grade" field here.
              if (_isTeacher) ...[
                const SizedBox(height: 16),
                AuthTextField(
                  label: 'Subject you teach',
                  hint: 'e.g. English Conversation',
                  icon: Icons.menu_book_outlined,
                  controller: _detailController,
                ),
              ],
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(child: _LanguageDropdown(label: 'Native Language', value: _nativeLang, options: _languages, onChanged: (v) => setState(() => _nativeLang = v))),
                  const SizedBox(width: 12),
                  Expanded(child: _LanguageDropdown(label: 'Learning', value: _learningLang, options: _languages, onChanged: (v) => setState(() => _learningLang = v))),
                ],
              ),
              const SizedBox(height: 28),
              AuthPrimaryButton(label: 'Finish & Continue', onPressed: _finish, loading: _loading),
            ],
          ),
        ),
      ),
    );
  }
}

class _LanguageDropdown extends StatelessWidget {
  final String label;
  final String value;
  final List<String> options;
  final ValueChanged<String> onChanged;

  const _LanguageDropdown({required this.label, required this.value, required this.options, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(color: AppColors.surfaceLight, borderRadius: BorderRadius.circular(14)),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: value,
              isExpanded: true,
              icon: const Icon(Icons.keyboard_arrow_down_rounded, color: AppColors.textTertiary),
              style: const TextStyle(fontSize: 14, color: AppColors.textPrimary, fontWeight: FontWeight.w500),
              items: options.map((o) => DropdownMenuItem(value: o, child: Text(o))).toList(),
              onChanged: (v) {
                if (v != null) onChanged(v);
              },
            ),
          ),
        ),
      ],
    );
  }
}
