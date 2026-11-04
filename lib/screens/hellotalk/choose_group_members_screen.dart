import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../models/user.dart';
import '../../services/chat_service.dart';
import '../../services/follow_service.dart';
import '../../services/partner_service.dart';
import '../../theme/app_colors.dart';
import '../../widgets/app_avatar.dart';
import 'chat_detail_screen.dart';

enum GroupMemberPickerMode { create, add }

/// Picks group members from the people the signed-in user follows — the app
/// has no broader "everyone" directory suitable for a group invite (unlike
/// 1:1 chat, which anyone can start via Add Contact's search), so Follow is
/// the trust boundary here, same as add_contact_screen.dart's Follow button
/// now is for starting a relationship at all.
///
/// Two modes sharing one picker UI: [GroupMemberPickerMode.create] (from
/// add_contact_screen.dart's "Create Group Chat") asks for a group name and
/// creates a brand-new group; [GroupMemberPickerMode.add] (from
/// group_info_screen.dart's "Add Members", admin-only) adds the picked
/// people to an existing one and excludes whoever's already in it.
class ChooseGroupMembersScreen extends StatefulWidget {
  final GroupMemberPickerMode mode;
  // Required for GroupMemberPickerMode.add.
  final String? chatId;
  final List<String> existingMemberIds;

  const ChooseGroupMembersScreen({
    super.key,
    required this.mode,
    this.chatId,
    this.existingMemberIds = const [],
  });

  @override
  State<ChooseGroupMembersScreen> createState() => _ChooseGroupMembersScreenState();
}

class _ChooseGroupMembersScreenState extends State<ChooseGroupMembersScreen> {
  final _searchController = TextEditingController();
  final _nameController = TextEditingController();
  String _query = '';
  final Set<String> _selectedIds = {};
  bool _working = false;

  List<AppUser> _following = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadFollowing();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _loadFollowing() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || uid.isEmpty) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    // A one-time snapshot rather than FollowService.streamFollowing: this
    // list only needs to be fresh when the picker opens, not stay live
    // while the user is mid-selection (and a stream re-ordering rows out
    // from under tapped checkboxes would be a worse experience here).
    final following = await FollowService.streamFollowing(uid).first;
    if (!mounted) return;
    setState(() {
      _following = following.where((u) => !widget.existingMemberIds.contains(u.id)).toList();
      _loading = false;
    });
  }

  List<AppUser> get _filtered {
    if (_query.isEmpty) return _following;
    final q = _query.toLowerCase();
    return _following.where((u) => u.name.toLowerCase().contains(q) || u.handle.toLowerCase().contains(q)).toList();
  }

  // ChatService.maxGroupMembers, minus whoever's already guaranteed a seat:
  // the creator themself (create mode) or the group's existing roster (add
  // mode).
  int get _maxSelectable => widget.mode == GroupMemberPickerMode.add
      ? ChatService.maxGroupMembers - widget.existingMemberIds.length
      : ChatService.maxGroupMembers - 1;

  // A real group minimum — a single selected person is just a 1:1 chat
  // already available elsewhere; Add mode has no such floor (adding even
  // one more person to an existing group is a normal action).
  bool get _canSubmit =>
      !_working && (widget.mode == GroupMemberPickerMode.add ? _selectedIds.isNotEmpty : _selectedIds.length >= 2);

  void _toggle(String uid) {
    final selected = _selectedIds.contains(uid);
    if (!selected && _selectedIds.length >= _maxSelectable) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('A group can have at most ${ChatService.maxGroupMembers} members.')),
      );
      return;
    }
    setState(() {
      if (selected) {
        _selectedIds.remove(uid);
      } else {
        _selectedIds.add(uid);
      }
    });
  }

  Future<void> _submit() async {
    if (!_canSubmit) return;
    final selected = _following.where((u) => _selectedIds.contains(u.id)).toList();
    setState(() => _working = true);
    try {
      if (widget.mode == GroupMemberPickerMode.create) {
        final name = _nameController.text.trim().isEmpty
            ? selected.map((u) => u.name).join(', ')
            : _nameController.text.trim();
        final chatId = await ChatService.createGroup(name: name, members: selected);
        if (!mounted) return;
        // Land the user straight in the new group — past this picker AND
        // the Add Contact sheet it was opened from, same as scan_qr_screen
        // .dart's pushReplacement lands straight in a resolved profile
        // rather than leaving a dead-end screen behind to back out of.
        final navigator = Navigator.of(context);
        navigator.pop();
        navigator.pop();
        navigator.push(
          MaterialPageRoute(builder: (_) => ChatDetailScreen(groupChatId: chatId)),
        );
      } else {
        await ChatService.addGroupMembers(
          chatId: widget.chatId!,
          currentMemberIds: widget.existingMemberIds,
          newMembers: selected,
        );
        if (!mounted) return;
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _working = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Couldn't ${widget.mode == GroupMemberPickerMode.create ? 'create the group' : 'add them'}: $e")),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isCreate = widget.mode == GroupMemberPickerMode.create;
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
        title: Text(
          isCreate ? 'New Group' : 'Add Members',
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 17, color: AppColors.textPrimary),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: TextButton(
              onPressed: _canSubmit ? _submit : null,
              child: _working
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2.2, color: AppColors.primaryPurple),
                    )
                  : Text(
                      isCreate ? 'Create' : 'Add',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                        color: _canSubmit ? AppColors.primaryPurple : AppColors.textTertiary,
                      ),
                    ),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          if (isCreate)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: TextField(
                controller: _nameController,
                decoration: const InputDecoration(
                  hintText: 'Group name (optional)',
                  filled: true,
                  fillColor: AppColors.surfaceLight,
                  border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(14)), borderSide: BorderSide.none),
                  contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Container(
              decoration: BoxDecoration(color: AppColors.surfaceLight, borderRadius: BorderRadius.circular(14)),
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  const Icon(Icons.search_rounded, size: 20, color: AppColors.textTertiary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _searchController,
                      onChanged: (v) => setState(() => _query = v.trim()),
                      decoration: const InputDecoration(
                        hintText: 'Search people you follow',
                        hintStyle: TextStyle(color: AppColors.textTertiary, fontSize: 14),
                        border: InputBorder.none,
                        isDense: true,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (_selectedIds.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '${_selectedIds.length}/$_maxSelectable selected',
                  style: const TextStyle(color: AppColors.textSecondary, fontSize: 12.5, fontWeight: FontWeight.w600),
                ),
              ),
            ),
          const SizedBox(height: 4),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator(strokeWidth: 2.4, color: AppColors.primaryPurple))
                : _filtered.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(32),
                          child: Text(
                            _following.isEmpty
                                ? "You're not following anyone yet — follow people from their profile to add them to a group."
                                : 'No matches for "$_query"',
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: AppColors.textTertiary, fontSize: 13.5),
                          ),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.only(bottom: 16),
                        itemCount: _filtered.length,
                        itemBuilder: (context, i) {
                          final user = _filtered[i];
                          final selected = _selectedIds.contains(user.id);
                          final atLimit = !selected && _selectedIds.length >= _maxSelectable;
                          return CheckboxListTile(
                            value: selected,
                            onChanged: atLimit ? null : (_) => _toggle(user.id),
                            controlAffinity: ListTileControlAffinity.leading,
                            activeColor: AppColors.primaryPurple,
                            // user.avatarUrl is FollowService's own denormalized
                            // snapshot — only as fresh as whenever this user was
                            // last followed/re-followed, so it very often lags a
                            // later-uploaded avatar. A live lookup, same as
                            // chat_list_screen.dart's row already does, instead
                            // of trusting that snapshot for display here.
                            secondary: StreamBuilder<String?>(
                              stream: PartnerService.streamAvatarUrl(user.id),
                              initialData: user.avatarUrl.isEmpty ? null : user.avatarUrl,
                              builder: (context, snapshot) {
                                return AppAvatar(seed: user.name, imageUrl: snapshot.data, size: 44);
                              },
                            ),
                            title: Text(user.name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                            subtitle: Text('@${user.handle}', style: const TextStyle(color: AppColors.textSecondary, fontSize: 12.5)),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}
