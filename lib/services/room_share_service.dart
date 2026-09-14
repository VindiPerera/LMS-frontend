import 'package:share_plus/share_plus.dart';

import '../config/api_config.dart';
import '../models/voiceroom.dart';

/// Builds and shares a voice room's invite link — same
/// share_plus/"Share more" pattern MyQRCodeScreen already uses for friend
/// links, just simpler: a room's Firestore id is safe to expose directly
/// (unlike a user profile, which routes through an opaque backend-generated
/// code for other reasons), so this needs no backend round-trip.
///
/// Known gap: tapping the resulting link does not yet reopen the room
/// in-app for someone who doesn't already have it running — that would
/// need a `/room/{id}` backend route plus matching DeepLinkService/App
/// Links wiring (see AndroidManifest.xml's existing `/u/` intent-filter for
/// the pattern this would follow), which is real native-platform and
/// backend infrastructure beyond this feature's current scope. The share
/// message is worded to still read fine on its own until that's built.
class RoomShareService {
  static String linkFor(VoiceRoom room) => '${ApiConfig.baseUrl}/room/${room.id}';

  static Future<void> shareRoom(VoiceRoom room) {
    final link = linkFor(room);
    final title = room.title.trim().isEmpty ? 'a Voice Room' : '"${room.title.trim()}"';
    return Share.share('Join $title on FaceTalk — I\'m live right now: $link');
  }
}
