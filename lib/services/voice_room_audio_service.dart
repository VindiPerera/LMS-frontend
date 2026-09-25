import 'dart:async';

import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';

import 'room_participant_service.dart';
import 'voice_room_token_service.dart';

enum VoiceAudioStatus { idle, connecting, connected, failed }

/// Live audio for the ONE voice room the signed-in user is currently in
/// (open, or minimized into the mini window) — a thin Agora layer under the
/// existing Firestore presence model, not a replacement for it.
///
/// Design: Firestore's `voiceRooms/{roomId}/participants/{myUid}` doc is
/// already the single source of truth for everything that decides what this
/// user's audio should be doing — its `role` (seat), `isMuted` (mic
/// button, host/moderator mute), and its existence (kicked/left/swept). So
/// this service watches that one doc and DERIVES the Agora state from it,
/// rather than every existing action (raise hand, accept invite, promote,
/// demote, kick, mute...) having to remember to also call into audio:
///
///   seated (host/moderator/speaker)  -> Agora broadcaster (publishes)
///   anyone else                      -> Agora audience (listen only)
///   isMuted (or no mic permission)   -> mic capture off entirely
///   doc gone                         -> muted immediately, channel left
///                                       after a short grace period
///
/// Because it owns its own subscription, audio keeps following role/mute
/// changes while the room is minimized (VoiceRoomDetailScreen disposed).
///
/// What "seated" means for the token is decided SERVER-SIDE (see
/// VoiceRoomTokenService) — the client only reflects it. Listeners are
/// never asked for microphone permission; that prompt only appears the
/// first time someone is seated and unmuted.
///
/// Scope: Android/iOS only, foreground audio only (no background service
/// yet). On web/desktop every method is a no-op and the room behaves exactly
/// as it did before live audio existed.
class VoiceRoomAudioService extends ChangeNotifier {
  VoiceRoomAudioService._();
  static final VoiceRoomAudioService instance = VoiceRoomAudioService._();

  static const _seatedRoles = {'host', 'moderator', 'speaker'};
  static const _missingDocGrace = Duration(seconds: 15);
  static const _connectRetryDelays = [Duration(seconds: 2), Duration(seconds: 5), Duration(seconds: 10)];

  bool get _supported =>
      !kIsWeb && (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS);

  RtcEngine? _engine;
  String? _engineAppId;
  String? _roomId;

  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _participantSub;
  Timer? _missingDocTimer;

  // Bumped on every join/leave — any async step that resumes under a
  // different value than it started with belongs to a session that has
  // since ended and must stop touching state.
  int _gen = 0;

  // Desired state, straight from the participant doc.
  bool _wantPublisher = false;
  bool _wantMuted = true;

  // Actual state.
  bool _joined = false;
  bool _holdsPublisherToken = false;
  bool _applying = false;
  bool _dirty = false;
  bool _micDeniedNotified = false;
  VoiceAudioStatus _status = VoiceAudioStatus.idle;

  final StreamController<String> _errors = StreamController<String>.broadcast();

  /// Human-readable, user-facing problems (mic permission, server down...) —
  /// VoiceRoomDetailScreen shows these as snackbars.
  Stream<String> get errors => _errors.stream;

  VoiceAudioStatus get status => _status;
  String? get activeRoomId => _roomId;

  /// Starts live audio for [roomId]. Call only AFTER
  /// RoomParticipantService.join has completed — the server refuses a token
  /// to anyone without a participant doc. Idempotent for a room already
  /// connecting/connected (e.g. reopening a minimized room); switching rooms
  /// leaves the previous one first.
  Future<void> join(String roomId) async {
    if (!_supported || roomId.isEmpty) return;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    if (_roomId == roomId && (_status == VoiceAudioStatus.connecting || _status == VoiceAudioStatus.connected)) {
      return;
    }
    if (_roomId != null) await leave();

    final gen = ++_gen;
    _roomId = roomId;
    _wantPublisher = false;
    _wantMuted = true;
    _setStatus(VoiceAudioStatus.connecting);

    _participantSub = FirebaseFirestore.instance
        .collection('voiceRooms')
        .doc(roomId)
        .collection('participants')
        .doc(uid)
        .snapshots()
        .listen(_onParticipantSnapshot, onError: (Object e) {
      debugPrint('VoiceRoomAudioService: participant watch error (non-fatal): $e');
    });

    try {
      await _connectWithRetry(roomId, gen);
    } catch (e) {
      if (gen != _gen) return;
      debugPrint('VoiceRoomAudioService.join($roomId) failed: $e');
      _setStatus(VoiceAudioStatus.failed);
      _errors.add(e is VoiceRoomTokenException ? e.message : 'Could not start live audio.');
    }
  }

  /// Stops audio and releases the microphone. Safe to call when idle.
  Future<void> leave() async {
    _gen++;
    _dirty = false;
    _missingDocTimer?.cancel();
    _missingDocTimer = null;
    final sub = _participantSub;
    _participantSub = null;
    final engine = _engine;
    _engine = null;
    _engineAppId = null;
    _roomId = null;
    _joined = false;
    _holdsPublisherToken = false;
    _wantPublisher = false;
    _wantMuted = true;
    _micDeniedNotified = false;
    _setStatus(VoiceAudioStatus.idle);

    await sub?.cancel();
    if (engine != null) {
      try {
        await engine.leaveChannel();
      } catch (e) {
        debugPrint('VoiceRoomAudioService.leave: leaveChannel failed (non-fatal): $e');
      }
      try {
        await engine.release();
      } catch (e) {
        debugPrint('VoiceRoomAudioService.leave: release failed (non-fatal): $e');
      }
    }
  }

  Future<void> _connectWithRetry(String roomId, int gen) async {
    for (var attempt = 0;; attempt++) {
      try {
        await _connect(roomId, gen);
        return;
      } on VoiceRoomTokenException catch (e) {
        // 4xx = the server refused (not in room, room ended, signed out) —
        // retrying can't change that. Network trouble / 5xx can heal.
        final permanent = e.statusCode != null && e.statusCode! < 500;
        if (permanent || attempt >= _connectRetryDelays.length) rethrow;
      }
      await Future<void>.delayed(_connectRetryDelays[attempt]);
      if (gen != _gen) return;
    }
  }

  Future<void> _connect(String roomId, int gen) async {
    final rtc = await VoiceRoomTokenService.fetch(roomId);
    if (gen != _gen) return;

    final engine = await _ensureEngine(rtc.appId);
    if (gen != _gen) return;

    _holdsPublisherToken = rtc.isPublisher;
    await engine.joinChannel(
      token: rtc.token,
      channelId: rtc.channel,
      uid: rtc.uid,
      options: ChannelMediaOptions(
        channelProfile: ChannelProfileType.channelProfileLiveBroadcasting,
        clientRoleType: rtc.isPublisher ? ClientRoleType.clientRoleBroadcaster : ClientRoleType.clientRoleAudience,
        // Mic goes live only via _applyOnce, once joined and permitted.
        publishMicrophoneTrack: false,
        autoSubscribeAudio: true,
        autoSubscribeVideo: false,
      ),
    );
  }

  Future<RtcEngine> _ensureEngine(String appId) async {
    final existing = _engine;
    if (existing != null && _engineAppId == appId) return existing;
    if (existing != null) {
      await existing.release();
      _engine = null;
    }

    final engine = createAgoraRtcEngine();
    await engine.initialize(
      RtcEngineContext(appId: appId, channelProfile: ChannelProfileType.channelProfileLiveBroadcasting),
    );
    engine.registerEventHandler(
      RtcEngineEventHandler(
        onJoinChannelSuccess: (connection, elapsed) {
          if (_engine != engine) return;
          _joined = true;
          _setStatus(VoiceAudioStatus.connected);
          _scheduleApply();
        },
        onLeaveChannel: (connection, stats) {
          if (_engine == engine) _joined = false;
        },
        onConnectionStateChanged: (connection, state, reason) {
          if (_engine != engine) return;
          if (state == ConnectionStateType.connectionStateConnected) {
            _setStatus(VoiceAudioStatus.connected);
          } else if (state == ConnectionStateType.connectionStateReconnecting ||
              state == ConnectionStateType.connectionStateConnecting) {
            _setStatus(VoiceAudioStatus.connecting);
          } else if (state == ConnectionStateType.connectionStateFailed) {
            _setStatus(VoiceAudioStatus.failed);
            _errors.add('Lost connection to live audio.');
          }
        },
        onTokenPrivilegeWillExpire: (connection, token) => _renewToken(engine),
        onError: (err, msg) => debugPrint('VoiceRoomAudioService: Agora error $err: $msg'),
      ),
    );
    await engine.enableAudio();
    _engine = engine;
    _engineAppId = appId;
    return engine;
  }

  Future<void> _renewToken(RtcEngine engine) async {
    final roomId = _roomId;
    if (roomId == null) return;
    final gen = _gen;
    try {
      final rtc = await VoiceRoomTokenService.fetch(roomId);
      if (gen != _gen || _engine != engine) return;
      _holdsPublisherToken = rtc.isPublisher;
      await engine.renewToken(rtc.token);
    } catch (e) {
      debugPrint('VoiceRoomAudioService: token renewal failed: $e');
    }
  }

  void _onParticipantSnapshot(DocumentSnapshot<Map<String, dynamic>> snap) {
    if (!snap.exists) {
      // Kicked, left elsewhere, or swept — stop publishing right away, and
      // only tear the channel down if the doc stays gone (a heartbeat/sweep
      // race can make it flicker for a moment).
      _wantPublisher = false;
      _wantMuted = true;
      _scheduleApply();
      _missingDocTimer ??= Timer(_missingDocGrace, () {
        _missingDocTimer = null;
        leave();
      });
      return;
    }

    _missingDocTimer?.cancel();
    _missingDocTimer = null;
    final data = snap.data() ?? const <String, dynamic>{};
    _wantPublisher = _seatedRoles.contains(data['role']?.toString() ?? 'listener');
    _wantMuted = data['isMuted'] != false;
    _scheduleApply();
  }

  void _scheduleApply() {
    if (!_joined) return;
    _dirty = true;
    if (!_applying) _drain();
  }

  // Snapshots can arrive faster than an apply (token fetch + engine calls)
  // finishes — serialize them, always converging on the LATEST desired state.
  Future<void> _drain() async {
    _applying = true;
    final gen = _gen;
    try {
      while (_dirty && gen == _gen) {
        _dirty = false;
        await _applyOnce(gen);
      }
    } catch (e) {
      debugPrint('VoiceRoomAudioService: apply failed (non-fatal): $e');
    } finally {
      _applying = false;
    }
  }

  Future<void> _applyOnce(int gen) async {
    final engine = _engine;
    final roomId = _roomId;
    if (engine == null || roomId == null) return;

    final wantPublisher = _wantPublisher;
    final muted = _wantMuted;

    // Seat gained/lost -> the token's publish privilege must change too.
    if (wantPublisher != _holdsPublisherToken) {
      final rtc = await VoiceRoomTokenService.fetch(roomId);
      if (gen != _gen) return;
      await engine.renewToken(rtc.token);
      _holdsPublisherToken = rtc.isPublisher;
    }

    final publisher = wantPublisher && _holdsPublisherToken;
    var micLive = publisher && !muted;
    if (micLive && !await _ensureMicPermission()) {
      micLive = false;
      // The doc says "unmuted" but nothing is being sent — flip it back so
      // everyone's speaking indicator tells the truth.
      RoomParticipantService.setMuted(roomId, true).catchError((_) {});
    }
    if (gen != _gen) return;

    await engine.updateChannelMediaOptions(
      ChannelMediaOptions(
        clientRoleType: publisher ? ClientRoleType.clientRoleBroadcaster : ClientRoleType.clientRoleAudience,
        publishMicrophoneTrack: micLive,
        autoSubscribeAudio: true,
      ),
    );
    // Capture hardware fully off whenever nothing is being published, so
    // the OS "microphone in use" indicator is only ever on when it's true.
    await engine.enableLocalAudio(micLive);
  }

  Future<bool> _ensureMicPermission() async {
    var status = await Permission.microphone.status;
    if (!status.isGranted) status = await Permission.microphone.request();
    if (status.isGranted) {
      _micDeniedNotified = false;
      return true;
    }
    if (!_micDeniedNotified) {
      _micDeniedNotified = true;
      _errors.add(
        status.isPermanentlyDenied
            ? 'Microphone access is blocked. Enable it in Settings to speak.'
            : 'Microphone permission is needed to speak.',
      );
    }
    return false;
  }

  void _setStatus(VoiceAudioStatus status) {
    if (_status == status) return;
    _status = status;
    notifyListeners();
  }
}
