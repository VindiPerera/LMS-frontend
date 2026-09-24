import 'package:flutter/material.dart';

import '../../models/user.dart';
import '../../theme/app_colors.dart';

/// Monthly calendar view of the signed-in user's VIP subscription window —
/// opened from the "VIP Calendar" row on the profile tab (me_screen.dart),
/// only shown while `user.isVip` is true.
///
/// There's no VIP purchase flow wired up yet, so [AppUser.vipExpiresAt] is
/// usually null even for a VIP user — in that case this falls back to a
/// 30-day window starting today, just so the calendar has something real to
/// show. Once a real subscription flow sets `vipExpiresAt` on the user
/// document, this picks that up automatically.
class VipCalendarScreen extends StatefulWidget {
  final AppUser user;
  const VipCalendarScreen({super.key, required this.user});

  @override
  State<VipCalendarScreen> createState() => _VipCalendarScreenState();
}

class _VipCalendarScreenState extends State<VipCalendarScreen> {
  static const _weekdayLabels = ['SUN', 'MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT'];
  static const _monthNames = [
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December',
  ];

  late final DateTime _expiresOn = widget.user.vipExpiresAt ??
      DateTime.now().add(const Duration(days: 30));
  late final DateTime _startsOn = widget.user.vipExpiresAt != null
      ? _expiresOn.subtract(const Duration(days: 30))
      : DateTime.now();

  late DateTime _visibleMonth = DateTime(_startsOn.year, _startsOn.month);

  DateTime _stripTime(DateTime d) => DateTime(d.year, d.month, d.day);

  bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  bool _isInVipRange(DateTime day) {
    final d = _stripTime(day);
    return !d.isBefore(_stripTime(_startsOn)) && !d.isAfter(_stripTime(_expiresOn));
  }

  void _changeMonth(int delta) {
    setState(() => _visibleMonth = DateTime(_visibleMonth.year, _visibleMonth.month + delta));
  }

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now();
    final daysLeft = _stripTime(_expiresOn).difference(_stripTime(today)).inDays;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        title: const Text('VIP membership calendar', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildMonthNav(),
          const SizedBox(height: 12),
          _buildWeekdayHeader(),
          const SizedBox(height: 6),
          _buildMonthGrid(),
          const SizedBox(height: 20),
          _buildSummaryCard(daysLeft),
        ],
      ),
    );
  }

  Widget _buildMonthNav() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        _navButton(Icons.chevron_left_rounded, () => _changeMonth(-1)),
        Text(
          '${_monthNames[_visibleMonth.month - 1]} ${_visibleMonth.year}',
          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: AppColors.textPrimary),
        ),
        _navButton(Icons.chevron_right_rounded, () => _changeMonth(1)),
      ],
    );
  }

  Widget _navButton(IconData icon, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        width: 36,
        height: 36,
        decoration: const BoxDecoration(color: AppColors.surfaceLight, shape: BoxShape.circle),
        child: Icon(icon, color: AppColors.textSecondary),
      ),
    );
  }

  Widget _buildWeekdayHeader() {
    return Row(
      children: _weekdayLabels
          .map((label) => Expanded(
                child: Center(
                  child: Text(
                    label,
                    style: const TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textTertiary,
                    ),
                  ),
                ),
              ))
          .toList(),
    );
  }

  Widget _buildMonthGrid() {
    final firstOfMonth = DateTime(_visibleMonth.year, _visibleMonth.month, 1);
    final daysInMonth = DateTime(_visibleMonth.year, _visibleMonth.month + 1, 0).day;
    // DateTime.weekday is Mon=1..Sun=7; this calendar starts on Sunday, so
    // Sunday needs a leading-blank count of 0, Monday 1, ... Saturday 6.
    final leadingBlanks = firstOfMonth.weekday % 7;
    final today = DateTime.now();

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 7),
      itemCount: leadingBlanks + daysInMonth,
      itemBuilder: (context, index) {
        if (index < leadingBlanks) return const SizedBox.shrink();

        final day = index - leadingBlanks + 1;
        final date = DateTime(_visibleMonth.year, _visibleMonth.month, day);
        final isToday = _isSameDay(date, today);
        final inRange = _isInVipRange(date);
        final isBoundary = _isSameDay(date, _startsOn) || _isSameDay(date, _expiresOn);

        return Padding(
          padding: const EdgeInsets.all(3),
          child: Container(
            decoration: BoxDecoration(
              color: isToday
                  ? AppColors.primaryPurple
                  : inRange
                      ? AppColors.vipCardBg
                      : Colors.transparent,
              shape: BoxShape.circle,
              border: isBoundary && !isToday ? Border.all(color: AppColors.vipGold, width: 1.5) : null,
            ),
            alignment: Alignment.center,
            child: Text(
              '$day',
              style: TextStyle(
                fontSize: 13,
                fontWeight: isToday || isBoundary ? FontWeight.w800 : FontWeight.w500,
                color: isToday
                    ? Colors.white
                    : inRange
                        ? AppColors.vipCardText
                        : AppColors.textPrimary,
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildSummaryCard(int daysLeft) {
    final expired = daysLeft < 0;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.vipCardBg,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('👑', style: TextStyle(fontSize: 16)),
              const SizedBox(width: 6),
              Text(
                expired ? 'VIP subscription expired' : 'VIP subscription active',
                style: TextStyle(
                  color: AppColors.vipCardText,
                  fontWeight: FontWeight.w800,
                  fontSize: 14.5,
                ),
              ),
              const Spacer(),
              if (!expired)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(color: AppColors.vipGold, borderRadius: BorderRadius.circular(10)),
                  child: Text(
                    '$daysLeft day${daysLeft == 1 ? '' : 's'} left',
                    style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w800),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 14),
          _dateRow('Start date', _startsOn),
          const SizedBox(height: 8),
          _dateRow('Expires on', _expiresOn),
        ],
      ),
    );
  }

  Widget _dateRow(String label, DateTime date) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: TextStyle(color: AppColors.vipCardText.withValues(alpha: 0.7), fontSize: 13)),
        Text(
          '${_monthNames[date.month - 1].substring(0, 3)} ${date.day}, ${date.year}',
          style: TextStyle(color: AppColors.vipCardText, fontWeight: FontWeight.w700, fontSize: 13),
        ),
      ],
    );
  }
}
