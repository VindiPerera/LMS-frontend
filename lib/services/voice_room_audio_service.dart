import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart' as fgt;
import 'package:http/http.dart' as http;
import 'package:livekit_client/livekit_client.dart';

import '../config/api_config.dart';

/// Live voice for a voice room, carried over LiveKit. Firestore keeps owning
/// *who is in the room and what role/mute state they have*
/// (RoomParticipantService); this only moves the audio.
///
/// Singleton, like VoiceRoomSessionController, because the audio has to
/// outlive VoiceRoomDetailScreen while the room is minimized: the screen
/// calls [connect] on join and [disconnect] on leave, and skips the latter
/// when it hands off to the minimized window.
///
/// Once connected, this service drives itself from the signed-in user's own
/// `voiceRooms/{roomId}/participants/{uid}` doc rather than being told what
/// to do by the screen:
///  - seated (host/moderator/speaker) and `isMuted == false` -> mic on;
///    otherwise mic off. A moderator muting someone (RoomParticipantService.
///    setParticipantMuted) therefore cuts their audio even if their screen
///    is minimized.
///  - gaining or losing a seat changes what the server lets the token do
///    (see hello-backend's VoiceRoomController), so the connection is
///    re-established with a fresh token.
class VoiceRoomAudioService extends ChangeNotifier {
  VoiceRoomAudioService._();
  static final VoiceRoomAudioService instance = VoiceRoomAudioService._();

  static const _seatedRoles = {'host', 'moderator', 'speaker'};

  Room? _room;
  String? _roomId;
  bool _canPublish = false;
  bool _wantMic = false;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _selfSub;
  EventsListener<RoomEvent>? _events;

  // Serializes connect / reconnect / mic changes so a burst of Firestore
  // snapshots can't interleave two connection attempts.
  Future<void> _queue = Future.value();

  Set<String> _speakingUids = const {};
  String? _error;

  // Auto-reconnect. A connection LiveKit couldn't resume on its own (network
  // drop, Wi-Fi <-> mobile data switch, server restart) used to stay dead
  // for the rest of the room — and since [connect] is idempotent per room,
  // even reopening the screen couldn't revive it. Now a lost connection is
  // re-established with a fresh token, backing off up to [_maxRetryDelay].
  static const _maxRetryDelay = Duration(seconds: 15);
  Timer? _retryTimer;
  int _retryAttempt = 0;
  bool _reconnecting = false;
  // Set when the server says this user may not have voice here at all (room
  // ended, removed/banned) — retrying can't help, so stop.
  bool _tokenRefused = false;

  String? get roomId => _roomId;
  bool get isConnected => _room?.connectionState == ConnectionState.connected;

  /// True while voice dropped and is being re-established — for a
  /// "Reconnecting…" hint.
  bool get isReconnecting => _reconnecting;

  /// uids LiveKit currently hears talking — for a speaking indicator.
  Set<String> get speakingUids => _speakingUids;

  /// Human-readable reason voice isn't working, or null.
  String? get error => _error;

  bool _needsAudioUnlock = false;

  /// True when the browser's autoplay policy is blocking remote voices (web
  /// only — Chrome won't play audio until the user taps something). The
  /// screen offers a button that calls [unlockAudio] from that tap.
  bool get needsAudioUnlock => _needsAudioUnlock;

  /// Must be called from a user gesture (a tap) to satisfy the browser.
  Future<void> unlockAudio() async {
    final room = _room;
    if (room == null) return;
    try {
      await room.startAudio();
    } catch (e) {
      debugPrint('VoiceRoomAudioService: startAudio failed: $e');
    }
    _needsAudioUnlock = !room.canPlaybackAudio;
    notifyListeners();
  }

  /// Joins [roomId]'s audio session. Call after RoomParticipantService.join
  /// has landed (the server refuses a token for someone with no participant
  /// doc). Never throws — failures land in [error]. Idempotent for the room
  /// already connected, which is what reopening a minimized room hits.
  Future<void> connect(String roomId) {
    if (roomId.isEmpty) return Future.value();
    if (_roomId == roomId) return _queue;
    return _enqueue(() async {
      await _teardown();
      _roomId = roomId;
      _watchSelf(roomId);
      await _startKeepAlive();
      await _connectRoom(roomId);
    });
  }

  /// Leaves [roomId]'s audio session — a no-op if the service has meanwhile
  /// moved on to a different room. Scoped (and checked inside the queue, not
  /// at call time) because the caller is often a room that is going away
  /// *after* the user already entered the next one: a minimized room ending
  /// in the background, or the previous VoiceRoomDetailScreen disposing only
  /// once its route transition finishes. Unscoped, that late cleanup tore
  /// down the new room's connection, leaving it silent.
  Future<void> disconnect(String roomId) => _enqueue(() async {
        if (_roomId != roomId) return;
        await _teardown();
      });

  Future<void> _enqueue(Future<void> Function() task) {
    final next = _queue.then((_) => task()).catchError((Object e) {
      debugPrint('VoiceRoomAudioService: $e');
    });
    _queue = next;
    return next;
  }

  Future<void> _teardown() async {
    _retryTimer?.cancel();
    _retryTimer = null;
    _retryAttempt = 0;
    _reconnecting = false;
    _tokenRefused = false;
    await _stopKeepAlive();
    await _selfSub?.cancel();
    _selfSub = null;
    await _events?.dispose();
    _events = null;
    final room = _room;
    _room = null;
    _roomId = null;
    _canPublish = false;
    _wantMic = false;
    _error = null;
    _needsAudioUnlock = false;
    _speakingUids = const {};
    if (room != null) {
      try {
        await room.disconnect();
      } catch (_) {}
      await room.dispose();
    }
    notifyListeners();
  }

  void _watchSelf(String roomId) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    _selfSub = FirebaseFirestore.instance
        .collection('voiceRooms')
        .doc(roomId)
        .collection('participants')
        .doc(uid)
        .snapshots()
        .listen((snap) {
      final data = snap.data();
      if (data == null) return; // kicked/left — the screen handles that
      final seated = _seatedRoles.contains(data['role']);
      // Same default as RoomParticipant.fromFirestore: absent means muted.
      final wantMic = seated && data['isMuted'] == false;
      _enqueue(() => _apply(roomId, seated: seated, wantMic: wantMic));
    }, onError: (Object e) => debugPrint('VoiceRoomAudioService self-watch: $e'));
  }

  Future<void> _apply(String roomId, {required bool seated, required bool wantMic}) async {
    if (_roomId != roomId) return; // torn down or switched rooms meanwhile
    _wantMic = wantMic;
    if (seated != _canPublish) {
      // Promotion/demotion: the token's publish grant is now wrong.
      await _connectRoom(roomId);
      return;
    }
    await _syncMic();
  }

  Future<void> _syncMic() async {
    final room = _room;
    if (room == null || room.connectionState != ConnectionState.connected) return;
    final enable = _wantMic && _canPublish;
    try {
      await room.localParticipant?.setMicrophoneEnabled(enable);
      if (_error != null) {
        _error = null;
        notifyListeners();
      }
    } catch (e) {
      // Most commonly the user denied the microphone permission.
      debugPrint('VoiceRoomAudioService: mic toggle failed: $e');
      _error = 'Could not use the microphone. Check the app\'s mic permission.';
      notifyListeners();
    }
  }

  /// (Re)establishes the LiveKit connection with a fresh server-issued token.
  Future<void> _connectRoom(String roomId) async {
    final old = _room;
    _room = null;
    await _events?.dispose();
    _events = null;
    if (old != null) {
      try {
        await old.disconnect();
      } catch (_) {}
      await old.dispose();
    }

    final grant = await _fetchToken(roomId);
    if (_roomId != roomId) return;
    if (grant == null) {
      // Network error / server hiccup -> try again shortly. A refusal (room
      // ended, removed from the room) is final; the screen handles leaving.
      if (!_tokenRefused) _scheduleReconnect(roomId);
      return;
    }

    final room = Room(
      roomOptions: const RoomOptions(
        adaptiveStream: false,
        dynacast: false,
        defaultAudioPublishOptions: AudioPublishOptions(dtx: true),
      ),
    );
    try {
      await room.connect(grant.url, grant.token);
    } catch (e) {
      debugPrint('VoiceRoomAudioService: connect failed: $e');
      await room.dispose();
      _error = 'Could not connect to voice.';
      notifyListeners();
      _scheduleReconnect(roomId);
      return;
    }
    if (_roomId != roomId) {
      await room.disconnect();
      await room.dispose();
      return;
    }

    _room = room;
    _canPublish = grant.canPublish;
    _error = null;
    _reconnecting = false;
    _retryAttempt = 0;
    // A seat change can reconnect while a retry is still pending — that
    // retry is now redundant.
    _retryTimer?.cancel();
    _retryTimer = null;
    _events = room.createListener()
      ..on<ActiveSpeakersChangedEvent>((e) {
        _speakingUids = {for (final p in e.speakers) p.identity};
        notifyListeners();
      })
      // LiveKit's own quick resume attempts — surface them as
      // "Reconnecting…" too.
      ..on<RoomReconnectingEvent>((_) {
        _reconnecting = true;
        notifyListeners();
      })
      ..on<RoomReconnectedEvent>((_) {
        _reconnecting = false;
        notifyListeners();
      })
      ..on<RoomDisconnectedEvent>((e) {
        _speakingUids = const {};
        // Only react if this is still the live connection — _connectRoom /
        // _teardown dispose the listener before disconnecting on purpose,
        // but be defensive about late events from a replaced Room.
        if (!identical(_room, room) || _roomId != roomId) {
          notifyListeners();
          return;
        }
        switch (e.reason) {
          // Deliberate ends — reconnecting would be wrong: we left, the
          // room was closed, a moderator removed us, or this account
          // joined from another device (retrying would ping-pong with it).
          case DisconnectReason.clientInitiated:
          case DisconnectReason.roomDeleted:
          case DisconnectReason.participantRemoved:
          case DisconnectReason.duplicateIdentity:
            notifyListeners();
          // Everything else (network loss, server restart, failed resume…)
          // — get a fresh token and rejoin.
          default:
            _reconnecting = true;
            notifyListeners();
            _scheduleReconnect(roomId);
        }
      })
      ..on<AudioPlaybackStatusChanged>((_) {
        _needsAudioUnlock = !room.canPlaybackAudio;
        notifyListeners();
      });
    _needsAudioUnlock = !room.canPlaybackAudio;
    notifyListeners();
    await _syncMic();
  }

  /// Queues a fresh-token rejoin of [roomId] after a backoff of 1, 2, 4, 8,
  /// then 15s (repeating) — runs for as long as the user stays in the room,
  /// so voice comes back by itself once the network does. Cancelled by
  /// [_teardown] (leave / switch rooms).
  void _scheduleReconnect(String roomId) {
    if (_roomId != roomId || _retryTimer != null) return;
    _reconnecting = true;
    final seconds = 1 << _retryAttempt.clamp(0, 4);
    final delay = Duration(seconds: seconds) > _maxRetryDelay
        ? _maxRetryDelay
        : Duration(seconds: seconds);
    _retryAttempt++;
    debugPrint('VoiceRoomAudioService: reconnecting in ${delay.inSeconds}s '
        '(attempt $_retryAttempt)');
    _retryTimer = Timer(delay, () {
      _retryTimer = null;
      _enqueue(() async {
        if (_roomId != roomId) return;
        await _connectRoom(roomId);
      });
    });
  }

  /// Android: a foreground service ("Voice room active" notification) for
  /// the whole time the user is in a room. Without it Android freezes the
  /// app soon after the screen locks or the user switches apps — mic and
  /// audio stop, heartbeats stop, and after 90s other clients sweep the
  /// user out of the room. No-op on web/iOS.
  static bool _keepAliveInitialized = false;

  Future<void> _startKeepAlive() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    try {
      if (!_keepAliveInitialized) {
        fgt.FlutterForegroundTask.init(
          androidNotificationOptions: fgt.AndroidNotificationOptions(
            channelId: 'voice_room_channel',
            channelName: 'Voice room',
            channelDescription: 'Keeps voice running while you are in a room.',
            onlyAlertOnce: true,
          ),
          iosNotificationOptions: const fgt.IOSNotificationOptions(
            showNotification: false,
          ),
          foregroundTaskOptions: fgt.ForegroundTaskOptions(
            eventAction: fgt.ForegroundTaskEventAction.nothing(),
            allowWakeLock: true,
            allowWifiLock: true,
          ),
        );
        _keepAliveInitialized = true;
      }
      if (await fgt.FlutterForegroundTask.isRunningService) return;

      // Microphone type needs RECORD_AUDIO already granted on Android 14+;
      // a listener who never granted it falls back to playback-only.
      for (final types in const [
        [fgt.ForegroundServiceTypes.microphone, fgt.ForegroundServiceTypes.mediaPlayback],
        [fgt.ForegroundServiceTypes.mediaPlayback],
      ]) {
        final result = await fgt.FlutterForegroundTask.startService(
          serviceId: 4711,
          serviceTypes: types,
          notificationTitle: 'Voice room active',
          notificationText: 'Tap to return to the room',
        );
        if (result is fgt.ServiceRequestSuccess) return;
        debugPrint('VoiceRoomAudioService: keep-alive start failed ($types): '
            '${(result as fgt.ServiceRequestFailure).error}');
      }
    } catch (e) {
      debugPrint('VoiceRoomAudioService: keep-alive unavailable: $e');
    }
  }

  Future<void> _stopKeepAlive() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    try {
      if (await fgt.FlutterForegroundTask.isRunningService) {
        await fgt.FlutterForegroundTask.stopService();
      }
    } catch (e) {
      debugPrint('VoiceRoomAudioService: keep-alive stop failed: $e');
    }
  }

  Future<_Grant?> _fetchToken(String roomId) async {
    _tokenRefused = false;
    try {
      final idToken = await FirebaseAuth.instance.currentUser?.getIdToken();
      if (idToken == null) return null;
      final res = await http
          .post(
            Uri.parse('${ApiConfig.baseUrl}/api/voice-rooms/$roomId/token'),
            headers: {
              'Authorization': 'Bearer $idToken',
              'Accept': 'application/json',
            },
          )
          .timeout(const Duration(seconds: 15));
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      if (res.statusCode != 200 || body['success'] != true) {
        // 401 bad Firebase token / 403 not (or no longer) in the room /
        // 404 room ended — permanent for this session, don't retry. 5xx
        // stays retryable.
        _tokenRefused = res.statusCode >= 400 && res.statusCode < 500;
        _error = (body['message'] as String?) ?? 'Could not start voice.';
        notifyListeners();
        return null;
      }
      return _Grant(
        url: body['url'] as String,
        token: body['token'] as String,
        canPublish: body['canPublish'] == true,
      );
    } catch (e) {
      debugPrint('VoiceRoomAudioService: token request failed: $e');
      _error = 'Could not reach the voice server.';
      notifyListeners();
      return null;
    }
  }
}

class _Grant {
  final String url;
  final String token;
  final bool canPublish;
  const _Grant({required this.url, required this.token, required this.canPublish});
}
