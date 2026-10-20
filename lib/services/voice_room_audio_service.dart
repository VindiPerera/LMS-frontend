import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
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

  String? get roomId => _roomId;
  bool get isConnected => _room?.connectionState == ConnectionState.connected;

  /// uids LiveKit currently hears talking — for a speaking indicator.
  Set<String> get speakingUids => _speakingUids;

  /// Human-readable reason voice isn't working, or null.
  String? get error => _error;

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
      await _connectRoom(roomId);
    });
  }

  Future<void> disconnect() => _enqueue(_teardown);

  Future<void> _enqueue(Future<void> Function() task) {
    final next = _queue.then((_) => task()).catchError((Object e) {
      debugPrint('VoiceRoomAudioService: $e');
    });
    _queue = next;
    return next;
  }

  Future<void> _teardown() async {
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
    if (grant == null || _roomId != roomId) return;

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
    _events = room.createListener()
      ..on<ActiveSpeakersChangedEvent>((e) {
        _speakingUids = {for (final p in e.speakers) p.identity};
        notifyListeners();
      })
      ..on<RoomDisconnectedEvent>((_) {
        _speakingUids = const {};
        notifyListeners();
      });
    notifyListeners();
    await _syncMic();
  }

  Future<_Grant?> _fetchToken(String roomId) async {
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
