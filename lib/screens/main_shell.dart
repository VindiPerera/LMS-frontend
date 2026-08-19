import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../services/chat_service.dart';
import '../services/notification_service.dart';
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

class _MainShellState extends State<MainShell> with WidgetsBindingObserver {
  int _index = 0;
  late final Stream<int> _unreadStream = ChatService.streamTotalUnread();
  late final Stream<int> _notificationUnreadStream = NotificationService.streamUnreadCount();

  final _screens = const [
    ChatListScreen(),
    ConnectScreen(),
    MomentsScreen(),
    VoiceroomScreen(),
    MeScreen(),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // MainShell only ever mounts post-login, so this covers "already
    // signed in and the app just launched" — AuthService's own
    // _afterSignIn() covers the moment of signing in itself.
    AuthService.instance.setOnlineStatus(true);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // resumed = back in the foreground; everything else (paused, inactive,
    // hidden, detached) is some flavor of "not actively in front of the
    // user right now" — see AuthService.setOnlineStatus's doc comment for
    // the one gap this doesn't cover (an abrupt kill skips this entirely).
    switch (state) {
      case AppLifecycleState.resumed:
        AuthService.instance.setOnlineStatus(true);
        break;
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
        AuthService.instance.setOnlineStatus(false);
        break;
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
        break;
    }
  }

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
                            // Message (index 0) and Moments (index 2) are
                            // the only tabs with a live unread badge — chat
                            // unread count and Moments notification count,
                            // respectively.
                            if (i == 0 || i == 2)
                              StreamBuilder<int>(
                                stream: i == 0 ? _unreadStream : _notificationUnreadStream,
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
