import 'dart:typed_data';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../../services/auth_service.dart';
import '../../services/storage_service.dart';
import '../../theme/app_colors.dart';
import '../../widgets/app_avatar.dart';
import '../../widgets/auth_widgets.dart';
import 'select_interests_screen.dart';
import 'signup_screen.dart';

class CreateProfileScreen extends StatefulWidget {
  final FaceTalkRole role;

  const CreateProfileScreen({super.key, this.role = FaceTalkRole.student});

  @override
  State<CreateProfileScreen> createState() => _CreateProfileScreenState();
}

/// Male/Female picker for the Create Profile screen — feeds `AppUser.gender`
/// (previously never set from this screen, so it silently stayed at the
/// model's 'other' default for every account).
class _GenderSelector extends StatelessWidget {
  final String value;
  final ValueChanged<String> onChanged;

  const _GenderSelector({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Gender',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(child: _option('male', 'Male', Icons.male_rounded)),
            const SizedBox(width: 12),
            Expanded(child: _option('female', 'Female', Icons.female_rounded)),
          ],
        ),
      ],
    );
  }

  Widget _option(String optionValue, String label, IconData icon) {
    final selected = value == optionValue;
    return GestureDetector(
      onTap: () => onChanged(optionValue),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 13),
        decoration: BoxDecoration(
          color: selected ? AppColors.primaryPurple : AppColors.surfaceLight,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? AppColors.primaryPurple : AppColors.divider,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 18,
              color: selected ? Colors.white : AppColors.textTertiary,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: selected ? Colors.white : AppColors.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CreateProfileScreenState extends State<CreateProfileScreen> {
  final _nameController = TextEditingController();
  final _bioController = TextEditingController();
  final _detailController = TextEditingController();
  String _nativeLang = 'English';
  String _learningLang = 'Spanish';
  String _gender = 'male';
  bool _loading = false;
  bool _uploadingPhoto = false;
  String? _avatarUrl;

  static const _languages = [
    'English',
    'Spanish',
    'Sinhala',
    'Japanese',
    'French',
    'German',
    'Chinese',
  ];

  @override
  void dispose() {
    _nameController.dispose();
    _bioController.dispose();
    _detailController.dispose();
    super.dispose();
  }

  bool get _isTeacher => widget.role == FaceTalkRole.teacher;

  void _showError(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(message), backgroundColor: AppColors.badgeRed),
      );
  }

  Future<void> _pickPhoto() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 512,
      imageQuality: 85,
    );
    if (picked == null) return;

    setState(() => _uploadingPhoto = true);
    try {
      final Uint8List bytes = await picked.readAsBytes();
      final url = await StorageService.uploadAvatar(uid, bytes);
      if (mounted) setState(() => _avatarUrl = url);
    } catch (_) {
      _showError('Could not upload photo. Please try again.');
    } finally {
      if (mounted) setState(() => _uploadingPhoto = false);
    }
  }

  Future<void> _finish() async {
    setState(() => _loading = true);
    try {
      // Persists profileCompleted = true, so a restored session (see
      // splash_screen.dart) goes straight into the app next time instead of
      // looping back here.
      await AuthService.instance.updateProfile({
        if (_nameController.text.trim().isNotEmpty)
          'name': _nameController.text.trim(),
        'bio': _bioController.text.trim(),
        if (_isTeacher) 'detail': _detailController.text.trim(),
        'nativeLang': _nativeLang,
        'learningLang': _learningLang,
        'gender': _gender,
        if (_avatarUrl != null) 'avatarUrl': _avatarUrl,
      });
    } on FirebaseException catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      _showError(e.message ?? 'Could not save your profile.');
      return;
    } catch (_) {
      // Firebase unreachable — still let the user into the app locally
      // rather than blocking them; profile just won't be saved yet.
    }

    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const SelectInterestsScreen()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final displayName = _nameController.text.trim().isEmpty
        ? '?'
        : _nameController.text.trim();

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text(
          'Create Profile',
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: GestureDetector(
                  onTap: _uploadingPhoto ? null : _pickPhoto,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      AppAvatar(
                        seed: displayName,
                        size: 92,
                        imageUrl: _avatarUrl,
                      ),
                      Positioned(
                        right: -2,
                        bottom: -2,
                        child: Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: AppColors.primaryPurple,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: AppColors.background,
                              width: 2.5,
                            ),
                          ),
                          child: _uploadingPhoto
                              ? const SizedBox(
                                  width: 15,
                                  height: 15,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(
                                  Icons.camera_alt_rounded,
                                  size: 15,
                                  color: Colors.white,
                                ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceLight,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    _isTeacher ? '🧑‍🏫  Teacher' : '🎓  Student',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textSecondary,
                    ),
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
                hint: _isTeacher
                    ? 'Tell students about your teaching style'
                    : 'Tell others what you want to learn',
                icon: Icons.edit_note_rounded,
                controller: _bioController,
              ),
              const SizedBox(height: 16),
              _GenderSelector(
                value: _gender,
                onChanged: (v) => setState(() => _gender = v),
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
                  Expanded(
                    child: LanguageDropdown(
                      label: 'Native Language',
                      value: _nativeLang,
                      options: _languages,
                      onChanged: (v) => setState(() => _nativeLang = v),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: LanguageDropdown(
                      label: 'Learning',
                      value: _learningLang,
                      options: _languages,
                      onChanged: (v) => setState(() => _learningLang = v),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 28),
              AuthPrimaryButton(
                label: 'Finish & Continue',
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
