import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/moment.dart';
import 'auth_service.dart';
import 'friend_service.dart';

/// One page of the Moments feed, keyed by a [DocumentSnapshot] cursor
/// (never a raw timestamp — two posts can share a createdAt down to the
/// millisecond, which would silently skip/duplicate rows with a value
/// cursor instead of a document cursor).
class MomentPage {
  final List<Moment> moments;
  final DocumentSnapshot<Map<String, dynamic>>? lastDoc;
  final bool hasMore;

  const MomentPage({
    required this.moments,
    required this.lastDoc,
    required this.hasMore,
  });

  static const empty = MomentPage(moments: [], lastDoc: null, hasMore: false);
}

/// All Firestore access for `moments/{postId}` (and the reads it needs from
/// `users/{uid}`). Screens/widgets never talk to Firestore directly — see
/// lib/widgets/moment_card.dart and lib/screens/moments/moments_screen.dart.
///
/// `commentCount`/`reshareCount` are deliberately never written here —
/// they're Cloud-Function-only (functions/index.js), matching firestore.rules
/// which reject client updates to those fields.
class MomentService {
  static const int defaultPageSize = 15;
  static const String defaultReactionEmoji = '❤️';

  static CollectionReference<Map<String, dynamic>> get _moments =>
      FirebaseFirestore.instance.collection('moments');

  // --------------------------------------------------------------------
  // Audience — see firestore.rules `visibleToMe()` for the read side.
  // --------------------------------------------------------------------
  //
  // A Firestore *list* query (as opposed to a single-doc get) is validated
  // against its own filters, not against the documents it actually returns
  // — so a rule condition like "isFriendOf(post.user.id)" that isn't
  // mirrored by an equivalent query filter causes the whole feed query to
  // be rejected with permission-denied, regardless of what's really in the
  // collection. `visibility` alone can't be queried around a live
  // friendship lookup, so every moment also carries a denormalized
  // `audience` array — the literal 'public', or the uids allowed to read
  // it — computed here at write time and matched with a `.where('audience',
  // arrayContainsAny: [...])` filter on every list query below.
  //
  // Trade-off: for `friends` visibility, `audience` is a snapshot of the
  // owner's friends *at write time*. A friend added after posting won't
  // retroactively see it, and an unfriended uid won't retroactively lose
  // access, until the post is next edited (or archived/deleted).

  static List<String> _audienceKeysForReader() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    return uid == null || uid.isEmpty ? const ['public'] : ['public', uid];
  }

  static Future<List<String>> _audienceFor({
    required MomentVisibility visibility,
    required String ownerUid,
  }) async {
    switch (visibility) {
      case MomentVisibility.public:
        return [ownerUid, 'public'];
      case MomentVisibility.onlyMe:
        return [ownerUid];
      case MomentVisibility.friends:
        final friendIds = await FriendService.instance.getFriendIds();
        return {ownerUid, ...friendIds}.toList();
    }
  }

  // --------------------------------------------------------------------
  // Reads
  // --------------------------------------------------------------------

  /// Live view of the newest [limit] non-deleted moments. Used for the
  /// feed's first page only — later pages come from [fetchPage], which is a
  /// one-time read keyed off the last loaded document, so scrolling doesn't
  /// fight with the live listener re-ordering things underneath the user.
  static Stream<List<Moment>> streamFirstPage({int limit = defaultPageSize}) {
    return _moments
        .where('isDeleted', isEqualTo: false)
        .where('audience', arrayContainsAny: _audienceKeysForReader())
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .snapshots()
        .map((snap) => snap.docs.map(Moment.fromFirestore).toList());
  }

  /// One-time fetch of the next [limit] moments after [startAfter] (pass
  /// null for the very first page). See firestore.indexes.json index #1.
  static Future<MomentPage> fetchPage({
    DocumentSnapshot<Map<String, dynamic>>? startAfter,
    int limit = defaultPageSize,
  }) async {
    Query<Map<String, dynamic>> query = _moments
        .where('isDeleted', isEqualTo: false)
        .where('audience', arrayContainsAny: _audienceKeysForReader())
        .orderBy('createdAt', descending: true)
        .limit(limit);
    if (startAfter != null) {
      query = query.startAfterDocument(startAfter);
    }

    final snap = await query.get();
    return MomentPage(
      moments: snap.docs.map(Moment.fromFirestore).toList(),
      lastDoc: snap.docs.isEmpty ? startAfter : snap.docs.last,
      hasMore: snap.docs.length == limit,
    );
  }

  /// Stream moments published by a specific user, restricted to the ones
  /// the *current* signed-in user may actually see. See
  /// firestore.indexes.json index #2 (`user.id` ASC, `isDeleted` ASC,
  /// `audience` CONTAINS, `createdAt` DESC).
  static Stream<List<Moment>> streamUserMoments({
    required String userId,
    int limit = 30,
  }) {
    if (userId.isEmpty) return const Stream<List<Moment>>.empty();

    return _moments
        .where('user.id', isEqualTo: userId)
        .where('isDeleted', isEqualTo: false)
        .where('audience', arrayContainsAny: _audienceKeysForReader())
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .snapshots()
        .map((snap) => snap.docs.map(Moment.fromFirestore).toList());
  }

  /// One-time fetch, used to hydrate the read-only original-post preview
  /// inside a reshare (see lib/widgets/embedded_post_card.dart). Returns
  /// null both when the post was hard-deleted and when it was soft-deleted
  /// — callers should treat both as "Original post has been removed".
  static Future<Moment?> fetchMoment(String postId) async {
    if (postId.isEmpty) return null;
    final doc = await _moments.doc(postId).get();
    if (!doc.exists) return null;
    final moment = Moment.fromFirestore(doc);
    return moment.isDeleted ? null : moment;
  }

  /// Live single-post view, for post_detail_screen.dart (opened from a
  /// notification/deep link) and anywhere else that needs one post's likes/
  /// comments/reshare counts to update in real time without the whole feed.
  static Stream<Moment?> streamMoment(String postId) {
    if (postId.isEmpty) return Stream.value(null);
    return _moments.doc(postId).snapshots().map(
          (doc) => doc.exists ? Moment.fromFirestore(doc) : null,
        );
  }

  // --------------------------------------------------------------------
  // Create / edit / archive / soft-delete
  // --------------------------------------------------------------------

  /// Allocates a post id up front, before any media upload starts.
  /// MediaService uploads to `moments/{uid}/{postId}/...`, so the id needs
  /// to exist before the first file goes to Storage; pass it back into
  /// [createMoment] once uploads finish.
  static String newPostId() => _moments.doc().id;

  /// Creates a new moment (or a reshare, when [isReshare] is true). All
  /// media must already be uploaded to Storage — pass the resulting
  /// download URLs, never a local file path. Pass [postId] from
  /// [newPostId] when the create flow involved media uploads, so the
  /// Storage path and the Firestore doc id line up; omit it for text-only
  /// posts or reshares (an id is allocated inline in that case).
  static Future<String> createMoment({
    required String text,
    String? postId,
    List<String> imageUrls = const [],
    String? videoUrl,
    String? videoThumbnailUrl,
    MomentMediaType mediaType = MomentMediaType.none,
    MomentVisibility visibility = MomentVisibility.public,
    bool isReshare = false,
    String? originalPostId,
  }) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final currentUser = AuthService.instance.currentUser;
    if (uid == null || currentUser == null) {
      throw StateError('You must be signed in to post a moment.');
    }

    final cleanText = text.trim();
    if (cleanText.isEmpty && imageUrls.isEmpty && videoUrl == null && !isReshare) {
      throw StateError('Add some text or media before posting.');
    }

    final draft = Moment(
      user: currentUser,
      text: cleanText,
      imageUrls: imageUrls,
      videoUrl: videoUrl,
      videoThumbnailUrl: videoThumbnailUrl,
      mediaType: mediaType,
      visibility: visibility,
      isReshare: isReshare,
      originalPostId: originalPostId,
    );
    final audience = await _audienceFor(visibility: visibility, ownerUid: uid);

    final ref = postId != null && postId.isNotEmpty ? _moments.doc(postId) : _moments.doc();
    await ref.set({...draft.toCreateMap(), 'audience': audience});

    if (isReshare && originalPostId != null && originalPostId.isNotEmpty) {
      try {
        await _moments.doc(originalPostId).update({
          'reshareCount': FieldValue.increment(1),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      } catch (_) {}
    }

    return ref.id;
  }

  /// Edits an existing post. Only pass the fields that changed — `null`
  /// means "leave as-is". `imageUrls`/`videoUrl` should already contain the
  /// final merged set (kept originals + freshly uploaded replacements);
  /// see create_moment_screen.dart for how edit mode assembles that.
  static Future<void> updateMoment({
    required String postId,
    String? text,
    List<String>? imageUrls,
    String? videoUrl,
    String? videoThumbnailUrl,
    MomentMediaType? mediaType,
    MomentVisibility? visibility,
  }) async {
    if (postId.isEmpty) return;
    final update = <String, dynamic>{'updatedAt': FieldValue.serverTimestamp()};
    if (text != null) update['text'] = text.trim();
    if (imageUrls != null) update['imageUrls'] = imageUrls;
    if (videoUrl != null) update['videoUrl'] = videoUrl;
    if (videoThumbnailUrl != null) update['videoThumbnailUrl'] = videoThumbnailUrl;
    if (mediaType != null) update['mediaType'] = mediaType.storageValue;
    if (visibility != null) {
      update['visibility'] = visibility.storageValue;
      // Only the owner can change visibility (see firestore.rules), so
      // recomputing the audience from the caller's own uid is safe here.
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid != null) {
        update['audience'] = await _audienceFor(visibility: visibility, ownerUid: uid);
      }
    }
    await _moments.doc(postId).update(update);
  }

  /// Archive == keep the post but only its owner can see it.
  static Future<void> archiveMoment(String postId) async {
    if (postId.isEmpty) return;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    await _moments.doc(postId).update({
      'visibility': MomentVisibility.onlyMe.storageValue,
      if (uid != null) 'audience': [uid],
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Soft delete only — functions/index.js's onPostDelete handles Storage
  /// and comment cleanup for an actual (Admin-SDK/console) hard delete, but
  /// the client must never issue one itself (firestore.rules blocks it too).
  static Future<void> softDeleteMoment(String postId) async {
    if (postId.isEmpty) return;
    await _moments.doc(postId).update({
      'isDeleted': true,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  // --------------------------------------------------------------------
  // Likes / reactions
  // --------------------------------------------------------------------

  static Map<String, List<String>> _decodeReactions(Object? raw) {
    final out = <String, List<String>>{};
    if (raw is Map) {
      raw.forEach((key, value) {
        out[key.toString()] =
            (value as List?)?.map((e) => e.toString()).toList() ?? <String>[];
      });
    }
    return out;
  }

  /// Single-tap heart: toggles a plain like. Adding a like also drops the
  /// uid into the default heart reaction bucket so `topReactionEmojis`
  /// stays meaningful for people who never open the reaction picker.
  static Future<void> toggleLike({
    required String postId,
    required String uid,
  }) async {
    if (postId.isEmpty || uid.isEmpty) return;
    final ref = _moments.doc(postId);
    await FirebaseFirestore.instance.runTransaction((tx) async {
      final snap = await tx.get(ref);
      if (!snap.exists) return;
      final data = snap.data()!;
      final likes =
          (data['likes'] as List?)?.map((e) => e.toString()).toList() ??
              <String>[];
      final reactions = _decodeReactions(data['reactions']);

      if (likes.contains(uid)) {
        likes.remove(uid);
        for (final bucket in reactions.values) {
          bucket.remove(uid);
        }
      } else {
        likes.add(uid);
        final heart = reactions[defaultReactionEmoji] ?? <String>[];
        if (!heart.contains(uid)) heart.add(uid);
        reactions[defaultReactionEmoji] = heart;
      }

      tx.update(ref, {
        'likes': likes,
        'reactions': reactions,
        'likeCount': likes.length,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });
  }

  /// Long-press → emoji picker: sets (or, if [emoji] was already the user's
  /// reaction, clears) a specific reaction. Picking a new emoji always
  /// replaces whichever one the user had before — one reaction per user.
  static Future<void> setReaction({
    required String postId,
    required String uid,
    required String emoji,
  }) async {
    if (postId.isEmpty || uid.isEmpty) return;
    final ref = _moments.doc(postId);
    await FirebaseFirestore.instance.runTransaction((tx) async {
      final snap = await tx.get(ref);
      if (!snap.exists) return;
      final data = snap.data()!;
      final likes =
          (data['likes'] as List?)?.map((e) => e.toString()).toList() ??
              <String>[];
      final reactions = _decodeReactions(data['reactions']);

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

      tx.update(ref, {
        'likes': likes,
        'reactions': reactions,
        'likeCount': likes.length,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });
  }
}
