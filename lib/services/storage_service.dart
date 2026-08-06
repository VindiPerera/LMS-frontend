import 'dart:typed_data';
import 'package:firebase_storage/firebase_storage.dart';

/// Uploads user-generated files (currently just avatars) to Firebase Cloud
/// Storage — replaces what would otherwise be a file-upload endpoint on a
/// traditional backend.
class StorageService {
  /// Uploads [bytes] as this user's avatar and returns its public download
  /// URL, ready to store on the `users/{uid}` Firestore document.
  static Future<String> uploadAvatar(String uid, Uint8List bytes) async {
    final ref = FirebaseStorage.instance.ref('avatars/$uid.jpg');
    await ref.putData(bytes, SettableMetadata(contentType: 'image/jpeg'));
    return ref.getDownloadURL();
  }
}
