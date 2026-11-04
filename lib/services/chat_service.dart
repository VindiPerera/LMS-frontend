import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import '../config/api_config.dart';
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
          (snap) => snap.docs
              // Swiped-to-delete by this user (see hideChat) — a per-user
              // flag, not an actual delete: the thread document is shared
              // with the other participant (firestore.rules blocks
              // deleting it outright), and _send clears this again for
              // whoever gets the next message, so "deleting" a chat here
              // just hides it until either side messages again, the same
              // behavior most chat apps give "delete conversation".
              .where((doc) => !_hiddenFor(doc.data(), uid))
              .map((doc) => _previewFromDoc(doc, uid))
              .toList(),
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
        // A chat either side swiped to delete (see hideChat) reappears the
        // moment there's new activity — same as most chat apps' "delete
        // conversation" only hides it until the next message, rather than
        // leaving someone able to message into a thread the recipient can
        // no longer see at all.
        'hiddenFor': FieldValue.arrayRemove(ids),
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

  static bool _hiddenFor(Map<String, dynamic> data, String uid) {
    final hidden = data['hiddenFor'] as List?;
    return hidden != null && hidden.contains(uid);
  }

  /// Swipe-to-delete on a chat list row (chat_list_screen.dart) — takes the
  /// thread's own id directly (ChatPreview.id) rather than deriving it,
  /// since a group thread's id isn't a function of its members the way a
  /// 1:1 thread's is; works for either shape unchanged. Only hides the
  /// thread from the caller's own list (see streamChatPreviews' doc
  /// comment) — firestore.rules blocks deleting a chats/{chatId} doc
  /// outright (`allow delete: if false`) since it's shared with every other
  /// participant, who'd otherwise lose their own copy of the conversation
  /// the moment this user "deleted" it. No-op if the thread doesn't exist.
  static Future<void> hideChat(String chatId) async {
    final uid = _uid();
    try {
      await _chats.doc(chatId).update({
        'hiddenFor': FieldValue.arrayUnion([uid]),
      });
    } catch (_) {
      // No thread yet, or offline — nothing to hide.
    }
  }

  /// Sends a photo — the composer's "+" > Photo option. [imageUrl] is
  /// already uploaded (see MediaService.uploadImageBytes) before this is
  /// called, same division of labor as [sendVoiceMessage]/[sendFileMessage].
  static Future<void> sendImageMessage({
    required AppUser other,
    required String imageUrl,
  }) {
    return _send(
      other: other,
      previewText: '📷 Photo',
      fields: {'text': '', 'type': 'image', 'mediaUrl': imageUrl},
    );
  }

  /// Sends a voice note — the composer's mic button. [audioUrl] is already
  /// uploaded (see MediaService.uploadVoiceBytes) by the time this runs.
  static Future<void> sendVoiceMessage({
    required AppUser other,
    required String audioUrl,
    required int seconds,
  }) {
    return _send(
      other: other,
      previewText: '🎤 Voice message',
      fields: {
        'text': '',
        'type': 'voice',
        'mediaUrl': audioUrl,
        'voiceSeconds': seconds,
      },
    );
  }

  /// Sends a generic file attachment — the composer's "+" > File option.
  static Future<void> sendFileMessage({
    required AppUser other,
    required String fileUrl,
    required String fileName,
    required int fileSize,
  }) {
    return _send(
      other: other,
      previewText: '📎 $fileName',
      fields: {
        'text': '',
        'type': 'file',
        'mediaUrl': fileUrl,
        'fileName': fileName,
        'fileSize': fileSize,
      },
    );
  }

  // ------------------------------------------------------------------
  // Group chats — chats/{chatId} with isGroup: true, a plain Firestore
  // auto-id (not chatIdFor's deterministic 2-person id), adminId (the
  // creator; see leaveGroup for what happens if they leave), and the same
  // participants/participantInfo/unread shape 1:1 threads already use —
  // see ChatThread, which chat_detail_screen.dart's group header and
  // group_info_screen.dart's member list both stream from here rather than
  // each re-deriving it independently.
  // ------------------------------------------------------------------

  // Keep in sync with firestore.rules' own hardcoded 8 in the chats create
  // and admin-roster update branches — rules can't reference a Dart
  // constant, so both sides just have to agree on the same number.
  static const int maxGroupMembers = 8;

  static Stream<ChatThread?> streamGroupThread(String chatId) {
    if (chatId.isEmpty) return Stream.value(null);
    return _chats
        .doc(chatId)
        .snapshots()
        .map((doc) => doc.exists ? ChatThread.fromDoc(doc.id, doc.data()!) : null)
        .withFallback(() => null);
  }

  /// Creates a new group with [members] (not including the caller, who's
  /// added automatically as the admin) — "Create Group Chat" in
  /// add_contact_screen.dart, via choose_group_members_screen.dart's
  /// following-based picker. Returns the new chatId.
  static Future<String> createGroup({
    required String name,
    required List<AppUser> members,
  }) async {
    final uid = _uid();
    final me = AuthService.instance.currentUser;
    if (me == null) throw StateError('Not signed in.');
    if (members.length + 1 > maxGroupMembers) {
      throw StateError('A group can have at most $maxGroupMembers members.');
    }
    final cleanName = name.trim().isEmpty ? 'New Group' : name.trim();

    final chatRef = _chats.doc();
    final participantIds = [uid, ...members.map((m) => m.id)];
    final participantInfo = <String, dynamic>{uid: _infoFor(me)};
    for (final m in members) {
      participantInfo[m.id] = _infoFor(m);
    }
    final unread = <String, dynamic>{for (final id in participantIds) id: 0};

    await chatRef.set({
      'isGroup': true,
      'groupName': cleanName,
      'groupAvatar': '',
      'adminId': uid,
      'participants': participantIds,
      'participantInfo': participantInfo,
      'unread': unread,
      'lastMessage': '${me.name} created the group',
      'lastMessageAt': FieldValue.serverTimestamp(),
      'lastMessageSenderId': uid,
      'createdAt': FieldValue.serverTimestamp(),
    });

    // A system line so the thread never opens empty — same spirit as a 1:1
    // thread's very first message, just not attributable to any one
    // "first message" since the group itself is the event.
    await chatRef.collection('messages').add({
      'senderId': uid,
      'type': 'system',
      'text': '${me.name} created the group',
      'createdAt': FieldValue.serverTimestamp(),
      'participants': participantIds,
    });

    for (final m in members) {
      // ignore: discarded_futures
      NotificationApiService.sendPush(
        recipientUid: m.id,
        title: cleanName,
        body: '${me.name} added you to the group',
        data: {'type': 'chat', 'chatId': chatRef.id, 'senderId': uid},
      );
    }

    return chatRef.id;
  }

  /// Admin-only: adds [newMembers] to [chatId]. [currentMemberIds] is the
  /// group's live member list (the caller — group_info_screen.dart — is
  /// already streaming [ChatThread], so this avoids a second read just to
  /// know who to write the system message's `participants` snapshot for;
  /// see firestore.rules' matching isGroup update branch, which enforces
  /// the admin-only part server-side too).
  static Future<void> addGroupMembers({
    required String chatId,
    required List<String> currentMemberIds,
    required List<AppUser> newMembers,
  }) async {
    if (newMembers.isEmpty) return;
    if (currentMemberIds.length + newMembers.length > maxGroupMembers) {
      throw StateError('A group can have at most $maxGroupMembers members.');
    }
    final uid = _uid();
    final me = AuthService.instance.currentUser;
    final chatRef = _chats.doc(chatId);
    final newIds = newMembers.map((m) => m.id).toList();
    final allIds = [...currentMemberIds, ...newIds];

    final updates = <String, dynamic>{
      'participants': FieldValue.arrayUnion(newIds),
    };
    for (final m in newMembers) {
      updates['participantInfo.${m.id}'] = _infoFor(m);
      updates['unread.${m.id}'] = 0;
    }
    await chatRef.update(updates);

    final names = newMembers.map((m) => m.name).join(', ');
    await chatRef.collection('messages').add({
      'senderId': uid,
      'type': 'system',
      'text': '${me?.name ?? 'Someone'} added $names',
      'createdAt': FieldValue.serverTimestamp(),
      'participants': allIds,
    });

    for (final m in newMembers) {
      // ignore: discarded_futures
      NotificationApiService.sendPush(
        recipientUid: m.id,
        title: 'Added to a group',
        body: '${me?.name ?? 'Someone'} added you to a group',
        data: {'type': 'chat', 'chatId': chatId, 'senderId': uid},
      );
    }
  }

  /// Admin-only: removes [memberId] from [chatId] — see firestore.rules'
  /// isGroup update branch for the server-side admin check. The removed
  /// member's own participantInfo/unread entries are left in place rather
  /// than deleted: harmless once they're out of `participants` (nothing
  /// reads them for a non-member), and deleting by dynamic map key here
  /// would need its own FieldValue.delete() per field for no real benefit.
  static Future<void> removeGroupMember({
    required String chatId,
    required List<String> currentMemberIds,
    required String memberId,
    required String memberName,
  }) async {
    final uid = _uid();
    final me = AuthService.instance.currentUser;
    final chatRef = _chats.doc(chatId);
    final remainingIds = currentMemberIds.where((id) => id != memberId).toList();

    await chatRef.update({
      'participants': FieldValue.arrayRemove([memberId]),
    });

    await chatRef.collection('messages').add({
      'senderId': uid,
      'type': 'system',
      'text': '${me?.name ?? 'Someone'} removed $memberName',
      'createdAt': FieldValue.serverTimestamp(),
      // The removed member no longer needs (or should keep) read access to
      // this or any later message — only who's left can read it.
      'participants': remainingIds,
    });
  }

  /// Self-removal — the group_info_screen.dart "Leave Group" action,
  /// available to any member including the admin. If the admin leaves and
  /// others remain, admin passes to the next member in [currentMemberIds]
  /// (its existing join order) rather than leaving the group permanently
  /// unmanageable; firestore.rules' isGroup leave branch enforces that this
  /// can only ever happen as part of the leaver's own removal, never an
  /// arbitrary admin handoff.
  static Future<void> leaveGroup({
    required String chatId,
    required List<String> currentMemberIds,
    required String currentAdminId,
  }) async {
    final uid = _uid();
    final me = AuthService.instance.currentUser;
    final chatRef = _chats.doc(chatId);
    final remainingIds = currentMemberIds.where((id) => id != uid).toList();

    final updates = <String, dynamic>{
      'participants': FieldValue.arrayRemove([uid]),
    };
    if (currentAdminId == uid && remainingIds.isNotEmpty) {
      updates['adminId'] = remainingIds.first;
    }
    await chatRef.update(updates);

    if (remainingIds.isNotEmpty) {
      await chatRef.collection('messages').add({
        'senderId': uid,
        'type': 'system',
        'text': '${me?.name ?? 'Someone'} left the group',
        'createdAt': FieldValue.serverTimestamp(),
        // Includes the leaver, not just remainingIds — firestore.rules'
        // messages create rule requires the sender be in their own
        // message's participants list, and there's no real reason to hide
        // someone's own "I left" announcement from them anyway.
        'participants': currentMemberIds,
      });
    }
  }

  /// Admin-only: sets the group's display photo — group_info_screen.dart's
  /// avatar tap. [avatarUrl] is already uploaded (see MediaService.
  /// uploadGroupAvatarBytes) before this is called. firestore.rules'
  /// isGroup update branches only let the admin touch this field; everyone
  /// else's writes to a group doc are restricted to leaving it or the
  /// ordinary per-message fields (lastMessage/unread/hiddenFor), which
  /// never include groupAvatar.
  static Future<void> updateGroupAvatar({
    required String chatId,
    required String avatarUrl,
  }) async {
    await _chats.doc(chatId).update({'groupAvatar': avatarUrl});
  }

  /// Admin-only: "Delete Group" — group_info_screen.dart. Not a real
  /// Firestore delete (chats/{chatId} blocks that outright — see its own
  /// `allow delete: if false` and doc comment); instead empties
  /// `participants`, which removes the thread from every member's chat
  /// list (streamChatPreviews' `arrayContains` query stops matching for
  /// everyone at once) without leaving the `messages` subcollection
  /// dangling under a now-deleted parent, and without needing a cascading
  /// delete this project has no Cloud Functions to run anyway.
  static Future<void> deleteGroup({
    required String chatId,
    required List<String> currentMemberIds,
  }) async {
    final uid = _uid();
    final me = AuthService.instance.currentUser;
    final chatRef = _chats.doc(chatId);

    // Written BEFORE participants is cleared — everyone still listed in
    // currentMemberIds (including the admin themself) can still read this
    // closing line; see firestore.rules' messages create rule, which reads
    // live membership off the parent doc at write time.
    await chatRef.collection('messages').add({
      'senderId': uid,
      'type': 'system',
      'text': '${me?.name ?? 'Someone'} deleted the group',
      'createdAt': FieldValue.serverTimestamp(),
      'participants': currentMemberIds,
    });

    await chatRef.update({'participants': <String>[]});
  }

  /// Sends into an EXISTING group [chatId] — unlike [_send] (1:1), the
  /// thread doc and its participantInfo already exist (see [createGroup]/
  /// [addGroupMembers]) and aren't rewritten on every message; this only
  /// touches the per-message fields 1:1 sends also touch. [recipientUids]
  /// (every OTHER current member) drives the unread fan-out and pushes —
  /// the caller already has this live from [streamGroupThread].
  static Future<void> _sendToGroup({
    required String chatId,
    required List<String> recipientUids,
    required String previewText,
    required Map<String, dynamic> fields,
    String? pushBody,
  }) async {
    final uid = _uid();
    final chatRef = _chats.doc(chatId);
    final batch = FirebaseFirestore.instance.batch();

    batch.update(chatRef, {
      'lastMessage': previewText,
      'lastMessageAt': FieldValue.serverTimestamp(),
      'lastMessageSenderId': uid,
      'unread.$uid': 0,
      for (final r in recipientUids) 'unread.$r': FieldValue.increment(1),
    });

    final msgRef = chatRef.collection('messages').doc();
    batch.set(msgRef, {
      'senderId': uid,
      'createdAt': FieldValue.serverTimestamp(),
      'participants': [uid, ...recipientUids],
      ...fields,
    });

    await batch.commit();

    for (final r in recipientUids) {
      // ignore: discarded_futures
      NotificationApiService.sendPush(
        recipientUid: r,
        title: AuthService.instance.currentUser?.name ?? 'New message',
        body: pushBody ?? previewText,
        data: {'type': 'chat', 'chatId': chatId, 'senderId': uid},
      );
    }
  }

  static Future<void> sendGroupMessage({
    required String chatId,
    required List<String> recipientUids,
    required String text,
  }) {
    return _sendToGroup(
      chatId: chatId,
      recipientUids: recipientUids,
      previewText: text,
      fields: {'text': text, 'type': 'text'},
    );
  }

  static Future<void> sendGroupImageMessage({
    required String chatId,
    required List<String> recipientUids,
    required String imageUrl,
  }) {
    return _sendToGroup(
      chatId: chatId,
      recipientUids: recipientUids,
      previewText: '📷 Photo',
      fields: {'text': '', 'type': 'image', 'mediaUrl': imageUrl},
    );
  }

  static Future<void> sendGroupVoiceMessage({
    required String chatId,
    required List<String> recipientUids,
    required String audioUrl,
    required int seconds,
  }) {
    return _sendToGroup(
      chatId: chatId,
      recipientUids: recipientUids,
      previewText: '🎤 Voice message',
      fields: {
        'text': '',
        'type': 'voice',
        'mediaUrl': audioUrl,
        'voiceSeconds': seconds,
      },
    );
  }

  static Future<void> sendGroupFileMessage({
    required String chatId,
    required List<String> recipientUids,
    required String fileUrl,
    required String fileName,
    required int fileSize,
  }) {
    return _sendToGroup(
      chatId: chatId,
      recipientUids: recipientUids,
      previewText: '📎 $fileName',
      fields: {
        'text': '',
        'type': 'file',
        'mediaUrl': fileUrl,
        'fileName': fileName,
        'fileSize': fileSize,
      },
    );
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
    final ts = data['lastMessageAt'];
    final dt = ts is Timestamp ? ts.toDate() : null;
    final unread = ((data['unread'] as Map?)?[uid] as num?)?.toInt() ?? 0;

    if (data['isGroup'] == true) {
      final groupInfo = (data['participantInfo'] as Map?) ?? const {};
      return ChatPreview(
        id: doc.id,
        isGroup: true,
        groupName: data['groupName']?.toString() ?? 'Group',
        groupAvatar: ApiConfig.resolveUrl(data['groupAvatar']?.toString() ?? ''),
        memberCount: participants.length,
        // GroupAvatar._maxInRing caps the ring at 6 anyway, matched here
        // so this preview carries exactly what it'll actually use.
        members: participants
            .take(6)
            .map((id) => (uid: id, name: (groupInfo[id] as Map?)?['name']?.toString() ?? ''))
            .toList(),
        lastMessage: data['lastMessage']?.toString() ?? '',
        time: dt != null ? formatChatTime(dt) : '',
        unreadCount: unread,
      );
    }

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

    return ChatPreview(
      id: doc.id,
      user: otherUser,
      lastMessage: data['lastMessage']?.toString() ?? '',
      time: dt != null ? formatChatTime(dt) : '',
      unreadCount: unread,
    );
  }
}
