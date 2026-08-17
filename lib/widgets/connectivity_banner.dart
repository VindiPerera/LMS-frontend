import 'dart:async';

import 'package:flutter/material.dart';

import '../services/connectivity_service.dart';
import '../theme/app_colors.dart';

/// Persistent red "No internet connection" banner while offline; briefly
/// shows a green "Back online" banner for 2s on reconnect, then collapses
/// to nothing. Sits at the top of moments_screen.dart's body.
class ConnectivityBanner extends StatefulWidget {
  const ConnectivityBanner({super.key});

  @override
  State<ConnectivityBanner> createState() => _ConnectivityBannerState();
}

class _ConnectivityBannerState extends State<ConnectivityBanner> {
  StreamSubscription<bool>? _subscription;
  bool? _online;
  bool _showBackOnline = false;
  Timer? _hideTimer;

  @override
  void initState() {
    super.initState();
    _subscription = ConnectivityService.instance.onlineStatus.listen(_handleUpdate);
  }

  void _handleUpdate(bool online) {
    if (!mounted) return;
    final reconnected = online && _online == false;
    setState(() {
      _online = online;
      if (reconnected) {
        _showBackOnline = true;
        _hideTimer?.cancel();
        _hideTimer = Timer(const Duration(seconds: 2), () {
          if (mounted) setState(() => _showBackOnline = false);
        });
      }
    });
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _hideTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    Widget child = const SizedBox.shrink();
    if (_online == false) {
      child = const _Banner(
        key: ValueKey('offline'),
        color: AppColors.badgeRed,
        icon: Icons.wifi_off_rounded,
        text: 'No internet connection',
      );
    } else if (_showBackOnline) {
      child = const _Banner(
        key: ValueKey('online'),
        color: AppColors.online,
        icon: Icons.wifi_rounded,
        text: 'Back online',
      );
    }

    return AnimatedSize(
      duration: const Duration(milliseconds: 200),
      alignment: Alignment.topCenter,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 200),
        child: child,
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  final Color color;
  final IconData icon;
  final String text;

  const _Banner({
    super.key,
    required this.color,
    required this.icon,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: color,
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 14, color: Colors.white),
          const SizedBox(width: 6),
          Text(
            text,
            style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}
