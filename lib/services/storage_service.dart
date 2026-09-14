import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import '../config/api_config.dart';

/// Uploads user-generated files (avatars, whiteboard images) to
/// hello-backend and persists them in MySQL.
class StorageService {
  /// Uploads [bytes] as this user's avatar and returns its public URL.
  static Future<String> uploadAvatar(String uid, Uint8List bytes) {
    return _upload(uid: uid, bytes: bytes, type: 'avatar');
  }

  /// Uploads [bytes] (e.g. from ImagePicker) as a voice room whiteboard
  /// image and returns its public URL — same MediaController::upload
  /// endpoint as [uploadAvatar], just tagged with a different `type` so
  /// the backend's Media row records what it actually is.
  static Future<String> uploadWhiteboardImage(String uid, Uint8List bytes) {
    return _upload(uid: uid, bytes: bytes, type: 'whiteboard');
  }

  static Future<String> _upload({required String uid, required Uint8List bytes, required String type}) async {
    final candidateUrls = ApiConfig.candidateUploadUrls;
    String lastServerError = '';

    for (final uploadUrl in candidateUrls) {
      // 1. Base64 payload
      try {
        final uri = Uri.parse(uploadUrl);
        final base64String = base64Encode(bytes);

        final response = await http.post(
          uri,
          headers: {'Content-Type': 'application/json', 'Accept': 'application/json'},
          body: jsonEncode({
            'user_id': uid,
            'type': type,
            'extension': 'jpg',
            'file_base64': base64String,
          }),
        ).timeout(const Duration(seconds: 25));

        if (response.statusCode >= 200 && response.statusCode < 300) {
          final data = jsonDecode(response.body) as Map<String, dynamic>;
          if (data['success'] == true && data['url'] != null) {
            return data['url'] as String;
          }
        } else {
          lastServerError = 'HTTP ${response.statusCode}: ${response.body}';
        }
      } catch (e) {
        lastServerError = e.toString();
      }

      // 2. Multipart fallback
      try {
        final uri = Uri.parse(uploadUrl);
        final request = http.MultipartRequest('POST', uri);

        request.fields['user_id'] = uid;
        request.fields['type'] = type;

        final multipartFile = http.MultipartFile.fromBytes(
          'file',
          bytes,
          filename: '$uid.jpg',
          contentType: MediaType('image', 'jpeg'),
        );
        request.files.add(multipartFile);

        final streamedResponse = await request.send().timeout(const Duration(seconds: 20));
        final response = await http.Response.fromStream(streamedResponse);

        if (response.statusCode >= 200 && response.statusCode < 300) {
          final data = jsonDecode(response.body) as Map<String, dynamic>;
          if (data['success'] == true && data['url'] != null) {
            return data['url'] as String;
          }
        } else {
          lastServerError = 'HTTP ${response.statusCode}: ${response.body}';
        }
      } catch (e) {
        lastServerError = e.toString();
      }
    }

    throw Exception(
      'Failed to upload $type to backend: ${lastServerError.isNotEmpty ? lastServerError : "Server rejected upload."}',
    );
  }
}
