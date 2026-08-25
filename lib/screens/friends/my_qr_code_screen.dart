import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../models/user.dart';
import '../../services/auth_service.dart';
import '../../services/friend_link_service.dart';
import '../../theme/app_colors.dart';
import '../../widgets/app_avatar.dart';

/// Shows the signed-in user's own QR code — always THEIR identity, never a
/// stand-in. This screen intentionally has no way to display someone else's
/// code (that wouldn't make sense for something titled "My QR Code").
class MyQRCodeScreen extends StatefulWidget {
  const MyQRCodeScreen({super.key});

  @override
  State<MyQRCodeScreen> createState() => _MyQRCodeScreenState();
}

class _MyQRCodeScreenState extends State<MyQRCodeScreen> {
  String _friendLink = '';
  bool _loading = true;

  // Only ever the real signed-in user — this screen is reachable exclusively
  // from post-login UI (add_contact_screen.dart, me_screen.dart's "Invite
  // Friends"), so a null user here means something upstream broke, not a
  // normal state to paper over with mock data.
  AppUser? get _user => AuthService.instance.currentUser;

  @override
  void initState() {
    super.initState();
    _loadFriendLink();
  }

  Future<void> _loadFriendLink() async {
    final user = _user;
    if (user == null || user.id.isEmpty) {
      if (!mounted) return;
      setState(() => _loading = false);
      return;
    }
    final link = await FriendLinkService.instance.generateFriendLink(user);
    if (!mounted) return;
    setState(() {
      _friendLink = link;
      _loading = false;
    });
  }

  Future<void> _shareWhatsApp() async {
    final text = 'Add me on FaceTalk: $_friendLink';
    final url = Uri.parse('https://wa.me/?text=${Uri.encodeComponent(text)}');
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    } else {
      _copyLink();
    }
  }

  Future<void> _shareMessenger() async {
    final url = Uri.parse('fb-messenger://share?link=${Uri.encodeComponent(_friendLink)}');
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    } else {
      _copyLink();
    }
  }

  void _copyLink() {
    Clipboard.setData(ClipboardData(text: _friendLink));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Link copied to clipboard'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  void _shareMore() {
    Share.share('Add me on FaceTalk: $_friendLink');
  }

  @override
  Widget build(BuildContext context) {
    final user = _user;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        centerTitle: true,
        title: const Text(
          'My QR Code',
          style: TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 18,
            color: AppColors.textPrimary,
          ),
        ),
      ),
      body: user == null
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text(
                  "Couldn't load your profile. Please sign in again.",
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.textTertiary),
                ),
              ),
            )
          : _buildContent(user),
    );
  }

  Widget _buildContent(AppUser user) {
    return SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        child: Column(
          children: [
            const SizedBox(height: 12),
            // User Avatar & Name Card
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 16,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Column(
                children: [
                  AppAvatar.forUser(
                    user,
                    size: 72,
                    showFlag: true,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    user.name,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '@${user.handle}',
                    style: const TextStyle(
                      fontSize: 14,
                      color: AppColors.textSecondary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 24),

                  // QR Code Box
                  Container(
                    width: 230,
                    height: 230,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: AppColors.divider,
                        width: 1.2,
                      ),
                    ),
                    child: _loading
                        ? const Center(
                            child: CircularProgressIndicator(
                              strokeWidth: 2.4,
                              color: AppColors.primaryPurple,
                            ),
                          )
                        : QrImageView(
                            data: _friendLink,
                            size: 220,
                            version: QrVersions.auto,
                            eyeStyle: const QrEyeStyle(
                              eyeShape: QrEyeShape.square,
                              color: AppColors.primaryPurple,
                            ),
                            dataModuleStyle: const QrDataModuleStyle(
                              dataModuleShape: QrDataModuleShape.square,
                              color: AppColors.textPrimary,
                            ),
                          ),
                  ),
                  const SizedBox(height: 18),
                  const Text(
                    'Scan to add me on FaceTalk',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 28),

            // Share Buttons Section
            const Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Share via',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
            const SizedBox(height: 14),

            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _ShareButton(
                  icon: Icons.chat,
                  color: const Color(0xFF25D366),
                  label: 'WhatsApp',
                  onTap: _shareWhatsApp,
                ),
                _ShareButton(
                  icon: Icons.send_rounded,
                  color: const Color(0xFF0084FF),
                  label: 'Messenger',
                  onTap: _shareMessenger,
                ),
                _ShareButton(
                  icon: Icons.link_rounded,
                  color: const Color(0xFF7B68F4),
                  label: 'Copy link',
                  onTap: _copyLink,
                ),
                _ShareButton(
                  icon: Icons.more_horiz_rounded,
                  color: const Color(0xFF6E6E78),
                  label: 'More',
                  onTap: _shareMore,
                ),
              ],
            ),
            const SizedBox(height: 24),
          ],
        ),
      );
  }
}



class _ShareButton extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final VoidCallback onTap;

  const _ShareButton({
    required this.icon,
    required this.color,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Column(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 26),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: const TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}
