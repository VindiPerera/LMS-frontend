import 'package:flutter/material.dart';
import '../../models/chat_message.dart';
import '../../models/user.dart';
import '../../services/auth_service.dart';
import '../../services/chat_service.dart';
import '../../services/partner_service.dart';
import '../../theme/app_colors.dart';

import '../../widgets/app_avatar.dart';
import '../../widgets/group_avatar.dart';
import '../hellotalk/chat_detail_screen.dart';
import 'partner_profile_screen.dart';

class ConnectScreen extends StatefulWidget {
  const ConnectScreen({super.key});

  @override
  State<ConnectScreen> createState() => _ConnectScreenState();
}

class _ConnectScreenState extends State<ConnectScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  final _filters = const ['Recommended', 'New Users', 'Same Country'];
  int _filterIndex = 0;

  bool _searching = false;
  final _searchController = TextEditingController();
  String _searchQuery = '';

  List<AppUser>? _partners;
  String? _error;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadPartners();
  }

  void _toggleSearch() {
    setState(() {
      _searching = !_searching;
      if (!_searching) {
        _searchController.clear();
        _searchQuery = '';
      }
    });
  }

  Future<void> _loadPartners() async {
    setState(() => _error = null);
    try {
      final partners = await PartnerService.fetchPartners();
      if (!mounted) return;
      setState(() => _partners = partners);
    } catch (e) {
      // Requires a composite index on (isOnline desc, createdAt desc) — see
      // firestore.indexes.json. Without it Firestore rejects this query
      // outright, and this falls back to "no partners" rather than
      // surfacing the real cause, hence the debugPrint.
      debugPrint('ConnectScreen._loadPartners failed (showing no partners): $e');
      if (!mounted) return;
      setState(() => _partners = []);
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        // The add-friend entry point now lives only on the Message tab
        // (chat_list_screen.dart's "Add People" button) — no need for a
        // second one here too.
        title: _searching
            ? TextField(
                controller: _searchController,
                autofocus: true,
                onChanged: (val) =>
                    setState(() => _searchQuery = val.trim().toLowerCase()),
                decoration: const InputDecoration(
                  hintText: 'Search by name or @handle',
                  hintStyle: TextStyle(
                    color: AppColors.textTertiary,
                    fontSize: 16,
                    fontWeight: FontWeight.w400,
                  ),
                  border: InputBorder.none,
                ),
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              )
            : const Text(
                'Connect',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 19),
              ),
        actions: [
          IconButton(
            icon: Icon(_searching ? Icons.close_rounded : Icons.search_rounded),
            onPressed: _toggleSearch,
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          indicatorColor: AppColors.primaryPurple,
          labelColor: AppColors.primaryPurple,
          unselectedLabelColor: AppColors.textSecondary,
          labelStyle: const TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 14.5,
          ),
          tabAlignment: TabAlignment.start,
          tabs: const [
            Tab(text: 'Partners'),
            Tab(text: 'Groups'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _PartnersTab(
            filters: _filters,
            filterIndex: _filterIndex,
            onFilter: (i) => setState(() => _filterIndex = i),
            partners: _partners,
            error: _error,
            onRetry: _loadPartners,
            searchQuery: _searchQuery,
          ),
          const _GroupsTab(),
        ],
      ),
    );
  }
}


class _PartnersTab extends StatelessWidget {
  final List<String> filters;
  final int filterIndex;
  final ValueChanged<int> onFilter;
  final List<AppUser>? partners;
  final String? error;
  final VoidCallback onRetry;
  final String searchQuery;

  const _PartnersTab({
    required this.filters,
    required this.filterIndex,
    required this.onFilter,
    required this.partners,
    required this.error,
    required this.onRetry,
    this.searchQuery = '',
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SizedBox(
          height: 44,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            itemCount: filters.length,
            separatorBuilder: (context, i) => const SizedBox(width: 8),
            itemBuilder: (context, i) {
              final selected = i == filterIndex;
              return ChoiceChip(
                label: Text(filters[i]),
                selected: selected,
                onSelected: (_) => onFilter(i),
                showCheckmark: false,
                labelStyle: TextStyle(
                  color: selected ? Colors.white : AppColors.textSecondary,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
                backgroundColor: AppColors.surfaceLight,
                selectedColor: AppColors.primaryPurple,
                side: BorderSide.none,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
              );
            },
          ),
        ),
        Expanded(child: _buildBody()),
      ],
    );
  }

  // "Recommended" is just the unfiltered list — this app has no actual
  // recommendation engine, so it's the sensible default/catch-all rather
  // than an empty promise of one.
  static const _newUserWindow = Duration(days: 30);

  List<AppUser> _applyChipFilter(List<AppUser> users) {
    switch (filters[filterIndex]) {
      case 'New Users':
        final cutoff = DateTime.now().subtract(_newUserWindow);
        final recent = users.where((u) => u.createdAt != null && u.createdAt!.isAfter(cutoff)).toList()
          ..sort((a, b) => b.createdAt!.compareTo(a.createdAt!));
        return recent;
      case 'Same Country':
        final myFlag = AuthService.instance.currentUser?.countryFlag ?? '';
        if (myFlag.isEmpty) return const [];
        return users.where((u) => u.countryFlag == myFlag).toList();
      default:
        return users;
    }
  }

  String _emptyMessageFor(String filter) {
    switch (filter) {
      case 'New Users':
        return 'No one has joined in the last 30 days — check back soon!';
      case 'Same Country':
        return AuthService.instance.currentUser?.countryFlag.isEmpty ?? true
            ? "Set your country on your profile to see partners from it."
            : 'No partners from your country yet — check back soon!';
      default:
        return 'No partners yet — check back soon!';
    }
  }

  Widget _buildBody() {
    if (error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.cloud_off_rounded,
              size: 42,
              color: AppColors.textTertiary,
            ),
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Text(
                error!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.textTertiary),
              ),
            ),
            const SizedBox(height: 12),
            TextButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      );
    }

    final allUsers = partners;
    if (allUsers == null) {
      return const Center(
        child: CircularProgressIndicator(
          strokeWidth: 2.4,
          color: AppColors.primaryPurple,
        ),
      );
    }

    final chipFiltered = _applyChipFilter(allUsers);
    final users = searchQuery.isEmpty
        ? chipFiltered
        : chipFiltered.where((u) {
            return u.name.toLowerCase().contains(searchQuery) ||
                u.handle.toLowerCase().contains(searchQuery);
          }).toList();

    if (users.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Text(
            searchQuery.isNotEmpty
                ? 'No partners matching "$searchQuery"'
                : _emptyMessageFor(filters[filterIndex]),
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.textTertiary),
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () async => onRetry(),
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(14, 6, 14, 16),
        itemCount: users.length,
        separatorBuilder: (context, i) =>
            const Divider(height: 1, color: AppColors.divider),
        itemBuilder: (context, i) => _PartnerListTile(user: users[i]),
      ),
    );
  }
}

class _PartnerListTile extends StatefulWidget {
  final AppUser user;
  const _PartnerListTile({required this.user});

  @override
  State<_PartnerListTile> createState() => _PartnerListTileState();
}

class _PartnerListTileState extends State<_PartnerListTile> {
  AppUser get user => widget.user;

  // null = still checking whether a thread already exists; true/false once
  // known. Starts null (rather than defaulting to "no thread") so the row
  // doesn't flash a Wave button that immediately flips to Chat once the
  // check resolves for someone already said hi to.
  bool? _hasChat;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _checkExistingChat();
  }

  Future<void> _checkExistingChat() async {
    final hasChat = await ChatService.hasChatWith(user.id);
    if (!mounted) return;
    setState(() => _hasChat = hasChat);
  }

  void _openProfile(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => PartnerProfileScreen(initial: user)),
    );
  }

  void _openChat(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => ChatDetailScreen(user: user)),
    );
  }

  Future<void> _sendWave() async {
    if (_sending) return;
    setState(() => _sending = true);
    try {
      await ChatService.sendWave(other: user);
      if (!mounted) return;
      setState(() {
        _hasChat = true;
        _sending = false;
      });
      // Take them straight into the thread they just started — the button
      // alone flipping to "Chat" isn't enough feedback that the wave went
      // through, and this is exactly where they'd want to be next anyway.
      _openChat(context);
    } catch (e) {
      if (!mounted) return;
      setState(() => _sending = false);
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: const Text("Wave didn't send. Please try again."),
            backgroundColor: AppColors.badgeRed,
          ),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => _openProfile(context),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Column(
              children: [
                AppAvatar.forUser(user, size: 60, showFlag: true),
                const SizedBox(height: 6),
                if (user.activeLabel.isNotEmpty)
                  Row(
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
                        const SizedBox(width: 3),
                      ],
                      Flexible(
                        child: Text(
                          user.activeLabel,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 10,
                            color: AppColors.textTertiary,
                          ),
                        ),
                      ),
                    ],
                  ),
              ],
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          user.name,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 16.5,
                          ),
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
                              fontSize: 9,
                              fontWeight: FontWeight.w800,
                              color: Colors.black,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      _langPill(
                        user.nativeLang.languageCode,
                        AppColors.perfectGreen,
                      ),
                      const SizedBox(width: 6),
                      const Icon(
                        Icons.sync_alt_rounded,
                        size: 13,
                        color: AppColors.textTertiary,
                      ),
                      const SizedBox(width: 6),
                      _langPill(
                        user.learningLang.languageCode,
                        AppColors.primaryPurple,
                        dotted: true,
                      ),
                    ],
                  ),
                  if (user.bio.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      user.bio,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppColors.textSecondary,
                        height: 1.3,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            _WaveOrChatButton(
              hasChat: _hasChat,
              sending: _sending,
              onWave: _sendWave,
              onChat: () => _openChat(context),
            ),
          ],
        ),
      ),
    );
  }

  Widget _langPill(String text, Color color, {bool dotted = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        border: Border.all(color: color, width: 1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 10,
          color: color,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

/// The trailing circular button on a Connect card: a waving hand while no
/// thread exists with this person yet, or a chat bubble once one does
/// (either because a wave was already sent, or because they've messaged
/// before through some other entry point — chat_list_screen.dart's "Add
/// People", a teacher's "Say Hi", etc.). `hasChat == null` means the
/// existence check (`ChatService.hasChatWith`) hasn't resolved yet, so a
/// neutral loading spinner shows instead of guessing either icon.
class _WaveOrChatButton extends StatelessWidget {
  final bool? hasChat;
  final bool sending;
  final VoidCallback onWave;
  final VoidCallback onChat;

  const _WaveOrChatButton({
    required this.hasChat,
    required this.sending,
    required this.onWave,
    required this.onChat,
  });

  @override
  Widget build(BuildContext context) {
    final loading = hasChat == null || sending;
    return GestureDetector(
      onTap: loading
          ? null
          : (hasChat! ? onChat : onWave),
      child: Container(
        width: 44,
        height: 44,
        padding: const EdgeInsets.all(7),
        decoration: BoxDecoration(
          color: const Color(0xFFF3EFFF),
          shape: BoxShape.circle,
          border: Border.all(color: AppColors.primaryPurple.withValues(alpha: 0.18), width: 1),
        ),
        child: loading
            ? const Padding(
                padding: EdgeInsets.all(9),
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AppColors.primaryPurple,
                ),
              )
            : (hasChat!
                ? const Icon(Icons.chat_bubble_rounded, color: AppColors.primaryPurple, size: 20)
                : Image.asset('assets/images/say_hi_hand.png', fit: BoxFit.contain)),
      ),
    );
  }
}

/// The groups the signed-in user is already a member of — the obvious
/// content for this tab once group chats existed at all (see
/// ChatService.createGroup/hellotalk/group_info_screen.dart). Reuses
/// ChatService.streamChatPreviews() (the same live list the Message tab's
/// chat_list_screen.dart already shows, mixing 1:1 and group threads
/// together) rather than a second query, just filtered down to isGroup —
/// so a group's unread state here is always exactly what Message would
/// show for it too, never a second source of truth to drift out of sync.
class _GroupsTab extends StatelessWidget {
  const _GroupsTab();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<ChatPreview>>(
      stream: ChatService.streamChatPreviews(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
          return const Center(
            child: CircularProgressIndicator(strokeWidth: 2.4, color: AppColors.primaryPurple),
          );
        }
        final groups = (snapshot.data ?? const []).where((c) => c.isGroup).toList();
        if (groups.isEmpty) {
          return const _EmptyTab(
            icon: Icons.groups_rounded,
            label: "No groups yet — create one from Message's \"Add People\".",
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          itemCount: groups.length,
          separatorBuilder: (context, i) => const Divider(height: 1, color: AppColors.divider),
          itemBuilder: (context, i) => _GroupTile(group: groups[i]),
        );
      },
    );
  }
}

class _GroupTile extends StatelessWidget {
  final ChatPreview group;
  const _GroupTile({required this.group});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => ChatDetailScreen(groupChatId: group.id)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          children: [
            GroupAvatar(
              groupName: group.groupName,
              groupAvatar: group.groupAvatar,
              members: group.members,
              size: 54,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    group.groupName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: AppColors.textPrimary),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${group.memberCount} members',
                    style: const TextStyle(color: AppColors.textTertiary, fontSize: 12.5),
                  ),
                  if (group.lastMessage.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      group.lastMessage,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: group.unreadCount > 0 ? AppColors.textPrimary : AppColors.textSecondary,
                        fontSize: 13.5,
                        fontWeight: group.unreadCount > 0 ? FontWeight.w700 : FontWeight.w400,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (group.unreadCount > 0)
              Container(
                margin: const EdgeInsets.only(left: 8),
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(color: AppColors.primaryPurple, borderRadius: BorderRadius.circular(10)),
                child: Text(
                  '${group.unreadCount}',
                  style: const TextStyle(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.w800),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _EmptyTab extends StatelessWidget {
  final IconData icon;
  final String label;
  const _EmptyTab({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 48, color: AppColors.textTertiary),
          const SizedBox(height: 12),
          Text(label, style: const TextStyle(color: AppColors.textTertiary)),
        ],
      ),
    );
  }
}
