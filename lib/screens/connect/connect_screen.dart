import 'package:flutter/material.dart';
import '../../models/user.dart';
import '../../services/api_client.dart';
import '../../services/partner_service.dart';
import '../../theme/app_colors.dart';
import '../../widgets/app_avatar.dart';

class ConnectScreen extends StatefulWidget {
  const ConnectScreen({super.key});

  @override
  State<ConnectScreen> createState() => _ConnectScreenState();
}

class _ConnectScreenState extends State<ConnectScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  final _filters = const ['Recommended', 'Nearby', 'New Users', 'Same City'];
  int _filterIndex = 0;

  List<AppUser>? _partners;
  String? _error;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadPartners();
  }

  Future<void> _loadPartners() async {
    setState(() => _error = null);
    try {
      final partners = await PartnerService.fetchPartners();
      if (!mounted) return;
      setState(() => _partners = partners);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'Could not reach the server. Is the backend running?');
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Add Friends', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 19)),
            const SizedBox(width: 6),
            IconButton(
              icon: const Icon(Icons.add_rounded, size: 20),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              onPressed: () {},
            ),
          ],
        ),
        actions: [
          IconButton(icon: const Icon(Icons.tune_rounded), onPressed: () {}),
          IconButton(icon: const Icon(Icons.search_rounded), onPressed: () {}),
        ],
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          indicatorColor: AppColors.primaryPurple,
          labelColor: AppColors.primaryPurple,
          unselectedLabelColor: AppColors.textSecondary,
          labelStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14.5),
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
          ),
          const _EmptyTab(icon: Icons.groups_rounded, label: 'No groups yet'),
          const _EmptyTab(icon: Icons.school_rounded, label: 'No teachers yet'),
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

  const _PartnersTab({
    required this.filters,
    required this.filterIndex,
    required this.onFilter,
    required this.partners,
    required this.error,
    required this.onRetry,
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
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
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
            const Icon(Icons.cloud_off_rounded, size: 42, color: AppColors.textTertiary),
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Text(error!, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.textTertiary)),
            ),
            const SizedBox(height: 12),
            TextButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      );
    }

    final users = partners;
    if (users == null) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2.4, color: AppColors.primaryPurple));
    }

    if (users.isEmpty) {
      return const Center(
        child: Text('No partners yet — check back soon!', style: TextStyle(color: AppColors.textTertiary)),
      );
    }

    return RefreshIndicator(
      onRefresh: () async => onRetry(),
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(14, 6, 14, 16),
        itemCount: users.length,
        separatorBuilder: (context, i) => const Divider(height: 1, color: AppColors.divider),
        itemBuilder: (context, i) => _PartnerListTile(user: users[i]),
      ),
    );
  }
}

class _PartnerListTile extends StatelessWidget {
  final AppUser user;
  const _PartnerListTile({required this.user});

  @override
  Widget build(BuildContext context) {
    return Padding(
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
                        decoration: const BoxDecoration(color: AppColors.online, shape: BoxShape.circle),
                      ),
                      const SizedBox(width: 3),
                    ],
                    Flexible(
                      child: Text(
                        user.activeLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 10, color: AppColors.textTertiary),
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
                        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16.5),
                      ),
                    ),
                    if (user.isVip) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(color: AppColors.vipGold, borderRadius: BorderRadius.circular(6)),
                        child: const Text('VIP', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w800, color: Colors.black)),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    _langPill(user.nativeLang.substring(0, 2).toUpperCase(), AppColors.perfectGreen),
                    const SizedBox(width: 6),
                    const Icon(Icons.sync_alt_rounded, size: 13, color: AppColors.textTertiary),
                    const SizedBox(width: 6),
                    _langPill(user.learningLang.substring(0, 2).toUpperCase(), AppColors.primaryPurple, dotted: true),
                  ],
                ),
                if (user.bio.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    user.bio,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13, color: AppColors.textSecondary, height: 1.3),
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
          Container(
            width: 44,
            height: 44,
            decoration: const BoxDecoration(color: AppColors.primaryPurple, shape: BoxShape.circle),
            child: const Icon(Icons.front_hand_rounded, color: Colors.white, size: 20),
          ),
        ],
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
      child: Text(text, style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.w800)),
    );
  }

  Widget _tagChip(String text) {
    final isHighlight = text.contains('both like') || text == 'New' || text == 'Free to Chat';
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
          color: isHighlight ? const Color(0xFFD9722E) : AppColors.textSecondary,
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
