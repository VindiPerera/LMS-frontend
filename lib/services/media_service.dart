import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';

import '../config/api_config.dart';

/// Picking, compressing, and uploading Moments media to hello-backend (persisted in MySQL).
class MediaService {
  static const _uuid = Uuid();
  static final _picker = ImagePicker();

  // --------------------------------------------------------------------
  // Picking
  // --------------------------------------------------------------------

  static Future<XFile?> pickImage(ImageSource source) {
    return _picker.pickImage(source: source, imageQuality: 95);
  }

  // --------------------------------------------------------------------
  // Compression
  // --------------------------------------------------------------------

  /// Compresses [bytes] down to a max 1080px edge at 80% quality.
  static Future<Uint8List> compressImageBytes(Uint8List bytes) async {
    try {
      final compressed = await FlutterImageCompress.compressWithList(
        bytes,
        minWidth: 1080,
        minHeight: 1080,
        quality: 80,
        format: CompressFormat.jpeg,
      );
      if (compressed.isEmpty) return bytes;
      return compressed;
    } catch (_) {
      // Compression is a nice-to-have — never block a post over it.
      return bytes;
    }
  }

  // --------------------------------------------------------------------
  // Upload
  // --------------------------------------------------------------------

  static Future<String> uploadImageBytes({
    required Uint8List bytes,
    required String uid,
    required String postId,
    void Function(double progress)? onProgress,
  }) {
    return _uploadToBackend(
      bytes: bytes,
      filename: '${_uuid.v4()}.jpg',
      extension: 'jpg',
      contentType: MediaType('image', 'jpeg'),
      uid: uid,
      postId: postId,
      type: 'image',
      onProgress: onProgress,
    );
  }

  static Future<String> _uploadToBackend({
    required Uint8List bytes,
    required String filename,
    required String extension,
    required MediaType contentType,
    required String uid,
    required String postId,
    required String type,
    void Function(double progress)? onProgress,
  }) async {
    final candidateUrls = ApiConfig.candidateUploadUrls;
    String lastServerError = '';

    for (final uploadUrl in candidateUrls) {
      // 1. Try base64 direct payload first (100% reliable across all PHP/server/temp configs)
      try {
        onProgress?.call(0.2);
        final uri = Uri.parse(uploadUrl);
        final base64String = base64Encode(bytes);

        final response = await http.post(
          uri,
          headers: {
            'Content-Type': 'application/json',
            'Accept': 'application/json',
          },
          body: jsonEncode({
            'user_id': uid,
            'post_id': postId,
            'type': type,
            'extension': extension,
            'file_base64': base64String,
          }),
        ).timeout(const Duration(seconds: 45));

        if (response.statusCode >= 200 && response.statusCode < 300) {
          final data = jsonDecode(response.body) as Map<String, dynamic>;
          if (data['success'] == true && data['url'] != null) {
            onProgress?.call(1.0);
            return data['url'] as String;
          }
        } else {
          lastServerError = 'HTTP ${response.statusCode}: ${response.body}';
          debugPrint('Base64 upload to $uploadUrl returned status ${response.statusCode}: ${response.body}');
        }
      } catch (e) {
        lastServerError = e.toString();
        debugPrint('Base64 upload to $uploadUrl failed: $e. Trying multipart...');
      }

      // 2. Fallback: Try multipart form-data upload
      try {
        onProgress?.call(0.5);
        final uri = Uri.parse(uploadUrl);
        final request = http.MultipartRequest('POST', uri);

        request.fields['user_id'] = uid;
        request.fields['post_id'] = postId;
        request.fields['type'] = type;

        final multipartFile = http.MultipartFile.fromBytes(
          'file',
          bytes,
          filename: filename,
          contentType: contentType,
        );
        request.files.add(multipartFile);

        final streamedResponse = await request.send().timeout(const Duration(seconds: 45));
        final response = await http.Response.fromStream(streamedResponse);

        if (response.statusCode >= 200 && response.statusCode < 300) {
          final data = jsonDecode(response.body) as Map<String, dynamic>;
          if (data['success'] == true && data['url'] != null) {
            onProgress?.call(1.0);
            return data['url'] as String;
          }
        } else {
          lastServerError = 'HTTP ${response.statusCode}: ${response.body}';
          debugPrint('Multipart upload to $uploadUrl returned status ${response.statusCode}: ${response.body}');
        }
      } catch (e) {
        lastServerError = e.toString();
        debugPrint('Multipart upload to $uploadUrl failed: $e');
      }
    }

    throw Exception(
      'Failed to upload media to backend ($candidateUrls): ${lastServerError.isNotEmpty ? lastServerError : "Server rejected file."}',
    );
  }
}
