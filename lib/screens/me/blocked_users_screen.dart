import 'package:flutter/material.dart';

import '../../models/user.dart';
import '../../services/block_service.dart';
import '../../services/partner_service.dart';
import '../../theme/app_colors.dart';
import '../../widgets/app_avatar.dart';

/// me_screen.dart's "Blocked Users" settings entry — lists everyone the
/// signed-in user has blocked (BlockService.streamBlockedUserIds), with an
/// Unblock action per row. A blocked user's moments are already hidden
/// server-side (firestore.rules' isBlockedBy) — this is just the
/// management view for that state, same as any messaging/social app needs.
class BlockedUsersScreen extends StatelessWidget {
  const BlockedUsersScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        title: const Text('Blocked Users', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 17)),
      ),
      body: StreamBuilder<List<String>>(
        stream: BlockService.streamBlockedUserIds(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(
              child: CircularProgressIndicator(strokeWidth: 2.4, color: AppColors.primaryPurple),
            );
          }

          final uids = snapshot.data!;
          if (uids.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.block_rounded, size: 40, color: AppColors.textTertiary),
                    SizedBox(height: 12),
                    Text(
                      "You haven't blocked anyone",
                      style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: AppColors.textPrimary),
                    ),
                    SizedBox(height: 6),
                    Text(
                      'People you block will show up here.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 12.5, color: AppColors.textTertiary),
                    ),
                  ],
                ),
              ),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.symmetric(vertical: 4),
            itemCount: uids.length,
            separatorBuilder: (_, _) => const Divider(height: 1, indent: 72, color: AppColors.divider),
            itemBuilder: (context, i) => _BlockedRow(uid: uids[i]),
          );
        },
      ),
    );
  }
}

class _BlockedRow extends StatelessWidget {
  final String uid;
  const _BlockedRow({required this.uid});

  Future<void> _unblock(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    await BlockService.unblockUser(uid);
    messenger.showSnackBar(const SnackBar(content: Text('Unblocked')));
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<AppUser>(
      future: PartnerService.fetchPartner(uid),
      builder: (context, snapshot) {
        final user = snapshot.data;
        return ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          leading: AppAvatar(
            seed: user?.name ?? uid,
            imageUrl: user?.avatarUrl,
            size: 48,
            showFlag: user?.countryFlag.isNotEmpty == true,
            flag: user?.countryFlag,
          ),
          title: Text(
            user?.name ?? 'Loading…',
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
          ),
          subtitle: user != null
              ? Text('@${user.handle}', style: const TextStyle(color: AppColors.textSecondary, fontSize: 13))
              : null,
          trailing: OutlinedButton(
            onPressed: () => _unblock(context),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.primaryPurple,
              side: const BorderSide(color: AppColors.primaryPurple),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            ),
            child: const Text('Unblock', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
          ),
        );
      },
    );
  }
}
