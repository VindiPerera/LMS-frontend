import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/voiceroom.dart';
import 'room_participant_service.dart';
import 'voice_room_service.dart';

/// Tracks the signed-in user's minimized voice room, if any — the single
/// source of truth VoiceRoomMiniWindow (lib/widgets/voice_room_mini_window
/// .dart) renders from. Only one room can be minimized at a time, matching
/// RoomParticipantService.join's own one-seat-per-uid model.
///
/// Ownership model: while VoiceRoomDetailScreen is open, IT owns the
/// heartbeat timer and room-ended subscription (see its initState/dispose).
/// The moment the user minimizes, this controller takes over both — with
/// its own fresh Timer/StreamSubscription, not the screen's — so they keep
/// running after the screen's State is disposed. Reopening the room simply
/// pushes a brand-new VoiceRoomDetailScreen, which calls
/// RoomParticipantService.join again; join() is explicitly documented as
/// idempotent/reconnect-safe, so this transparently reclaims the same
/// participant doc under a fresh sessionId instead of needing any handoff
/// of the actual Timer/subscription objects.
class VoiceRoomSessionController extends ChangeNotifier {
  VoiceRoomSessionController._();
  static final VoiceRoomSessionController instance = VoiceRoomSessionController._();

  VoiceRoom? _room;
  String? _sessionId;
  Timer? _heartbeatTimer;
  StreamSubscription<VoiceRoom?>? _roomSub;

  VoiceRoom? get minimizedRoom => _room;
  bool get isMinimized => _room != null;

  /// Called by VoiceRoomDetailScreen's "Minimize the room" action, right
  /// before it pops. [sessionId] must be the same one the screen has been
  /// heartbeating with, so this controller's heartbeat keeps refreshing the
  /// same participant doc rather than racing a stale one.
  void minimize({required VoiceRoom room, required String sessionId}) {
    if (room.id.isEmpty) return;
    _cancelSubscriptions();
    _room = room;
    _sessionId = sessionId;
    _heartbeatTimer = Timer.periodic(RoomParticipantService.heartbeatInterval, (_) {
      RoomParticipantService.heartbeat(room.id, sessionId);
    });
    _roomSub = VoiceRoomService.streamRoom(room.id).listen((liveRoom) {
      if (liveRoom == null || !liveRoom.isActive) {
        // The room itself is gone/ended — nothing left to leave() for.
        clear(leaveRoom: false);
      }
    });
    notifyListeners();
  }

  /// Drops the minimized session. [leaveRoom] is true for an explicit close
  /// (the mini window's X button) and false when reopening the room (a
  /// fresh VoiceRoomDetailScreen takes over presence itself) or when the
  /// room already ended on its own.
  void clear({required bool leaveRoom}) {
    final room = _room;
    final sessionId = _sessionId;
    _cancelSubscriptions();
    _room = null;
    _sessionId = null;
    notifyListeners();
    if (leaveRoom && room != null && sessionId != null) {
      RoomParticipantService.leave(room.id, sessionId);
    }
  }

  void _cancelSubscriptions() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    _roomSub?.cancel();
    _roomSub = null;
  }
}
