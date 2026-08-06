import 'package:flutter/material.dart';
import '../../models/user.dart';
import '../../services/partner_service.dart';
import '../../theme/app_colors.dart';
import '../../widgets/app_avatar.dart';
import '../../widgets/auth_widgets.dart';
import '../hellotalk/chat_detail_screen.dart';

/// Full profile view for a partner tapped from connect_screen.dart's list.
/// Shows the [initial] user immediately (already fetched for the list), then
/// silently refreshes from GET /api/partners/{id} in the background so the
/// view reflects the latest backend data.
class PartnerProfileScreen extends StatefulWidget {
  final AppUser initial;

  const PartnerProfileScreen({super.key, required this.initial});

  @override
  State<PartnerProfileScreen> createState() => _PartnerProfileScreenState();
}

class _PartnerProfileScreenState extends State<PartnerProfileScreen> {
  late AppUser _user;

  @override
  void initState() {
    super.initState();
    _user = widget.initial;
    _refresh();
  }

  Future<void> _refresh() async {
    if (_user.id.isEmpty) {
      return; // nothing to refresh a local/mock user against
    }
    try {
      final fresh = await PartnerService.fetchPartner(_user.id);
      if (mounted) setState(() => _user = fresh);
    } catch (_) {
      // Keep showing the cached copy passed in from the list.
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = _user;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(
          user.name,
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: AppAvatar.forUser(
                  user,
                  size: 96,
                  showOnlineDot: true,
                  showFlag: true,
                ),
              ),
              const SizedBox(height: 14),
              Center(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      user.name,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    if (user.isVip) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.vipGold,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Text(
                          'VIP',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            color: Colors.black,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (user.handle.isNotEmpty) ...[
                const SizedBox(height: 4),
                Center(
                  child: Text(
                    '@${user.handle}',
                    style: const TextStyle(
                      color: AppColors.textTertiary,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
              if (user.activeLabel.isNotEmpty) ...[
                const SizedBox(height: 6),
                Center(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (user.isOnline) ...[
                        Container(
                          width: 6,
                          height: 6,
                          decoration: const BoxDecoration(
                            color: AppColors.online,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 4),
                      ],
                      Text(
                        user.activeLabel,
                        style: const TextStyle(
                          fontSize: 12.5,
                          color: AppColors.textTertiary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _langPill(
                    user.nativeLang.isEmpty ? '—' : user.nativeLang,
                    AppColors.perfectGreen,
                  ),
                  const SizedBox(width: 10),
                  const Icon(
                    Icons.sync_alt_rounded,
                    size: 16,
                    color: AppColors.textTertiary,
                  ),
                  const SizedBox(width: 10),
                  _langPill(
                    user.learningLang.isEmpty ? '—' : user.learningLang,
                    AppColors.primaryPurple,
                  ),
                ],
              ),
              if (user.age > 0 ||
                  user.gender.isNotEmpty ||
                  user.detail.isNotEmpty) ...[
                const SizedBox(height: 16),
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (user.age > 0)
                      _infoChip(Icons.cake_outlined, '${user.age} yrs'),
                    if (user.gender.isNotEmpty && user.gender != 'other')
                      _infoChip(Icons.person_outline_rounded, user.gender),
                    if (user.detail.isNotEmpty)
                      _infoChip(
                        user.role == 'teacher'
                            ? Icons.menu_book_outlined
                            : Icons.school_outlined,
                        user.detail,
                      ),
                  ],
                ),
              ],
              if (user.bio.isNotEmpty) ...[
                const SizedBox(height: 24),
                const Text(
                  'About',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 8),
                Text(
                  user.bio,
                  style: const TextStyle(
                    fontSize: 14,
                    height: 1.5,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
              if (user.tags.isNotEmpty) ...[
                const SizedBox(height: 20),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: user.tags.map(_tagChip).toList(),
                ),
              ],
              const SizedBox(height: 32),
              AuthPrimaryButton(
                label: 'Say Hi',
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => ChatDetailScreen(user: user),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _langPill(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        border: Border.all(color: color, width: 1.2),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 12.5,
          color: color,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  Widget _infoChip(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.surfaceLight,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: AppColors.textSecondary),
          const SizedBox(width: 5),
          Text(
            label,
            style: const TextStyle(
              fontSize: 12.5,
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _tagChip(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.surfaceLight,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 12,
          color: AppColors.textSecondary,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
