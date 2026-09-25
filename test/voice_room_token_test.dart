import 'package:flutter_test/flutter_test.dart';
import 'package:facetalk_clone/services/voice_room_token_service.dart';

void main() {
  group('VoiceRoomRtcToken.fromJson', () {
    test('publisher role maps to isPublisher', () {
      final t = VoiceRoomRtcToken.fromJson({
        'app_id': 'appid',
        'channel': 'room1',
        'uid': 123456,
        'role': 'publisher',
        'token': 'tok',
        'expires_at': 1700000000,
      });

      expect(t.isPublisher, isTrue);
      expect(t.appId, 'appid');
      expect(t.channel, 'room1');
      expect(t.uid, 123456);
      expect(t.token, 'tok');
    });

    test('audience role (or anything else) is not a publisher', () {
      final t = VoiceRoomRtcToken.fromJson({
        'app_id': 'a',
        'channel': 'c',
        'uid': 1,
        'role': 'audience',
        'token': 't',
      });

      expect(t.isPublisher, isFalse);
    });

    test('accepts a numeric uid delivered as a double', () {
      final t = VoiceRoomRtcToken.fromJson({
        'app_id': 'a',
        'channel': 'c',
        'uid': 42.0,
        'role': 'audience',
        'token': 't',
      });

      expect(t.uid, 42);
    });
  });

  test('VoiceRoomTokenException surfaces its message and status', () {
    const e = VoiceRoomTokenException('Join the room before requesting audio.', statusCode: 403);

    expect(e.toString(), 'Join the room before requesting audio.');
    expect(e.statusCode, 403);
  });
}
