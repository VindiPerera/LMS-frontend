import 'dart:io';
import 'dart:typed_data';

import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';
import 'package:video_compress/video_compress.dart';
import 'package:video_thumbnail/video_thumbnail.dart' as vt;

/// Picking, compressing, and uploading Moments media. All Storage calls
/// live here so create_moment_screen.dart never touches
/// firebase_storage/image_picker/video_compress directly.
///
/// Upload path convention: `moments/{uid}/{postId}/{uuid}.{ext}`. This lets
/// functions/index.js's onPostDelete clean up an entire post's media with a
/// single prefix delete instead of parsing each download URL. Because of
/// this, [MomentService.newPostId] must be called (to pre-allocate the
/// Firestore doc id) *before* any upload starts on the create flow.
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
      return compressed;
    } catch (_) {
      // Compression is a nice-to-have — never block a post over it.
      return bytes;
    }
  }

  /// Compresses a picked video with video_compress. Returns the original
  /// [file] unchanged if compression fails for any reason (unmaintained
  /// plugin — see pubspec.yaml's note on video_compress) so a post never
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
  static Future<Uint8List?> generateVideoThumbnail(String videoPath) {
    return vt.VideoThumbnail.thumbnailData(
      video: videoPath,
      imageFormat: vt.ImageFormat.JPEG,
      maxWidth: 480,
      quality: 70,
    );
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
    return _upload(
      bytes: bytes,
      path: 'moments/$uid/$postId/${_uuid.v4()}.jpg',
      contentType: 'image/jpeg',
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
    return _upload(
      bytes: bytes,
      path: 'moments/$uid/$postId/${_uuid.v4()}.mp4',
      contentType: 'video/mp4',
      onProgress: onProgress,
    );
  }

  static Future<String> uploadVideoThumbnail({
    required Uint8List bytes,
    required String uid,
    required String postId,
  }) {
    return _upload(
      bytes: bytes,
      path: 'moments/$uid/$postId/${_uuid.v4()}_thumb.jpg',
      contentType: 'image/jpeg',
    );
  }

  static Future<String> _upload({
    required Uint8List bytes,
    required String path,
    required String contentType,
    void Function(double progress)? onProgress,
  }) async {
    final ref = FirebaseStorage.instance.ref(path);
    final task = ref.putData(bytes, SettableMetadata(contentType: contentType));

    final subscription = onProgress == null
        ? null
        : task.snapshotEvents.listen((snap) {
            if (snap.totalBytes > 0) {
              onProgress(snap.bytesTransferred / snap.totalBytes);
            }
          });

    try {
      final snapshot = await task;
      return await snapshot.ref.getDownloadURL();
    } finally {
      await subscription?.cancel();
    }
  }
}
