import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/chat_message.dart';
import '../models/user.dart';
import '../utils/chat_time.dart';
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
  /// hellotalk/chat_list_screen.dart, newest message first.
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
        .handleError((_) => <ChatPreview>[]);
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
        .handleError((_) => 0);
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
        .handleError((_) => <ChatMessage>[]);
  }


  /// Sends a text message, creating or updating the thread document on contact
  /// between these two users using a WriteBatch for instant optimistic updates
  /// and robust offline/online operation.
  static Future<void> sendMessage({
    required AppUser other,
    required String text,
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
        'lastMessage': text,
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
      'text': text,
      'type': 'text',
      'createdAt': FieldValue.serverTimestamp(),
      'participants': ids,
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
      body: text,
      data: {'type': 'chat', 'chatId': chatId, 'senderId': uid},
    );
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
