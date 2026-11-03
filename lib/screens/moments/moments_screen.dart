import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../models/moment.dart';
import '../../models/user.dart';
import '../../services/auth_service.dart';
import '../../services/follow_service.dart';
import '../../services/moment_service.dart';
import '../../theme/app_colors.dart';
import '../../widgets/app_avatar.dart';
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
  bool _hasUserSharedFirstMoment = false;

  final Set<String> _hiddenPostIds = {}; // reported this session

  final _searchController = TextEditingController();
  String _searchQuery = '';

  // Set on any failure loading/streaming the feed (e.g. a missing Firestore
  // index or a permission-denied) so the UI can show a retry state instead
  // of spinning forever or silently staying empty.
  Object? _loadError;

  final _scrollController = ScrollController();
  StreamSubscription<List<Moment>>? _liveSub;

  // Following tab: who the signed-in user follows, kept live so a
  // follow/unfollow elsewhere in the app is reflected here without a
  // restart. Filters the *same* `_posts` the Recent tab already loads
  // (see _followingPosts) rather than running a second feed query — a
  // combined `user.id whereIn ids` + `audience arrayContainsAny` Firestore
  // query isn't reliably supported together, and this reuses exactly the
  // data/pagination the Recent tab already maintains.
  Set<String> _followingIds = {};
  bool _followingLoaded = false;
  StreamSubscription<List<AppUser>>? _followingSub;
  final _followingScrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _followingScrollController.addListener(_onFollowingScroll);
    _loadFirstPage();
    _subscribeLiveWindow();
    _subscribeFollowing();
    _checkUserMoments();
  }

  void _subscribeFollowing() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || uid.isEmpty) {
      setState(() => _followingLoaded = true);
      return;
    }
    _followingSub = FollowService.streamFollowing(uid).listen(
      (users) {
        if (!mounted) return;
        setState(() {
          _followingIds = users.map((u) => u.id).toSet();
          _followingLoaded = true;
        });
      },
      onError: (Object e, StackTrace st) {
        debugPrint('MomentsScreen: following stream error: $e\n$st');
        if (!mounted) return;
        setState(() => _followingLoaded = true);
      },
    );
  }

  void _onFollowingScroll() {
    if (!_followingScrollController.hasClients) return;
    final threshold = _followingScrollController.position.maxScrollExtent - 600;
    if (_followingScrollController.position.pixels >= threshold) {
      _loadMore();
    }
  }

  Future<void> _checkUserMoments() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || uid.isEmpty) return;
    if (_posts.any((p) => p.user.id == uid)) {
      if (mounted && !_hasUserSharedFirstMoment) {
        setState(() => _hasUserSharedFirstMoment = true);
      }
      return;
    }
    final count = await MomentService.getUserMomentsCount(uid);
    if (mounted) {
      setState(() => _hasUserSharedFirstMoment = count > 0);
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _followingScrollController.dispose();
    _searchController.dispose();
    _liveSub?.cancel();
    _followingSub?.cancel();
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
      _checkUserMoments();
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
        _checkUserMoments();
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

  // Visibility (public/followers/onlyMe) is already enforced server-side via
  // each moment's `audience` field (see MomentService/firestore.rules) —
  // every post reaching `_posts` is one this user is allowed to see. This
  // only needs to cover this session's own reports — a purely client-side,
  // instantly-toggleable concern (blocking isn't implemented anywhere in
  // the app yet, so there's nothing else to filter here).
  List<Moment> get _visiblePosts {
    return _posts
        .where((moment) => !_hiddenPostIds.contains(moment.id) && _matchesSearch(moment))
        .toList();
  }

  // Client-side, against whatever's already loaded in `_posts` — same
  // approach chat_list_screen.dart's search uses, since there's no backend
  // full-text search service wired into this app (Firestore itself can't do
  // substring matching). Scrolling to load more pages naturally surfaces
  // more candidates for the current query as they come in.
  bool _matchesSearch(Moment moment) {
    if (_searchQuery.isEmpty) return true;
    final q = _searchQuery.toLowerCase();
    return moment.text.toLowerCase().contains(q) ||
        moment.user.name.toLowerCase().contains(q) ||
        moment.user.handle.toLowerCase().contains(q);
  }

  /// Visible posts (same reported/search filtering as Recent) narrowed to
  /// authors the signed-in user follows.
  List<Moment> get _followingPosts =>
      _visiblePosts.where((moment) => _followingIds.contains(moment.user.id)).toList();

  Future<void> _openCreateMoment({String? initialText, String? initialPicker}) async {
    final posted = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => CreateMomentScreen(
          initialText: initialText,
          initialPicker: initialPicker,
        ),
      ),
    );
    if (posted == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Moment posted!')));
      setState(() => _hasUserSharedFirstMoment = true);
      await _refresh();
    }
  }

  Widget _buildComposerHeader() {
    if (!_hasUserSharedFirstMoment) {
      return _PostPromptBanner(
        onPostTap: _openCreateMoment,
        onPhotoTap: () => _openCreateMoment(initialPicker: 'image'),
        onTopicTap: (topic) => _openCreateMoment(initialText: '$topic '),
      );
    }

    return _RegularPostMomentCard(
      onTap: _openCreateMoment,
      onPhotoTap: () => _openCreateMoment(initialPicker: 'image'),
      onTextTap: () => _openCreateMoment(),
    );
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
            // A TextField's prefixIcon fights a fixed-height parent for
            // vertical space (that's what pushed the hint text off-center
            // before) — a plain Row + isDense TextField, same as
            // chat_list_screen.dart's search bar, centers reliably instead.
            child: Row(
              children: [
                const Icon(
                  Icons.search_rounded,
                  size: 18,
                  color: AppColors.textTertiary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    textAlignVertical: TextAlignVertical.center,
                    onChanged: (val) => setState(() => _searchQuery = val.trim()),
                    decoration: const InputDecoration(
                      border: InputBorder.none,
                      isDense: true,
                      contentPadding: EdgeInsets.zero,
                      hintText: 'Search moments',
                      hintStyle: TextStyle(
                        color: AppColors.textTertiary,
                        fontSize: 13.5,
                      ),
                    ),
                    style: const TextStyle(fontSize: 13.5),
                  ),
                ),
                if (_searchQuery.isNotEmpty)
                  GestureDetector(
                    onTap: () {
                      _searchController.clear();
                      setState(() => _searchQuery = '');
                    },
                    child: const Icon(
                      Icons.cancel_rounded,
                      size: 17,
                      color: AppColors.textTertiary,
                    ),
                  ),
              ],
            ),
          ),
          actions: [
            IconButton(
              icon: const NotificationBadge(
                child: Icon(Icons.notifications_none_rounded),
              ),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const NotificationScreen()),
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
                  _buildFollowingTab(),
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

    if (posts.isEmpty && _searchQuery.isNotEmpty) {
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
                    const Icon(Icons.search_off_rounded, size: 48, color: AppColors.textTertiary),
                    const SizedBox(height: 14),
                    Text(
                      'No moments matching "$_searchQuery"',
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: AppColors.textPrimary),
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
            _buildComposerHeader(),

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

    // No composer header while a search is active — a blank "share what's
    // on your mind" box above filtered results reads oddly mid-search.
    final headerCount = _searchQuery.isEmpty ? 1 : 0;

    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView.builder(
        controller: _scrollController,
        padding: const EdgeInsets.only(bottom: 20),
        itemCount: posts.length + headerCount + 1,
        itemBuilder: (context, index) {
          if (headerCount == 1 && index == 0) {
            return _buildComposerHeader();
          }
          if (index == posts.length + headerCount) {
            if (!_hasMore) return const SizedBox.shrink();
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: Center(child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primaryPurple)),
            );
          }
          final post = posts[index - headerCount];
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

  Widget _buildFollowingTab() {
    if (_initialLoading || !_followingLoaded) {
      return ListView.builder(
        padding: const EdgeInsets.only(bottom: 20),
        itemCount: 3,
        itemBuilder: (context, index) => const MomentCardShimmer(),
      );
    }

    if (_followingIds.isEmpty) {
      return RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            const SizedBox(height: 70),
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Column(
                  children: [
                    const Icon(Icons.people_outline_rounded, size: 52, color: AppColors.textTertiary),
                    const SizedBox(height: 14),
                    const Text(
                      "You're not following anyone yet",
                      textAlign: TextAlign.center,
                      style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: AppColors.textPrimary),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Follow partners from Connect to see their moments here.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 12.5, color: AppColors.textTertiary),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    }

    final posts = _followingPosts;

    if (posts.isEmpty) {
      return RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            const SizedBox(height: 70),
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Column(
                  children: [
                    const Icon(Icons.inbox_outlined, size: 52, color: AppColors.textTertiary),
                    const SizedBox(height: 14),
                    Text(
                      _searchQuery.isNotEmpty
                          ? 'No moments matching "$_searchQuery"'
                          : 'No moments yet from people you follow',
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: AppColors.textPrimary),
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
        controller: _followingScrollController,
        padding: const EdgeInsets.only(bottom: 20),
        itemCount: posts.length + 1,
        itemBuilder: (context, index) {
          if (index == posts.length) {
            if (!_hasMore) return const SizedBox.shrink();
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: Center(child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primaryPurple)),
            );
          }
          final post = posts[index];
          return MomentCard(
            key: ValueKey('following_${post.id}'),
            moment: post,
            onDeleted: () => setState(() => _posts.removeWhere((p) => p.id == post.id)),
            onReported: () => setState(() => _hiddenPostIds.add(post.id)),
          );
        },
      ),
    );
  }
}

class _RegularPostMomentCard extends StatelessWidget {
  final VoidCallback onTap;
  final VoidCallback onPhotoTap;
  final VoidCallback onTextTap;

  const _RegularPostMomentCard({
    required this.onTap,
    required this.onPhotoTap,
    required this.onTextTap,
  });

  @override
  Widget build(BuildContext context) {
    final user = AuthService.instance.currentUser;

    return Container(
      margin: const EdgeInsets.fromLTRB(14, 10, 14, 14),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(20),
            child: Row(
              children: [
                if (user != null)
                  AppAvatar.forUser(user, size: 38)
                else
                  const AppAvatar(seed: 'me', size: 38),
                const SizedBox(width: 12),
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceLight,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: AppColors.divider.withValues(alpha: 0.6)),
                    ),
                    child: const Text(
                      'Share what is on your mind...',
                      style: TextStyle(
                        color: AppColors.textTertiary,
                        fontSize: 13.5,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          const Divider(height: 1, color: AppColors.divider),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _actionItem(
                icon: Icons.image_outlined,
                label: 'Photo',
                color: const Color(0xFF00C48C),
                onTap: onPhotoTap,
              ),
              _actionItem(
                icon: Icons.edit_note_rounded,
                label: 'Write',
                color: AppColors.primaryPurple,
                onTap: onTextTap,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _actionItem({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Row(
          children: [
            Icon(icon, size: 19, color: color),
            const SizedBox(width: 6),
            Text(
              label,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w600,
                fontSize: 12.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PostPromptBanner extends StatelessWidget {
  final VoidCallback onPostTap;
  final VoidCallback onPhotoTap;
  final ValueChanged<String> onTopicTap;

  const _PostPromptBanner({
    required this.onPostTap,
    required this.onPhotoTap,
    required this.onTopicTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(14, 10, 14, 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Row
          InkWell(
            onTap: onPostTap,
            borderRadius: BorderRadius.circular(12),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: AppColors.primaryPurple.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.explore_rounded,
                    color: AppColors.primaryPurple,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: const [
                      Text(
                        'Post your first Moment',
                        style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                      ),
                      SizedBox(height: 3),
                      Text(
                        'Share with partners worldwide to start learning together!',
                        style: TextStyle(
                          color: AppColors.textTertiary,
                          fontSize: 12,
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
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
                  ),
                  child: const Text(
                    'Post',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 14),
          const Divider(height: 1, color: AppColors.divider),
          const SizedBox(height: 12),

          // Shortcut Actions (Photo, Video, Write)
          Row(
            children: [
              _shortcutButton(
                icon: Icons.image_outlined,
                label: 'Photo',
                color: const Color(0xFF00C48C),
                onTap: onPhotoTap,
              ),
              const SizedBox(width: 10),
              _shortcutButton(
                icon: Icons.edit_note_rounded,
                label: 'Write',
                color: AppColors.primaryPurple,
                onTap: onPostTap,
              ),
            ],
          ),

          const SizedBox(height: 12),

          // Quick Topic Prompt Pills
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _topicPill('👋 #SelfIntroduction', onTopicTap),
                const SizedBox(width: 8),
                _topicPill('🎯 #DailyGoal', onTopicTap),
                const SizedBox(width: 8),
                _topicPill('❓ #AskQuestion', onTopicTap),
                const SizedBox(width: 8),
                _topicPill('📸 #MyCity', onTopicTap),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _shortcutButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 18, color: color),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.w700,
                  fontSize: 12.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _topicPill(String topic, ValueChanged<String> onTap) {
    return GestureDetector(
      onTap: () => onTap(topic),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: AppColors.surfaceLight,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.divider),
        ),
        child: Text(
          topic,
          style: const TextStyle(
            fontSize: 12,
            color: AppColors.textSecondary,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}


