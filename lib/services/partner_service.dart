import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/user.dart';

/// Fetches language-exchange partners for the Connect tab from the
/// `users` Firestore collection (see connect_screen.dart).
class PartnerService {
  static final _users = FirebaseFirestore.instance.collection('users');

  /// Other users, online first then newest first. Requires a composite
  /// index on (isOnline desc, createdAt desc) — see firestore.indexes.json;
  /// Firestore will also print a direct console link to create it the first
  /// time this query runs without one.
  static Future<List<AppUser>> fetchPartners({int limit = 30}) async {
    final selfUid = FirebaseAuth.instance.currentUser?.uid;

    final snapshot = await _users
        .orderBy('isOnline', descending: true)
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .get();

    return snapshot.docs
        .where((doc) => doc.id != selfUid)
        .map((doc) => AppUser.fromJson({...doc.data(), 'id': doc.id}))
        .toList();
  }

  /// A single partner's full profile, for partner_profile_screen.dart.
  static Future<AppUser> fetchPartner(String id) async {
    final doc = await _users.doc(id).get();
    if (!doc.exists) {
      throw StateError('This user no longer exists.');
    }
    return AppUser.fromJson({...doc.data()!, 'id': doc.id});
  }
}
