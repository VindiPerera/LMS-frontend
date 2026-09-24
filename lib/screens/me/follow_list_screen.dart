import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../models/user.dart';
import '../../services/follow_service.dart';
import '../../theme/app_colors.dart';
import '../../widgets/app_avatar.dart';
import '../friends/friend_profile_screen.dart';

/// Who [uid] follows / is followed by — reached by tapping the Following or
/// Followers count on me_screen.dart's (or, via partner_profile_screen.dart,
/// anyone's) profile header. [initialTab] picks which list opens first.
class FollowListScreen extends StatefulWidget {
  final String uid;
  final String userName;
  final int initialTab; // 0: Following, 1: Followers

  const FollowListScreen({
    super.key,
    required this.uid,
    required this.userName,
    this.initialTab = 0,
  });

  @override
  State<FollowListScreen> createState() => _FollowListScreenState();
}

class _FollowListScreenState extends State<FollowListScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 2,
      vsync: this,
      initialIndex: widget.initialTab,
    );
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        centerTitle: true,
        title: Text(
          widget.userName,
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 17),
        ),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: AppColors.primaryPurple,
          labelColor: AppColors.primaryPurple,
          unselectedLabelColor: AppColors.textSecondary,
          labelStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14.5),
          tabs: const [Tab(text: 'Following'), Tab(text: 'Followers')],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _FollowList(stream: FollowService.streamFollowing(widget.uid)),
          _FollowList(stream: FollowService.streamFollowers(widget.uid)),
        ],
      ),
    );
  }
}

class _FollowList extends StatelessWidget {
  final Stream<List<AppUser>> stream;
  const _FollowList({required this.stream});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<AppUser>>(
      stream: stream,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(
            child: CircularProgressIndicator(
              strokeWidth: 2.4,
              color: AppColors.primaryPurple,
            ),
          );
        }

        final users = snapshot.data!;
        if (users.isEmpty) {
          return const Center(
            child: Text(
              'Nobody here yet',
              style: TextStyle(color: AppColors.textTertiary),
            ),
          );
        }

        return ListView.separated(
          padding: const EdgeInsets.symmetric(vertical: 4),
          itemCount: users.length,
          separatorBuilder: (_, _) =>
              const Divider(height: 1, indent: 72, color: AppColors.divider),
          itemBuilder: (context, i) => _FollowRow(user: users[i]),
        );
      },
    );
  }
}

class _FollowRow extends StatelessWidget {
  final AppUser user;
  const _FollowRow({required this.user});

  bool get _isSelf => user.id == FirebaseAuth.instance.currentUser?.uid;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: AppAvatar.forUser(user, size: 48, showFlag: true),
      title: Text(
        user.name,
        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
      ),
      subtitle: Text(
        '@${user.handle}',
        style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
      ),
      trailing: _isSelf ? null : _FollowButton(user: user),
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => FriendProfileScreen(friendId: user.id, source: 'search'),
          ),
        );
      },
    );
  }
}

class _FollowButton extends StatelessWidget {
  final AppUser user;
  const _FollowButton({required this.user});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<bool>(
      stream: FollowService.streamIsFollowing(user.id),
      initialData: false,
      builder: (context, snapshot) {
        final isFollowing = snapshot.data ?? false;
        return SizedBox(
          height: 32,
          child: OutlinedButton(
            onPressed: () {
              if (isFollowing) {
                FollowService.unfollow(user.id);
              } else {
                FollowService.follow(user);
              }
            },
            style: OutlinedButton.styleFrom(
              foregroundColor: isFollowing
                  ? AppColors.textSecondary
                  : AppColors.primaryPurple,
              side: BorderSide(
                color: isFollowing ? AppColors.divider : AppColors.primaryPurple,
              ),
              padding: const EdgeInsets.symmetric(horizontal: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            ),
            child: Text(
              isFollowing ? 'Following' : 'Follow',
              style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
            ),
          ),
        );
      },
    );
  }
}
