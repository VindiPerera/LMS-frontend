import 'package:flutter/material.dart';

import '../../services/auth_service.dart';
import '../../theme/app_colors.dart';

/// Settings > Notifications. Currently a single toggle for Voice Room
/// invite pushes ("X invited you to a Voice Room") — the only notification
/// type in the app that comes from a single other user's action rather than
/// something the signed-in user opted into directly (a chat, a friend
/// request). More toggles can be added here later following the same
/// pattern: a bool field on `users/{uid}`, checked by the specific send
/// site it gates (see NotificationService.voiceRoomNotificationsEnabledFor),
/// never inside the shared NotificationApiService.sendPush.
class NotificationSettingsScreen extends StatefulWidget {
  const NotificationSettingsScreen({super.key});

  @override
  State<NotificationSettingsScreen> createState() => _NotificationSettingsScreenState();
}

class _NotificationSettingsScreenState extends State<NotificationSettingsScreen> {
  late bool _voiceRoomEnabled =
      AuthService.instance.currentUser?.voiceRoomNotificationsEnabled ?? true;
  bool _saving = false;

  Future<void> _toggleVoiceRoom(bool value) async {
    final previous = _voiceRoomEnabled;
    setState(() {
      _voiceRoomEnabled = value;
      _saving = true;
    });
    try {
      await AuthService.instance.setVoiceRoomNotificationsEnabled(value);
    } catch (e) {
      if (!mounted) return;
      setState(() => _voiceRoomEnabled = previous);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not update setting: ${e.toString().replaceFirst('Exception: ', '')}')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        centerTitle: true,
        title: const Text(
          'Notifications',
          style: TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 18,
            color: AppColors.textPrimary,
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Padding(
            padding: EdgeInsets.only(bottom: 8, left: 4),
            child: Text(
              'VOICE ROOM',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5,
                color: AppColors.textTertiary,
              ),
            ),
          ),
          Material(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(14),
            clipBehavior: Clip.antiAlias,
            child: SwitchListTile(
              value: _voiceRoomEnabled,
              onChanged: _saving ? null : _toggleVoiceRoom,
              activeTrackColor: AppColors.primaryPurple,
              title: const Text(
                'Voice Room invites',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
              ),
              subtitle: const Text(
                'Get notified when a friend invites you to a Voice Room they’ve started.',
                style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
              ),
            ),
          ),
          const Padding(
            padding: EdgeInsets.only(top: 10, left: 4, right: 4),
            child: Text(
              'Turning this off only mutes Voice Room invites — your other notifications, like chats and friend requests, keep working as usual.',
              style: TextStyle(fontSize: 12, color: AppColors.textTertiary),
            ),
          ),
        ],
      ),
    );
  }
}
