import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:facetalk_clone/models/moment.dart';
import 'package:facetalk_clone/models/user.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Moment.fromJson maps a Firestore document into a real moment model', () {
    final createdAt = Timestamp.fromDate(DateTime.now().subtract(const Duration(minutes: 5)));

    final moment = Moment.fromJson({
      'id': 'moment_123',
      'text': 'Hello everyone!',
      'imageUrls': ['https://example.com/a.jpg', 'https://example.com/b.jpg'],
      'mediaType': 'image',
      'likes': ['user_456', 'user_789'],
      'reactions': {
        '❤️': ['user_456'],
        '😂': ['user_789'],
      },
      'likeCount': 2,
      'commentCount': 4,
      'reshareCount': 1,
      'reportCount': 0,
      'visibility': 'public',
      'isReshare': false,
      'isDeleted': false,
      'createdAt': createdAt,
      'user': {
        'id': 'user_123',
        'name': 'Alice',
        'handle': 'alice',
        'avatarUrl': '',
        'countryFlag': '🇺🇸',
        'nativeLang': 'English',
        'learningLang': 'Spanish',
      },
    });

    expect(moment.id, 'moment_123');
    expect(moment.user.id, 'user_123');
    expect(moment.user.name, 'Alice');
    expect(moment.text, 'Hello everyone!');
    expect(moment.imageUrls, hasLength(2));
    expect(moment.mediaType, MomentMediaType.image);
    expect(moment.likeCount, 2);
    expect(moment.commentCount, 4);
    expect(moment.reshareCount, 1);
    expect(moment.visibility, MomentVisibility.public);
    expect(moment.isDeleted, isFalse);
    expect(moment.isLikedBy('user_456'), isTrue);
    expect(moment.isLikedBy('someone_else'), isFalse);
    expect(moment.reactionOf('user_789'), '😂');
    expect(moment.timeAgo, isNotEmpty);
  });

  test('Moment.toCreateMap resets every server-owned field for a fresh post', () {
    const moment = Moment(
      id: 'ignored-on-create',
      user: AppUser(
        id: 'user_456',
        name: 'Bob',
        handle: 'bob',
        avatarUrl: '',
        countryFlag: '🇬🇧',
        nativeLang: 'English',
        learningLang: 'Japanese',
      ),
      text: '  I am learning Japanese.  ',
      visibility: MomentVisibility.friends,
    );

    final map = moment.toCreateMap();

    expect(map['user']['id'], 'user_456');
    expect(map['user']['name'], 'Bob');
    expect(map['text'], '  I am learning Japanese.  ');
    expect(map['likes'], isEmpty);
    expect(map['reactions'], isEmpty);
    expect(map['likeCount'], 0);
    expect(map['commentCount'], 0);
    expect(map['reshareCount'], 0);
    expect(map['visibility'], 'friends');
    expect(map['isDeleted'], isFalse);
    expect(map.containsKey('id'), isFalse);
  });

  test('copyWith only changes the fields it is given', () {
    const original = Moment(
      user: AppUser(
        id: 'user_1',
        name: 'Cy',
        handle: 'cy',
        avatarUrl: '',
        countryFlag: '',
        nativeLang: '',
        learningLang: '',
      ),
      text: 'original text',
      likeCount: 3,
    );

    final updated = original.copyWith(isDeleted: true);

    expect(updated.isDeleted, isTrue);
    expect(updated.text, 'original text');
    expect(updated.likeCount, 3);
  });
}
