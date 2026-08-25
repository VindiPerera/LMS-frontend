import 'package:flutter/material.dart';
import '../../models/user.dart';
import '../../services/partner_service.dart';
import '../../services/teacher_service.dart';
import '../../theme/app_colors.dart';

import '../../widgets/app_avatar.dart';
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
  final _filters = const ['Recommended', 'Nearby', 'New Users', 'Same City'];
  int _filterIndex = 0;

  bool _searching = false;
  final _searchController = TextEditingController();
  String _searchQuery = '';

  List<AppUser>? _partners;
  String? _error;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
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
    } catch (_) {
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
            Tab(text: 'Teachers'),
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
          const _EmptyTab(icon: Icons.groups_rounded, label: 'No groups yet'),
          _TeachersTab(searchQuery: _searchQuery),
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

    final users = searchQuery.isEmpty
        ? allUsers
        : allUsers.where((u) {
            return u.name.toLowerCase().contains(searchQuery) ||
                u.handle.toLowerCase().contains(searchQuery);
          }).toList();

    if (users.isEmpty) {
      return Center(
        child: Text(
          searchQuery.isNotEmpty
              ? 'No partners matching "$searchQuery"'
              : 'No partners yet — check back soon!',
          style: const TextStyle(color: AppColors.textTertiary),
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

class _PartnerListTile extends StatelessWidget {
  final AppUser user;
  const _PartnerListTile({required this.user});

  void _openProfile(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => PartnerProfileScreen(initial: user)),
    );
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
                  if (user.tags.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: user.tags.map((t) => _tagChip(t)).toList(),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => ChatDetailScreen(user: user)),
              ),
              child: Container(
                width: 44,
                height: 44,
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: const Color(0xFFF3EFFF),
                  shape: BoxShape.circle,
                  border: Border.all(color: AppColors.primaryPurple.withValues(alpha: 0.18), width: 1),
                ),
                child: Image.asset(
                  'assets/images/say_hi_hand.png',
                  fit: BoxFit.contain,
                ),
              ),
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

  Widget _tagChip(String text) {
    final isHighlight =
        text.contains('both like') || text == 'New' || text == 'Free to Chat';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: isHighlight ? const Color(0xFFFFE9D9) : AppColors.surfaceLight,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11.5,
          color: isHighlight
              ? const Color(0xFFD9722E)
              : AppColors.textSecondary,
          fontWeight: FontWeight.w600,
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

class _TeachersTab extends StatefulWidget {
  final String searchQuery;
  const _TeachersTab({this.searchQuery = ''});

  @override
  State<_TeachersTab> createState() => _TeachersTabState();
}

class _TeachersTabState extends State<_TeachersTab> {
  List<AppUser>? _teachers;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadTeachers();
  }

  Future<void> _loadTeachers() async {
    final teachers = await TeacherService.fetchTeachers();
    if (!mounted) return;
    setState(() {
      _teachers = teachers;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(
          strokeWidth: 2.4,
          color: AppColors.primaryPurple,
        ),
      );
    }

    final allTeachers = _teachers ?? const [];
    final query = widget.searchQuery;
    final teachers = query.isEmpty
        ? allTeachers
        : allTeachers.where((t) {
            return t.name.toLowerCase().contains(query) ||
                t.handle.toLowerCase().contains(query);
          }).toList();

    if (teachers.isEmpty) {
      return Center(
        child: Text(
          query.isNotEmpty
              ? 'No teachers matching "$query"'
              : 'No teachers available right now.',
          style: const TextStyle(color: AppColors.textTertiary),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadTeachers,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 24),
        itemCount: teachers.length,
        separatorBuilder: (_, _) => const SizedBox(height: 12),

        itemBuilder: (context, i) => _TeacherCard(teacher: teachers[i]),
      ),
    );
  }
}

class _TeacherCard extends StatelessWidget {
  final AppUser teacher;
  const _TeacherCard({required this.teacher});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => PartnerProfileScreen(initial: teacher)),
        );
      },
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.divider),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.03),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AppAvatar.forUser(teacher, size: 54, showFlag: true),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              teacher.name,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 16.5,
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFF6B47EB),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Text(
                              'TEACHER',
                              style: TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.w800,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        teacher.detail.isNotEmpty ? teacher.detail : 'English Tutor',
                        style: const TextStyle(
                          fontSize: 12.5,
                          color: AppColors.primaryPurple,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          const Icon(Icons.star_rounded, size: 15, color: Color(0xFFFFB300)),
                          const SizedBox(width: 3),
                          const Text(
                            '4.9 (120+ lessons)',
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textSecondary,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '• ${teacher.activeLabel.isNotEmpty ? teacher.activeLabel : "Active now"}',
                            style: const TextStyle(
                              fontSize: 11.5,
                              color: AppColors.textTertiary,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (teacher.bio.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(
                teacher.bio,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 12.5,
                  color: AppColors.textSecondary,
                  height: 1.3,
                ),
              ),
            ],
            const SizedBox(height: 12),
            const Divider(height: 1, color: AppColors.divider),
            const SizedBox(height: 10),
            Row(
              children: [
                // Say Hi Button with waving hand asset
                GestureDetector(
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => ChatDetailScreen(user: teacher)),
                    );
                  },
                  child: Container(
                    height: 38,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF3EFFF),
                      borderRadius: BorderRadius.circular(19),
                      border: Border.all(
                        color: AppColors.primaryPurple.withValues(alpha: 0.18),
                        width: 1,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Image.asset(
                          'assets/images/say_hi_hand.png',
                          width: 20,
                          height: 20,
                        ),
                        const SizedBox(width: 6),
                        const Text(
                          'Say Hi',
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                            color: AppColors.primaryPurple,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                const Spacer(),

                // Book Tutor Button
                ElevatedButton.icon(
                  onPressed: () {
                    TeacherService.bookTutor(context, teacher: teacher);
                  },
                  icon: const Icon(Icons.calendar_month_rounded, size: 16),
                  label: const Text(
                    'Book Tutor',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF6B47EB),
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

