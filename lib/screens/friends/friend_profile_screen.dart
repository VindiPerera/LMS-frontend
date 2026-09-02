import 'package:flutter/material.dart';
import '../../models/moment.dart';
import '../../models/user.dart';
import '../../models/voiceroom.dart';
import '../../services/friend_service.dart';
import '../../services/moment_service.dart';
import '../../services/voice_room_service.dart';
import '../../theme/app_colors.dart';
import '../../widgets/app_avatar.dart';
import '../hellotalk/chat_detail_screen.dart';
import '../moments/user_moments_screen.dart';
import '../voiceroom/voice_room_detail_screen.dart';

class FriendProfileScreen extends StatefulWidget {
  final String friendId;
  final String source; // 'qr' | 'link' | 'search' | 'notification'

  const FriendProfileScreen({
    super.key,
    required this.friendId,
    this.source = 'search',
  });

  @override
  State<FriendProfileScreen> createState() => _FriendProfileScreenState();
}

class _FriendProfileScreenState extends State<FriendProfileScreen> {
  AppUser? _user;
  bool _loadingUser = true;
  // Set only when the profile genuinely failed to load (user deleted their
  // account, bad/corrupted QR data, offline) — shown instead of a stuck
  // spinner or a made-up profile.
  String? _loadError;

  // Local state for optimistic UI updates
  FriendStatus? _optimisticStatus;
  bool _actionLoading = false;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    try {
      final user = await FriendService.instance.getFriendProfile(widget.friendId);
      if (!mounted) return;
      setState(() {
        _user = user;
        _loadingUser = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadError = e is StateError
            ? e.message
            : 'Could not load this profile. Check your connection and try again.';
        _loadingUser = false;
      });
    }
  }

  /// Runs a friend-status write with optimistic UI: applies [optimistic]
  /// immediately, then reverts it and surfaces a real error on failure
  /// instead of pretending the action succeeded — the live
  /// streamFriendshipStatus() below is the actual source of truth once a
  /// write does succeed.
  Future<void> _runAction({
    required FriendStatus optimistic,
    required Future<void> Function() action,
    required String successMessage,
    required String failureMessage,
  }) async {
    setState(() {
      _optimisticStatus = optimistic;
      _actionLoading = true;
    });
    try {
      await action();
      if (!mounted) return;
      _showSnackBar(successMessage);
    } catch (_) {
      if (!mounted) return;
      setState(() => _optimisticStatus = null); // fall back to the live status
      _showSnackBar(failureMessage);
    } finally {
      if (mounted) setState(() => _actionLoading = false);
    }
  }

  Future<void> _sendFriendRequest() => _runAction(
        optimistic: FriendStatus.pending,
        action: () => FriendService.instance.sendFriendRequest(widget.friendId),
        successMessage: 'Friend request sent!',
        failureMessage: "Couldn't send the request. Try again.",
      );

  Future<void> _acceptRequest() => _runAction(
        optimistic: FriendStatus.friends,
        action: () => FriendService.instance.acceptRequest(widget.friendId),
        successMessage: 'Friend request accepted!',
        failureMessage: "Couldn't accept the request. Try again.",
      );

  Future<void> _declineRequest() => _runAction(
        optimistic: FriendStatus.none,
        action: () => FriendService.instance.declineRequest(widget.friendId),
        successMessage: 'Request declined',
        failureMessage: "Couldn't decline the request. Try again.",
      );

  Future<void> _cancelRequest() => _runAction(
        optimistic: FriendStatus.none,
        action: () => FriendService.instance.cancelRequest(widget.friendId),
        successMessage: 'Request cancelled',
        failureMessage: "Couldn't cancel the request. Try again.",
      );

  Future<void> _unfriend() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Unfriend'),
        content: Text('Are you sure you want to remove ${_user?.name ?? "this user"} from your friends?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Unfriend', style: TextStyle(color: AppColors.badgeRed)),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    await _runAction(
      optimistic: FriendStatus.none,
      action: () => FriendService.instance.unfriend(widget.friendId),
      successMessage: 'Removed from friends',
      failureMessage: "Couldn't remove them. Try again.",
    );
  }

  void _showSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message), duration: const Duration(seconds: 2)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: AppColors.textPrimary),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text(
          'Profile',
          style: TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 18,
            color: AppColors.textPrimary,
          ),
        ),
        centerTitle: true,
      ),
      body: _loadingUser
          ? const Center(
              child: CircularProgressIndicator(
                strokeWidth: 2.4,
                color: AppColors.primaryPurple,
              ),
            )
          : _loadError != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.person_off_outlined,
                          size: 42,
                          color: AppColors.textTertiary,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          _loadError!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: AppColors.textTertiary),
                        ),
                        const SizedBox(height: 12),
                        TextButton(
                          onPressed: () {
                            setState(() {
                              _loadError = null;
                              _loadingUser = true;
                            });
                            _loadProfile();
                          },
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  ),
                )
              : StreamBuilder<FriendStatus>(
              stream: FriendService.instance.streamFriendshipStatus(widget.friendId),
              builder: (context, snapshot) {
                final currentStatus = _optimisticStatus ?? snapshot.data ?? FriendStatus.none;

                return SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  child: Column(
                    children: [
                      // Source Banner (if scanned via QR or opened via deep link)
                      if (widget.source == 'qr' || widget.source == 'link') ...[
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                          decoration: BoxDecoration(
                            color: AppColors.primaryPurple.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: AppColors.primaryPurple.withValues(alpha: 0.2)),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                widget.source == 'qr' ? Icons.qr_code_scanner_rounded : Icons.link_rounded,
                                color: AppColors.primaryPurple,
                                size: 20,
                              ),
                              const SizedBox(width: 10),
                              Text(
                                widget.source == 'qr' ? 'Added via QR code' : 'Opened via shared link',
                                style: const TextStyle(
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.primaryPurple,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 18),
                      ],

                      // Profile Main Card
                      Container(
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(24),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.04),
                              blurRadius: 14,
                              offset: const Offset(0, 5),
                            ),
                          ],
                        ),
                        child: Column(
                          children: [
                            AppAvatar.forUser(
                              _user!,
                              size: 84,
                              showFlag: true,
                              showOnlineDot: true,
                            ),
                            const SizedBox(height: 14),
                            Text(
                              _user!.name,
                              style: const TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w800,
                                color: AppColors.textPrimary,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '@${_user!.handle}',
                              style: const TextStyle(
                                fontSize: 14,
                                color: AppColors.textSecondary,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(height: 12),
                            if (_user!.bio.isNotEmpty) ...[
                              Text(
                                _user!.bio,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  fontSize: 13.5,
                                  height: 1.4,
                                  color: AppColors.textSecondary,
                                ),
                              ),
                              const SizedBox(height: 16),
                            ],

                            // Language Chips
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: AppColors.surfaceLight,
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Text(
                                    'Native: ${_user!.nativeLang}',
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: AppColors.textPrimary,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: AppColors.primaryPurple.withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Text(
                                    'Learning: ${_user!.learningLang}',
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: AppColors.primaryPurple,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            if (_user!.tags.isNotEmpty) ...[
                              const SizedBox(height: 16),
                              const Align(
                                alignment: Alignment.centerLeft,
                                child: Text(
                                  'Interest & Hobbies',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 13.5,
                                    color: AppColors.textPrimary,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 8),
                              Wrap(
                                spacing: 6,
                                runSpacing: 6,
                                children: _user!.tags
                                    .map((t) => Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 10,
                                            vertical: 4,
                                          ),
                                          decoration: BoxDecoration(
                                            color: AppColors.surfaceLight,
                                            borderRadius: BorderRadius.circular(12),
                                          ),
                                          child: Text(
                                            t,
                                            style: const TextStyle(
                                              fontSize: 12,
                                              color: AppColors.textSecondary,
                                            ),
                                          ),
                                        ))
                                    .toList(),
                              ),
                            ],
                            const SizedBox(height: 18),

                            // Active Voice Room Card (if currently hosting)
                            StreamBuilder<VoiceRoom?>(
                              stream: VoiceRoomService.streamActiveRoomForUser(
                                widget.friendId.isNotEmpty ? widget.friendId : _user!.id,
                              ),
                              builder: (context, snapshot) {
                                final room = snapshot.data;
                                if (room == null) return const SizedBox.shrink();
                                return Container(
                                  margin: const EdgeInsets.only(bottom: 16),
                                  padding: const EdgeInsets.all(14),
                                  decoration: BoxDecoration(
                                    gradient: const LinearGradient(
                                      colors: [Color(0xFF8E2DE2), Color(0xFF4A00E0)],
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                    ),
                                    borderRadius: BorderRadius.circular(16),
                                    boxShadow: [
                                      BoxShadow(
                                        color: const Color(0xFF8E2DE2).withValues(alpha: 0.3),
                                        blurRadius: 10,
                                        offset: const Offset(0, 4),
                                      ),
                                    ],
                                  ),
                                  child: Row(
                                    children: [
                                      const CircleAvatar(
                                        backgroundColor: Colors.white24,
                                        child: Icon(Icons.mic_rounded, color: Colors.white),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Row(
                                              children: [
                                                Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                  decoration: BoxDecoration(
                                                    color: Colors.redAccent,
                                                    borderRadius: BorderRadius.circular(8),
                                                  ),
                                                  child: const Text(
                                                    'LIVE NOW',
                                                    style: TextStyle(
                                                      color: Colors.white,
                                                      fontSize: 10,
                                                      fontWeight: FontWeight.w900,
                                                    ),
                                                  ),
                                                ),
                                                const SizedBox(width: 6),
                                                Text(
                                                  room.category,
                                                  style: const TextStyle(
                                                    color: Colors.white70,
                                                    fontSize: 11,
                                                  ),
                                                ),
                                              ],
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                              room.title,
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontWeight: FontWeight.bold,
                                                fontSize: 14,
                                              ),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      ElevatedButton(
                                        onPressed: () {
                                          Navigator.of(context).push(
                                            MaterialPageRoute(
                                              builder: (_) => VoiceRoomDetailScreen(room: room),
                                            ),
                                          );
                                        },
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: Colors.white,
                                          foregroundColor: AppColors.primaryPurple,
                                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(12),
                                          ),
                                        ),
                                        child: const Text(
                                          'Join',
                                          style: TextStyle(fontWeight: FontWeight.bold),
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),

                            // Moments Card Button
                            StreamBuilder<List<Moment>>(
                              stream: MomentService.streamUserMoments(
                                userId: _user!.id.isNotEmpty ? _user!.id : _user!.handle,
                              ),
                              builder: (context, snapshot) {
                                final count = snapshot.data?.length ?? 0;
                                return InkWell(
                                  onTap: () {
                                    Navigator.of(context).push(
                                      MaterialPageRoute(
                                        builder: (_) => UserMomentsScreen(
                                          userId: _user!.id.isNotEmpty
                                              ? _user!.id
                                              : _user!.handle,
                                          userName: _user!.name,
                                        ),
                                      ),
                                    );
                                  },
                                  borderRadius: BorderRadius.circular(16),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 14,
                                      vertical: 12,
                                    ),
                                    decoration: BoxDecoration(
                                      color: AppColors.background,
                                      borderRadius: BorderRadius.circular(16),
                                      border: Border.all(color: AppColors.divider),
                                    ),
                                    child: Row(
                                      children: [
                                        Container(
                                          width: 32,
                                          height: 32,
                                          decoration: BoxDecoration(
                                            color: AppColors.primaryPurple.withValues(alpha: 0.12),
                                            shape: BoxShape.circle,
                                          ),
                                          child: const Icon(
                                            Icons.public_rounded,
                                            size: 16,
                                            color: AppColors.primaryPurple,
                                          ),
                                        ),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                "${_user!.name}'s Moments",
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.w700,
                                                  fontSize: 13.5,
                                                ),
                                              ),
                                              Text(
                                                count > 0 ? '$count moments posted' : 'View moment history',
                                                style: const TextStyle(
                                                  color: AppColors.textTertiary,
                                                  fontSize: 11.5,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        const Icon(
                                          Icons.chevron_right_rounded,
                                          color: AppColors.textTertiary,
                                          size: 20,
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                            const SizedBox(height: 20),

                            // Dynamic Friend Status Action Buttons
                            _buildActionButton(currentStatus),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
    );
  }

  Widget _buildActionButton(FriendStatus status) {
    if (_actionLoading) {
      return const SizedBox(
        height: 48,
        child: Center(
          child: CircularProgressIndicator(
            strokeWidth: 2.4,
            color: AppColors.primaryPurple,
          ),
        ),
      );
    }

    switch (status) {
      case FriendStatus.none:
        return SizedBox(
          width: double.infinity,
          height: 48,
          child: ElevatedButton.icon(
            onPressed: _sendFriendRequest,
            icon: const Icon(Icons.person_add_rounded, size: 20),
            label: const Text(
              'Add Friend',
              style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primaryPurple,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
              ),
            ),
          ),
        );

      case FriendStatus.pending:
        return SizedBox(
          width: double.infinity,
          height: 48,
          child: OutlinedButton.icon(
            onPressed: _cancelRequest,
            icon: const Icon(Icons.access_time_rounded, size: 19),
            label: const Text(
              'Request Sent (Tap to Cancel)',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.textSecondary,
              side: const BorderSide(color: AppColors.divider, width: 1.4),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
              ),
            ),
          ),
        );

      case FriendStatus.incoming:
        return Row(
          children: [
            Expanded(
              child: SizedBox(
                height: 48,
                child: ElevatedButton(
                  onPressed: _acceptRequest,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primaryPurple,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(24),
                    ),
                  ),
                  child: const Text(
                    'Accept',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: SizedBox(
                height: 48,
                child: OutlinedButton(
                  onPressed: _declineRequest,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.badgeRed,
                    side: const BorderSide(color: AppColors.badgeRed, width: 1.4),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(24),
                    ),
                  ),
                  child: const Text(
                    'Decline',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ),
          ],
        );

      case FriendStatus.friends:
        return Row(
          children: [
            Expanded(
              child: SizedBox(
                height: 48,
                child: OutlinedButton.icon(
                  onPressed: _unfriend,
                  icon: const Icon(Icons.check_circle_rounded, color: AppColors.online, size: 20),
                  label: const Text(
                    'Friends ✓',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: AppColors.online,
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: AppColors.online, width: 1.4),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(24),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            SizedBox(
              height: 48,
              width: 48,
              child: IconButton(
                onPressed: () {
                  if (_user != null) {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => ChatDetailScreen(user: _user!),
                      ),
                    );
                  }
                },
                icon: const Icon(Icons.chat_bubble_rounded, color: AppColors.primaryPurple),
                style: IconButton.styleFrom(
                  backgroundColor: AppColors.primaryPurple.withValues(alpha: 0.1),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
              ),
            ),
          ],
        );

      case FriendStatus.blocked:
        return const SizedBox.shrink();
    }
  }
}
