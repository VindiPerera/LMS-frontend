import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../models/user.dart';
import '../screens/hellotalk/chat_detail_screen.dart';
import '../services/chat_service.dart';
import '../services/follow_service.dart';
import '../services/friend_link_service.dart';
import '../services/partner_service.dart';
import '../theme/app_colors.dart';
import 'app_avatar.dart';

/// "Share Profile" from a user's "⋮" menu (partner_profile_screen.dart) —
/// picks someone from the signed-in user's own Following list and sends
/// them [user]'s profile link as a chat message, one tap per recipient.
/// Following, not a general search: the app has no broader "everyone"
/// directory suitable for "send this to someone," so Follow is the same
/// trust boundary choose_group_members_screen.dart's picker already scopes
/// a group invite to.
Future<void> showShareProfileSheet(BuildContext context, {required AppUser user}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _ShareProfileSheet(user: user),
  );
}

class _ShareProfileSheet extends StatefulWidget {
  final AppUser user;
  const _ShareProfileSheet({required this.user});

  @override
  State<_ShareProfileSheet> createState() => _ShareProfileSheetState();
}

class _ShareProfileSheetState extends State<_ShareProfileSheet> {
  List<AppUser>? _following;
  // Fetched once up front (not per Send tap) so every recipient gets the
  // exact same link and a slow backend call only ever happens once per
  // sheet open, not once per person shared with.
  String? _link;
  bool _loadFailed = false;
  final Set<String> _sendingTo = {};
  final Set<String> _sentTo = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final followingFuture = (uid == null || uid.isEmpty)
        ? Future.value(<AppUser>[])
        : FollowService.streamFollowing(uid).first;
    final linkFuture = FriendLinkService.instance.generateFriendLink(widget.user);
    final results = await Future.wait([followingFuture, linkFuture]);
    if (!mounted) return;
    final link = results[1] as String;
    setState(() {
      _following = results[0] as List<AppUser>;
      _link = link.isEmpty ? null : link;
      _loadFailed = link.isEmpty;
    });
  }

  void _openChat(AppUser recipient) {
    Navigator.of(context).pop();
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => ChatDetailScreen(user: recipient)),
    );
  }

  Future<void> _send(AppUser recipient) async {
    final link = _link;
    if (link == null || _sendingTo.contains(recipient.id) || _sentTo.contains(recipient.id)) return;
    setState(() => _sendingTo.add(recipient.id));
    try {
      await ChatService.sendMessage(
        other: recipient,
        text: "Check out ${widget.user.name}'s profile on FaceTalk: $link",
      );
      if (!mounted) return;
      setState(() {
        _sendingTo.remove(recipient.id);
        _sentTo.add(recipient.id);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _sendingTo.remove(recipient.id));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Couldn't send to ${recipient.name}: $e")),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: FractionallySizedBox(
        heightFactor: 0.72,
        child: Container(
          decoration: const BoxDecoration(
            color: AppColors.background,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              const SizedBox(height: 10),
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(color: AppColors.divider, borderRadius: BorderRadius.circular(2)),
              ),
              const SizedBox(height: 14),
              Text(
                "Share ${widget.user.name}'s profile",
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: AppColors.textPrimary),
              ),
              const SizedBox(height: 4),
              const Text(
                'Send to someone you follow',
                style: TextStyle(color: AppColors.textTertiary, fontSize: 12.5),
              ),
              const SizedBox(height: 10),
              Expanded(child: _buildBody()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBody() {
    final following = _following;
    if (following == null) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2.4, color: AppColors.primaryPurple));
    }
    if (_loadFailed) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            "Couldn't create a shareable link. Check your connection and try again.",
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.textTertiary),
          ),
        ),
      );
    }
    if (following.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            "You're not following anyone yet — follow people from their profile to share with them.",
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.textTertiary),
          ),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: following.length,
      separatorBuilder: (context, i) => const Divider(height: 1, color: AppColors.divider),
      itemBuilder: (context, i) {
        final recipient = following[i];
        final sending = _sendingTo.contains(recipient.id);
        final sent = _sentTo.contains(recipient.id);
        return ListTile(
          contentPadding: EdgeInsets.zero,
          onTap: () => _openChat(recipient),
          // recipient.avatarUrl is FollowService's own denormalized
          // snapshot — only as fresh as whenever this person was last
          // followed/re-followed. Live lookup instead, same fix as
          // choose_group_members_screen.dart/follow_list_screen.dart.
          leading: StreamBuilder<String?>(
            stream: PartnerService.streamAvatarUrl(recipient.id),
            initialData: recipient.avatarUrl.isEmpty ? null : recipient.avatarUrl,
            builder: (context, snapshot) {
              return AppAvatar(seed: recipient.name, imageUrl: snapshot.data, size: 44);
            },
          ),
          title: Text(recipient.name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
          subtitle: Text('@${recipient.handle}', style: const TextStyle(color: AppColors.textSecondary, fontSize: 12.5)),
          trailing: sent
              ? const Icon(Icons.check_circle_rounded, color: AppColors.online)
              : SizedBox(
                  height: 32,
                  child: OutlinedButton(
                    onPressed: sending ? null : () => _send(recipient),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.primaryPurple,
                      backgroundColor: Colors.transparent,
                      side: const BorderSide(color: AppColors.primaryPurple),
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      minimumSize: const Size(0, 32),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                    child: sending
                        ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Text('Send', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
                  ),
                ),
        );
      },
    );
  }
}
