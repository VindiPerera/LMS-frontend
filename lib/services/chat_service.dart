import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import '../models/chat_message.dart';
import '../models/user.dart';
import '../models/voiceroom.dart';
import '../utils/chat_time.dart';
import '../utils/stream_fallback.dart';
import 'auth_service.dart';
import 'notification_api_service.dart';

/// 1:1 chat threads, backed by Firestore:
///
///   chats/{chatId}
///     participants: [uidA, uidB]                 (sorted; see chatIdFor)
///     participantInfo: { uid: {name, avatarUrl, countryFlag, handle} }
///     lastMessage, lastMessageAt, lastMessageSenderId
///     unread: { uid: count }
///
///   chats/{chatId}/messages/{messageId}
///     senderId, text, type, voiceSeconds, createdAt
///
/// `participantInfo` is denormalized (a snapshot of each user's profile,
/// refreshed every time they send a message) so the chat list can render
/// avatars/names without an extra read per row — see this project's
/// firestore.rules for the corresponding access rules.
class ChatService {
  static final _chats = FirebaseFirestore.instance.collection('chats');

  /// Fixed sender id the admin panel's broadcast feature writes as the
  /// "FaceTalk" system message (see hello-backend's
  /// FirestoreChatBroadcastService, which must agree on this exact string).
  /// Not a real Firebase Auth account — just a well-known id both sides
  /// treat specially. chat_detail_screen.dart hides the reply composer for
  /// it; firestore.rules blocks message writes into a thread flagged
  /// `isReadOnly` regardless.
  static const String systemUid = 'facetalk_system';

  static bool isSystemChat(String otherUid) => otherUid == systemUid;

  static String _uid() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) throw StateError('Not signed in.');
    return uid;
  }

  /// Deterministic thread id for exactly these two users, so starting a
  /// chat with the same person twice reuses one thread instead of creating
  /// duplicates.
  static String chatIdFor(String otherUid) {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? 'guest_user';
    final targetId = otherUid.isNotEmpty ? otherUid : 'target_user';
    final ids = [uid, targetId]..sort();
    return ids.join('_');
  }

  /// Live list of the current user's chat threads for
  /// hellotalk/chat_list_screen.dart, newest message first. Requires a
  /// composite index on (participants CONTAINS, lastMessageAt desc) — see
  /// firestore.indexes.json; without it this query fails outright, and
  /// (unlike a plain `.handleError((_) => <ChatPreview>[])`, whose return
  /// value is silently discarded — the callback is `void`, not a stream
  /// transform, so it swallows the error without ever emitting the
  /// fallback) `withFallback` below actually pushes `[]` downstream so the
  /// chat list's StreamBuilder resolves instead of spinning forever.
  static Stream<List<ChatPreview>> streamChatPreviews() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return const Stream.empty();
    return _chats
        .where('participants', arrayContains: uid)
        .orderBy('lastMessageAt', descending: true)
        .snapshots()
        .map(
          (snap) => snap.docs.map((doc) => _previewFromDoc(doc, uid)).toList(),
        )
        .withFallback(
          () => <ChatPreview>[],
          onError: (e) => debugPrint('ChatService.streamChatPreviews failed (showing no chats): $e'),
        );
  }

  /// Sum of unread counts across every thread, for the bottom nav badge.
  static Stream<int> streamTotalUnread() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return Stream.value(0);
    return _chats
        .where('participants', arrayContains: uid)
        .snapshots()
        .map((snap) {
          return snap.docs.fold<int>(0, (total, doc) {
            final unread = (doc.data()['unread'] as Map?)?[uid];
            return total + ((unread as num?)?.toInt() ?? 0);
          });
        })
        .withFallback(() => 0);
  }

  /// Live messages for one thread, oldest first, for
  /// hellotalk/chat_detail_screen.dart.
  ///
  /// Filters by `participants` (denormalized onto every message doc — see
  /// [sendMessage]) even though every message here already belongs to the
  /// caller's own thread: firestore.rules' per-message read rule checks
  /// `resource.data.participants`, and Firestore can only allow a *list*
  /// query against a per-document rule when the query carries a matching
  /// filter — an unfiltered `.collection('messages').snapshots()` would be
  /// rejected outright as unprovable, regardless of what's actually stored.
  static Stream<List<ChatMessage>> streamMessages(String chatId) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (chatId.isEmpty || uid == null) return const Stream.empty();
    return _chats
        .doc(chatId)
        .collection('messages')
        .where('participants', arrayContains: uid)
        .snapshots()
        .map((snap) {
          final messages = snap.docs
              .map((doc) => ChatMessage.fromDoc(doc.id, doc.data()))
              .toList();
          messages.sort((a, b) {
            final aTime = a.createdAt ?? DateTime.now();
            final bTime = b.createdAt ?? DateTime.now();
            return aTime.compareTo(bTime);
          });
          return messages;
        })
        .withFallback(() => <ChatMessage>[]);
  }


  /// Sends a text message, creating or updating the thread document on contact
  /// between these two users using a WriteBatch for instant optimistic updates
  /// and robust offline/online operation.
  static Future<void> sendMessage({
    required AppUser other,
    required String text,
  }) {
    return _send(other: other, previewText: text, fields: {'text': text, 'type': 'text'});
  }

  /// Sends the "👋 Wave" a user taps on someone's Connect card
  /// (connect_screen.dart's `_PartnerListTile`) — a lightweight, no-strings
  /// first contact. It's just a regular text message under the hood, so it
  /// goes through the exact same [sendMessage] path (and the same
  /// participants-only Firestore rules — see firestore.rules'
  /// chats/{chatId}/messages create rule) as any other message: two users
  /// can wave/chat freely without first becoming friends or following each
  /// other, since nothing in this app's chat model requires that.
  static Future<void> sendWave({required AppUser other}) {
    return sendMessage(other: other, text: '👋');
  }

  /// Sends a "join my Voice Room" invitation card into a chat thread — the
  /// "Share to a Chat" option on voice_room_detail_screen.dart's Share
  /// sheet. [room] is snapshotted onto the message (see ChatMessage's
  /// roomId/roomTitle/etc. fields) so the card still renders correctly even
  /// if the room is later renamed; VoiceRoomInviteCard looks up the room's
  /// *live* isActive state fresh when it renders, so a stale card just
  /// shows as ended rather than pretending it's still joinable.
  static Future<void> sendVoiceRoomInvite({
    required AppUser other,
    required VoiceRoom room,
  }) {
    final preview = '🎙️ Invited you to "${room.title}"';
    return _send(
      other: other,
      previewText: preview,
      pushBody: '🎙️ Invited you to a Voice Room',
      fields: {
        'text': preview,
        'type': 'voiceRoomInvite',
        'roomId': room.id,
        'roomTitle': room.title,
        'roomHostName': room.hostName,
        'roomHostAvatar': room.hostAvatar,
        'roomCategory': room.category,
        'roomTag': room.tag,
      },
    );
  }

  /// Shared plumbing behind [sendMessage] and [sendVoiceRoomInvite]: creates
  /// or updates the thread document and adds one message to its
  /// subcollection in a single batch (so a brand-new thread's very first
  /// message always lands atomically with the thread doc that owns it),
  /// then fires the recipient's push notification. [fields] is merged into
  /// the message document as-is — always include `text` (the chat list's
  /// preview also reads `lastMessage`, not the message doc directly) and
  /// `type`.
  static Future<void> _send({
    required AppUser other,
    required String previewText,
    required Map<String, dynamic> fields,
    String? pushBody,
  }) async {
    final uid = _uid();
    final chatId = chatIdFor(other.id);
    final chatRef = _chats.doc(chatId);
    final ids = [uid, other.id]..sort();

    final batch = FirebaseFirestore.instance.batch();

    // Set or merge thread document
    batch.set(
      chatRef,
      {
        'participants': ids,
        'participantInfo': {
          uid: _infoFor(AuthService.instance.currentUser),
          other.id: _infoFor(other),
        },
        'lastMessage': previewText,
        'lastMessageAt': FieldValue.serverTimestamp(),
        'lastMessageSenderId': uid,
        'unread.${other.id}': FieldValue.increment(1),
        'unread.$uid': 0,
      },
      SetOptions(merge: true),
    );

    // Add message to subcollection
    final msgRef = chatRef.collection('messages').doc();
    batch.set(msgRef, {
      'senderId': uid,
      'createdAt': FieldValue.serverTimestamp(),
      'participants': ids,
      ...fields,
    });

    await batch.commit();

    // Fire-and-forget: notifies the recipient's device even while the app
    // is backgrounded/locked (the Firestore write above only covers the
    // in-app unread badge, which nobody sees until they open the app).
    // See NotificationApiService's class doc for why this goes through
    // hello-backend rather than a Cloud Function.
    // ignore: discarded_futures
    NotificationApiService.sendPush(
      recipientUid: other.id,
      title: AuthService.instance.currentUser?.name ?? 'New message',
      body: pushBody ?? previewText,
      data: {'type': 'chat', 'chatId': chatId, 'senderId': uid},
    );
  }

  /// Whether a chat thread with [otherUid] already exists — used by
  /// connect_screen.dart to decide whether a Connect card should show the
  /// "Wave" button (no thread yet) or a "Chat" button (already said hi).
  /// A single doc read rather than a stream: this is checked once per row
  /// on the Partners list, not something that needs to stay live while the
  /// list is on screen.
  static Future<bool> hasChatWith(String otherUid) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || otherUid.isEmpty) return false;
    try {
      final doc = await _chats.doc(chatIdFor(otherUid)).get();
      return doc.exists;
    } catch (_) {
      // Offline or a transient read failure — fall back to "no thread yet"
      // so the row still renders something tappable (Wave) instead of
      // getting stuck.
      return false;
    }
  }

  /// Clears the current user's unread count for a thread — call when
  /// opening it. A thread that doesn't exist yet (no message sent) has
  /// nothing to mark, so failures here are silently ignored.
  static Future<void> markRead(String chatId) async {
    final uid = _uid();
    try {
      await _chats.doc(chatId).update({'unread.$uid': 0});
    } catch (_) {
      // No thread yet, or offline — fine, there's nothing to clear.
    }
  }

  static Map<String, dynamic> _infoFor(AppUser? user) {
    return {
      'name': user?.name ?? '',
      'avatarUrl': user?.avatarUrl ?? '',
      'countryFlag': user?.countryFlag ?? '',
      'handle': user?.handle ?? '',
    };
  }

  static ChatPreview _previewFromDoc(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
    String uid,
  ) {
    final data = doc.data();
    final participants = List<String>.from(
      data['participants'] as List? ?? const [],
    );
    final otherUid = participants.firstWhere(
      (id) => id != uid,
      orElse: () => '',
    );
    final info =
        (data['participantInfo'] as Map?)?[otherUid] as Map? ?? const {};

    final otherUser = AppUser(
      id: otherUid,
      name: info['name']?.toString() ?? 'Unknown',
      handle: info['handle']?.toString() ?? '',
      avatarUrl: info['avatarUrl']?.toString() ?? '',
      countryFlag: info['countryFlag']?.toString() ?? '',
      nativeLang: '',
      learningLang: '',
    );

    final ts = data['lastMessageAt'];
    final dt = ts is Timestamp ? ts.toDate() : null;
    final unread = ((data['unread'] as Map?)?[uid] as num?)?.toInt() ?? 0;

    return ChatPreview(
      user: otherUser,
      lastMessage: data['lastMessage']?.toString() ?? '',
      time: dt != null ? formatChatTime(dt) : '',
      unreadCount: unread,
    );
  }
}
