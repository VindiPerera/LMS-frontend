import 'package:cached_network_image/cached_network_image.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_linkify/flutter_linkify.dart';
// UserTagLinkifier/UserTagElement (the @mention linkifier) live in the
// underlying linkify package, not re-exported by flutter_linkify.
import 'package:linkify/linkify.dart' show UserTagLinkifier, UserTagElement;
import 'package:url_launcher/url_launcher.dart';

import '../models/moment.dart';
import '../screens/friends/friend_profile_screen.dart';
import '../screens/moments/create_moment_screen.dart';
import '../screens/moments/image_viewer_screen.dart';
import '../screens/moments/video_player_screen.dart';
import '../services/comment_service.dart';
import '../services/moment_service.dart';
import '../theme/app_colors.dart';
import 'app_avatar.dart';
import 'comment_sheet.dart';
import 'embedded_post_card.dart';
import 'post_image_grid.dart';
import 'reaction_picker.dart';
import 'report_sheet.dart';
import 'reshare_sheet.dart';

/// Hashtag support isn't built into package:linkify, unlike @mentions
/// (UserTagLinkifier) — this mirrors that package's own Linkifier pattern.
class _HashtagElement extends LinkableElement {
  final String tag;
  _HashtagElement(this.tag) : super('#$tag', '#$tag');

  @override
  bool operator ==(other) => equals(other);
  @override
  int get hashCode => Object.hash(text, originText, url, tag);
  @override
  bool equals(other) => other is _HashtagElement && super.equals(other) && other.tag == tag;
}

class _HashtagLinkifier extends Linkifier {
  const _HashtagLinkifier();
  static final _pattern = RegExp(r'#(\w+)');

  @override
  List<LinkifyElement> parse(List<LinkifyElement> elements, LinkifyOptions options) {
    final list = <LinkifyElement>[];
    for (final element in elements) {
      if (element is TextElement) {
        var start = 0;
        for (final match in _pattern.allMatches(element.text)) {
          if (match.start > start) {
            list.add(TextElement(element.text.substring(start, match.start)));
          }
          list.add(_HashtagElement(match.group(1)!));
          start = match.end;
        }
        if (start < element.text.length) {
          list.add(TextElement(element.text.substring(start)));
        }
      } else {
        list.add(element);
      }
    }
    return list;
  }
}

/// The full Moments feed post card: header/menu, linkified text,
/// image/video, reactions, comment/reshare counts, and (for a reshare) the
/// embedded original post.
class MomentCard extends StatefulWidget {
  final Moment moment;

  /// Called after a successful soft-delete so the feed can drop this card
  /// immediately instead of waiting for the next snapshot.
  final VoidCallback? onDeleted;

  /// Called after a successful report so the feed can hide this card for
  /// the rest of the session.
  final VoidCallback? onReported;

  const MomentCard({super.key, required this.moment, this.onDeleted, this.onReported});

  @override
  State<MomentCard> createState() => _MomentCardState();
}

class _MomentCardState extends State<MomentCard> {
  late Moment _moment = widget.moment;
  bool _expanded = false;
  final _heartKey = GlobalKey();

  String? get _uid => FirebaseAuth.instance.currentUser?.uid;
  bool get _isOwner => _uid != null && _uid == _moment.user.id;

  @override
  void didUpdateWidget(covariant MomentCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.moment.id != widget.moment.id ||
        oldWidget.moment.updatedAt != widget.moment.updatedAt ||
        oldWidget.moment.likeCount != widget.moment.likeCount ||
        oldWidget.moment.commentCount != widget.moment.commentCount ||
        oldWidget.moment.reshareCount != widget.moment.reshareCount ||
        oldWidget.moment.likes.length != widget.moment.likes.length ||
        oldWidget.moment.reactions != widget.moment.reactions) {
      setState(() {
        _moment = widget.moment;
      });
    }
  }

  void _toggleLike() {
    final uid = _uid;
    if (uid == null) return;
    final wasLiked = _moment.isLikedBy(uid);
    final prevMoment = _moment;

    setState(() {
      final likes = List<String>.from(_moment.likes);
      final reactions = _cloneReactions();
      if (wasLiked) {
        likes.remove(uid);
        for (final bucket in reactions.values) {
          bucket.remove(uid);
        }
      } else {
        likes.add(uid);
        final heart = reactions[MomentService.defaultReactionEmoji] ?? <String>[];
        if (!heart.contains(uid)) heart.add(uid);
        reactions[MomentService.defaultReactionEmoji] = heart;
      }
      _moment = _moment.copyWith(likes: likes, reactions: reactions, likeCount: likes.length);
    });

    HapticFeedback.lightImpact();
    MomentService.toggleLike(postId: _moment.id, uid: uid).catchError((e) {
      debugPrint('Error toggling like: $e');
      if (mounted) {
        setState(() => _moment = prevMoment);
      }
    });
  }

  void _setReaction(String emoji) {
    final uid = _uid;
    if (uid == null) return;
    final prevMoment = _moment;

    setState(() {
      final likes = List<String>.from(_moment.likes);
      final reactions = _cloneReactions();
      String? previous;
      for (final entry in reactions.entries) {
        if (entry.value.contains(uid)) {
          previous = entry.key;
          entry.value.remove(uid);
        }
      }
      if (previous == emoji) {
        likes.remove(uid);
      } else {
        final bucket = reactions[emoji] ?? <String>[];
        if (!bucket.contains(uid)) bucket.add(uid);
        reactions[emoji] = bucket;
        if (!likes.contains(uid)) likes.add(uid);
      }
      _moment = _moment.copyWith(likes: likes, reactions: reactions, likeCount: likes.length);
    });

    MomentService.setReaction(postId: _moment.id, uid: uid, emoji: emoji).catchError((e) {
      debugPrint('Error setting reaction: $e');
      if (mounted) {
        setState(() => _moment = prevMoment);
      }
    });
  }

  Map<String, List<String>> _cloneReactions() =>
      _moment.reactions.map((key, value) => MapEntry(key, List<String>.from(value)));

  void _showReactionPickerFromHeart() {
    final box = _heartKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return;
    final anchor = box.localToGlobal(box.size.center(Offset.zero));
    showReactionPicker(context, anchor: anchor, onSelect: _setReaction);
  }

  void _openComments() => showCommentSheet(context, moment: _moment);

  Future<void> _openReshare() async {
    final success = await showReshareSheet(context, original: _moment);
    if (success && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Reshared to your Moments.')),
      );
    }
  }

  void _openProfile() {
    if (_moment.user.id.isEmpty) return;
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => FriendProfileScreen(friendId: _moment.user.id, source: 'moment')),
    );
  }

  void _openImage(int index) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ImageViewerScreen(
          postId: _moment.id,
          imageUrls: _moment.imageUrls,
          initialIndex: index,
        ),
      ),
    );
  }

  void _openVideo() {
    final url = _moment.videoUrl;
    if (url == null) return;
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => VideoPlayerScreen(videoUrl: url)));
  }

  Future<void> _openMention(String handle) async {
    final uid = await CommentService.findUserIdByHandle(handle);
    if (!mounted || uid == null) return;
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => FriendProfileScreen(friendId: uid, source: 'moment')),
    );
  }

  Future<void> _handleLinkOpen(LinkableElement link) async {
    if (link is UrlElement) {
      final uri = Uri.tryParse(link.url);
      if (uri != null) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    } else if (link is UserTagElement) {
      await _openMention(link.userTag.replaceFirst('@', ''));
    } else if (link is _HashtagElement) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Hashtag search isn't available yet.")),
      );
    }
  }

  Future<void> _handleMenuSelect(String action) async {
    switch (action) {
      case 'edit':
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => CreateMomentScreen(existing: _moment)),
        );
        break;
      case 'archive':
        await MomentService.archiveMoment(_moment.id);
        if (!mounted) return;
        setState(() => _moment = _moment.copyWith(visibility: MomentVisibility.onlyMe));
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Moment archived — only you can see it now.')),
        );
        break;
      case 'delete':
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('Delete this moment?'),
            content: const Text('This cannot be undone.'),
            actions: [
              TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
              TextButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Delete', style: TextStyle(color: AppColors.badgeRed)),
              ),
            ],
          ),
        );
        if (confirmed == true) {
          HapticFeedback.mediumImpact();
          await MomentService.softDeleteMoment(_moment.id);
          widget.onDeleted?.call();
        }
        break;
      case 'report':
        final reported = await showReportSheet(context, postId: _moment.id);
        if (reported) {
          widget.onReported?.call();
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Thanks for your report.')),
            );
          }
        }
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final uid = _uid;
    final isLiked = uid != null && _moment.isLikedBy(uid);

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.divider, width: 6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(),
          if (_moment.text.isNotEmpty) ...[
            const SizedBox(height: 10),
            _buildText(),
          ],
          if (_moment.isReshare && (_moment.originalPostId ?? '').isNotEmpty)
            EmbeddedPostCard(originalPostId: _moment.originalPostId!)
          else if (_moment.mediaType == MomentMediaType.image && _moment.imageUrls.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: PostImageGrid(
                  postId: _moment.id,
                  imageUrls: _moment.imageUrls,
                  onTapImage: _openImage,
                ),
              ),
            )
          else if (_moment.mediaType == MomentMediaType.video && _moment.videoUrl != null)
            Padding(padding: const EdgeInsets.only(top: 10), child: _buildVideoThumb()),
          const SizedBox(height: 8),
          _buildActionBar(isLiked: isLiked),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          onTap: _openProfile,
          child: AppAvatar.forUser(_moment.user, size: 44, showFlag: true),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: GestureDetector(
            onTap: _openProfile,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        _moment.user.name,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                      ),
                    ),
                    if (_moment.isReshare) ...[
                      const SizedBox(width: 6),
                      const Icon(Icons.repeat_rounded, size: 13, color: AppColors.textTertiary),
                      const SizedBox(width: 2),
                      const Text(
                        'reshared',
                        style: TextStyle(color: AppColors.textTertiary, fontSize: 11.5),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 3),
                Row(
                  children: [
                    _langBadge(_moment.user.nativeLang, AppColors.perfectGreen),
                    const SizedBox(width: 4),
                    const Icon(Icons.sync_alt_rounded, size: 12, color: AppColors.textTertiary),
                    const SizedBox(width: 4),
                    _langBadge(_moment.user.learningLang, AppColors.primaryPurple),
                  ],
                ),
              ],
            ),
          ),
        ),
        Text(_moment.timeAgo, style: const TextStyle(color: AppColors.textTertiary, fontSize: 11.5)),
        _buildMenu(),
      ],
    );
  }

  Widget _buildMenu() {
    final items = _isOwner
        ? const [
            PopupMenuItem(value: 'edit', child: Text('Edit')),
            PopupMenuItem(value: 'archive', child: Text('Archive')),
            PopupMenuItem(value: 'delete', child: Text('Delete')),
          ]
        : const [PopupMenuItem(value: 'report', child: Text('Report'))];

    return PopupMenuButton<String>(
      icon: const Icon(Icons.more_horiz_rounded, size: 18, color: AppColors.textTertiary),
      padding: EdgeInsets.zero,
      itemBuilder: (_) => items,
      onSelected: _handleMenuSelect,
    );
  }

  Widget _langBadge(String text, Color color) {
    if (text.isEmpty) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(border: Border.all(color: color, width: 1), borderRadius: BorderRadius.circular(4)),
      child: Text(text, style: TextStyle(fontSize: 9.5, color: color, fontWeight: FontWeight.w700)),
    );
  }

  Widget _buildText() {
    return LayoutBuilder(
      builder: (context, constraints) {
        const style = TextStyle(fontSize: 14, height: 1.35, color: AppColors.textPrimary);
        final painter = TextPainter(
          text: TextSpan(text: _moment.text, style: style),
          maxLines: 3,
          textDirection: TextDirection.ltr,
        )..layout(maxWidth: constraints.maxWidth);
        final overflows = painter.didExceedMaxLines;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Linkify(
              text: _moment.text,
              maxLines: _expanded || !overflows ? null : 3,
              overflow: TextOverflow.ellipsis,
              linkifiers: const [UrlLinkifier(), UserTagLinkifier(), _HashtagLinkifier()],
              onOpen: _handleLinkOpen,
              options: const LinkifyOptions(humanize: false),
              style: style,
              linkStyle: style.copyWith(color: AppColors.primaryPurple, fontWeight: FontWeight.w600),
            ),
            if (overflows)
              GestureDetector(
                onTap: () => setState(() => _expanded = !_expanded),
                child: Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    _expanded ? 'See less' : 'See more',
                    style: const TextStyle(color: AppColors.textTertiary, fontSize: 12.5, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _buildVideoThumb() {
    return GestureDetector(
      onTap: _openVideo,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: AspectRatio(
          aspectRatio: 16 / 9,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (_moment.videoThumbnailUrl != null)
                CachedNetworkImage(imageUrl: _moment.videoThumbnailUrl!, fit: BoxFit.cover)
              else
                Container(color: Colors.black),
              Container(color: Colors.black.withValues(alpha: 0.25)),
              const Center(
                child: Icon(Icons.play_circle_fill_rounded, color: Colors.white, size: 56),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildActionBar({required bool isLiked}) {
    final topEmojis = _moment.topReactionEmojis;

    return Row(
      children: [
        GestureDetector(
          key: _heartKey,
          onTap: _toggleLike,
          onLongPress: _showReactionPickerFromHeart,
          child: Row(
            children: [
              Icon(
                isLiked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                size: 19,
                color: isLiked ? AppColors.badgeRed : AppColors.textTertiary,
              ),
              const SizedBox(width: 5),
              if (topEmojis.isNotEmpty) ...[
                Text(topEmojis.join(), style: const TextStyle(fontSize: 12)),
                const SizedBox(width: 3),
              ],
              Text(
                '${_moment.likeCount}',
                style: TextStyle(
                  color: isLiked ? AppColors.badgeRed : AppColors.textTertiary,
                  fontSize: 12.5,
                  fontWeight: isLiked ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 20),
        GestureDetector(
          onTap: _openComments,
          child: _actionIcon(Icons.chat_bubble_outline_rounded, '${_moment.commentCount}'),
        ),
        const SizedBox(width: 20),
        GestureDetector(
          onTap: _openReshare,
          child: _actionIcon(Icons.repeat_rounded, '${_moment.reshareCount}'),
        ),
      ],
    );
  }

  Widget _actionIcon(IconData icon, String label) {
    return Row(
      children: [
        Icon(icon, size: 19, color: AppColors.textTertiary),
        const SizedBox(width: 5),
        Text(label, style: const TextStyle(color: AppColors.textTertiary, fontSize: 12.5)),
      ],
    );
  }
}
