import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../models/moment.dart';
import '../../services/friend_service.dart';
import '../../services/moment_service.dart';
import '../../theme/app_colors.dart';
import '../../widgets/connectivity_banner.dart';
import '../../widgets/moment_card.dart';
import '../../widgets/moment_card_shimmer.dart';
import '../../widgets/notification_badge.dart';
import 'create_moment_screen.dart';
import 'notification_screen.dart';

class MomentsScreen extends StatefulWidget {
  const MomentsScreen({super.key});

  @override
  State<MomentsScreen> createState() => _MomentsScreenState();
}

class _MomentsScreenState extends State<MomentsScreen> {
  final List<Moment> _posts = [];
  DocumentSnapshot<Map<String, dynamic>>? _lastDoc;
  bool _hasMore = true;
  bool _initialLoading = true;
  bool _loadingMore = false;

  final Set<String> _hiddenPostIds = {}; // reported this session
  Set<String> _blockedIds = {};

  // Set on any failure loading/streaming the feed (e.g. a missing Firestore
  // index or a permission-denied) so the UI can show a retry state instead
  // of spinning forever or silently staying empty.
  Object? _loadError;

  final _scrollController = ScrollController();
  StreamSubscription<List<Moment>>? _liveSub;
  StreamSubscription<Set<String>>? _blockedSub;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _blockedSub = FriendService.instance.streamBlockedIds().listen((ids) {
      if (mounted) setState(() => _blockedIds = ids);
    });
    _loadFirstPage();
    _subscribeLiveWindow();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _liveSub?.cancel();
    _blockedSub?.cancel();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final threshold = _scrollController.position.maxScrollExtent - 600;
    if (_scrollController.position.pixels >= threshold) {
      _loadMore();
    }
  }

  Future<void> _loadFirstPage() async {
    try {
      final page = await MomentService.fetchPage(startAfter: null);
      if (!mounted) return;
      setState(() {
        _posts
          ..clear()
          ..addAll(page.moments);
        _lastDoc = page.lastDoc;
        _hasMore = page.hasMore;
        _initialLoading = false;
        _loadError = null;
      });
    } catch (e, st) {
      debugPrint('MomentsScreen: failed to load feed: $e\n$st');
      if (!mounted) return;
      setState(() {
        _initialLoading = false;
        _loadError = e;
      });
    }
  }

  /// Live view of the newest ~15 posts, merged into [_posts] by id so
  /// new/edited/removed posts reflect instantly without disturbing the
  /// pagination cursor (which only ever advances from one-time
  /// [MomentService.fetchPage] reads — see class docs on MomentService).
  void _subscribeLiveWindow() {
    _liveSub = MomentService.streamFirstPage().listen(
      (livePosts) {
        if (!mounted) return;
        setState(() {
          _initialLoading = false;
          _loadError = null;
          final liveIds = livePosts.map((m) => m.id).toSet();
          _posts.removeWhere((p) => _knownLiveIds.contains(p.id) && !liveIds.contains(p.id));
          for (final post in livePosts.reversed) {
            final idx = _posts.indexWhere((p) => p.id == post.id);
            if (idx >= 0) {
              _posts[idx] = post;
            } else {
              _posts.insert(0, post);
            }
          }
          _knownLiveIds = liveIds;
        });
      },
      onError: (Object e, StackTrace st) {
        // Most commonly a missing composite Firestore index or a rules
        // rejection on the `audience` filter — see MomentService docs.
        debugPrint('MomentsScreen: live feed stream error: $e\n$st');
        if (!mounted) return;
        setState(() {
          _initialLoading = false;
          _loadError = e;
        });
      },
    );
  }

  Set<String> _knownLiveIds = {};

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore || _lastDoc == null) return;
    setState(() => _loadingMore = true);
    try {
      final page = await MomentService.fetchPage(startAfter: _lastDoc);
      if (!mounted) return;
      setState(() {
        for (final post in page.moments) {
          if (!_posts.any((p) => p.id == post.id)) {
            _posts.add(post);
          }
        }
        _lastDoc = page.lastDoc;
        _hasMore = page.hasMore;
        _loadingMore = false;
      });
    } catch (e, st) {
      debugPrint('MomentsScreen: failed to load more: $e\n$st');
      if (!mounted) return;
      setState(() => _loadingMore = false);
    }
  }

  Future<void> _refresh() async {
    _lastDoc = null;
    _hasMore = true;
    await _loadFirstPage();
  }

  // Visibility (public/friends/onlyMe) is already enforced server-side via
  // each moment's `audience` field (see MomentService/firestore.rules) —
  // every post reaching `_posts` is one this user is allowed to see. This
  // only needs to cover the two purely-client-side, instantly-toggleable
  // concerns: this session's own reports, and live block status.
  List<Moment> get _visiblePosts {
    return _posts.where((moment) {
      if (_hiddenPostIds.contains(moment.id)) return false;
      if (_blockedIds.contains(moment.user.id)) return false;
      return true;
    }).toList();
  }

  Future<void> _openCreateMoment() async {
    final posted = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const CreateMomentScreen()),
    );
    if (posted == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Moment posted!')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          titleSpacing: 12,
          title: Container(
            height: 40,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: AppColors.surfaceLight,
              borderRadius: BorderRadius.circular(18),
            ),
            child: const TextField(
              decoration: InputDecoration(
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                contentPadding: EdgeInsets.only(top: 8),
                hintText: 'Search moments',
                hintStyle: TextStyle(
                  color: AppColors.textTertiary,
                  fontSize: 13.5,
                ),
                prefixIcon: Icon(
                  Icons.search_rounded,
                  size: 18,
                  color: AppColors.textTertiary,
                ),
                prefixIconConstraints: BoxConstraints(minWidth: 20, minHeight: 20),
              ),
            ),
          ),
          actions: [
            NotificationBadge(
              child: IconButton(
                icon: const Icon(Icons.notifications_none_rounded),
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const NotificationScreen()),
                ),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.edit_outlined),
              onPressed: _openCreateMoment,
            ),
          ],
          bottom: const TabBar(
            isScrollable: false,
            indicatorColor: AppColors.primaryPurple,
            labelColor: AppColors.textPrimary,
            unselectedLabelColor: AppColors.textSecondary,
            labelStyle: TextStyle(fontWeight: FontWeight.w600, fontSize: 14.5),
            tabs: [
              Tab(text: 'Recent'),
              Tab(text: 'Following'),
            ],
          ),
        ),
        body: Column(
          children: [
            const ConnectivityBanner(),
            Expanded(
              child: TabBarView(
                children: [
                  _buildRecentTab(),
                  const Center(
                    child: Text('Following posts', style: TextStyle(color: AppColors.textTertiary)),
                  ),
                ],
              ),
            ),
          ],
        ),

        floatingActionButton: FloatingActionButton(
          onPressed: _openCreateMoment,
          backgroundColor: AppColors.primaryPurple,
          child: const Icon(Icons.add_rounded, size: 28),
        ),
      ),
    );
  }

  Widget _buildRecentTab() {
    if (_initialLoading) {
      return ListView.builder(
        padding: const EdgeInsets.only(bottom: 20),
        itemCount: 3,
        itemBuilder: (context, index) => const MomentCardShimmer(),
      );
    }

    final posts = _visiblePosts;

    if (posts.isEmpty && _loadError != null) {
      return RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            const SizedBox(height: 60),
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Column(
                  children: [
                    const Icon(Icons.error_outline_rounded, size: 48, color: AppColors.textTertiary),
                    const SizedBox(height: 14),
                    const Text(
                      "Couldn't load moments",
                      textAlign: TextAlign.center,
                      style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: AppColors.textPrimary),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '$_loadError',
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 11.5, color: AppColors.textTertiary),
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: _refresh,
                      style: ElevatedButton.styleFrom(backgroundColor: AppColors.primaryPurple),
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    }

    if (posts.isEmpty) {
      return RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            _PostPromptBanner(onPostTap: _openCreateMoment),
            const SizedBox(height: 60),
            const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 32),
                child: Column(
                  children: [
                    Icon(Icons.travel_explore_rounded, size: 56, color: AppColors.textTertiary),
                    SizedBox(height: 14),
                    Text(
                      'Be the first to share a moment!',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: AppColors.textPrimary),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView.builder(
        controller: _scrollController,
        padding: const EdgeInsets.only(bottom: 20),
        itemCount: posts.length + 2,
        itemBuilder: (context, index) {
          if (index == 0) return _PostPromptBanner(onPostTap: _openCreateMoment);
          if (index == posts.length + 1) {
            if (!_hasMore) return const SizedBox.shrink();
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: Center(child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primaryPurple)),
            );
          }
          final post = posts[index - 1];
          return MomentCard(
            key: ValueKey(post.id),
            moment: post,
            onDeleted: () => setState(() => _posts.removeWhere((p) => p.id == post.id)),
            onReported: () => setState(() => _hiddenPostIds.add(post.id)),
          );
        },
      ),
    );
  }
}

class _PostPromptBanner extends StatelessWidget {
  final VoidCallback onPostTap;

  const _PostPromptBanner({required this.onPostTap});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(14, 10, 14, 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppColors.primaryPurple.withValues(alpha: 0.2),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.travel_explore_rounded,
              color: AppColors.primaryPurple,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                Text(
                  'Post your first Moment',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5),
                ),
                SizedBox(height: 2),
                Text(
                  'More partners will see you and reach out to learn together!',
                  style: TextStyle(
                    color: AppColors.textTertiary,
                    fontSize: 11.5,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          ElevatedButton(
            onPressed: onPostTap,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primaryPurple,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
            ),
            child: const Text(
              'Post',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}
