import 'package:flutter/material.dart';
import '../../data/mock_data.dart';
import '../../models/room_participant.dart';
import '../../models/voiceroom.dart';
import '../../services/room_participant_service.dart';
import '../../services/voice_room_service.dart';
import '../../theme/app_colors.dart';
import '../../widgets/app_avatar.dart';
import '../../widgets/mic_etiquette_banner.dart';
import 'live_tab.dart';
import 'learn_tab.dart';
import 'open_voice_room.dart';
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
    'Korean',
    'Sinhala',
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

    // This app only ever creates public rooms — listed on Voice for anyone
    // to join — so the sheet no longer offers a Private option at all
    // (there is nothing left here for it to gate).
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
                  hintText: 'English Practice',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: tagController,
                decoration: const InputDecoration(
                  labelText: 'Tag (Optional)',
                  hintText: 'Beginner Level English',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              const Row(
                children: [
                  Icon(Icons.public_rounded, size: 15, color: Colors.black45),
                  SizedBox(width: 6),
                  Text(
                    'Listed on Voice for anyone to join',
                    style: TextStyle(fontSize: 12.5, color: Colors.black45),
                  ),
                ],
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
                        builder: (_) => VoiceRoomDetailScreen(room: newRoom, justCreated: true),
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
        titleSpacing: 8,
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.vipGold.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'VIP',
                    style: TextStyle(
                      color: AppColors.vipGold,
                      fontWeight: FontWeight.w800,
                      fontSize: 12,
                    ),
                  ),
                  SizedBox(width: 3),
                  Icon(
                    Icons.workspace_premium_rounded,
                    size: 13,
                    color: AppColors.vipGold,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TabBar(
                controller: _tabController,
                indicatorColor: AppColors.primaryPurple,
                labelColor: AppColors.textPrimary,
                unselectedLabelColor: AppColors.textTertiary,
                indicatorSize: TabBarIndicatorSize.label,
                labelPadding: const EdgeInsets.symmetric(horizontal: 4),
                labelStyle: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                ),
                unselectedLabelStyle: const TextStyle(
                  fontWeight: FontWeight.w500,
                  fontSize: 15,
                ),
                dividerColor: Colors.transparent,
                tabs: const [
                  Tab(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text('Voice'),
                    ),
                  ),
                  Tab(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text('Live'),
                    ),
                  ),
                  Tab(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text('Learn'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 10),
            child: ElevatedButton.icon(
              onPressed: _openCreateRoomSheet,
              icon: const Icon(Icons.mic_rounded, size: 15),
              label: const Text(
                'Start',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primaryPurple,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
                minimumSize: const Size(0, 34),
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
        const MicEtiquetteBanner(),
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

class _VoiceRoomCard extends StatelessWidget {
  final VoiceRoom room;
  const _VoiceRoomCard({required this.room});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => openVoiceRoom(context, room),
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
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Host block: always the room's own denormalized host
                // fields (never waits on a live roster fetch to render
                // correctly) — avatar, name, and a gold "Host" badge so
                // there's no mistaking who's hosting.
                _Avatar(seed: room.hostName, imageUrl: room.hostAvatar, size: _kHostAvatarSize, isHost: true),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              room.hostName,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ),
                          const SizedBox(width: 4),
                          Text(room.hostFlag, style: const TextStyle(fontSize: 12)),
                        ],
                      ),
                      const SizedBox(height: 4),
                      const _HostBadge(),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                // Everyone else currently on stage — kept separate from,
                // and to the right of, the host block above so the two
                // never visually collide.
                _StageParticipants(room: room),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// Sizing shared between _StageParticipants and _OthersCluster below — kept
// as file-level constants (rather than nested inside one class) since both
// widgets need to agree on them and Dart privacy is per-library anyway.
const double _kHostAvatarSize = 44;
const double _kOtherAvatarSize = 28;
// Overlap only ever applies WITHIN the others cluster (each one tucked
// slightly behind the next) — the host avatar sits apart from this group
// entirely (see the Row in _VoiceRoomCard.build) rather than overlapping
// it, so there's never a mismatched-size collision to misread as a badge.
const double _kOtherOverlap = 8;
// Up to this many other stage members before folding the rest into a "+N"
// bubble — keeps the cluster's width predictable no matter how many people
// are actually on stage.
const int _kMaxOtherAvatars = 3;

/// A gold "Host" pill under the host's name — a second, explicit cue (on
/// top of the avatar's own gold ring — see [_Avatar]) so there's no
/// mistaking who's hosting even at a glance, matching the same gold =
/// "host" language voice_room_detail_screen.dart's speaker-grid star badge
/// already uses inside the room itself.
class _HostBadge extends StatelessWidget {
  const _HostBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.vipGold,
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.star_rounded, size: 10, color: Colors.white),
          SizedBox(width: 3),
          Text(
            'Host',
            style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: Colors.white),
          ),
        ],
      ),
    );
  }
}

/// Who else is on stage right now, at a glance — pinned to the right of the
/// card, opposite the host block, so the two never visually collide (see
/// _VoiceRoomCard.build). Replaces the old static "please mute your mic"
/// reminder chip (which only ever spoke to the host, about their own room,
/// after they'd already started it) with something every browser of the
/// feed benefits from: seeing who's actually speaking before deciding to
/// tap in, the same way Clubhouse/HelloTalk-style room cards do it.
///
/// Backed by a live [RoomParticipantService.streamParticipants] listener
/// (small subcollection, one listener per visible card — the same
/// per-list-item streaming pattern chat_list_screen.dart already uses for
/// live online dots), so it updates in real time as people join the stage
/// or leave — never a stale snapshot from whenever the room was created.
class _StageParticipants extends StatelessWidget {
  final VoiceRoom room;
  const _StageParticipants({required this.room});

  @override
  Widget build(BuildContext context) {
    // Decorative/mock rooms (see mock_data.dart) have no id and therefore no
    // real Firestore roster to stream.
    if (room.id.isEmpty) return const SizedBox.shrink();

    return StreamBuilder<List<RoomParticipant>>(
      stream: RoomParticipantService.streamParticipants(room.id),
      builder: (context, snapshot) {
        final roster = snapshot.data ?? const <RoomParticipant>[];
        // The host has their own dedicated avatar in the block on the left
        // (see _VoiceRoomCard.build) — excluded here by uid so they're
        // never shown twice.
        final nonHostSeated = roster.where((p) => p.isSeated && p.uid != room.hostId && !p.isEmptySeat).toList();
        final others = nonHostSeated.take(_kMaxOtherAvatars).toList();
        final overflow = nonHostSeated.length - others.length;
        return _OthersCluster(others: others, overflow: overflow);
      },
    );
  }
}

/// The other stage members (moderators/speakers, host excluded), fanned
/// out with a small, uniform overlap — all the same size, so — unlike
/// overlapping the differently-sized host — this reads as one tidy group
/// rather than a collision.
class _OthersCluster extends StatelessWidget {
  final List<RoomParticipant> others;
  final int overflow;
  const _OthersCluster({required this.others, required this.overflow});

  @override
  Widget build(BuildContext context) {
    final slots = others.length + (overflow > 0 ? 1 : 0);
    if (slots == 0) return const SizedBox.shrink();
    final width = _kOtherAvatarSize + (slots - 1) * (_kOtherAvatarSize - _kOtherOverlap);

    return SizedBox(
      width: width,
      height: _kOtherAvatarSize,
      child: Stack(
        clipBehavior: Clip.none,
        // Left-to-right paint order: each later avatar sits on top of the
        // one before it, the usual "fanned" look for a same-size group.
        children: [
          for (var i = 0; i < others.length; i++)
            Positioned(
              left: i * (_kOtherAvatarSize - _kOtherOverlap),
              child: _Avatar(seed: others[i].name, imageUrl: others[i].avatarUrl, size: _kOtherAvatarSize),
            ),
          if (overflow > 0)
            Positioned(
              left: others.length * (_kOtherAvatarSize - _kOtherOverlap),
              child: Container(
                width: _kOtherAvatarSize,
                height: _kOtherAvatarSize,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.primaryPurple.withValues(alpha: 0.14),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 1.5),
                ),
                child: Text(
                  '+$overflow',
                  style: const TextStyle(
                    fontSize: 9.5,
                    fontWeight: FontWeight.w800,
                    color: AppColors.primaryPurple,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  final String seed;
  final String imageUrl;
  final double size;
  final bool isHost;
  const _Avatar({
    required this.seed,
    required this.imageUrl,
    required this.size,
    this.isHost = false,
  });

  @override
  Widget build(BuildContext context) {
    return AppAvatar(
      seed: seed.isEmpty ? 'H' : seed,
      size: size,
      imageUrl: imageUrl,
      borderWidth: isHost ? 2.5 : 2,
      borderColor: isHost ? AppColors.vipGold : Colors.white,
    );
  }
}
