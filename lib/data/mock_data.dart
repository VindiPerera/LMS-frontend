import 'package:flutter/material.dart';
import '../models/user.dart';
import '../models/chat_message.dart';
import '../models/moment.dart';
import '../models/voiceroom.dart';
import '../models/live_stream.dart';
import '../models/learn_item.dart';
import '../models/room_participant.dart';

/// Deterministic placeholder "avatar" color + initial, so the UI has zero
/// network dependency while still looking populated.
class AvatarSpec {
  final String initial;
  final Color color;
  const AvatarSpec(this.initial, this.color);
}

const currentUser = AppUser(
  name: 'Vinuk Lakvindu',
  handle: 'talk_vinuklakvin',
  avatarUrl: 'V',
  countryFlag: '🇱🇰',
  nativeLang: 'Sinhala',
  learningLang: 'English',
  isVip: false,
  age: 24,
  gender: 'male',
);

const mockUsers = [
  AppUser(
    name: 'Kevin',
    handle: 'kevin_jp',
    avatarUrl: 'K',
    countryFlag: '🇯🇵',
    nativeLang: 'Japanese',
    learningLang: 'English',
    isOnline: true,
    age: 27,
    gender: 'male',
    bio: "Hello! I'm Kevin from Japan. I love hiking and photography 📷",
    activeLabel: 'Active now',
    tags: ['Free to Chat', 'Very active', 'Photography'],
  ),
  AppUser(
    name: 'Andrew Ferdinandus',
    handle: 'andrew_f',
    avatarUrl: 'A',
    countryFlag: '🇦🇺',
    nativeLang: 'English',
    learningLang: 'Sinhala',
    isOnline: false,
    age: 31,
    gender: 'male',
    bio: 'G\'day! Learning Sinhala for a trip to Sri Lanka next year.',
    activeLabel: 'Active 2 hours ago',
    tags: ['Similar age range', 'Travel'],
  ),
  AppUser(
    name: 'Zet',
    handle: 'zetify',
    avatarUrl: 'Z',
    countryFlag: '🇮🇩',
    nativeLang: 'Indonesian',
    learningLang: 'English',
    isOnline: true,
    isVip: true,
    age: 25,
    gender: 'male',
    bio: 'Music producer 🎧 always down to talk about R&B and beats.',
    activeLabel: 'Active now',
    tags: ['You both like Music', 'Very Responsive'],
  ),
  AppUser(
    name: 'Zuhri',
    handle: 'zuhri_m',
    avatarUrl: 'Z',
    countryFlag: '🇮🇩',
    nativeLang: 'Indonesian',
    learningLang: 'English',
    isOnline: true,
    age: 22,
    gender: 'female',
    bio: 'Wants to visit: New York 🗽 Let\'s practice speaking!',
    activeLabel: 'Active now',
    tags: ['Free to Chat', 'New'],
  ),
  AppUser(
    name: 'HelloTalk Assistant',
    handle: 'hellotalk_team_helper',
    avatarUrl: 'H',
    countryFlag: '🌐',
    nativeLang: 'English',
    learningLang: 'Cantonese',
    isOnline: true,
    age: 0,
    gender: 'female',
    bio: 'Official HelloTalk team helper account.',
    activeLabel: 'Active now',
    tags: ['Official'],
  ),
  AppUser(
    name: 'Maria Santos',
    handle: 'maria_es',
    avatarUrl: 'M',
    countryFlag: '🇪🇸',
    nativeLang: 'Spanish',
    learningLang: 'English',
    isOnline: false,
    age: 29,
    gender: 'female',
    bio: '¡Hola! I\'m Maria from Spain, learning English every day 🇪🇸',
    activeLabel: 'Active 1 hour ago',
    tags: ['Passionate about speaking practice', 'Similar age range'],
  ),
  AppUser(
    name: 'Wei Chen',
    handle: 'wei_cn',
    avatarUrl: 'W',
    countryFlag: '🇨🇳',
    nativeLang: 'Chinese',
    learningLang: 'Sinhala',
    isOnline: true,
    age: 26,
    gender: 'male',
    bio: 'Software engineer, love badminton 🏸 and language exchange.',
    activeLabel: 'Active now',
    tags: ['You both like Badminton', 'Very active'],
  ),
];

final List<Color> avatarPalette = [
  const Color(0xFF7B68F4),
  const Color(0xFF3DDC97),
  const Color(0xFFFF7A45),
  const Color(0xFF4FA8FF),
  const Color(0xFFFF4D8D),
  const Color(0xFFF5B942),
  const Color(0xFF9B59B6),
];

Color avatarColorFor(String seed) {
  final idx = seed.codeUnits.fold<int>(0, (a, b) => a + b) % avatarPalette.length;
  return avatarPalette[idx];
}

final List<ChatPreview> mockChats = [
  ChatPreview(
    user: mockUsers[4],
    lastMessage: 'Welcome to HelloTalk! Tap here to get started 🎉',
    time: '12:26 PM',
    unreadCount: 2,
  ),
  ChatPreview(
    user: mockUsers[0],
    lastMessage: '[Photo] My first post 🌸',
    time: '4h',
    unreadCount: 1,
  ),
  ChatPreview(
    user: mockUsers[1],
    lastMessage: 'Cover... translate this for me?',
    time: 'Yesterday',
    isTyping: true,
  ),
  ChatPreview(
    user: mockUsers[5],
    lastMessage: '¡Hola! ¿Cómo estás hoy?',
    time: 'Yesterday',
  ),
  ChatPreview(
    user: mockUsers[6],
    lastMessage: '[Voice message] 0:12',
    time: '2 days ago',
    isMuted: true,
  ),
];

final List<ChatMessage> mockConversation = [
  ChatMessage(text: 'Hi! Nice to meet you 😊', isMe: false, time: '12:20 PM'),
  ChatMessage(text: 'Hello! Nice to meet you too!', isMe: true, time: '12:21 PM'),
  ChatMessage(
    text: 'I am learning English, could you correct my sentence?',
    isMe: false,
    time: '12:22 PM',
  ),
  ChatMessage(
    text: 'Of course! Send it over.',
    isMe: true,
    time: '12:23 PM',
    type: MessageType.correction,
  ),
  ChatMessage(text: '', isMe: false, time: '12:24 PM', type: MessageType.voice, voiceSeconds: 12),
  ChatMessage(text: 'Sounds great, thank you! 🙏', isMe: true, time: '12:26 PM'),
];

final List<Moment> mockMoments = [
  Moment(
    user: mockUsers[0],
    timeAgo: '4 hours ago',
    text: 'My first post',
    imageUrl: 'flowers',
    likes: 7,
    comments: 2,
  ),
  Moment(
    user: mockUsers[1],
    timeAgo: 'Yesterday',
    text: 'Cover... could someone translate this sentence into Sinhala for me? 🙏',
    tag: '#topik hangat',
    likes: 12,
    comments: 5,
    isTranslatable: true,
  ),
  Moment(
    user: mockUsers[3],
    timeAgo: '2 days ago',
    text: 'Anyone up for a music-themed voiceroom tonight? 🎶 Come practice English with me!',
    tag: '#FIFA World Cup',
    likes: 21,
    comments: 9,
  ),
  Moment(
    user: mockUsers[5],
    timeAgo: '3 days ago',
    text: '¿Alguien puede corregir mi español? Estoy practicando todos los días.',
    likes: 15,
    comments: 4,
    isTranslatable: true,
  ),
];

final List<VoiceRoom> mockVoiceRooms = [
  VoiceRoom(
    title: 'ZETIFY 🎧 | Asian R&B Selection ✨',
    hostName: 'ZET',
    hostAvatar: 'Z',
    hostFlag: '🇮🇩',
    category: 'EN',
    tag: 'FIFA World Cup',
    participantCount: 69,
    isTop: true,
    coverGradientSeed: 'a',
  ),
  VoiceRoom(
    title: 'music station 🎧',
    hostName: 'ZUHRI',
    hostAvatar: 'Z',
    hostFlag: '🇮🇩',
    category: 'EN',
    tag: 'FIFA World Cup',
    participantCount: 21,
    isCreator: true,
    coverGradientSeed: 'b',
  ),
  VoiceRoom(
    title: 'could you teach me english?',
    hostName: '开心',
    hostAvatar: '开',
    hostFlag: '🇨🇳',
    category: 'EN',
    tag: 'FIFA World Cup',
    participantCount: 7,
    coverGradientSeed: 'c',
  ),
  VoiceRoom(
    title: 'Enjoy music 🎧',
    hostName: 'MH',
    hostAvatar: 'M',
    hostFlag: '🇰🇷',
    category: 'EN',
    tag: 'FIFA World Cup',
    participantCount: 25,
    isCreator: true,
    coverGradientSeed: 'd',
  ),
  VoiceRoom(
    title: 'Tasking Which I dnt like 🧘 / Morning music 🎵🍀💗🌸',
    hostName: 'Uosini',
    hostAvatar: 'U',
    hostFlag: '🇱🇰',
    category: 'EN',
    tag: 'Strange Stories',
    participantCount: 4,
    coverGradientSeed: 'e',
  ),
];

const languageCourses = [
  {'name': 'HelloWords', 'icon': Icons.grid_view_rounded, 'color': Color(0xFF2ECC71), 'badge': true},
  {'name': 'LiveClass', 'icon': Icons.menu_book_rounded, 'color': Color(0xFF4FA8FF), 'badge': false},
  {'name': 'Pro Partner', 'icon': Icons.people_alt_rounded, 'color': Color(0xFFFF4D8D), 'badge': false},
  {'name': 'HelloEnglish', 'icon': Icons.chat_bubble_rounded, 'color': Color(0xFF4FA8FF), 'badge': false},
  {'name': 'Podcast', 'icon': Icons.podcasts_rounded, 'color': Color(0xFF2E3A8C), 'badge': true},
  {'name': 'Grammar', 'icon': Icons.spellcheck_rounded, 'color': Color(0xFFFF7A45), 'badge': false},
  {'name': 'Idioms', 'icon': Icons.menu_book_rounded, 'color': Color(0xFFE84393), 'badge': false},
  {'name': 'Flashcards', 'icon': Icons.style_rounded, 'color': Color(0xFF00CEC9), 'badge': false},
];

final List<LiveStream> mockLiveStreams = [
  LiveStream(
    hostName: 'Bp',
    hostFlag: '🇮🇳',
    title: "Don't come or u will be kicked out",
    tag: 'My Playlist',
    viewers: 767,
    badgeLabel: 'Hot',
    coverSeed: 'live_a',
  ),
  LiveStream(
    hostName: 'Elyyyy',
    hostFlag: '🇨🇳',
    title: 'Singing with piano',
    tag: 'FIFA World Cup',
    viewers: 899,
    badgeLabel: 'Creator',
    coverSeed: 'live_b',
  ),
  LiveStream(
    hostName: 'monia',
    hostFlag: '🇮🇹',
    title: 'waiting for the rain to stop to continue walking to work',
    tag: 'My Playlist',
    viewers: 1066,
    badgeLabel: '',
    coverSeed: 'live_c',
  ),
  LiveStream(
    hostName: 'Zidan 李泽安',
    hostFlag: '🇺🇸',
    title: '🧑‍🍳 Cooking after the gym 🏋️',
    tag: 'Strange Stories',
    viewers: 956,
    badgeLabel: '',
    coverSeed: 'live_d',
  ),
  LiveStream(
    hostName: 'LOVELY',
    hostFlag: '🇮🇩',
    title: 'Is your life boring?',
    tag: 'Reading Plan',
    viewers: 421,
    badgeLabel: '',
    coverSeed: 'live_e',
  ),
  LiveStream(
    hostName: 'Rizza',
    hostFlag: '🇵🇭',
    title: 'quick live 🤳',
    tag: 'My Playlist',
    viewers: 312,
    badgeLabel: '',
    coverSeed: 'live_f',
  ),
];

const learnLanguageFlags = [
  {'name': 'English', 'flag': '🇺🇸'},
  {'name': 'Japanese', 'flag': '🇯🇵'},
  {'name': 'Korean', 'flag': '🇰🇷'},
  {'name': 'Spanish', 'flag': '🇪🇸'},
  {'name': 'Chinese', 'flag': '🇨🇳'},
  {'name': 'French', 'flag': '🇫🇷'},
  {'name': 'German', 'flag': '🇩🇪'},
  {'name': 'Italian', 'flag': '🇮🇹'},
  {'name': 'Russian', 'flag': '🇷🇺'},
  {'name': 'Arabic', 'flag': '🇸🇦'},
];

final List<LearnCard> learnCourseCards = [
  const LearnCard(
    title: 'HelloWords',
    subtitle: 'Unlock new words',
    badge: 'AI Tech',
    coverSeed: 'course_a',
  ),
  const LearnCard(
    title: 'LiveClass',
    subtitle: 'Tailored Courses For All Level',
    coverSeed: 'course_b',
  ),
  const LearnCard(
    title: 'HelloEnglish',
    subtitle: 'Learn anywhere anytime',
    coverSeed: 'course_c',
  ),
];

final List<WordPack> latestWordPacks = [
  const WordPack(title: 'AI Tech 2', progress: '0/10', badge: 'New'),
  const WordPack(title: 'AI Creativity', progress: '0/12'),
  const WordPack(title: 'Museum', progress: '0/12'),
];

final List<WordPack> recommendedWordPacks = [
  const WordPack(title: 'Fun', progress: '0/13'),
  const WordPack(title: 'Athletics', progress: 'Locked', locked: true),
  const WordPack(title: 'Home Workout', progress: 'Locked', locked: true),
];

final List<WordPack> basicWordPacks = [
  const WordPack(title: 'Question Words', progress: '0/8'),
  const WordPack(title: 'Time', progress: 'Locked', locked: true),
  const WordPack(title: 'Calendar', progress: 'Locked', locked: true),
];

const courseBanner = CourseBanner(
  tagline: 'Hot Pick',
  title: '1-on-1 English LiveClass',
  subtitle: '',
  ctaLabel: 'Buy Now!',
  coverSeed: 'banner',
);

const liveClassBanner = CourseBanner(
  tagline: '',
  title: '1-on-1 English LiveClass',
  subtitle: 'Learn with Structured Courses',
  ctaLabel: 'Buy Now!',
  coverSeed: 'liveclass',
);

const proPartnerBanner = CourseBanner(
  tagline: '',
  title: 'English Pro Partner',
  subtitle: 'Abundant topics to choose from\nChat freely with native partners',
  ctaLabel: 'Book now',
  coverSeed: 'propartner',
);

const roomParticipants = [
  RoomParticipant(name: 'Peter', flag: '🇺🇸', isHost: true, isSpeaking: true),
  RoomParticipant(name: 'Lina', flag: '🇰🇷', isMuted: true),
  RoomParticipant(name: 'Sandra', flag: '🇧🇷', isMuted: true),
  RoomParticipant(name: 'João', flag: '🇵🇹'),
  RoomParticipant(name: 'Jeffrey', flag: '🇺🇸'),
  RoomParticipant(name: 'Iza', flag: '🇹🇷'),
  RoomParticipant(name: '', flag: '', isEmptySeat: true),
  RoomParticipant(name: '', flag: '', isEmptySeat: true),
];

const roomBackRow = [
  RoomParticipant(name: 'Anne', flag: '🇫🇷'),
  RoomParticipant(name: 'Courtney', flag: '🇬🇧'),
  RoomParticipant(name: 'Leo', flag: '🇮🇹'),
  RoomParticipant(name: 'Chloe', flag: '🇨🇦'),
  RoomParticipant(name: 'Ichiro', flag: '🇯🇵'),
  RoomParticipant(name: 'Ali', flag: '🇹🇷'),
];
const roomOthersCount = 13;

const speakingTutors = [
  Tutor(
    name: 'Den',
    flag: '🇺🇸',
    languages: 'English/Russian',
    bio: 'Hello friends! 👋',
  ),
  Tutor(
    name: 'Sajida',
    flag: '🇬🇧',
    languages: 'English',
    bio: "Im sajida from England. I'm a graduate in Biomed...",
  ),
  Tutor(
    name: 'KIRSTIN',
    flag: '🇨🇦',
    languages: 'English',
    bio: '💎 PRO PARTNER ENGLISH TUTOR 💎',
    isPro: true,
  ),
  Tutor(
    name: 'Paul Charles',
    flag: '🇬🇧',
    languages: 'English',
    bio: '*Note - I teach adults only, intermediate level and ab...',
  ),
];

const classCategories = [
  {'name': '1v1 LiveClass', 'icon': Icons.chat_bubble_rounded, 'color': Color(0xFF7B4FE0), 'badge': 'HOT'},
  {'name': 'Speaking', 'icon': Icons.forum_rounded, 'color': Color(0xFFE8A23C), 'badge': ''},
  {'name': 'Pro Partner', 'icon': Icons.people_alt_rounded, 'color': Color(0xFFFF4D8D), 'badge': ''},
  {'name': 'Popular Host Class', 'icon': Icons.ondemand_video_rounded, 'color': Color(0xFF2CB5C0), 'badge': ''},
];

const roomChatLog = [
  RoomChatMessage(sender: 'Jeffrey', text: 'Long time no see Leo!'),
  RoomChatMessage(sender: 'Lina', senderBadge: '20', text: '好喜欢你的英文口音!', isTranslated: true, icon: RoomMessageIcon.translate),
  RoomChatMessage(
    sender: 'Tommy',
    senderBadge: '10',
    text: "Welcome to the English Chit-chat! We're talking about family expectations in our country",
    icon: RoomMessageIcon.gift,
  ),
  RoomChatMessage(
    sender: 'Notice',
    text: 'Welcome to the Voiceroom! Please remember to be respectful, inclusive, and of course have fun!',
    isSystem: true,
    icon: RoomMessageIcon.notice,
  ),
  RoomChatMessage(sender: '好多鱼的界', text: 'Happy New Year !', icon: RoomMessageIcon.gift),
  RoomChatMessage(sender: 'Tommy', text: '我只会一点中文 在大学有学过', icon: RoomMessageIcon.translate),
  RoomChatMessage(
    sender: 'Tommy',
    text: "I stopped learning Chinese when my family moved to the US for my dad's job",
    icon: RoomMessageIcon.star,
  ),
];

const roomQuickReplies = ['Hey, everyone!', "I'm new here.", 'Welcome!'];

const boardSpeakers = [
  RoomParticipant(
    name: 'supun',
    flag: '🇨🇦',
    isHost: true,
    isSpeaking: true,
    gender: 'male',
    age: 24,
    nativeLang: 'EN',
    learningLang: 'SI',
    location: 'Toronto, Canada',
    nativeLanguageFull: 'English',
    learningLanguagesFull: ['Sinhalese'],
    hobbies: [
      'Traveling', 'Reading', 'Movies', 'TV-series', 'Music',
      'Fitness', 'Swimming', 'Camping', 'Fashion', 'Gardning',
      'Photography', 'Dancing', 'Foot ball', 'Cricket',
    ],
  ),
  RoomParticipant(name: '', flag: '', isEmptySeat: true),
  RoomParticipant(name: '', flag: '', isEmptySeat: true),
  RoomParticipant(name: '', flag: '', isEmptySeat: true),
  RoomParticipant(name: '', flag: '', isEmptySeat: true),
  RoomParticipant(name: '', flag: '', isEmptySeat: true),
  RoomParticipant(name: '', flag: '', isEmptySeat: true),
  RoomParticipant(name: '', flag: '', isEmptySeat: true),
];

const boardStripCount = 7;
const boardOthersCount = 10;

const boardComments = [
  BoardComment(sender: 'Mike B.', text: 'Good Morning🌟'),
  BoardComment(sender: 'Mike B.', text: 'Good Morning🌟'),
  BoardComment(sender: 'Mike B.', text: 'Good Morning🌟\nGood Morning🌟'),
  BoardComment(sender: 'Mike B.', text: 'Good Morning🌟'),
  BoardComment(sender: 'Mike B.', text: 'Good Morning🌟'),
];
