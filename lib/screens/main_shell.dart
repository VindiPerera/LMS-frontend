import 'package:flutter/material.dart';
import '../services/chat_service.dart';
import '../theme/app_colors.dart';
import 'hellotalk/chat_list_screen.dart';
import 'connect/connect_screen.dart';
import 'moments/moments_screen.dart';
import 'voiceroom/voiceroom_screen.dart';
import 'me/me_screen.dart';

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _index = 0;
  late final Stream<int> _unreadStream = ChatService.streamTotalUnread();

  final _screens = const [
    ChatListScreen(),
    ConnectScreen(),
    MomentsScreen(),
    VoiceroomScreen(),
    MeScreen(),
  ];

  // The Message tab's unread badge is driven live by _unreadStream below,
  // not part of this static tab list.
  final _tabs = const [
    _TabSpec(
      'Message',
      Icons.chat_bubble_outline_rounded,
      Icons.chat_bubble_rounded,
    ),
    _TabSpec('Connect', Icons.groups_outlined, Icons.groups_rounded),
    _TabSpec('Moments', Icons.public_outlined, Icons.public_rounded),
    _TabSpec('Voiceroom', Icons.mic_none_rounded, Icons.mic_rounded),
    _TabSpec('Profile', Icons.person_outline_rounded, Icons.person_rounded),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _index, children: _screens),
      bottomNavigationBar: DecoratedBox(
        decoration: const BoxDecoration(
          color: AppColors.background,
          border: Border(top: BorderSide(color: AppColors.divider, width: 0.6)),
        ),
        child: SafeArea(
          top: false,
          child: SizedBox(
            height: 58,
            child: Row(
              children: List.generate(_tabs.length, (i) {
                final tab = _tabs[i];
                final selected = i == _index;
                return Expanded(
                  child: InkWell(
                    onTap: () => setState(() => _index = i),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Stack(
                          clipBehavior: Clip.none,
                          children: [
                            Icon(
                              selected ? tab.filledIcon : tab.icon,
                              color: selected
                                  ? AppColors.primaryPurple
                                  : AppColors.textTertiary,
                              size: 24,
                            ),
                            // Only the Message tab (index 0) has a live badge
                            // — real unread counts from ChatService.
                            if (i == 0)
                              StreamBuilder<int>(
                                stream: _unreadStream,
                                builder: (context, snapshot) {
                                  final count = snapshot.data ?? 0;
                                  if (count <= 0) {
                                    return const SizedBox.shrink();
                                  }
                                  return Positioned(
                                    right: -6,
                                    top: -4,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 4,
                                        vertical: 1,
                                      ),
                                      decoration: const BoxDecoration(
                                        color: AppColors.badgeRed,
                                        shape: BoxShape.circle,
                                      ),
                                      constraints: const BoxConstraints(
                                        minWidth: 16,
                                        minHeight: 16,
                                      ),
                                      child: Text(
                                        '$count',
                                        textAlign: TextAlign.center,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 10,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              ),
                          ],
                        ),
                        const SizedBox(height: 3),
                        Text(
                          tab.label,
                          style: TextStyle(
                            fontSize: 11,
                            color: selected
                                ? AppColors.primaryPurple
                                : AppColors.textTertiary,
                            fontWeight: selected
                                ? FontWeight.w600
                                : FontWeight.w400,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }),
            ),
          ),
        ),
      ),
    );
  }
}

class _TabSpec {
  final String label;
  final IconData icon;
  final IconData filledIcon;
  const _TabSpec(this.label, this.icon, this.filledIcon);
}
