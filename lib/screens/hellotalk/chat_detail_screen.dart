import 'dart:async';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../models/chat_message.dart';
import '../../models/user.dart';
import '../../models/voiceroom.dart';
import '../../services/chat_service.dart';
import '../../services/media_service.dart';
import '../../services/partner_service.dart';
import '../../services/push_notification_service.dart';
import '../../services/room_participant_service.dart';
import '../../theme/app_colors.dart';
import '../../utils/chat_time.dart';
import '../../widgets/app_avatar.dart';
import '../../widgets/voice_room_invite_card.dart';
import '../connect/partner_profile_screen.dart';
import '../moments/image_viewer_screen.dart';
import '../voiceroom/open_voice_room.dart';

class ChatDetailScreen extends StatefulWidget {
  final AppUser user;
  const ChatDetailScreen({super.key, required this.user});

  @override
  State<ChatDetailScreen> createState() => _ChatDetailScreenState();
}

class _ChatDetailScreenState extends State<ChatDetailScreen> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  late final String _chatId = ChatService.chatIdFor(widget.user.id);
  late final Stream<List<ChatMessage>> _messagesStream =
      ChatService.streamMessages(_chatId);
  // Live online/offline for the header — widget.user.isOnline alone would
  // just be whatever was true the moment this screen opened, never
  // updating while the chat stays open. Skipped for the FaceTalk system
  // account: it isn't a real user doc, so there's nothing to listen to.
  late final Stream<bool> _theirOnlineStream = _isSystemChat
      ? const Stream.empty()
      : PartnerService.streamIsOnline(widget.user.id);
  // widget.user.avatarUrl is a denormalized participantInfo snapshot —
  // only refreshed when either side next sends a message in this thread
  // (see ChatService's class doc) — so a newly-uploaded avatar needs its
  // own live listener to show up here right away instead of waiting for
  // that next message.
  late final Stream<String?> _theirAvatarStream = _isSystemChat
      ? const Stream.empty()
      : PartnerService.streamAvatarUrl(widget.user.id);
  // The voice room they're actually, currently present in — NOT
  // PartnerService.streamActiveRoomId's raw users/{uid}.activeRoomId, which
  // only self-clears via RoomParticipantService.leave and so can stay
  // stuck pointing at a room long after they've actually left it (crash,
  // force-kill, lost connection — see that method's own doc comment on the
  // stale-participant sweep deliberately not touching this field). This
  // cross-checks their actual non-stale participant doc instead, the same
  // source of truth partner_profile_screen.dart's "Go Look" card uses.
  late final Stream<VoiceRoom?> _theirActiveRoomStream = _isSystemChat
      ? const Stream.empty()
      : RoomParticipantService.streamRoomUserIsIn(widget.user.id);

  bool get _isSystemChat => ChatService.isSystemChat(widget.user.id);

  @override
  void initState() {
    super.initState();
    // Fire-and-forget: clears my unread count for this thread now that
    // it's open. Silently no-ops if the thread doesn't exist yet.
    ChatService.markRead(_chatId);
    // While this thread is open, a "new message" push for it would just be
    // a redundant banner on top of the message already appearing live in
    // the list below — see push_notification_service.dart.
    PushNotificationService.instance.setActiveChat(_chatId);
  }

  @override
  void dispose() {
    if (PushNotificationService.instance.activeChatId == _chatId) {
      PushNotificationService.instance.setActiveChat(null);
    }
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
    });
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;

    _controller.clear();
    try {
      await ChatService.sendMessage(other: widget.user, text: text);
      _scrollToBottom();
    } on FirebaseException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(e.message ?? "Message didn't send."),
            backgroundColor: AppColors.badgeRed,
          ),
        );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text("Message didn't send: ${e.toString()}"),
            backgroundColor: AppColors.badgeRed,
          ),
        );
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message), backgroundColor: AppColors.badgeRed));
  }

  // True while a photo/file/voice note is being uploaded — disables the "+"
  // and mic buttons so a slow upload can't be fired twice, same spirit as
  // _controller.clear() in _send() happening before the await above.
  bool _sendingAttachment = false;

  /// "+" > Photo. Picking, compressing, and uploading all reuse MediaService
  /// (already the Moments image pipeline — see create_moment_screen.dart);
  /// only the final ChatService call is chat-specific.
  Future<void> _sendPhoto() async {
    final picked = await MediaService.pickImage(ImageSource.gallery);
    if (picked == null || !mounted) return;
    setState(() => _sendingAttachment = true);
    try {
      final bytes = await picked.readAsBytes();
      final compressed = await MediaService.compressImageBytes(bytes);
      final url = await MediaService.uploadImageBytes(
        bytes: compressed,
        uid: FirebaseAuth.instance.currentUser?.uid ?? '',
        postId: _chatId,
      );
      await ChatService.sendImageMessage(other: widget.user, imageUrl: url);
      _scrollToBottom();
    } catch (e) {
      _showError("Photo didn't send: $e");
    } finally {
      if (mounted) setState(() => _sendingAttachment = false);
    }
  }

  /// "+" > File — any document/archive/etc., not just media. `withData:
  /// true` loads the picked file's bytes directly (no separate read-from-
  /// path step needed, and works on web where there is no real filesystem
  /// path to read from anyway).
  Future<void> _sendFile() async {
    final result = await FilePicker.pickFiles(withData: true);
    final picked = result?.files.single;
    if (picked == null || !mounted) return;
    final bytes = picked.bytes;
    if (bytes == null) {
      _showError("Couldn't read that file.");
      return;
    }
    setState(() => _sendingAttachment = true);
    try {
      final url = await MediaService.uploadFileBytes(
        bytes: bytes,
        uid: FirebaseAuth.instance.currentUser?.uid ?? '',
        chatId: _chatId,
        filename: picked.name,
        extension: picked.extension ?? 'bin',
      );
      await ChatService.sendFileMessage(
        other: widget.user,
        fileUrl: url,
        fileName: picked.name,
        fileSize: bytes.length,
      );
      _scrollToBottom();
    } catch (e) {
      _showError("File didn't send: $e");
    } finally {
      if (mounted) setState(() => _sendingAttachment = false);
    }
  }

  /// The mic button, once a recording actually finishes (see _Composer,
  /// which owns the recorder itself and only hands this screen the finished
  /// local file once the user taps stop/send). [path] is always deleted
  /// afterward — win or lose, there's nothing left to clean up once either
  /// the upload finishes or fails for good.
  Future<void> _sendVoice(String path, int seconds) async {
    if (seconds < 1) {
      // A near-instant tap-release — not a real message, nothing to send.
      try {
        await File(path).delete();
      } catch (_) {}
      return;
    }
    if (mounted) setState(() => _sendingAttachment = true);
    try {
      final bytes = await File(path).readAsBytes();
      final url = await MediaService.uploadVoiceBytes(
        bytes: bytes,
        uid: FirebaseAuth.instance.currentUser?.uid ?? '',
        chatId: _chatId,
      );
      await ChatService.sendVoiceMessage(other: widget.user, audioUrl: url, seconds: seconds);
      _scrollToBottom();
    } catch (e) {
      _showError("Voice message didn't send: $e");
    } finally {
      try {
        await File(path).delete();
      } catch (_) {}
      if (mounted) setState(() => _sendingAttachment = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final myUid = FirebaseAuth.instance.currentUser?.uid ?? '';

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: StreamBuilder<bool>(
          stream: _theirOnlineStream,
          initialData: widget.user.isOnline,
          builder: (context, snapshot) {
            final isOnline = snapshot.data ?? false;
            // The system/broadcast account has no real profile to open —
            // tapping it is a no-op, same as its hidden online dot above.
            return InkWell(
              onTap: _isSystemChat
                  ? null
                  : () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => PartnerProfileScreen(initial: widget.user),
                      ),
                    ),
              child: Row(
                children: [
                  // Built directly (not via AppAvatar.forUser) so the dot
                  // uses the live `isOnline` above instead of the static
                  // widget.user.isOnline snapshot forUser would read.
                  StreamBuilder<String?>(
                    stream: _theirAvatarStream,
                    initialData: widget.user.avatarUrl.isEmpty ? null : widget.user.avatarUrl,
                    builder: (context, avatarSnapshot) {
                      return AppAvatar(
                        seed: widget.user.name,
                        imageUrl: avatarSnapshot.data,
                        size: 36,
                        showFlag: false,
                        showOnlineDot: !_isSystemChat,
                        isOnline: isOnline,
                      );
                    },
                  ),
                  const SizedBox(width: 10),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            widget.user.name,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          if (_isSystemChat) ...[
                            const SizedBox(width: 4),
                            const Icon(
                              Icons.verified_rounded,
                              size: 15,
                              color: AppColors.primaryPurple,
                            ),
                          ],
                        ],
                      ),
                      Text(
                        _isSystemChat
                            ? 'Official account'
                            : (isOnline ? 'Active now' : 'Offline'),
                        style: TextStyle(
                          fontSize: 11.5,
                          color: _isSystemChat
                              ? AppColors.textTertiary
                              : (isOnline ? AppColors.online : AppColors.textTertiary),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        ),
      ),
      body: Column(
        children: [
          StreamBuilder<VoiceRoom?>(
            stream: _theirActiveRoomStream,
            builder: (context, roomSnapshot) {
              final room = roomSnapshot.data;
              // streamRoomUserIsIn already only considers active, visible
              // rooms where their participant doc is actually present and
              // non-stale, so a null here covers "not in a room", "room
              // ended", and "their session went stale" all at once.
              if (room == null) return const SizedBox.shrink();
              return _PartnerVoiceRoomBanner(room: room);
            },
          ),
          Expanded(
            child: StreamBuilder<List<ChatMessage>>(
              stream: _messagesStream,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
                  return const Center(
                    child: CircularProgressIndicator(
                      strokeWidth: 2.4,
                      color: AppColors.primaryPurple,
                    ),
                  );
                }

                final messages = snapshot.data ?? const [];
                if (messages.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 68,
                            height: 68,
                            padding: const EdgeInsets.all(12),
                            decoration: const BoxDecoration(
                              color: Color(0xFFF3EFFF),
                              shape: BoxShape.circle,
                            ),
                            child: Image.asset(
                              'assets/images/say_hi_hand.png',
                              fit: BoxFit.contain,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'Say hi to ${widget.user.name} 👋',
                            style: const TextStyle(
                              color: AppColors.textPrimary,
                              fontWeight: FontWeight.w700,
                              fontSize: 16,
                            ),
                          ),
                          const SizedBox(height: 6),
                          const Text(
                            'Start practicing languages and chat together!',
                            style: TextStyle(
                              color: AppColors.textTertiary,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }


                _scrollToBottom();
                return ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  itemCount: messages.length,
                  itemBuilder: (context, i) => _MessageBubble(
                    message: messages[i],
                    user: widget.user,
                    myUid: myUid,
                  ),
                );
              },
            ),
          ),
          _isSystemChat
              ? const _ReadOnlyNotice()
              : _Composer(
                  controller: _controller,
                  onSend: _send,
                  onPickPhoto: _sendPhoto,
                  onPickFile: _sendFile,
                  onVoiceRecorded: _sendVoice,
                  busy: _sendingAttachment,
                ),
        ],
      ),
    );
  }
}

/// Banner shown atop a chat thread while the OTHER person is currently in a
/// live Voice Room — any role (host/moderator/speaker/listener), not just
/// hosting (see _theirActiveRoomStream). Tapping it (or "Go Look") opens
/// that room via the normal openVoiceRoom entry point, ban check included.
class _PartnerVoiceRoomBanner extends StatelessWidget {
  final VoiceRoom room;
  const _PartnerVoiceRoomBanner({required this.room});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => openVoiceRoom(context, room),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 8, offset: const Offset(0, 2)),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: AppColors.primaryPurple.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.mic_rounded, color: AppColors.primaryPurple, size: 19),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'In the Voiceroom',
                      style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w700, fontSize: 14),
                    ),
                    Text(
                      room.title,
                      style: const TextStyle(color: AppColors.textTertiary, fontSize: 12),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: () => openVoiceRoom(context, room),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primaryPurple,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                ),
                child: const Text('Go Look', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  final ChatMessage message;
  final AppUser user;
  final String myUid;
  const _MessageBubble({
    required this.message,
    required this.user,
    required this.myUid,
  });

  @override
  Widget build(BuildContext context) {
    final isMe = message.isMine(myUid);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: isMe
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isMe) ...[
            AppAvatar.forUser(user, size: 30),
            const SizedBox(width: 8),
          ],
          Flexible(child: _bubbleContent(context, isMe)),
          if (isMe) const SizedBox(width: 4),
        ],
      ),
    );
  }

  Widget _bubbleContent(BuildContext context, bool isMe) {
    final bg = isMe ? AppColors.primaryPurple : AppColors.surfaceLight;
    final radius = BorderRadius.only(
      topLeft: const Radius.circular(16),
      topRight: const Radius.circular(16),
      bottomLeft: Radius.circular(isMe ? 16 : 4),
      bottomRight: Radius.circular(isMe ? 4 : 16),
    );
    final timeLabel = message.createdAt != null
        ? formatChatTime(message.createdAt!)
        : '';

    if (message.type == MessageType.voiceRoomInvite) {
      // No bubble chrome around this one — VoiceRoomInviteCard already has
      // its own gradient "card" look (matching the in-room share banner),
      // so wrapping it in the usual purple/gray bubble would just double up
      // the background. Capped to a comfortable card width rather than
      // stretching edge-to-edge like a text bubble would.
      return ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 260),
        child: VoiceRoomInviteCard(
          roomId: message.roomId,
          title: message.roomTitle,
          hostName: message.roomHostName,
          hostAvatar: message.roomHostAvatar,
        ),
      );
    }

    if (message.type == MessageType.voice) {
      return _VoiceBubble(
        url: message.mediaUrl,
        seconds: message.voiceSeconds,
        isMe: isMe,
        bg: bg,
        radius: radius,
      );
    }

    if (message.type == MessageType.image) {
      return ClipRRect(
        borderRadius: radius,
        child: GestureDetector(
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => ImageViewerScreen(
                postId: message.id,
                imageUrls: [message.mediaUrl],
              ),
            ),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 220, maxHeight: 260),
            child: CachedNetworkImage(
              imageUrl: message.mediaUrl,
              fit: BoxFit.cover,
              placeholder: (_, _) => Container(
                width: 160,
                height: 160,
                color: AppColors.surfaceLight,
                alignment: Alignment.center,
                child: const CircularProgressIndicator(strokeWidth: 2.2),
              ),
              errorWidget: (_, _, _) => Container(
                width: 160,
                height: 160,
                color: AppColors.surfaceLight,
                alignment: Alignment.center,
                child: const Icon(Icons.broken_image_outlined, color: AppColors.textTertiary),
              ),
            ),
          ),
        ),
      );
    }

    if (message.type == MessageType.file) {
      return GestureDetector(
        onTap: () => launchUrl(Uri.parse(message.mediaUrl), mode: LaunchMode.externalApplication),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          constraints: const BoxConstraints(maxWidth: 220),
          decoration: BoxDecoration(color: bg, borderRadius: radius),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.insert_drive_file_rounded,
                color: isMe ? Colors.white : AppColors.primaryPurple,
                size: 28,
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      message.fileName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: isMe ? Colors.white : AppColors.textPrimary,
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                    Text(
                      _formatFileSize(message.fileSize),
                      style: TextStyle(
                        color: isMe ? Colors.white70 : AppColors.textTertiary,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: isMe
          ? CrossAxisAlignment.end
          : CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(color: bg, borderRadius: radius),
          child: Text(
            message.text,
            style: TextStyle(
              color: isMe ? Colors.white : AppColors.textPrimary,
              fontSize: 14.5,
            ),
          ),
        ),
        if (message.type == MessageType.correction)
          const Padding(
            padding: EdgeInsets.only(top: 4, right: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.check_circle_rounded,
                  size: 13,
                  color: AppColors.perfectGreen,
                ),
                SizedBox(width: 4),
                Text(
                  'Perfect!',
                  style: TextStyle(
                    fontSize: 11.5,
                    color: AppColors.perfectGreen,
                  ),
                ),
              ],
            ),
          ),
        if (timeLabel.isNotEmpty) ...[
          const SizedBox(height: 3),
          Text(
            timeLabel,
            style: const TextStyle(
              fontSize: 10.5,
              color: AppColors.textTertiary,
            ),
          ),
        ],
      ],
    );
  }

  static String _formatFileSize(int bytes) {
    if (bytes >= 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    if (bytes >= 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
    return '$bytes B';
  }
}

/// A sent/received voice note's bubble — the real play/pause + progress
/// this replaces the old static waveform decoration with. Owns its own
/// [AudioPlayer] (one per bubble, not shared) rather than funneling
/// playback through _ChatDetailScreenState: each voice note plays
/// independently, same as e.g. WhatsApp allows multiple notes mid-playback
/// at once — keeping it self-contained here means a bubble scrolled off
/// (and disposed) cleans up its own player automatically.
class _VoiceBubble extends StatefulWidget {
  final String url;
  final int seconds;
  final bool isMe;
  final Color bg;
  final BorderRadius radius;
  const _VoiceBubble({
    required this.url,
    required this.seconds,
    required this.isMe,
    required this.bg,
    required this.radius,
  });

  @override
  State<_VoiceBubble> createState() => _VoiceBubbleState();
}

class _VoiceBubbleState extends State<_VoiceBubble> {
  final _player = AudioPlayer();
  bool _playing = false;
  Duration _position = Duration.zero;
  Duration? _duration;
  StreamSubscription<Duration>? _positionSub;
  StreamSubscription<Duration>? _durationSub;
  StreamSubscription<void>? _completeSub;

  @override
  void initState() {
    super.initState();
    _positionSub = _player.onPositionChanged.listen((p) {
      if (mounted) setState(() => _position = p);
    });
    _durationSub = _player.onDurationChanged.listen((d) {
      if (mounted) setState(() => _duration = d);
    });
    _completeSub = _player.onPlayerComplete.listen((_) {
      if (!mounted) return;
      setState(() {
        _playing = false;
        _position = Duration.zero;
      });
    });
  }

  @override
  void dispose() {
    _positionSub?.cancel();
    _durationSub?.cancel();
    _completeSub?.cancel();
    _player.dispose();
    super.dispose();
  }

  Future<void> _toggle() async {
    if (widget.url.isEmpty) return;
    if (_playing) {
      await _player.pause();
      if (mounted) setState(() => _playing = false);
      return;
    }
    await _player.play(UrlSource(widget.url));
    if (mounted) setState(() => _playing = true);
  }

  @override
  Widget build(BuildContext context) {
    final fg = widget.isMe ? Colors.white : AppColors.textPrimary;
    final track = widget.isMe ? Colors.white24 : AppColors.divider;
    final total = _duration ?? Duration(seconds: widget.seconds);
    final progress = total.inMilliseconds == 0
        ? 0.0
        : (_position.inMilliseconds / total.inMilliseconds).clamp(0.0, 1.0);
    final remaining = _position > Duration.zero ? (total - _position) : total;
    final label = '0:${remaining.inSeconds.clamp(0, 59).toString().padLeft(2, '0')}';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(color: widget.bg, borderRadius: widget.radius),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          GestureDetector(
            onTap: _toggle,
            child: Icon(
              _playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
              color: fg,
              size: 20,
            ),
          ),
          const SizedBox(width: 6),
          SizedBox(
            width: 60,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 3,
                backgroundColor: track,
                valueColor: AlwaysStoppedAnimation(fg),
              ),
            ),
          ),
          const SizedBox(width: 6),
          Text(label, style: TextStyle(color: fg, fontSize: 12)),
        ],
      ),
    );
  }
}

/// Shown instead of [_Composer] for the FaceTalk system/broadcast thread —
/// replies aren't offered at all, rather than a text field that would just
/// fail (see firestore.rules' `isReadOnly` guard on chats/{chatId}/messages).
class _ReadOnlyNotice extends StatelessWidget {
  const _ReadOnlyNotice();

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: const BoxDecoration(
          color: AppColors.surface,
          border: Border(top: BorderSide(color: AppColors.divider, width: 0.6)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.lock_outline_rounded, size: 15, color: AppColors.textTertiary),
            const SizedBox(width: 6),
            Text(
              'Official announcements — you can\'t reply here',
              style: const TextStyle(fontSize: 12.5, color: AppColors.textTertiary),
            ),
          ],
        ),
      ),
    );
  }
}

class _Composer extends StatefulWidget {
  final TextEditingController controller;
  final VoidCallback onSend;
  final Future<void> Function() onPickPhoto;
  final Future<void> Function() onPickFile;
  final Future<void> Function(String path, int seconds) onVoiceRecorded;
  // True while a previously-recorded/picked attachment is still uploading —
  // see _ChatDetailScreenState._sendingAttachment. Disables the mic/+
  // buttons so a slow upload can't be started twice.
  final bool busy;
  const _Composer({
    required this.controller,
    required this.onSend,
    required this.onPickPhoto,
    required this.onPickFile,
    required this.onVoiceRecorded,
    required this.busy,
  });

  @override
  State<_Composer> createState() => _ComposerState();
}

class _ComposerState extends State<_Composer> {
  final _recorder = AudioRecorder();
  bool _recording = false;
  int _elapsedSeconds = 0;
  Timer? _ticker;

  bool get _hasText => widget.controller.text.trim().isNotEmpty;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onTextChanged);
    _ticker?.cancel();
    // Fire-and-forget: a recording still running when this widget is torn
    // down (the user backed out of the chat mid-recording) has nowhere left
    // to send to — discard it rather than leaking the recorder/file.
    if (_recording) _recorder.cancel();
    _recorder.dispose();
    super.dispose();
  }

  void _onTextChanged() => setState(() {});

  Future<void> _startRecording() async {
    if (widget.busy || _recording) return;
    if (!await _recorder.hasPermission()) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Microphone permission is needed to record a voice message.')),
      );
      return;
    }
    final dir = await getTemporaryDirectory();
    final path = '${dir.path}/voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
    await _recorder.start(const RecordConfig(encoder: AudioEncoder.aacLc), path: path);
    if (!mounted) return;
    setState(() {
      _recording = true;
      _elapsedSeconds = 0;
    });
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _elapsedSeconds++);
    });
  }

  Future<void> _cancelRecording() async {
    _ticker?.cancel();
    await _recorder.cancel();
    if (!mounted) return;
    setState(() => _recording = false);
  }

  Future<void> _stopAndSend() async {
    _ticker?.cancel();
    final path = await _recorder.stop();
    final seconds = _elapsedSeconds;
    if (!mounted) return;
    setState(() => _recording = false);
    if (path != null) await widget.onVoiceRecorded(path, seconds);
  }

  void _openAttachmentSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => SafeArea(
        child: Container(
          margin: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.image_rounded, color: AppColors.primaryPurple),
                title: const Text('Photo'),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  widget.onPickPhoto();
                },
              ),
              ListTile(
                leading: const Icon(Icons.attach_file_rounded, color: AppColors.primaryPurple),
                title: const Text('File'),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  widget.onPickFile();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: const BoxDecoration(
          color: AppColors.surface,
          border: Border(top: BorderSide(color: AppColors.divider, width: 0.6)),
        ),
        child: _recording ? _buildRecordingRow() : _buildNormalRow(),
      ),
    );
  }

  Widget _buildRecordingRow() {
    final minutes = (_elapsedSeconds ~/ 60).toString().padLeft(1, '0');
    final seconds = (_elapsedSeconds % 60).toString().padLeft(2, '0');
    return Row(
      children: [
        IconButton(
          icon: const Icon(Icons.delete_outline_rounded, color: AppColors.textTertiary),
          onPressed: _cancelRecording,
        ),
        const SizedBox(width: 4),
        const _RecordingDot(),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            '$minutes:$seconds',
            style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600),
          ),
        ),
        const Text(
          'Recording voice message…',
          style: TextStyle(fontSize: 12.5, color: AppColors.textTertiary),
        ),
        IconButton(
          icon: const Icon(Icons.send_rounded, color: AppColors.primaryPurple),
          onPressed: _stopAndSend,
        ),
      ],
    );
  }

  Widget _buildNormalRow() {
    return Row(
      children: [
        IconButton(
          icon: const Icon(Icons.mic_none_rounded),
          onPressed: widget.busy ? null : _startRecording,
        ),
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 8,
            ),
            decoration: BoxDecoration(
              color: AppColors.surfaceLight,
              borderRadius: BorderRadius.circular(20),
            ),
            child: TextField(
              controller: widget.controller,
              style: const TextStyle(fontSize: 14.5),
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => widget.onSend(),
              decoration: const InputDecoration(
                hintText: 'Message',
                hintStyle: TextStyle(color: AppColors.textTertiary),
                border: InputBorder.none,
                isDense: true,
              ),
            ),
          ),
        ),
        if (_hasText)
          IconButton(
            icon: const Icon(
              Icons.send_rounded,
              color: AppColors.primaryPurple,
            ),
            onPressed: widget.onSend,
          )
        else
          widget.busy
              ? const Padding(
                  padding: EdgeInsets.all(12),
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2.2),
                  ),
                )
              : IconButton(
                  icon: const Icon(Icons.add_circle_outline_rounded),
                  onPressed: _openAttachmentSheet,
                ),
      ],
    );
  }
}

/// A small pulsing red dot next to the elapsed timer while recording — the
/// standard "recording in progress" affordance (voice memo apps, every
/// camera app's video mode), so it's clear at a glance this isn't just a
/// static timer sitting there.
class _RecordingDot extends StatefulWidget {
  const _RecordingDot();

  @override
  State<_RecordingDot> createState() => _RecordingDotState();
}

class _RecordingDotState extends State<_RecordingDot> with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 700),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween(begin: 0.3, end: 1.0).animate(_controller),
      child: const Icon(Icons.fiber_manual_record_rounded, color: AppColors.badgeRed, size: 12),
    );
  }
}
