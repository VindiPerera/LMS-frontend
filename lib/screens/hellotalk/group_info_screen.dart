import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../models/chat_message.dart';
import '../../services/chat_service.dart';
import '../../services/media_service.dart';
import '../../services/partner_service.dart';
import '../../theme/app_colors.dart';
import '../../widgets/app_avatar.dart';
import '../../widgets/group_avatar.dart';
import '../connect/partner_profile_screen.dart';
import 'choose_group_members_screen.dart';

/// Member list + management for a group thread — reached from
/// chat_detail_screen.dart's group header. Live (streamGroupThread), so an
/// add/remove from another device shows up here immediately. Only the
/// group's admin sees Add/Remove/photo-change/Delete Group controls; every
/// member (admin included) gets Leave Group.
class GroupInfoScreen extends StatefulWidget {
  final String chatId;
  const GroupInfoScreen({super.key, required this.chatId});

  @override
  State<GroupInfoScreen> createState() => _GroupInfoScreenState();
}

class _GroupInfoScreenState extends State<GroupInfoScreen> {
  bool _leaving = false;
  bool _deleting = false;
  bool _changingPhoto = false;

  String get _myUid => FirebaseAuth.instance.currentUser?.uid ?? '';

  Future<void> _changePhoto() async {
    if (_changingPhoto) return;
    final picked = await MediaService.pickImage(ImageSource.gallery);
    if (picked == null || !mounted) return;
    setState(() => _changingPhoto = true);
    try {
      final bytes = await picked.readAsBytes();
      final compressed = await MediaService.compressImageBytes(bytes);
      final url = await MediaService.uploadGroupAvatarBytes(
        bytes: compressed,
        uid: _myUid,
        chatId: widget.chatId,
      );
      await ChatService.updateGroupAvatar(chatId: widget.chatId, avatarUrl: url);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Couldn't update the group photo: $e")));
    } finally {
      if (mounted) setState(() => _changingPhoto = false);
    }
  }

  Future<void> _removeMember(ChatThread thread, GroupMember member) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove member?'),
        content: Text('${member.name} will be removed from "${thread.groupName}".'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Remove', style: TextStyle(color: AppColors.badgeRed)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await ChatService.removeGroupMember(
        chatId: widget.chatId,
        currentMemberIds: thread.memberIds,
        memberId: member.uid,
        memberName: member.name,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Couldn't remove ${member.name}: $e")));
    }
  }

  Future<void> _leaveGroup(ChatThread thread) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Leave group?'),
        content: Text('You\'ll stop receiving messages from "${thread.groupName}" — the rest of the group can still see it.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Leave', style: TextStyle(color: AppColors.badgeRed)),
          ),
        ],
      ),
    );
    // The dialog closing hands focus back to whatever requested it — the
    // Leave Group button itself — which Material 3 then renders with a
    // visible focus tint until something else takes focus. Cleared
    // unconditionally (not just on confirm) since a Cancel leaves the same
    // stuck highlight behind.
    if (mounted) FocusManager.instance.primaryFocus?.unfocus();
    if (confirmed != true || !mounted) return;
    setState(() => _leaving = true);
    try {
      await ChatService.leaveGroup(
        chatId: widget.chatId,
        currentMemberIds: thread.memberIds,
        currentAdminId: thread.adminId,
      );
      if (!mounted) return;
      // Back out past both this screen and the group's own chat thread —
      // there's nothing left here to look at once you've left it.
      Navigator.of(context).popUntil((route) => route.isFirst);
    } catch (e) {
      if (!mounted) return;
      setState(() => _leaving = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Couldn't leave the group: $e")));
    }
  }

  Future<void> _deleteGroup(ChatThread thread) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete this group?'),
        content: Text('"${thread.groupName}" will be removed for every member. This can\'t be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete', style: TextStyle(color: AppColors.badgeRed)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _deleting = true);
    try {
      await ChatService.deleteGroup(chatId: widget.chatId, currentMemberIds: thread.memberIds);
      if (!mounted) return;
      Navigator.of(context).popUntil((route) => route.isFirst);
    } catch (e) {
      if (!mounted) return;
      setState(() => _deleting = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Couldn't delete the group: $e")));
    }
  }

  Future<void> _openMemberProfile(GroupMember member) async {
    try {
      final user = await PartnerService.fetchPartner(member.uid);
      if (!mounted) return;
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => PartnerProfileScreen(initial: user)));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Couldn't load that profile.")));
    }
  }

  // Shared by Leave Group and Delete Group — a compact purple-outlined
  // pill (this app's own accent color, not a hardcoded warning red; see
  // app_colors.dart) rather than a full-height button for what's really a
  // secondary, infrequent action on this screen. The overlay override is
  // still needed even at this size: Material 3's OutlinedButton otherwise
  // tints its background with the foreground color on hover/focus (e.g.
  // focus landing back on the button once its confirm dialog closes),
  // which reads as a stuck "highlighted" fill rather than a plain outline.
  ButtonStyle get _actionButtonStyle => OutlinedButton.styleFrom(
        foregroundColor: AppColors.primaryPurple,
        backgroundColor: Colors.transparent,
        side: const BorderSide(color: AppColors.primaryPurple),
        padding: const EdgeInsets.symmetric(vertical: 8),
        // minimumSize.width: double.infinity, not the surrounding
        // SizedBox(width: double.infinity) alone — OutlinedButton centers
        // its own content via an inner Align that shrink-wraps unless the
        // button's OWN minimumSize says otherwise, so without this the
        // outer SizedBox's width was being ignored and the button rendered
        // only as wide as "Leave Group"/"Delete Group" needed.
        minimumSize: const Size(double.infinity, 38),
        textStyle: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ).copyWith(
        overlayColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.hovered) || states.contains(WidgetState.focused)) {
            return Colors.transparent;
          }
          return null;
        }),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: AppColors.textPrimary),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text('Group Info', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 17, color: AppColors.textPrimary)),
      ),
      body: StreamBuilder<ChatThread?>(
        stream: ChatService.streamGroupThread(widget.chatId),
        builder: (context, snapshot) {
          final thread = snapshot.data;
          if (thread == null) {
            return const Center(child: CircularProgressIndicator(strokeWidth: 2.4, color: AppColors.primaryPurple));
          }
          final isAdmin = thread.adminId == _myUid;
          final canAddMore = thread.members.length < ChatService.maxGroupMembers;

          return ListView(
            padding: const EdgeInsets.symmetric(vertical: 16),
            children: [
              Center(
                child: Column(
                  children: [
                    GestureDetector(
                      onTap: isAdmin ? _changePhoto : null,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          GroupAvatar(
                            groupName: thread.groupName,
                            groupAvatar: thread.groupAvatar,
                            members: thread.members.map((m) => (uid: m.uid, name: m.name)).toList(),
                            size: 72,
                          ),
                          if (isAdmin)
                            Positioned(
                              right: -2,
                              bottom: -2,
                              child: Container(
                                width: 26,
                                height: 26,
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  color: AppColors.primaryPurple,
                                  shape: BoxShape.circle,
                                  border: Border.all(color: AppColors.background, width: 2),
                                ),
                                child: _changingPhoto
                                    ? const SizedBox(
                                        width: 12,
                                        height: 12,
                                        child: CircularProgressIndicator(strokeWidth: 1.8, color: Colors.white),
                                      )
                                    : const Icon(Icons.camera_alt_rounded, size: 14, color: Colors.white),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      thread.groupName,
                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18, color: AppColors.textPrimary),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${thread.members.length}/${ChatService.maxGroupMembers} members',
                      style: const TextStyle(color: AppColors.textTertiary, fontSize: 12.5),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    const Text(
                      'Members',
                      style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: AppColors.textPrimary),
                    ),
                    const Spacer(),
                    if (isAdmin && canAddMore)
                      TextButton.icon(
                        onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => ChooseGroupMembersScreen(
                              mode: GroupMemberPickerMode.add,
                              chatId: widget.chatId,
                              existingMemberIds: thread.memberIds,
                            ),
                          ),
                        ),
                        icon: const Icon(Icons.person_add_alt_1_rounded, size: 17),
                        label: const Text('Add'),
                      ),
                  ],
                ),
              ),
              ...thread.members.map((member) {
                final isSelf = member.uid == _myUid;
                final memberIsAdmin = member.uid == thread.adminId;
                return ListTile(
                  onTap: () => _openMemberProfile(member),
                  // member.avatarUrl is the group's own participantInfo
                  // snapshot — only as fresh as whenever they joined/were
                  // last re-added, so (same fix as choose_group_members_
                  // screen.dart/follow_list_screen.dart) a live lookup
                  // instead of trusting it directly.
                  leading: StreamBuilder<String?>(
                    stream: PartnerService.streamAvatarUrl(member.uid),
                    initialData: member.avatarUrl.isEmpty ? null : member.avatarUrl,
                    builder: (context, avatarSnapshot) {
                      return StreamBuilder<String?>(
                        stream: PartnerService.streamCountryFlag(member.uid),
                        initialData: member.countryFlag.isEmpty ? null : member.countryFlag,
                        builder: (context, flagSnapshot) {
                          final flag = flagSnapshot.data ?? '';
                          return AppAvatar(
                            seed: member.name,
                            imageUrl: avatarSnapshot.data,
                            size: 46,
                            flag: flag,
                            showFlag: flag.isNotEmpty,
                          );
                        },
                      );
                    },
                  ),
                  title: Text(
                    isSelf ? '${member.name} (You)' : member.name,
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14.5),
                  ),
                  subtitle: memberIsAdmin
                      ? const Text('Admin', style: TextStyle(color: AppColors.primaryPurple, fontSize: 12, fontWeight: FontWeight.w600))
                      : null,
                  trailing: (isAdmin && !isSelf)
                      ? IconButton(
                          icon: const Icon(Icons.remove_circle_outline_rounded, color: AppColors.badgeRed),
                          onPressed: () => _removeMember(thread, member),
                        )
                      : null,
                );
              }),
              const SizedBox(height: 24),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  children: [
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: _leaving ? null : () => _leaveGroup(thread),
                        icon: _leaving
                            ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(Icons.logout_rounded, size: 17),
                        label: const Text('Leave Group'),
                        style: _actionButtonStyle,
                      ),
                    ),
                    if (isAdmin) ...[
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: _deleting ? null : () => _deleteGroup(thread),
                          icon: _deleting
                              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                              : const Icon(Icons.delete_outline_rounded, size: 17),
                          label: const Text('Delete Group'),
                          style: _actionButtonStyle,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
