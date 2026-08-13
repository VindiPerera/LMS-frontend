import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/comment_model.dart';
import '../models/moment.dart';
import '../screens/friends/friend_profile_screen.dart';
import '../services/auth_service.dart';
import '../services/comment_service.dart';
import '../theme/app_colors.dart';
import 'app_avatar.dart';
import 'report_sheet.dart';

final RegExp _mentionToken = RegExp(r'@([a-zA-Z0-9_]{2,30})');

/// Opens the comments DraggableScrollableSheet for [moment].
Future<void> showCommentSheet(BuildContext context, {required Moment moment}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => CommentSheet(moment: moment),
  );
}

class CommentSheet extends StatefulWidget {
  final Moment moment;

  const CommentSheet({super.key, required this.moment});

  @override
  State<CommentSheet> createState() => _CommentSheetState();
}

class _CommentSheetState extends State<CommentSheet> {
  final _draggableController = DraggableScrollableController();
  final _listController = ScrollController();
  final _textController = TextEditingController();
  final _focusNode = FocusNode();

  late int _commentCount = widget.moment.commentCount;
  CommentModel? _replyingTo;
  bool _posting = false;
  List<Map<String, String>> _mentionSuggestions = const [];
  Timer? _mentionDebounce;

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(() {
      if (_focusNode.hasFocus) {
        // Give the keyboard animation a moment before scrolling to bottom.
        Future.delayed(const Duration(milliseconds: 250), _scrollToBottom);
      }
    });
  }

  @override
  void dispose() {
    _mentionDebounce?.cancel();
    _draggableController.dispose();
    _listController.dispose();
    _textController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    if (!_listController.hasClients) return;
    _listController.animateTo(
      _listController.position.maxScrollExtent,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
  }

  void _startReply(CommentModel comment) {
    setState(() => _replyingTo = comment);
    _focusNode.requestFocus();
  }

  void _cancelReply() => setState(() => _replyingTo = null);

  void _onTextChanged(String text) {
    _mentionDebounce?.cancel();
    final cursor = _textController.selection.baseOffset;
    final upToCursor = cursor < 0 || cursor > text.length ? text : text.substring(0, cursor);
    final match = RegExp(r'@([a-zA-Z0-9_]{1,30})$').firstMatch(upToCursor);
    if (match == null) {
      if (_mentionSuggestions.isNotEmpty) setState(() => _mentionSuggestions = const []);
      return;
    }
    final query = match.group(1)!;
    _mentionDebounce = Timer(const Duration(milliseconds: 200), () async {
      final results = await CommentService.searchUsersByHandle(query);
      if (!mounted) return;
      setState(() => _mentionSuggestions = results);
    });
  }

  void _applyMention(String handle) {
    final text = _textController.text;
    final cursor = _textController.selection.baseOffset;
    final upToCursor = cursor < 0 || cursor > text.length ? text : text.substring(0, cursor);
    final match = RegExp(r'@([a-zA-Z0-9_]{1,30})$').firstMatch(upToCursor);
    if (match == null) return;

    final replaced = '${text.substring(0, match.start)}@$handle ${text.substring(cursor)}';
    _textController.value = TextEditingValue(
      text: replaced,
      selection: TextSelection.collapsed(offset: match.start + handle.length + 2),
    );
    setState(() => _mentionSuggestions = const []);
  }

  Future<void> _submit() async {
    final text = _textController.text.trim();
    if (text.isEmpty || _posting) return;

    setState(() => _posting = true);
    try {
      await CommentService.addComment(
        postId: widget.moment.id,
        text: text,
        parentCommentId: _replyingTo?.id,
      );
      if (!mounted) return;
      HapticFeedback.lightImpact();
      _textController.clear();
      setState(() {
        _posting = false;
        _commentCount += 1;
        _replyingTo = null;
        _mentionSuggestions = const [];
      });
      Future.delayed(const Duration(milliseconds: 150), _scrollToBottom);
    } catch (_) {
      if (!mounted) return;
      setState(() => _posting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not post your comment. Try again.')),
      );
    }
  }

  Future<void> _openMention(String handle) async {
    final uid = await CommentService.findUserIdByHandle(handle);
    if (!mounted || uid == null) return;
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => FriendProfileScreen(friendId: uid, source: 'moment')),
    );
  }

  Future<void> _handleLongPress(CommentModel comment) async {
    final currentUid = AuthService.instance.currentUser?.id;
    final isOwn = currentUid != null && currentUid == comment.userId;

    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isOwn)
              ListTile(
                leading: const Icon(Icons.delete_outline_rounded, color: AppColors.badgeRed),
                title: const Text('Delete comment'),
                onTap: () => Navigator.of(context).pop('delete'),
              )
            else
              ListTile(
                leading: const Icon(Icons.flag_outlined, color: AppColors.badgeRed),
                title: const Text('Report comment'),
                onTap: () => Navigator.of(context).pop('report'),
              ),
          ],
        ),
      ),
    );

    if (!mounted || action == null) return;

    if (action == 'delete') {
      await CommentService.deleteComment(postId: widget.moment.id, commentId: comment.id);
      if (!mounted) return;
      setState(() => _commentCount = _commentCount > 0 ? _commentCount - 1 : 0);
    } else if (action == 'report') {
      // Comments don't have their own `reports` doc shape — reporting a
      // comment files a report against its parent post, same as reporting
      // the post itself.
      final reported = await showReportSheet(context, postId: widget.moment.id);
      if (reported && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Thanks for your report.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: DraggableScrollableSheet(
        controller: _draggableController,
        initialChildSize: 0.6,
        minChildSize: 0.3,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, scrollController) {
          // The list itself uses its own controller (_listController) so
          // this widget can programmatically scroll-to-bottom; the sheet's
          // drag handle still lives in the header above it.
          return Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: Column(
              children: [
                const SizedBox(height: 10),
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.divider,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 8, 6),
                  child: Row(
                    children: [
                      Text(
                        'Comments ($_commentCount)',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.close_rounded, size: 20),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: StreamBuilder<List<CommentModel>>(
                    stream: CommentService.streamTopLevelComments(widget.moment.id),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Center(child: CircularProgressIndicator(strokeWidth: 2));
                      }
                      final comments = snapshot.data ?? const [];
                      if (comments.isEmpty) {
                        return const Center(
                          child: Text(
                            'No comments yet. Be the first to reply!',
                            style: TextStyle(color: AppColors.textTertiary),
                          ),
                        );
                      }
                      return ListView.builder(
                        controller: _listController,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        itemCount: comments.length,
                        itemBuilder: (context, index) => _CommentTile(
                          postId: widget.moment.id,
                          comment: comments[index],
                          onReply: _startReply,
                          onLongPress: _handleLongPress,
                          onMentionTap: _openMention,
                        ),
                      );
                    },
                  ),
                ),
                if (_mentionSuggestions.isNotEmpty) _buildMentionSuggestions(),
                _buildComposer(),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildMentionSuggestions() {
    return Container(
      constraints: const BoxConstraints(maxHeight: 160),
      decoration: const BoxDecoration(
        color: AppColors.surfaceLight,
        border: Border(top: BorderSide(color: AppColors.divider)),
      ),
      child: ListView.builder(
        shrinkWrap: true,
        itemCount: _mentionSuggestions.length,
        itemBuilder: (context, index) {
          final user = _mentionSuggestions[index];
          return ListTile(
            dense: true,
            leading: AppAvatar(seed: user['name'] ?? '', size: 28, imageUrl: user['avatarUrl']),
            title: Text('@${user['handle']}', style: const TextStyle(fontSize: 13.5)),
            subtitle: Text(user['name'] ?? '', style: const TextStyle(fontSize: 11.5)),
            onTap: () => _applyMention(user['handle'] ?? ''),
          );
        },
      ),
    );
  }

  Widget _buildComposer() {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_replyingTo != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 6, left: 4),
                child: Row(
                  children: [
                    Text(
                      'Replying to @${_replyingTo!.userName}',
                      style: const TextStyle(
                        color: AppColors.primaryPurple,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 6),
                    GestureDetector(
                      onTap: _cancelReply,
                      child: const Icon(Icons.close_rounded, size: 14, color: AppColors.textTertiary),
                    ),
                  ],
                ),
              ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: TextField(
                    controller: _textController,
                    focusNode: _focusNode,
                    minLines: 1,
                    maxLines: 4,
                    onChanged: _onTextChanged,
                    decoration: const InputDecoration(
                      hintText: 'Write a comment...',
                      hintStyle: TextStyle(color: AppColors.textTertiary),
                      filled: true,
                      fillColor: AppColors.surfaceLight,
                      contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.all(Radius.circular(20)),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                ValueListenableBuilder<TextEditingValue>(
                  valueListenable: _textController,
                  builder: (context, value, _) {
                    final canSend = value.text.trim().isNotEmpty && !_posting;
                    return IconButton(
                      icon: _posting
                          ? const SizedBox(
                              height: 18,
                              width: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Icon(
                              Icons.send_rounded,
                              color: canSend ? AppColors.primaryPurple : AppColors.textTertiary,
                            ),
                      onPressed: canSend ? _submit : null,
                    );
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _CommentTile extends StatefulWidget {
  final String postId;
  final CommentModel comment;
  final ValueChanged<CommentModel> onReply;
  final ValueChanged<CommentModel> onLongPress;
  final ValueChanged<String> onMentionTap;

  const _CommentTile({
    required this.postId,
    required this.comment,
    required this.onReply,
    required this.onLongPress,
    required this.onMentionTap,
  });

  @override
  State<_CommentTile> createState() => _CommentTileState();
}

class _CommentTileState extends State<_CommentTile> {
  bool _repliesExpanded = false;

  @override
  Widget build(BuildContext context) {
    final comment = widget.comment;
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onLongPress: () => widget.onLongPress(comment),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AppAvatar(seed: comment.userName, size: 32, imageUrl: comment.userAvatar),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: AppColors.surfaceLight,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              comment.userName,
                              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5),
                            ),
                            const SizedBox(height: 2),
                            _MentionText(text: comment.text, onMentionTap: widget.onMentionTap),
                          ],
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Text(
                            comment.timeAgo,
                            style: const TextStyle(color: AppColors.textTertiary, fontSize: 11),
                          ),
                          const SizedBox(width: 14),
                          GestureDetector(
                            onTap: () => widget.onReply(comment),
                            child: const Text(
                              'Reply',
                              style: TextStyle(
                                color: AppColors.textTertiary,
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          StreamBuilder<List<CommentModel>>(
            stream: CommentService.streamReplies(widget.postId, comment.id),
            builder: (context, snapshot) {
              final replies = snapshot.data ?? const [];
              if (replies.isEmpty) return const SizedBox.shrink();

              final visible = _repliesExpanded ? replies : replies.take(2).toList();
              final remaining = replies.length - visible.length;

              return Padding(
                padding: const EdgeInsets.only(left: 42, top: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final reply in visible)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: GestureDetector(
                          onLongPress: () => widget.onLongPress(reply),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              AppAvatar(seed: reply.userName, size: 26, imageUrl: reply.userAvatar),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                                  decoration: BoxDecoration(
                                    color: AppColors.surfaceLight,
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        reply.userName,
                                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
                                      ),
                                      const SizedBox(height: 2),
                                      _MentionText(text: reply.text, onMentionTap: widget.onMentionTap),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    if (remaining > 0)
                      GestureDetector(
                        onTap: () => setState(() => _repliesExpanded = true),
                        child: Text(
                          'View $remaining more ${remaining == 1 ? 'reply' : 'replies'}',
                          style: const TextStyle(
                            color: AppColors.primaryPurple,
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

/// Renders [text] with "@handle" tokens as tappable spans.
class _MentionText extends StatelessWidget {
  final String text;
  final ValueChanged<String> onMentionTap;

  const _MentionText({required this.text, required this.onMentionTap});

  @override
  Widget build(BuildContext context) {
    final spans = <InlineSpan>[];
    var lastEnd = 0;
    for (final match in _mentionToken.allMatches(text)) {
      if (match.start > lastEnd) {
        spans.add(TextSpan(text: text.substring(lastEnd, match.start)));
      }
      final handle = match.group(1)!;
      spans.add(
        TextSpan(
          text: '@$handle',
          style: const TextStyle(color: AppColors.primaryPurple, fontWeight: FontWeight.w700),
          recognizer: TapGestureRecognizer()..onTap = () => onMentionTap(handle),
        ),
      );
      lastEnd = match.end;
    }
    if (lastEnd < text.length) {
      spans.add(TextSpan(text: text.substring(lastEnd)));
    }

    return RichText(
      text: TextSpan(
        style: const TextStyle(color: AppColors.textPrimary, fontSize: 13, height: 1.3),
        children: spans,
      ),
    );
  }
}
