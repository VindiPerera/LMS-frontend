import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../data/mock_data.dart';
import '../models/user.dart';
import '../screens/hellotalk/chat_detail_screen.dart';
import 'chat_service.dart';

class TeacherService {
  static final _users = FirebaseFirestore.instance.collection('users');

  /// Fetches all registered teachers from Firestore and falls back / merges with fixed teachers.
  static Future<List<AppUser>> fetchTeachers() async {
    try {
      final snap = await _users
          .where('role', isEqualTo: 'teacher')
          .limit(30)
          .get();

      final firestoreTeachers = snap.docs
          .map((d) => AppUser.fromJson({...d.data(), 'id': d.id}))
          .toList();

      final existingIds = firestoreTeachers.map((t) => t.id).toSet();
      final existingNames = firestoreTeachers.map((t) => t.name.toLowerCase()).toSet();

      final merged = List<AppUser>.from(firestoreTeachers);
      for (final fixed in fixedTeacherUsers) {
        if (!existingIds.contains(fixed.id) && !existingNames.contains(fixed.name.toLowerCase())) {
          merged.add(fixed);
        }
      }
      return merged;
    } catch (_) {
      return fixedTeacherUsers;
    }
  }

  /// Automatically sends a booking message to the teacher and opens the chat screen.
  static Future<void> bookTutor(
    BuildContext context, {
    required AppUser teacher,
    String? customMessage,
  }) async {
    final message = customMessage ??
        'Hello ${teacher.name}! 👋 I would like to book a 1-on-1 language tutoring session with you. Please let me know your available schedule!';

    try {
      await ChatService.sendMessage(
        other: teacher,
        text: message,
      );
    } catch (_) {
      // Allow navigation even if offline/mock so user can see conversation interface
    }

    if (!context.mounted) return;

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ChatDetailScreen(user: teacher),
      ),
    );
  }
}
