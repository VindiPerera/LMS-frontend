import 'package:flutter/material.dart';
import '../../data/mock_data.dart';
import '../../models/voiceroom.dart';
import '../../services/voice_room_service.dart';
import '../../theme/app_colors.dart';
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

  // Real, user-created rooms (see VoiceRoomService) come first; the mock
  // entries just keep the browse feed looking populated in a fresh project
  // with no live rooms yet.
  late final Stream<List<VoiceRoom>> _liveRoomsStream = VoiceRoomService.streamActiveRooms();

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

  List<VoiceRoom> _filteredRooms(List<VoiceRoom> rooms) {
    if (_categoryIndex == 0) return rooms;
    final cat = _categories[_categoryIndex].toLowerCase();
    return rooms.where((r) {
      return r.category.toLowerCase().contains(cat.substring(0, 2)) ||
          r.title.toLowerCase().contains(cat) ||
          r.tag.toLowerCase().contains(cat);
    }).toList();
  }

  void _openCreateRoomSheet() {
    final titleController = TextEditingController();
    final tagController = TextEditingController();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom + 16,
            left: 20,
            right: 20,
            top: 20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Text(
                    'Create a VoiceRoom',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 17,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              TextField(
                controller: titleController,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Room Topic / Title',
                  hintText: 'e.g. Free Talk & Practice English',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: tagController,
                decoration: const InputDecoration(
                  labelText: 'Tag (Optional)',
                  hintText: 'e.g. Beginner Friendly',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 18),
              ElevatedButton(
                onPressed: () async {
                  final title = titleController.text.trim();
                  if (title.isEmpty) return;
                  final tag = tagController.text.trim().isEmpty
                      ? 'General'
                      : tagController.text.trim();
                  final sheetContext = context;
                  try {
                    final newRoom = await VoiceRoomService.createRoom(
                      title: title,
                      tag: tag,
                      category: 'EN',
                    );
                    if (!sheetContext.mounted) return;
                    Navigator.of(sheetContext).pop();
                    Navigator.of(sheetContext).push(
                      MaterialPageRoute(
                        builder: (_) => VoiceRoomDetailScreen(room: newRoom),
                      ),
                    );
                  } catch (e) {
                    // Deliberately NOT falling back to a local-only room
                    // here — a room nobody else can ever see (it was never
                    // written to Firestore) is worse than a clear error,
                    // since it looks like it worked while silently not
                    // showing up anywhere else in the app (profile, Chat's
                    // "you're hosting" banner, etc).
                    if (!sheetContext.mounted) return;
                    ScaffoldMessenger.of(sheetContext).showSnackBar(
                      SnackBar(content: Text('Could not start room: ${e.toString().replaceFirst('Exception: ', '')}')),
                    );
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primaryPurple,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                ),
                child: const Text(
                  'Start Room Now',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: FloatingActionButton(
        onPressed: _openCreateRoomSheet,
        backgroundColor: AppColors.primaryPurple,
        child: const Icon(Icons.add_rounded, size: 28),
      ),
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
              child: const Row(
                children: [
                  Text(
                    'VIP',
                    style: TextStyle(
                      color: AppColors.vipGold,
                      fontWeight: FontWeight.w800,
                      fontSize: 12.5,
                    ),
                  ),
                  SizedBox(width: 4),
                  Icon(
                    Icons.workspace_premium_rounded,
                    size: 14,
                    color: AppColors.vipGold,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: TabBar(
                controller: _tabController,
                indicatorColor: AppColors.primaryPurple,
                labelColor: AppColors.textPrimary,
                unselectedLabelColor: AppColors.textTertiary,
                labelStyle: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                ),
                dividerColor: Colors.transparent,
                tabs: const [
                  Tab(text: 'Voice'),
                  Tab(text: 'Live'),
                  Tab(text: 'Learn'),
                ],
              ),
            ),
          ],
        ),
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 12),
            child: ElevatedButton.icon(
              onPressed: _openCreateRoomSheet,
              icon: const Icon(Icons.mic_rounded, size: 16),
              label: const Text(
                'Start',
                style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primaryPurple,
                foregroundColor: Colors.white,
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
                    StreamBuilder<List<VoiceRoom>>(
                      stream: _liveRoomsStream,
                      builder: (context, snapshot) {
                        final liveRooms = snapshot.data ?? const [];
                        final rooms = [...liveRooms, ...mockVoiceRooms];
                        return _VoiceRoomFeed(rooms: _filteredRooms(rooms));
                      },
                    ),
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
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFEFEFF4),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          const Text(
            '⚽',
            style: TextStyle(fontSize: 24),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                Text(
                  'FIFA World Cup VoiceRoom',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  'Join global football fans to talk & practice live',
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                  ),
                ),
              ],
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

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => VoiceRoomDetailScreen(room: room),
          ),
        );
      },
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.primaryPurple.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    room.tag,
                    style: const TextStyle(
                      color: AppColors.primaryPurple,
                      fontWeight: FontWeight.w700,
                      fontSize: 11.5,
                    ),
                  ),
                ),
                const Spacer(),
                const Icon(
                  Icons.equalizer_rounded,
                  size: 16,
                  color: AppColors.online,
                ),
                const SizedBox(width: 4),
                Text(
                  '${room.participantCount} online',
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              room.title,
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 15.5,
                color: AppColors.textPrimary,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                CircleAvatar(
                  radius: 14,
                  backgroundImage: NetworkImage(room.hostAvatar),
                  child: Text(room.hostName.isEmpty ? 'H' : room.hostName[0]),
                ),
                const SizedBox(width: 8),
                Text(
                  room.hostName,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(width: 4),
                Text(room.hostFlag, style: const TextStyle(fontSize: 12)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
