import 'package:flutter/material.dart';

import '../../models/moment.dart';
import '../../services/moment_service.dart';
import '../../theme/app_colors.dart';
import '../../widgets/moment_card.dart';

/// Single-post view, opened by deep links (push notification tap, or a
/// notification_screen.dart row) rather than from the feed itself.
class PostDetailScreen extends StatefulWidget {
  final String postId;

  const PostDetailScreen({super.key, required this.postId});

  @override
  State<PostDetailScreen> createState() => _PostDetailScreenState();
}

class _PostDetailScreenState extends State<PostDetailScreen> {
  late final Stream<Moment?> _momentStream = MomentService.streamMoment(widget.postId);
  bool _removed = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        title: const Text('Moment', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
      ),
      body: _removed
          ? const _MissingPost()
          : StreamBuilder<Moment?>(
              stream: _momentStream,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator(color: AppColors.primaryPurple));
                }
                final moment = snapshot.data;
                if (moment == null || moment.isDeleted) {
                  return const _MissingPost();
                }
                return SingleChildScrollView(
                  child: MomentCard(
                    moment: moment,
                    onDeleted: () => setState(() => _removed = true),
                  ),
                );
              },
            ),
    );
  }
}

class _MissingPost extends StatelessWidget {
  const _MissingPost();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.link_off_rounded, size: 40, color: AppColors.textTertiary),
            SizedBox(height: 12),
            Text(
              'This moment is no longer available',
              textAlign: TextAlign.center,
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: AppColors.textPrimary),
            ),
          ],
        ),
      ),
    );
  }
}
