import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

import '../config/api_config.dart';

/// What hello-backend's VoiceRoomTokenController returns for a room — the
/// credentials for one Agora channel join. [isPublisher] is decided by the
/// SERVER from the caller's Firestore participant role (host/moderator/
/// speaker), never by anything the client sends.
class VoiceRoomRtcToken {
  final String appId;
  final String channel;
  final int uid;
  final bool isPublisher;
  final String token;

  const VoiceRoomRtcToken({
    required this.appId,
    required this.channel,
    required this.uid,
    required this.isPublisher,
    required this.token,
  });

  factory VoiceRoomRtcToken.fromJson(Map<String, dynamic> json) {
    return VoiceRoomRtcToken(
      appId: json['app_id'].toString(),
      channel: json['channel'].toString(),
      uid: (json['uid'] as num).toInt(),
      isPublisher: json['role'] == 'publisher',
      token: json['token'].toString(),
    );
  }
}

class VoiceRoomTokenException implements Exception {
  final String message;
  final int? statusCode;

  const VoiceRoomTokenException(this.message, {this.statusCode});

  @override
  String toString() => message;
}

/// Requests a live-audio token from hello-backend. Unlike this app's older
/// backend calls (fcm-token, notifications...), this one authenticates with
/// the signed-in user's Firebase ID token — the server derives who is asking
/// from that, not from a uid in the body — so the audio join can't be
/// spoofed for someone else's account.
class VoiceRoomTokenService {
  static Future<VoiceRoomRtcToken> fetch(String roomId) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw const VoiceRoomTokenException('Sign in to join live audio.');
    }

    final String idToken;
    final Uri uri;
    try {
      idToken = await user.getIdToken() ?? '';
      uri = Uri.parse('${ApiConfig.baseUrl}/api/voice-rooms/$roomId/rtc-token');
    } catch (e) {
      // ApiConfig.baseUrl throws a descriptive StateError in a release build
      // with no backend configured — surface that instead of swallowing it.
      throw VoiceRoomTokenException(e.toString());
    }

    final http.Response response;
    try {
      response = await http
          .post(uri, headers: {'Authorization': 'Bearer $idToken', 'Accept': 'application/json'})
          .timeout(const Duration(seconds: 10));
    } catch (_) {
      throw const VoiceRoomTokenException('Could not reach the audio server. Check your connection.');
    }

    if (response.statusCode != 200) {
      String message = 'Live audio is unavailable right now.';
      try {
        message = (jsonDecode(response.body) as Map<String, dynamic>)['message']?.toString() ?? message;
      } catch (_) {}
      throw VoiceRoomTokenException(message, statusCode: response.statusCode);
    }

    return VoiceRoomRtcToken.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }
}
