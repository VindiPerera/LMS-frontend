import 'dart:typed_data';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../../models/user.dart';
import '../../services/auth_service.dart';
import '../../services/storage_service.dart';
import '../../theme/app_colors.dart';
import '../../widgets/app_avatar.dart';
import '../../widgets/auth_widgets.dart';

/// Lets the signed-in user edit their own profile (Firestore
/// `users/{uid}` document). Pops with the updated AppUser on success so
/// me_screen.dart can refresh without another round-trip.
class EditProfileScreen extends StatefulWidget {
  final AppUser user;

  const EditProfileScreen({super.key, required this.user});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  late final TextEditingController _nameController;
  late final TextEditingController _bioController;
  late final TextEditingController _detailController;
  late String _nativeLang;
  late String _learningLang;
  late String? _avatarUrl;
  bool _loading = false;
  bool _uploadingPhoto = false;

  static const _languages = [
    'English',
    'Spanish',
    'Sinhala',
    'Japanese',
    'French',
    'German',
    'Chinese',
  ];

  bool get _isTeacher => widget.user.role == 'teacher';

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.user.name);
    _bioController = TextEditingController(text: widget.user.bio);
    _detailController = TextEditingController(text: widget.user.detail);
    _avatarUrl = widget.user.avatarUrl.isEmpty ? null : widget.user.avatarUrl;
    _nativeLang = _languages.contains(widget.user.nativeLang)
        ? widget.user.nativeLang
        : _languages.first;
    _learningLang = _languages.contains(widget.user.learningLang)
        ? widget.user.learningLang
        : _languages[1];
  }

  @override
  void dispose() {
    _nameController.dispose();
    _bioController.dispose();
    _detailController.dispose();
    super.dispose();
  }

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

  Future<void> _save() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      _showError('Display name cannot be empty.');
      return;
    }

    setState(() => _loading = true);
    try {
      final updated = await AuthService.instance.updateProfile({
        'name': name,
        'bio': _bioController.text.trim(),
        if (_isTeacher) 'detail': _detailController.text.trim(),
        'nativeLang': _nativeLang,
        'learningLang': _learningLang,
        if (_avatarUrl != null) 'avatarUrl': _avatarUrl,
      });
      if (!mounted) return;
      Navigator.of(context).pop(updated);
    } on FirebaseException catch (e) {
      _showError(e.message ?? 'Could not save your profile.');
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
    final displayName = _nameController.text.trim().isEmpty
        ? '?'
        : _nameController.text.trim();

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text(
          'Edit Profile',
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
              // Matches create_profile_screen.dart: only teachers have a
              // "Subject you teach" field.
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
                label: 'Save Changes',
                onPressed: _save,
                loading: _loading,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
