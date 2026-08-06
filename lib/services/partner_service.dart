import '../models/user.dart';
import 'api_client.dart';

/// Fetches language-exchange partners for the Connect tab from
/// GET /api/partners (see connect_screen.dart).
class PartnerService {
  static Future<List<AppUser>> fetchPartners() async {
    final res = await ApiClient.instance.get('/partners');
    final list = (res['users'] as List?) ?? const [];
    return list.map((e) => AppUser.fromJson(e as Map<String, dynamic>)).toList();
  }
}
