import 'package:flutter/material.dart';
import '../../data/mock_data.dart';
import '../../models/voiceroom.dart';
import '../../theme/app_colors.dart';
import '../../widgets/app_avatar.dart';
import 'live_tab.dart';
import 'learn_tab.dart';
import 'voice_room_detail_screen.dart';

class VoiceroomScreen extends StatefulWidget {
  const VoiceroomScreen({super.key});

  @override
  State<VoiceroomScreen> createState() => _VoiceroomScreenState();
}

class _VoiceroomScreenState extends State<VoiceroomScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  final _categories = const [
    'All',
    'English',
    'Sinhala',
    'Interaction',
    'Music',
  ];
  int _categoryIndex = 0;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        titleSpacing: 12,
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: AppColors.vipGold.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                children: const [
                  Text(
                    'VIP',
                    style: TextStyle(
                      color: AppColors.vipGold,
                      fontWeight: FontWeight.w800,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            const Spacer(),
            TabBar(
              controller: _tabController,
              isScrollable: true,
              indicatorColor: Colors.transparent,
              labelColor: AppColors.textPrimary,
              unselectedLabelColor: AppColors.textSecondary,
              labelStyle: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 15,
              ),
              unselectedLabelStyle: const TextStyle(
                fontWeight: FontWeight.w400,
                fontSize: 15,
              ),
              dividerColor: Colors.transparent,
              tabAlignment: TabAlignment.center,
              tabs: const [
                Tab(text: 'Voice'),
                Tab(text: 'Live'),
                Tab(text: 'Learn'),
              ],
            ),
            const Spacer(),
          ],
        ),
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 12),
            child: ElevatedButton.icon(
              onPressed: () {},
              icon: const Icon(Icons.mic_rounded, size: 16),
              label: const Text(
                'Start',
                style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primaryPurple,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 14),
              ),
            ),
          ),
        ],
      ),
      body: AnimatedBuilder(
        animation: _tabController,
        builder: (context, _) {
          final showCategoryRow = _tabController.index == 0;
          return Column(
            children: [
              if (showCategoryRow)
                SizedBox(
                  height: 40,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 4,
                    ),
                    itemCount: _categories.length,
                    separatorBuilder: (context, i) => const SizedBox(width: 10),
                    itemBuilder: (context, i) {
                      final selected = i == _categoryIndex;
                      return GestureDetector(
                        onTap: () => setState(() => _categoryIndex = i),
                        child: Center(
                          child: Text(
                            _categories[i],
                            style: TextStyle(
                              color: selected
                                  ? AppColors.textPrimary
                                  : AppColors.textTertiary,
                              fontWeight: selected
                                  ? FontWeight.w700
                                  : FontWeight.w400,
                              fontSize: 14,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    _VoiceRoomFeed(rooms: mockVoiceRooms),
                    const LiveTab(),
                    const LearnTab(),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _VoiceRoomFeed extends StatelessWidget {
  final List<VoiceRoom> rooms;
  const _VoiceRoomFeed({required this.rooms});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 20),
      children: [
        _WorldCupBanner(),
        const SizedBox(height: 14),
        ...rooms.map(
          (r) => Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: _VoiceRoomCard(room: r),
          ),
        ),
      ],
    );
  }
}

class _WorldCupBanner extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      height: 130,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: const LinearGradient(
          colors: [Color(0xFF1E8449), Color(0xFF27AE60)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text(
            'FaceTalk World Cup',
            style: TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.25),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Text(
              'Join the Battle',
              style: TextStyle(
                color: Colors.white,
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _VoiceRoomCard extends StatelessWidget {
  final VoiceRoom room;
  const _VoiceRoomCard({required this.room});

  static const _gradients = {
    'a': [Color(0xFF2C2360), Color(0xFF120F2E)],
    'b': [Color(0xFF3A2E6B), Color(0xFF1A1740)],
    'c': [Color(0xFF6B2E4A), Color(0xFF241026)],
    'd': [Color(0xFF1D3E6B), Color(0xFF0E1F3B)],
    'e': [Color(0xFF2C4770), Color(0xFF15243F)],
  };

  @override
  Widget build(BuildContext context) {
    final colors = _gradients[room.coverGradientSeed] ?? _gradients['a']!;
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => VoiceRoomDetailScreen(room: room)),
      ),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: LinearGradient(
            colors: colors,
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _pill(room.category, Colors.white24, Colors.white),
                const SizedBox(width: 6),
                _pill(
                  '# ${room.tag}',
                  AppColors.primaryPurple.withValues(alpha: 0.25),
                  AppColors.primaryPurple.withValues(alpha: 0.9),
                ),
                const Spacer(),
                if (room.isTop)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.vipGold,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Text(
                      'Top 1',
                      style: TextStyle(
                        fontSize: 9.5,
                        fontWeight: FontWeight.w800,
                        color: Colors.black,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                const Icon(
                  Icons.graphic_eq_rounded,
                  color: Colors.white70,
                  size: 18,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    room.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 15.5,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                AppAvatar(
                  seed: room.hostName,
                  size: 30,
                  showFlag: true,
                  flag: room.hostFlag,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        room.hostName,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (room.isCreator)
                        Container(
                          margin: const EdgeInsets.only(top: 2),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 5,
                            vertical: 1,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.badgePink,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text(
                            'Creator',
                            style: TextStyle(
                              fontSize: 8.5,
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                SizedBox(
                  width: 92,
                  height: 24,
                  child: Stack(
                    children: List.generate(4, (i) {
                      return Positioned(
                        left: i * 18.0,
                        child: AppAvatar(
                          seed: '${room.hostName}$i',
                          size: 24,
                          borderWidth: 2,
                          borderColor: colors.last,
                        ),
                      );
                    }),
                  ),
                ),
                const SizedBox(width: 4),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${room.participantCount}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _pill(String text, Color bg, Color fg) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 10.5,
          color: fg,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
