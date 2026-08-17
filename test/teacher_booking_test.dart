import 'package:flutter_test/flutter_test.dart';
import 'package:facetalk_clone/data/mock_data.dart';
import 'package:facetalk_clone/models/learn_item.dart';
import 'package:facetalk_clone/models/user.dart';
import 'package:facetalk_clone/utils/location_helper.dart';


void main() {
  group('Teacher & Tutor Tests', () {
    test('speakingTutors are defined with complete profiles', () {
      expect(speakingTutors.isNotEmpty, isTrue);
      expect(speakingTutors.length, greaterThanOrEqualTo(4));

      final den = speakingTutors.firstWhere((t) => t.name == 'Den');
      expect(den.flag, equals('🇺🇸'));
      expect(den.rating, equals(4.9));
      expect(den.handle, equals('den_tutor'));
    });

    test('tutorToAppUser converts a Tutor to a valid teacher AppUser', () {
      final tutor = speakingTutors.first;
      final teacherUser = tutorToAppUser(tutor);

      expect(teacherUser.role, equals('teacher'));
      expect(teacherUser.name, equals(tutor.name));
      expect(teacherUser.countryFlag, equals(tutor.flag));
      expect(teacherUser.isOnline, isTrue);
    });

    test('fixedTeacherUsers are correctly converted', () {
      expect(fixedTeacherUsers.length, equals(speakingTutors.length));
      for (final user in fixedTeacherUsers) {
        expect(user.role, equals('teacher'));
        expect(user.name.isNotEmpty, isTrue);
      }
    });
  });

  group('Location & Time Tests', () {
    test('LocationHelper resolves Sri Lanka for user with LK flag', () {
      const user = AppUser(
        name: 'nushan hansana',
        handle: 'at_nushanhansana',
        avatarUrl: '',
        countryFlag: '🇱🇰',
        nativeLang: 'Sinhala',
        learningLang: 'English',
      );

      final loc = LocationHelper.getLocationInfo(user);
      expect(loc.city, equals('Colombo'));
      expect(loc.country, equals('Sri Lanka'));
      expect(loc.flag, equals('🇱🇰'));
      expect(loc.locationLabel, equals('Colombo, Sri Lanka'));
      expect(loc.timeLabel.contains(':'), isTrue);
    });

    test('LocationHelper resolves United States for US flag', () {
      const user = AppUser(
        name: 'Den',
        handle: 'den_tutor',
        avatarUrl: '',
        countryFlag: '🇺🇸',
        nativeLang: 'English',
        learningLang: 'Russian',
      );

      final loc = LocationHelper.getLocationInfo(user);
      expect(loc.city, equals('New York'));
      expect(loc.country, equals('United States'));
    });
  });
}
