import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../../data/mock_data.dart' as mock;
import '../../models/user.dart';
import '../../services/auth_service.dart';
import '../../services/friend_link_service.dart';
import '../../services/partner_service.dart';
import '../../theme/app_colors.dart';
import '../../widgets/app_avatar.dart';
import '../friends/friend_profile_screen.dart';
import '../friends/my_qr_code_screen.dart';
import '../friends/scan_qr_screen.dart';

/// Modal screen that slides up smoothly from bottom to top.
class AddContactScreen extends StatefulWidget {
  const AddContactScreen({super.key});

  /// Helper method to present AddContactScreen as a smooth bottom-to-top modal sheet
  static void show(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const AddContactScreen(),
    );
  }

  @override
  State<AddContactScreen> createState() => _AddContactScreenState();
}

class _AddContactScreenState extends State<AddContactScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  List<AppUser> _searchResults = [];
  bool _isSearching = false;
  String? _searchError;
  String _friendLink = '';
  bool _loadingLink = true;

  AppUser get _currentUser =>
      AuthService.instance.currentUser ?? mock.currentUser;

  @override
  void initState() {
    super.initState();
    _loadFriendLink();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadFriendLink() async {
    // The QR/link payload must carry the real Firestore uid — that's what
    // getFriendProfile()/scan_qr_screen.dart look up by. Falling back to the
    // handle here would silently generate a code nobody could ever redeem.
    final user = _currentUser;
    if (user.id.isEmpty) {
      if (!mounted) return;
      setState(() => _loadingLink = false);
      return;
    }
    final link = await FriendLinkService.instance.generateFriendLink(user);
    if (!mounted) return;
    setState(() {
      _friendLink = link;
      _loadingLink = false;
    });
  }

  Future<void> _onSearchChanged(String value) async {
    final query = value.trim();
    setState(() {
      _searchQuery = query;
      _searchError = null;
    });

    if (query.isEmpty) {
      setState(() {
        _searchResults = [];
        _isSearching = false;
      });
      return;
    }

    setState(() => _isSearching = true);

    try {
      final partners = await PartnerService.fetchPartners(limit: 50);
      final qLower = query.toLowerCase().replaceAll('@', '');
      final filtered = partners.where((user) {
        return user.name.toLowerCase().contains(qLower) ||
            user.handle.toLowerCase().contains(qLower);
      }).toList();

      if (!mounted) return;
      setState(() {
        _searchResults = filtered;
        _isSearching = false;
      });
    } catch (_) {
      // Real failure (offline/Firestore error) — say so rather than
      // quietly showing the signed-in user as a fake "search result".
      if (!mounted) return;
      setState(() {
        _searchResults = [];
        _searchError = 'Could not search right now. Check your connection.';
        _isSearching = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final userHandle = '@${_currentUser.handle}';

    return Container(
      decoration: const BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      clipBehavior: Clip.antiAlias,
      child: FractionallySizedBox(
        heightFactor: 0.94,
        child: Scaffold(
          backgroundColor: AppColors.background,
          appBar: AppBar(
            backgroundColor: AppColors.background,
            elevation: 0,
            centerTitle: true,
            leading: IconButton(
              icon: const Icon(
                Icons.close_rounded,
                color: AppColors.textPrimary,
                size: 26,
              ),
              onPressed: () => Navigator.of(context).pop(),
            ),
            title: const Text(
              'Add',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 19,
                color: AppColors.textPrimary,
              ),
            ),
          ),
          body: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Search Input
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFECECEF),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.search_rounded,
                        color: AppColors.textTertiary,
                        size: 22,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          controller: _searchController,
                          onChanged: _onSearchChanged,
                          decoration: const InputDecoration(
                            hintText: 'Search FaceTalk ID or name',
                            hintStyle: TextStyle(
                              color: AppColors.textTertiary,
                              fontSize: 15,
                              fontWeight: FontWeight.w400,
                            ),
                            border: InputBorder.none,
                          ),
                        ),
                      ),
                      if (_searchQuery.isNotEmpty)
                        IconButton(
                          icon: const Icon(
                            Icons.cancel_rounded,
                            color: AppColors.textTertiary,
                            size: 18,
                          ),
                          onPressed: () {
                            _searchController.clear();
                            _onSearchChanged('');
                          },
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                // If user is searching, render Search Results list
                if (_searchQuery.isNotEmpty) ...[
                  if (_isSearching)
                    const Padding(
                      padding: EdgeInsets.all(24.0),
                      child: CircularProgressIndicator(
                        strokeWidth: 2.4,
                        color: AppColors.primaryPurple,
                      ),
                    )
                  else if (_searchError != null)
                    Padding(
                      padding: const EdgeInsets.all(24.0),
                      child: Column(
                        children: [
                          Text(
                            _searchError!,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: AppColors.textTertiary,
                              fontSize: 14.5,
                            ),
                          ),
                          const SizedBox(height: 8),
                          TextButton(
                            onPressed: () => _onSearchChanged(_searchQuery),
                            child: const Text('Retry'),
                          ),
                        ],
                      ),
                    )
                  else if (_searchResults.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(24.0),
                      child: Text(
                        'No users found',
                        style: TextStyle(
                          color: AppColors.textTertiary,
                          fontSize: 14.5,
                        ),
                      ),
                    )
                  else
                    ListView.separated(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: _searchResults.length,
                      separatorBuilder: (context, i) =>
                          const Divider(height: 1, color: AppColors.divider),
                      itemBuilder: (context, i) {
                        final user = _searchResults[i];
                        return ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 4,
                            vertical: 4,
                          ),
                          leading: AppAvatar.forUser(user, size: 46),
                          title: Text(
                            user.name,
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 15.5,
                            ),
                          ),
                          subtitle: Text(
                            '@${user.handle}',
                            style: const TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 13,
                            ),
                          ),
                          trailing: ElevatedButton(
                            onPressed: () {
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => FriendProfileScreen(
                                    friendId: user.id.isNotEmpty
                                        ? user.id
                                        : user.handle,
                                    source: 'search',
                                  ),
                                ),
                              );
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.primaryPurple,
                              foregroundColor: Colors.white,
                              elevation: 0,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 6,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                            ),
                            child: const Text('View Profile'),
                          ),
                        );
                      },
                    ),
                ] else ...[
                  // Action Items Card
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(18),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.03),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        _ActionTile(
                          icon: Icons.group_add_outlined,
                          label: 'Create Group Chat',
                          onTap: () {},
                        ),
                        const Divider(
                          height: 1,
                          indent: 56,
                          color: AppColors.divider,
                        ),
                        _ActionTile(
                          icon: Icons.crop_free_rounded,
                          label: 'Scan QR Code',
                          onTap: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => const ScanQRScreen(),
                              ),
                            );
                          },
                        ),
                        const Divider(
                          height: 1,
                          indent: 56,
                          color: AppColors.divider,
                        ),
                        _ActionTile(
                          icon: Icons.mail_outline_rounded,
                          label: 'Invite',
                          onTap: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => const MyQRCodeScreen(),
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 32),

                  // My FaceTalk ID Title & Handle
                  const Text(
                    'My FaceTalk ID',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  GestureDetector(
                    onTap: () {
                      Clipboard.setData(ClipboardData(text: userHandle));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('FaceTalk ID copied to clipboard'),
                          duration: Duration(seconds: 2),
                        ),
                      );
                    },
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          userHandle,
                          style: const TextStyle(
                            fontSize: 14,
                            color: AppColors.textSecondary,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(width: 4),
                        const Icon(
                          Icons.copy_rounded,
                          size: 14,
                          color: AppColors.textTertiary,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),

                  // Real QR Code Box (using QrImageView with user's generated deep link)
                  GestureDetector(
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const MyQRCodeScreen(),
                        ),
                      );
                    },
                    child: Container(
                      width: 210,
                      height: 210,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.05),
                            blurRadius: 14,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: _loadingLink
                          ? const Center(
                              child: CircularProgressIndicator(
                                strokeWidth: 2.4,
                                color: AppColors.primaryPurple,
                              ),
                            )
                          : QrImageView(
                              data: _friendLink,
                              size: 180,
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
                  ),
                  const SizedBox(height: 24),

                  // Share QR Code Pill Button
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton.icon(
                      onPressed: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const MyQRCodeScreen(),
                          ),
                        );
                      },
                      icon: const Icon(
                        Icons.upload_rounded,
                        size: 20,
                        color: Colors.white,
                      ),
                      label: const Text(
                        'Share QR Code',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primaryPurple,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(26),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),

                  // Save as Image Button
                  TextButton(
                    onPressed: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Saved QR Code to gallery'),
                        ),
                      );
                    },
                    child: const Text(
                      'Save as Image',
                      style: TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textTertiary,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _ActionTile({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        child: Row(
          children: [
            Icon(icon, size: 23, color: AppColors.textPrimary),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                label,
                style: const TextStyle(
                  fontSize: 15.5,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
            const Icon(
              Icons.chevron_right_rounded,
              size: 22,
              color: AppColors.textTertiary,
            ),
          ],
        ),
      ),
    );
  }
}
