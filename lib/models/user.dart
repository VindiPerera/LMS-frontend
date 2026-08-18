import 'package:cloud_firestore/cloud_firestore.dart';

import '../config/api_config.dart';

class AppUser {
  // Firestore document id (== Firebase Auth uid for the signed-in user).
  // Empty for local/mock AppUsers that were never stored anywhere.
  final String id;
  final String name;
  final String handle;
  final String avatarUrl;
  final String countryFlag;
  final String nativeLang;
  final String learningLang;
  final bool isOnline;
  final bool isVip;
  // When the current VIP subscription lapses — null if not VIP, or if VIP
  // but no purchase flow has ever set it yet (there isn't one wired up
  // yet; see vip_calendar_screen.dart, which falls back to a 30-day window
  // starting today so the calendar still has something meaningful to show).
  final DateTime? vipExpiresAt;
  final int age;
  final String gender;
  final String bio;
  final String activeLabel;
  final List<String> tags;
  // Fields below only come from Firestore's users/{uid} document; mock/local
  // AppUsers leave them at their defaults.
  final String email;
  final String role;
  final String detail;
  final bool profileCompleted;

  const AppUser({
    this.id = '',
    required this.name,
    required this.handle,
    required this.avatarUrl,
    required this.countryFlag,
    required this.nativeLang,
    required this.learningLang,
    this.isOnline = false,
    this.isVip = false,
    this.vipExpiresAt,
    this.age = 0,
    this.gender = 'other',
    this.bio = '',
    this.activeLabel = '',
    this.tags = const [],
    this.email = '',
    this.role = 'student',
    this.detail = '',
    this.profileCompleted = false,
  });

  /// Decodes a `users/{uid}` Firestore document into an AppUser. Callers
  /// must merge the document id into the map first (as `'id'`) — Firestore
  /// document data doesn't include its own id.
  factory AppUser.fromJson(Map<String, dynamic> json) {
    return AppUser(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      handle: json['handle']?.toString() ?? '',
      avatarUrl: ApiConfig.resolveUrl(json['avatarUrl']?.toString() ?? ''),

      countryFlag: json['countryFlag']?.toString() ?? '',
      nativeLang: json['nativeLang']?.toString() ?? '',
      learningLang: json['learningLang']?.toString() ?? '',
      isOnline: json['isOnline'] == true,
      isVip: json['isVip'] == true,
      vipExpiresAt: _asDateTime(json['vipExpiresAt']),
      age: _asInt(json['age']),
      gender: json['gender']?.toString() ?? 'other',
      bio: json['bio']?.toString() ?? '',
      activeLabel: json['activeLabel']?.toString() ?? '',
      tags:
          (json['tags'] as List?)?.map((e) => e.toString()).toList() ??
          const [],
      email: json['email']?.toString() ?? '',
      role: json['role']?.toString() ?? 'student',
      detail: json['detail']?.toString() ?? '',
      profileCompleted: json['profileCompleted'] == true,
    );
  }

  static int _asInt(Object? value) {
    if (value is int) return value;
    return int.tryParse('$value') ?? 0;
  }

  static DateTime? _asDateTime(Object? value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    return null;
  }
}

extension LanguageCode on String {
  /// First two letters, upper-cased, for a language "chip" (e.g. "English"
  /// -> "EN"). A user can have an empty nativeLang/learningLang (profile
  /// not finished yet), where plain `substring(0, 2)` would throw a
  /// RangeError, so this falls back to "??" instead.
  String get languageCode {
    if (isEmpty) return '??';
    return substring(0, length < 2 ? length : 2).toUpperCase();
  }
}
