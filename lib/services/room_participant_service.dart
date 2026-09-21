import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../models/room_participant.dart';
import 'auth_service.dart';
import 'voice_room_service.dart';

/// "6h 20m", or "45 min" once under an hour — never a raw Duration dump.
/// Shared by [RoomBanException] and screens/voiceroom/open_voice_room.dart's
/// pre-join ban dialog, so the two never drift into slightly different
/// wording for the same remaining time.
String formatBanRemaining(Duration remaining) {
  final clamped = remaining.isNegative ? Duration.zero : remaining;
  final hours = clamped.inHours;
  final minutes = clamped.inMinutes % 60;
  if (hours <= 0) return '${clamped.inMinutes.clamp(1, 59)} min';
  return minutes > 0 ? '${hours}h ${minutes}m' : '${hours}h';
}

/// Thrown by [RoomParticipantService.join] when the signed-in user is still
/// serving a [RoomParticipantService.kickParticipant] ban for this room.
/// [remaining] is only ever an estimate from the caller's own clock, for
/// display (e.g. "try again in 6h 20m") — the actual 24h window is enforced
/// server-side by firestore.rules' isBanned(), entirely off server time, so
/// this exception being thrown (or not) has no bearing on what the rules
/// would have decided; it's purely a friendlier message layered on top of
/// the same rejection the rules already guarantee.
///
/// In practice this should rarely fire anymore — screens/voiceroom/
/// open_voice_room.dart checks ban status BEFORE ever navigating into the
/// room, so a still-banned user normally never reaches [join] at all. This
/// stays as [join]'s own belt-and-suspenders check for any entry point that
/// ever bypasses that pre-check (a race where a ban lands after the
/// pre-check passed but before the join write lands, or a future call site
/// that forgets to go through openVoiceRoom).
class RoomBanException implements Exception {
  final Duration remaining;
  const RoomBanException(this.remaining);

  String get remainingLabel => formatBanRemaining(remaining);

  @override
  String toString() =>
      "You've been removed from this room and can rejoin in $remainingLabel.";
}

/// Firestore access for `voiceRooms/{roomId}/participants/{uid}` and
/// `voiceRooms/{roomId}/comments/{commentId}` — the real per-room roster
/// and comment feed VoiceRoomDetailScreen renders (replacing the old
/// boardSpeakers/boardComments mock data, which was identical on every
/// room). See firestore.rules for the matching subcollection rules.
class RoomParticipantService {
  // Matches the speaker grid's existing 4-per-row layout (host + 7 seats).
  // Seat-claiming isn't done inside a transaction (see _hasOpenSeat and its
  // callers — acceptRaisedHand/acceptStageInvite), so the grid itself
  // tolerates a few more than this rather than ever dropping a real
  // participant — this is just the padding target.
  static const speakerSeats = 8;

  // Presence: VoiceRoomDetailScreen pings [heartbeat] on this interval while
  // open; a participant not heard from for [staleAfter] is swept by
  // whichever other client's stream notices first (see
  // sweepStaleParticipants) — nothing server-side is watching, since this
  // project has no deployed Cloud Functions. ~3 missed beats before
  // sweeping tolerates a brief network blip without evicting someone still
  // actually there.
  static const heartbeatInterval = Duration(seconds: 25);
  static const staleAfter = Duration(seconds: 90);

  // How long a kickParticipant ban keeps someone out of the room they were
  // kicked from — see [join]'s pre-check and firestore.rules' isBanned(),
  // which is the actual enforcement; this constant only drives this file's
  // own read of that same 24h window (both sides hard-code the same
  // duration.value(24, 'h') rather than one deriving it from the other,
  // since a Dart Duration and a rules `duration.value(...)` aren't
  // interchangeable — keep them in sync if this ever changes).
  static const banDuration = Duration(hours: 24);

  static CollectionReference<Map<String, dynamic>> _participants(String roomId) => FirebaseFirestore
      .instance
      .collection('voiceRooms')
      .doc(roomId)
      .collection('participants');

  static CollectionReference<Map<String, dynamic>> _bans(String roomId) =>
      FirebaseFirestore.instance.collection('voiceRooms').doc(roomId).collection('bans');

  static CollectionReference<Map<String, dynamic>> _comments(String roomId) =>
      FirebaseFirestore.instance.collection('voiceRooms').doc(roomId).collection('comments');

  static CollectionReference<Map<String, dynamic>> _subtitles(String roomId) =>
      FirebaseFirestore.instance.collection('voiceRooms').doc(roomId).collection('subtitles');

  static DocumentReference<Map<String, dynamic>> _room(String roomId) =>
      FirebaseFirestore.instance.collection('voiceRooms').doc(roomId);

  static String? get _uid => FirebaseAuth.instance.currentUser?.uid;

  /// A fresh, random token VoiceRoomDetailScreen generates once per mount
  /// (`State` field, not `late final` off a stream) and threads through
  /// [join]/[heartbeat]/[leave] as `sessionId`. Firestore's own
  /// auto-generated doc-id randomness is reused here purely as a cheap,
  /// dependency-free unique string — no document is ever created at this
  /// path.
  ///
  /// This exists to fix a real race: back-then-immediately-rejoin (or any
  /// two overlapping mounts for the same room) starts a new [join] before
  /// the old screen's fire-and-forget [leave] has necessarily finished.
  /// Without a fencing token, whichever of that stale leave/fresh join
  /// finishes last "wins" unpredictably — including the stale leave
  /// deleting the doc the fresh join just (re)claimed, silently dropping
  /// the host back to "not present" in the live roster. Every write below
  /// tags or checks `sessionId` so a leave can only ever remove the
  /// session that's actually still current.
  static String newSessionId() => FirebaseFirestore.instance.collection('_').doc().id;

  /// Registers the signed-in user as present in [roomId] — the host lands
  /// as an unmuted 'host', everyone else as a muted 'listener' (unless they
  /// are the room's designated moderator, in which case their role is
  /// restored to 'moderator'). Called once from
  /// VoiceRoomDetailScreen.initState; pairs with [leave].
  ///
  /// Idempotent and race-safe: reconnecting to a session that hasn't been
  /// swept as stale yet (e.g. a brief network drop while
  /// VoiceRoomDetailScreen stayed mounted, or navigating back in before the
  /// old doc expired) just refreshes the heartbeat and keeps whatever
  /// role/mute state they had — it does not reset them to a fresh
  /// listener, does not double-increment participantCount, and (via the
  /// transaction below) can't lose to a concurrent stale [leave] the way a
  /// plain read-then-write would.
  ///
  /// Moderator restoration: the host-assigned moderator uid is stored on the
  /// room doc itself (voiceRooms/{roomId}.moderatorUid — see
  /// VoiceRoomService.setModerator). When the moderator's own participant
  /// doc no longer exists (they left cleanly and their doc was deleted by
  /// [leave]), this join() reads that field and recreates them with
  /// role:'moderator' rather than the default 'listener', making rejoin
  /// transparent to the rest of the room.
  /// Remaining ban time if the signed-in user is still serving a
  /// [kickParticipant] ban for [roomId], or null if they're clear to join
  /// (never banned, or their ban has already expired). [join] checks this
  /// itself right before actually joining, but the real point of exposing
  /// it publicly is so a caller can check FIRST — see
  /// screens/voiceroom/open_voice_room.dart, which every "open this room"
  /// tap in the app should go through instead of pushing
  /// VoiceRoomDetailScreen directly, so a still-banned user never sees the
  /// room open at all. Fails open (returns null) on a read error — an
  /// unreadable ban doc isn't grounds to block someone client-side; the
  /// real enforcement is firestore.rules' isBanned() regardless.
  static Future<Duration?> banRemaining(String roomId) async {
    final uid = _uid;
    if (uid == null || roomId.isEmpty) return null;
    try {
      final banSnap = await _bans(roomId).doc(uid).get();
      final bannedAt = (banSnap.data()?['bannedAt'] as Timestamp?)?.toDate();
      if (bannedAt == null) return null;
      final remaining = bannedAt.add(banDuration).difference(DateTime.now());
      return remaining > Duration.zero ? remaining : null;
    } catch (e) {
      debugPrint('RoomParticipantService.banRemaining: could not check ban status (non-fatal): $e');
      return null;
    }
  }

  static Future<void> join({required String roomId, required bool isHost, required String sessionId}) async {
    final uid = _uid;
    final user = AuthService.instance.currentUser;
    if (uid == null || user == null || roomId.isEmpty) return;

    // Belt-and-suspenders — see RoomBanException's doc comment. The normal
    // path never reaches here still banned at all: screens/voiceroom/
    // open_voice_room.dart already checked (and refused to navigate here)
    // before this screen was ever pushed.
    final remaining = await banRemaining(roomId);
    if (remaining != null) {
      throw RoomBanException(remaining);
    }

    // Read the room doc once (outside the transaction — we only need the
    // moderatorUid field, which only the host can change, so reading it
    // slightly before the transaction is safe enough; a race here would at
    // worst cause a rejoining moderator to land as 'listener' for one join
    // tick, which is no worse than the status-quo before this fix).
    String? storedModeratorUid;
    try {
      final roomSnap = await _room(roomId).get();
      storedModeratorUid = roomSnap.data()?['moderatorUid']?.toString();
    } catch (e) {
      debugPrint('RoomParticipantService.join: could not read moderatorUid (non-fatal): $e');
    }

    final isModerator = !isHost && uid == storedModeratorUid;

    final participantRef = _participants(roomId).doc(uid);
    await FirebaseFirestore.instance.runTransaction((tx) async {
      final existing = await tx.get(participantRef);
      if (existing.exists) {
        final updates = <String, dynamic>{
          'sessionId': sessionId,
          'lastActiveAt': FieldValue.serverTimestamp(),
        };
        if (user.avatarUrl.isNotEmpty && (existing.data()?['avatarUrl']?.toString().isEmpty ?? true)) {
          updates['avatarUrl'] = user.avatarUrl;
        }
        if (isModerator && existing.data()?['role'] != 'moderator') {
          updates['role'] = 'moderator';
        }
        tx.update(participantRef, updates);
        return;
      }
      // Determine the correct starting role:
      //  - room's hostId owner  → 'host'   (unmuted)
      //  - room's moderatorUid  → 'moderator' (muted, but with mod powers)
      //  - everyone else        → 'listener' (muted)
      final role = isHost ? 'host' : (isModerator ? 'moderator' : 'listener');
      tx.set(participantRef, {
        'uid': uid,
        'sessionId': sessionId,
        'name': user.name,
        'avatarUrl': user.avatarUrl,
        'countryFlag': user.countryFlag,
        'gender': user.gender,
        'age': user.age,
        'nativeLang': user.nativeLang,
        'learningLang': user.learningLang,
        'tags': user.tags,
        'role': role,
        'isMuted': !isHost, // host starts unmuted; moderator & listener start muted
        'joinedAt': FieldValue.serverTimestamp(),
        'lastActiveAt': FieldValue.serverTimestamp(),
      });
      tx.update(_room(roomId), {'participantCount': FieldValue.increment(1)});
    });
  }

  /// Refreshes the signed-in user's presence timestamp — called on
  /// [heartbeatInterval] by VoiceRoomDetailScreen while it's open. No-ops
  /// if [sessionId] no longer matches (a newer join has since claimed this
  /// doc — see [newSessionId]) rather than refreshing presence that isn't
  /// this screen's to refresh. Silent on any failure (offline blip, or the
  /// doc was swept out from under a truly-gone session) — the next tick,
  /// or a fresh [join], is what actually recovers presence, not retrying
  /// this write.
  static Future<void> heartbeat(String roomId, String sessionId) async {
    final uid = _uid;
    if (uid == null || roomId.isEmpty) return;
    try {
      final ref = _participants(roomId).doc(uid);
      final snap = await ref.get();
      if (!snap.exists || snap.data()?['sessionId'] != sessionId) return;
      await ref.update({'lastActiveAt': FieldValue.serverTimestamp()});
    } catch (e) {
      debugPrint('RoomParticipantService.heartbeat failed (non-fatal): $e');
    }
  }

  /// Removes anyone in [participants] whose last heartbeat is older than
  /// [staleAfter] — called from VoiceRoomDetailScreen every time the
  /// participants stream updates, so any client still in the room acts as
  /// a decentralized janitor (no server-side sweep exists). Each removal
  /// is a transaction that re-checks staleness server-side before deleting
  /// (firestore.rules enforces the same check independently), so multiple
  /// clients racing to sweep the same stale entry is harmless — only the
  /// first actually removes anything.
  static Future<void> sweepStaleParticipants(String roomId, List<RoomParticipant> participants) async {
    final now = DateTime.now();
    for (final p in participants) {
      final lastActive = p.lastActiveAt;
      if (lastActive == null || now.difference(lastActive) < staleAfter) continue;
      // ignore: discarded_futures
      _removeStaleParticipant(roomId, p.uid);
    }
  }

  static Future<void> _removeStaleParticipant(String roomId, String staleUid) async {
    final participantRef = _participants(roomId).doc(staleUid);
    try {
      await FirebaseFirestore.instance.runTransaction((tx) async {
        final snap = await tx.get(participantRef);
        if (!snap.exists) return; // already cleaned up by another client
        final lastActive = (snap.data()?['lastActiveAt'] as Timestamp?)?.toDate();
        if (lastActive == null || DateTime.now().difference(lastActive) < staleAfter) {
          return; // they sent a heartbeat since we decided to sweep them
        }
        tx.delete(participantRef);
        tx.update(_room(roomId), {'participantCount': FieldValue.increment(-1)});
      });
    } catch (e) {
      debugPrint('RoomParticipantService: stale sweep of $staleUid failed (non-fatal): $e');
    }
  }

  /// Removes the signed-in user's own presence — covers the back button,
  /// closing the tab, or the host ending the room (all tear down
  /// VoiceRoomDetailScreen's State, which calls this from dispose).
  ///
  /// Only deletes if [sessionId] still matches the doc's current
  /// `sessionId` (set by [join]/[heartbeat]) — if a newer mount already
  /// reclaimed this doc (rejoining faster than this fire-and-forget call
  /// arrives), that's not this session's doc to remove anymore, and doing
  /// so anyway would silently drop the newer session back to "not
  /// present". Transactional so it can't race a concurrent [join] either.
  static Future<void> leave(String roomId, String sessionId) async {
    final uid = _uid;
    if (uid == null || roomId.isEmpty) return;
    final participantRef = _participants(roomId).doc(uid);
    try {
      await FirebaseFirestore.instance.runTransaction((tx) async {
        final snap = await tx.get(participantRef);
        if (!snap.exists || snap.data()?['sessionId'] != sessionId) return;
        tx.delete(participantRef);
        tx.update(_room(roomId), {'participantCount': FieldValue.increment(-1)});
      });
    } catch (e) {
      // Best-effort: the room doc may already be gone (host just ended it)
      // or the connection may have dropped on the way out — never block
      // the screen from closing over cleanup.
      debugPrint('RoomParticipantService.leave failed (non-fatal): $e');
    }
  }

  /// Live roster, oldest join first. VoiceRoomDetailScreen partitions this
  /// into the speaker grid (anyone RoomParticipant.isSeated — host,
  /// moderator, or speaker) vs. the listener strip (everyone else) and
  /// always pins the host to the first seat, since re-joining your own room
  /// shouldn't bump you out of it.
  static Stream<List<RoomParticipant>> streamParticipants(String roomId) {
    if (roomId.isEmpty) return Stream.value(const []);
    return _participants(roomId)
        .orderBy('joinedAt')
        .snapshots()
        .map((snap) => snap.docs.map((d) => RoomParticipant.fromFirestore(d.id, d.data())).toList())
        .handleError((e) {
          debugPrint('RoomParticipantService.streamParticipants failed (showing no one): $e');
          return <RoomParticipant>[];
        });
  }

  /// Toggles the signed-in user's own mic. Only meaningful once they have a
  /// seat (host/speaker) — callers should steer a listener toward
  /// [setHandRaised] first rather than calling this.
  static Future<void> setMuted(String roomId, bool muted) async {
    final uid = _uid;
    if (uid == null || roomId.isEmpty) return;
    await _participants(roomId).doc(uid).update({'isMuted': muted});
  }

  /// True while there's still an open speaker seat — shared by every path
  /// that can seat someone ([acceptRaisedHand], [acceptStageInvite]) so
  /// they all enforce the exact same capacity, and so a host bulk-accepting
  /// several raised hands in one go (see the Raised Hands sheet) naturally
  /// stops once seats run out rather than over-seating the room.
  static Future<bool> _hasOpenSeat(String roomId) async {
    final seated = await _participants(
      roomId,
    ).where('role', whereIn: ['host', 'moderator', 'speaker']).get();
    return seated.docs.length < speakerSeats;
  }

  /// Self-write: raises or lowers the signed-in listener's own hand — "I'd
  /// like to be invited up to speak." Listed live for the host/moderator
  /// via [streamRaisedHands] (surfaced as the toolbar's Raised Hands badge
  /// — see VoiceRoomDetailScreen), who can [acceptRaisedHand] (seats them)
  /// or [declineRaisedHand] (dismisses the request, seat or no seat).
  /// Unlike the old instant self-seat this replaces, raising a hand never
  /// claims a seat by itself — the host/moderator always has to act on it,
  /// even when seats are open, matching this app's expected "someone in
  /// charge lets people up" flow (see the Raised Hands sheet's UI for
  /// where that check actually happens).
  static Future<void> setHandRaised(String roomId, bool raised) async {
    final uid = _uid;
    if (uid == null || roomId.isEmpty) return;
    await _participants(roomId).doc(uid).update({
      'handRaised': raised,
      if (raised) 'handRaisedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Host/moderator-only: accepts [uid]'s raised hand — seats them as a
  /// speaker (same capacity guard as [acceptStageInvite]) and clears the
  /// hand-raise flag in the same write. Throws a plain-text message the UI
  /// can show directly once every seat is taken, same as [acceptStageInvite].
  static Future<void> acceptRaisedHand({required String roomId, required String uid}) async {
    if (roomId.isEmpty || uid.isEmpty) return;
    if (!await _hasOpenSeat(roomId)) {
      throw Exception('No stage seats are available right now.');
    }
    await _participants(roomId).doc(uid).update({
      'role': 'speaker',
      'isMuted': true,
      'handRaised': false,
    });
  }

  /// Host/moderator-only: dismisses [uid]'s raised hand without seating
  /// them — the Raised Hands sheet's "✕" on a row.
  static Future<void> declineRaisedHand({required String roomId, required String uid}) async {
    if (roomId.isEmpty || uid.isEmpty) return;
    await _participants(roomId).doc(uid).update({'handRaised': false});
  }

  /// Live queue of everyone currently waiting with a raised hand, oldest
  /// request first — the host/moderator's Raised Hands sheet, and the
  /// count on its toolbar badge. Requires the `handRaised`/`handRaisedAt`
  /// composite index in firestore.indexes.json (same "equality filter +
  /// orderBy on a different field always needs one" rule every other
  /// composite index in this project exists for).
  static Stream<List<RoomParticipant>> streamRaisedHands(String roomId) {
    if (roomId.isEmpty) return Stream.value(const []);
    return _participants(roomId)
        .where('handRaised', isEqualTo: true)
        .orderBy('handRaisedAt')
        .snapshots()
        .map((snap) => snap.docs.map((d) => RoomParticipant.fromFirestore(d.id, d.data())).toList())
        .handleError((e) {
          debugPrint('RoomParticipantService.streamRaisedHands failed (showing none): $e');
          return <RoomParticipant>[];
        });
  }

  /// Host/moderator-only: mutes or unmutes ANOTHER participant — the
  /// counterpart to [setMuted], which only ever touches the caller's own
  /// mic. See room_profile_sheet.dart's "Mute"/"Unmute" action, available
  /// against a stage speaker or an audience member alike (muting someone
  /// who isn't seated yet just means they start muted if/when they join
  /// the stage). firestore.rules: the host may update any other
  /// participant's doc freely; a moderator's write here only ever touches
  /// `isMuted` (role is left untouched), which the existing "moderator may
  /// set someone else's role to listener/speaker" rule branch already
  /// covers — it checks the RESULTING role, which stays whatever the
  /// target already had, so it's satisfied as long as that's 'listener' or
  /// 'speaker' (i.e. the target isn't the host or another moderator).
  static Future<void> setParticipantMuted({
    required String roomId,
    required String uid,
    required bool muted,
  }) async {
    if (roomId.isEmpty || uid.isEmpty) return;
    await _participants(roomId).doc(uid).update({'isMuted': muted});
  }

  /// Host/moderator-only: fully evicts [uid] from the room — deletes their
  /// participant doc outright (unlike [removeFromStage], which only demotes
  /// them back to the audience but leaves them in the room), decrements
  /// participantCount, and bans them from rejoining THIS room for
  /// [banDuration] (see the bans/{uid} doc this writes and firestore.rules'
  /// isBanned() / participants/{uid} create rule, which is what actually
  /// blocks the rejoin — [join]'s own ban check is only a friendlier
  /// message layered in front of that same rejection). See
  /// room_profile_sheet.dart's "Kick Out" action.
  ///
  /// The kicked person's own screen reacts to their participant doc
  /// disappearing — see VoiceRoomDetailScreen's role-watch subscription,
  /// which pops them with a notice — this call itself doesn't (can't)
  /// reach into their client.
  ///
  /// All three writes go in one batch: the ban doc's own create rule reads
  /// the target's (pre-delete) participant role to enforce the same
  /// host/moderator-over-non-host-non-moderator hierarchy [setParticipantMuted]
  /// and the participants delete rule already respect — batched writes are
  /// evaluated against pre-commit state, so that read still sees the
  /// participant doc as it was before this same batch deletes it.
  static Future<void> kickParticipant({required String roomId, required String uid}) async {
    if (roomId.isEmpty || uid.isEmpty) return;
    final batch = FirebaseFirestore.instance.batch();
    batch.delete(_participants(roomId).doc(uid));
    batch.update(_room(roomId), {'participantCount': FieldValue.increment(-1)});
    batch.set(_bans(roomId).doc(uid), {
      'bannedAt': FieldValue.serverTimestamp(),
      'bannedBy': _uid,
    });
    await batch.commit();
  }

  /// Host/moderator-only: invites [uid] — currently just listening in the
  /// audience — straight onto the stage as a speaker, without them having
  /// raised a hand first. See room_profile_sheet.dart's "Invite" button on
  /// an audience member's profile, and [acceptRaisedHand] for the other way
  /// someone ends up seated this same way (via the Raised Hands sheet).
  /// Muted by default, same as any other fresh seat. firestore.rules mirrors this:
  /// the host may set anyone's role freely, and a live moderator may set
  /// someone else's role to 'listener' (removeFromStage) or 'speaker'
  /// (this) but nothing else.
  /// Host/moderator-only: sends [uid] an invitation to join the stage — the
  /// mirror image of [setHandRaised]: there, the audience asks the host;
  /// here, the host asks the audience. Sets `stageInvitePending: true` on
  /// the invitee's own doc, shown to them via VoiceRoomDetailScreen's
  /// Accept/Ignore dialog (same pattern, and the same firestore.rules
  /// reasoning, as the existing moderator-invite flow —
  /// sendModeratorInvite/streamModeratorInvitePending — a host/moderator
  /// writing a flag onto someone else's participant doc is already
  /// unrestricted for the host, and for a moderator doesn't touch `role`
  /// at all so it's already covered by the existing self-untouched-role
  /// carve-out). See room_profile_sheet.dart's "Invite" button, which
  /// shows "Waiting" for as long as this stays true.
  static Future<void> sendStageInvite({required String roomId, required String uid}) async {
    if (roomId.isEmpty || uid.isEmpty) return;
    await _participants(roomId).doc(uid).update({'stageInvitePending': true});
  }

  /// Self-write: accepts a pending stage invite — seats the caller (same
  /// capacity guard as [acceptRaisedHand]) and clears the flag in the same
  /// write. Self-promoting to 'speaker' has always
  /// been unconditionally allowed by firestore.rules (see [setHandRaised]'s
  /// doc comment — the same rule branch requestToSpeak used to rely on), so
  /// this needs no special rules carve-out the way accepting a *moderator*
  /// invite did.
  static Future<void> acceptStageInvite(String roomId) async {
    final uid = _uid;
    if (uid == null || roomId.isEmpty) return;
    if (!await _hasOpenSeat(roomId)) {
      throw Exception('No stage seats are available right now.');
    }
    await _participants(roomId).doc(uid).update({
      'role': 'speaker',
      'isMuted': true,
      'stageInvitePending': false,
    });
  }

  /// Self-write: declines a pending stage invite without joining — lets the
  /// host/moderator see the button revert from "Waiting" back to "Invite"
  /// and try again later if they want to.
  static Future<void> declineStageInvite(String roomId) async {
    final uid = _uid;
    if (uid == null || roomId.isEmpty) return;
    await _participants(roomId).doc(uid).update({'stageInvitePending': false});
  }

  /// Streams [true] while [uid] has a pending stage invite for [roomId] —
  /// the invitee's own Accept/Ignore dialog trigger, and the "Invite" ->
  /// "Waiting" button state on their profile. `.distinct()` for the same
  /// reason [streamModeratorInvitePending] has it: this doc changes for
  /// plenty of reasons unrelated to this one flag (heartbeat, mic toggles,
  /// acceptStageInvite's own role/isMuted write before it gets to clearing
  /// this), and re-emitting an unchanged value on every one of those could
  /// pop the Accept/Ignore dialog right back open after it was just
  /// dismissed.
  static Stream<bool> streamStageInvitePending(String roomId, String uid) {
    if (roomId.isEmpty || uid.isEmpty) return Stream.value(false);
    return _participants(roomId)
        .doc(uid)
        .snapshots()
        .map((s) => s.exists && s.data()?['stageInvitePending'] == true)
        .distinct()
        .handleError((e) {
          debugPrint('RoomParticipantService.streamStageInvitePending error (non-fatal): $e');
          return false;
        });
  }

  /// Host/moderator-only: moves [uid] back to the audience. firestore.rules
  /// also enforces that only the room's host or a live moderator can do
  /// this. If the removed participant was the room's designated moderator,
  /// the room-level moderatorUid is also cleared so they don't get the role
  /// restored on a future rejoin.
  static Future<void> removeFromStage({required String roomId, required String uid}) async {
    if (roomId.isEmpty || uid.isEmpty) return;
    // Update the participant doc first.
    await _participants(roomId).doc(uid).update({'role': 'listener', 'isMuted': true});
    // Clear the room-level moderator record if it points at the removed user,
    // so a rejoin won't silently restore their moderator powers.
    try {
      final roomSnap = await _room(roomId).get();
      final storedMod = roomSnap.data()?['moderatorUid']?.toString();
      if (storedMod == uid) {
        await VoiceRoomService.clearModerator(roomId);
      }
    } catch (e) {
      debugPrint('RoomParticipantService.removeFromStage: could not clear moderatorUid (non-fatal): $e');
    }
  }

  /// Host-only: promotes a current stage participant to moderator — see
  /// VoiceRoomDetailScreen's Leave flow, the only place this is called from
  /// (moderator assignment is scoped to "before the host leaves", not a
  /// general anytime action). firestore.rules restricts this write to the
  /// room's host.
  ///
  /// Also persists the assignment on the room doc via
  /// [VoiceRoomService.setModerator] so the role is restored if the moderator
  /// leaves and rejoins — see [join]'s doc comment for the full flow.
  static Future<void> promoteToModerator({required String roomId, required String uid}) async {
    if (roomId.isEmpty || uid.isEmpty) return;
    // Write the participant doc role first — this is the live, immediately-
    // visible change (everyone streaming participants sees it instantly).
    await _participants(roomId).doc(uid).update({'role': 'moderator'});
    // Persist on the room doc so rejoin can restore the role even after
    // the participant doc is deleted by [leave]. Best-effort: if this write
    // fails the moderator still works for this session; they'll just lose
    // the role on rejoin.
    try {
      await VoiceRoomService.setModerator(roomId, uid);
    } catch (e) {
      debugPrint('RoomParticipantService.promoteToModerator: could not persist moderatorUid (non-fatal): $e');
    }
    // Clear the invite-pending flag from the participant doc so the invitee
    // no longer sees the Accept/Ignore dialog after their role is already set.
    await clearModeratorInvitePending(roomId, uid);
  }

  /// Host-only: sends a moderator invitation to [uid] by setting
  /// `moderatorInvitePending: true` on the invitee's own participant doc.
  ///
  /// Why participant doc instead of a subcollection:
  /// The host can already update any participant doc (host branch of the
  /// participants update rule), and the invitee can self-write their own
  /// doc (clearing the flag on Ignore). No new Firestore rules are needed.
  ///
  /// The actual role + moderatorUid are only written when the user Accepts
  /// (via [promoteToModerator]), keeping the invite entirely opt-in.
  static Future<void> sendModeratorInvite({required String roomId, required String uid}) async {
    if (roomId.isEmpty || uid.isEmpty) return;
    await _participants(roomId).doc(uid).update({'moderatorInvitePending': true});
  }

  /// Streams [true] when [uid]'s participant doc has `moderatorInvitePending == true`
  /// for [roomId] — used by VoiceRoomDetailScreen to show the Accept/Ignore
  /// dialog to the invitee in real time.
  ///
  /// `.distinct()` matters here, not just tidiness: the underlying doc
  /// changes for plenty of reasons that have nothing to do with this flag —
  /// [heartbeat] every 25s while the invitee is in the room, and Accept's
  /// own [promoteToModerator] writing `role` before it gets around to
  /// clearing this flag — and `.snapshots().map(...)` re-emits on every one
  /// of those regardless of whether the mapped boolean actually changed.
  /// Without dedup, one of those redundant "still true" echoes landing
  /// after Accept had already popped the dialog (but before the flag was
  /// actually cleared) would pop this exact dialog right back open,
  /// needing a second tap to close it for good.
  static Stream<bool> streamModeratorInvitePending(String roomId, String uid) {
    if (roomId.isEmpty || uid.isEmpty) return Stream.value(false);
    return _participants(roomId)
        .doc(uid)
        .snapshots()
        .map((s) => s.exists && s.data()?['moderatorInvitePending'] == true)
        .distinct()
        .handleError((e) {
      debugPrint('RoomParticipantService.streamModeratorInvitePending error (non-fatal): $e');
      return false;
    });
  }

  /// Removes the `moderatorInvitePending` flag from the participant doc.
  /// Called when the invitee taps Ignore (self-write) or after Accept
  /// (via [promoteToModerator]). Silently no-ops if the doc or field is absent.
  static Future<void> clearModeratorInvitePending(String roomId, String uid) async {
    if (roomId.isEmpty || uid.isEmpty) return;
    try {
      await _participants(roomId).doc(uid).update({'moderatorInvitePending': FieldValue.delete()});
    } catch (e) {
      debugPrint('RoomParticipantService.clearModeratorInvitePending error (non-fatal): $e');
    }
  }

  /// Host-only: demotes an assigned moderator back to a regular speaker on stage.
  /// Reverts their participant role to 'speaker' and clears the room-level
  /// moderatorUid record so they no longer have moderator powers now or on rejoin.
  static Future<void> demoteModeratorToSpeaker({required String roomId, required String uid}) async {
    if (roomId.isEmpty || uid.isEmpty) return;
    await _participants(roomId).doc(uid).update({'role': 'speaker'});
    try {
      final roomSnap = await _room(roomId).get();
      final storedMod = roomSnap.data()?['moderatorUid']?.toString();
      if (storedMod == uid) {
        await VoiceRoomService.clearModerator(roomId);
      }
    } catch (e) {
      debugPrint('RoomParticipantService.demoteModeratorToSpeaker: could not clear moderatorUid (non-fatal): $e');
    }
  }

  /// Chat is stage-only (host/moderator/speaker) — firestore.rules is the
  /// real enforcement, but checking here first avoids attempting a write
  /// the UI already shouldn't have offered (the composer disables itself
  /// for a non-seated caller).
  static Future<void> sendComment({required String roomId, required String text}) async {
    final uid = _uid;
    final user = AuthService.instance.currentUser;
    final trimmed = text.trim();
    if (uid == null || user == null || roomId.isEmpty || trimmed.isEmpty) return;

    final me = await _participants(roomId).doc(uid).get();
    final role = me.data()?['role']?.toString() ?? 'listener';
    if (!['host', 'moderator', 'speaker'].contains(role)) {
      throw Exception('Only stage participants can chat — raise your hand to join the stage.');
    }

    await _comments(roomId).add({
      'senderId': uid,
      'senderName': user.name,
      'text': trimmed,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  /// Live comment feed for a room, oldest-first (so new comments always append
  /// at the bottom of the UI list). [limit] caps how many docs are returned at
  /// once — `limitToLast` gives us the most-recent [limit] entries in
  /// ascending order, which is exactly what a chat-style feed needs: you see
  /// the last N messages in chronological order, not in reverse.
  ///
  /// Renamed from `streamRecentComments` (which used `limit(1)` + descending
  /// order) to make the corrected semantics clear at every call-site.
  static Stream<List<BoardComment>> streamComments(String roomId, {int limit = 100}) {
    if (roomId.isEmpty) return Stream.value(const []);
    return _comments(roomId)
        .orderBy('createdAt')
        .limitToLast(limit)
        .snapshots()
        .map(
          (snap) => snap.docs
              .map(
                (d) => BoardComment(
                  senderId: d.data()['senderId']?.toString() ?? '',
                  sender: d.data()['senderName']?.toString() ?? 'Someone',
                  text: d.data()['text']?.toString() ?? '',
                ),
              )
              .toList(),
        )
        .handleError((e) {
          debugPrint('RoomParticipantService.streamComments failed (showing none): $e');
          return <BoardComment>[];
        });
  }

  /// Writes one live caption line for the signed-in user — same shape and
  /// same "must actually be on stage" restriction as [sendComment], since a
  /// caption only ever comes from whoever is currently speaking. No caller
  /// exists yet (there's no speech-to-text/translation pipeline wired up),
  /// but this is the exact write path one will call once it exists: feed it
  /// the already-English-translated text for each recognized utterance and
  /// every client in the room picks it up via [streamSubtitles], no other
  /// change required.
  static Future<void> addSubtitleLine({required String roomId, required String text}) async {
    final uid = _uid;
    final user = AuthService.instance.currentUser;
    final trimmed = text.trim();
    if (uid == null || user == null || roomId.isEmpty || trimmed.isEmpty) return;

    final me = await _participants(roomId).doc(uid).get();
    final role = me.data()?['role']?.toString() ?? 'listener';
    if (!['host', 'moderator', 'speaker'].contains(role)) {
      throw Exception('Only stage participants can generate captions.');
    }

    await _subtitles(roomId).add({
      'senderId': uid,
      'senderName': user.name,
      'text': trimmed,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  /// Live caption feed for a room, oldest-first — same pagination semantics
  /// as [streamComments]. Backs VoiceRoomDetailScreen's captions panel.
  static Stream<List<SubtitleLine>> streamSubtitles(String roomId, {int limit = 50}) {
    if (roomId.isEmpty) return Stream.value(const []);
    return _subtitles(roomId)
        .orderBy('createdAt')
        .limitToLast(limit)
        .snapshots()
        .map(
          (snap) => snap.docs
              .map(
                (d) => SubtitleLine(
                  speakerId: d.data()['senderId']?.toString() ?? '',
                  speakerName: d.data()['senderName']?.toString() ?? 'Someone',
                  text: d.data()['text']?.toString() ?? '',
                ),
              )
              .toList(),
        )
        .handleError((e) {
          debugPrint('RoomParticipantService.streamSubtitles failed (showing none): $e');
          return <SubtitleLine>[];
        });
  }
}
