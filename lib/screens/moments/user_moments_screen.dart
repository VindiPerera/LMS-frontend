import 'package:flutter/material.dart';

import '../../models/moment.dart';
import '../../services/moment_service.dart';
import '../../theme/app_colors.dart';
import '../../widgets/moment_card.dart';

class UserMomentsScreen extends StatefulWidget {
  final String userId;
  final String userName;

  const UserMomentsScreen({
    super.key,
    required this.userId,
    required this.userName,
  });

  @override
  State<UserMomentsScreen> createState() => _UserMomentsScreenState();
}

class _UserMomentsScreenState extends State<UserMomentsScreen> {
  late final Stream<List<Moment>> _momentsStream =
      MomentService.streamUserMoments(userId: widget.userId);
  final Set<String> _removedIds = {};

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios_new_rounded,
            color: AppColors.textPrimary,
            size: 20,
          ),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          "${widget.userName}'s Moments",
          style: const TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 18,
            color: AppColors.textPrimary,
          ),
        ),
      ),
      body: StreamBuilder<List<Moment>>(
        stream: _momentsStream,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(
                strokeWidth: 2.4,
                color: AppColors.primaryPurple,
              ),
            );
          }

          final moments = (snapshot.data ?? const [])
              .where((m) => !_removedIds.contains(m.id))
              .toList();

          if (moments.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 64,
                      height: 64,
                      decoration: BoxDecoration(
                        color: AppColors.primaryPurple.withValues(alpha: 0.1),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.collections_bookmark_outlined,
                        size: 30,
                        color: AppColors.primaryPurple,
                      ),
                    ),
                    const SizedBox(height: 14),
                    const Text(
                      'No moments posted yet',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${widget.userName} hasn\'t shared any moments yet.',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.only(bottom: 20),
            itemCount: moments.length,
            itemBuilder: (context, index) {
              final moment = moments[index];
              return MomentCard(
                key: ValueKey(moment.id),
                moment: moment,
                onDeleted: () => setState(() => _removedIds.add(moment.id)),
                onReported: () => setState(() => _removedIds.add(moment.id)),
              );
            },
          );
        },
      ),
    );
  }
}
