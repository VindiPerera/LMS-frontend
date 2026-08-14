import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';
import 'package:video_compress/video_compress.dart';
import 'package:video_thumbnail/video_thumbnail.dart' as vt;

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

  static Future<XFile?> pickVideo(ImageSource source) {
    return _picker.pickVideo(source: source, maxDuration: const Duration(minutes: 5));
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

  /// Compresses a picked video with video_compress. Returns the original
  /// [file] unchanged if compression fails for any reason so a post never
  /// gets stuck just because compression didn't work on this device.
  static Future<File> compressVideo(File file) async {
    try {
      final info = await VideoCompress.compressVideo(
        file.path,
        quality: VideoQuality.MediumQuality,
        deleteOrigin: false,
      );
      return info?.file ?? file;
    } catch (_) {
      return file;
    }
  }

  /// First frame of [videoPath] as JPEG bytes, for the feed/thumbnail-row
  /// preview and as the `videoThumbnailUrl` upload.
  static Future<Uint8List?> generateVideoThumbnail(String videoPath) async {
    try {
      return await vt.VideoThumbnail.thumbnailData(
        video: videoPath,
        imageFormat: vt.ImageFormat.JPEG,
        maxWidth: 480,
        quality: 70,
      );
    } catch (_) {
      return null;
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

  static Future<String> uploadVideoFile({
    required File file,
    required String uid,
    required String postId,
    void Function(double progress)? onProgress,
  }) async {
    final bytes = await file.readAsBytes();
    return _uploadToBackend(
      bytes: bytes,
      filename: '${_uuid.v4()}.mp4',
      extension: 'mp4',
      contentType: MediaType('video', 'mp4'),
      uid: uid,
      postId: postId,
      type: 'video',
      onProgress: onProgress,
    );
  }

  static Future<String> uploadVideoThumbnail({
    required Uint8List bytes,
    required String uid,
    required String postId,
  }) {
    return _uploadToBackend(
      bytes: bytes,
      filename: '${_uuid.v4()}_thumb.jpg',
      extension: 'jpg',
      contentType: MediaType('image', 'jpeg'),
      uid: uid,
      postId: postId,
      type: 'thumbnail',
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
