import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../data/mock_data.dart';
import '../../theme/app_colors.dart';

/// Modal screen that slides up smoothly from bottom to top.
class AddContactScreen extends StatelessWidget {
  const AddContactScreen({super.key});

  /// Helper method to present AddContactScreen as a smooth bottom-to-top modal sheet
  static void show(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const AddContactScreen(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final userHandle = '@${currentUser.handle}';

    return Container(
      decoration: const BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      clipBehavior: Clip.antiAlias,
      child: FractionallySizedBox(
        heightFactor: 0.94,
        child: Scaffold(
          backgroundColor: AppColors.background,
          appBar: AppBar(
            backgroundColor: AppColors.background,
            elevation: 0,
            centerTitle: true,
            leading: IconButton(
              icon: const Icon(Icons.close_rounded, color: AppColors.textPrimary, size: 26),
              onPressed: () => Navigator.of(context).pop(),
            ),
            title: const Text(
              'Add',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 19,
                color: AppColors.textPrimary,
              ),
            ),
          ),
          body: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: Column(
              children: [
                // Search Input
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFECECEF),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    children: const [
                      Icon(Icons.search_rounded, color: AppColors.textTertiary, size: 22),
                      SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Search FaceTalk ID',
                          style: TextStyle(
                            color: AppColors.textTertiary,
                            fontSize: 15,
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                // Action Items Card
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(18),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.03),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      _ActionTile(
                        icon: Icons.group_add_outlined,
                        label: 'Create Group Chat',
                        onTap: () {},
                      ),
                      const Divider(height: 1, indent: 56, color: AppColors.divider),
                      _ActionTile(
                        icon: Icons.crop_free_rounded,
                        label: 'Scan QR Code',
                        onTap: () {},
                      ),
                      const Divider(height: 1, indent: 56, color: AppColors.divider),
                      _ActionTile(
                        icon: Icons.mail_outline_rounded,
                        label: 'Invite',
                        onTap: () {},
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 32),

                // My FaceTalk ID Title & Handle
                const Text(
                  'My FaceTalk ID',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                GestureDetector(
                  onTap: () {
                    Clipboard.setData(ClipboardData(text: userHandle));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('FaceTalk ID copied to clipboard'),
                        duration: Duration(seconds: 2),
                      ),
                    );
                  },
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        userHandle,
                        style: const TextStyle(
                          fontSize: 14,
                          color: AppColors.textSecondary,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(width: 4),
                      const Icon(
                        Icons.copy_rounded,
                        size: 14,
                        color: AppColors.textTertiary,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),

                // QR Code Box
                Container(
                  width: 210,
                  height: 210,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.05),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: CustomPaint(
                    painter: QrCodePainter(),
                  ),
                ),
                const SizedBox(height: 24),

                // Share QR Code Pill Button
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Sharing QR Code...')),
                      );
                    },
                    icon: const Icon(Icons.upload_rounded, size: 20, color: Colors.white),
                    label: const Text(
                      'Share QR Code',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primaryPurple,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(26),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 10),

                // Save as Image Button
                TextButton(
                  onPressed: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Saved QR Code to gallery')),
                    );
                  },
                  child: const Text(
                    'Save as Image',
                    style: TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textTertiary,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _ActionTile({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        child: Row(
          children: [
            Icon(icon, size: 23, color: AppColors.textPrimary),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                label,
                style: const TextStyle(
                  fontSize: 15.5,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
            const Icon(
              Icons.chevron_right_rounded,
              size: 22,
              color: AppColors.textTertiary,
            ),
          ],
        ),
      ),
    );
  }
}

/// Custom painter that draws an authentic 2D Barcode / QR Code pattern
class QrCodePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.black;
    final moduleSize = size.width / 21;

    // Corner Finder Patterns (Top-Left, Top-Right, Bottom-Left)
    _drawFinderPattern(canvas, 0, 0, moduleSize);
    _drawFinderPattern(canvas, 14 * moduleSize, 0, moduleSize);
    _drawFinderPattern(canvas, 0, 14 * moduleSize, moduleSize);

    // Matrix modules (deterministic pattern)
    final matrix = [
      [0,0,0,0,0,0,0, 0, 1,0,1,1,0, 0,0,0,0,0,0,0],
      [0,1,1,1,1,1,0, 1, 0,1,0,0,1, 0,1,1,1,1,1,0],
      [0,1,0,0,0,1,0, 0, 1,1,1,0,0, 0,1,0,0,0,1,0],
      [0,1,0,0,0,1,0, 1, 0,0,1,1,1, 0,1,0,0,0,1,0],
      [0,1,0,0,0,1,0, 0, 1,0,1,0,0, 0,1,0,0,0,1,0],
      [0,1,1,1,1,1,0, 1, 1,1,0,1,1, 0,1,1,1,1,1,0],
      [0,0,0,0,0,0,0, 0, 1,0,1,0,0, 0,0,0,0,0,0,0],
      [1,0,1,1,0,1,0, 1, 0,1,1,0,1, 1,0,1,1,0,1,1],
      [0,1,0,0,1,0,1, 0, 1,0,0,1,0, 0,1,0,1,0,0,1],
      [1,1,1,0,1,1,0, 1, 1,1,0,1,1, 1,0,1,0,1,1,0],
      [0,0,1,1,0,0,1, 0, 0,1,1,0,0, 0,1,1,1,0,0,1],
      [1,1,0,0,1,1,0, 1, 1,0,1,1,0, 1,0,0,1,1,1,0],
      [0,0,0,0,0,0,0, 0, 1,1,0,0,1, 0,1,0,1,0,0,1],
      [0,0,0,0,0,0,0, 1, 0,1,1,0,0, 0,0,0,0,0,0,0],
      [0,1,1,1,1,1,0, 0, 1,0,0,1,1, 1,0,1,1,1,0,1],
      [0,1,0,0,0,1,0, 1, 1,1,0,1,0, 0,1,0,0,1,1,0],
      [0,1,0,0,0,1,0, 0, 0,1,1,0,1, 1,0,1,1,0,0,1],
      [0,1,0,0,0,1,0, 1, 1,0,0,1,0, 0,1,0,0,1,1,0],
      [0,1,1,1,1,1,0, 0, 1,1,1,0,1, 1,0,1,1,0,1,1],
      [0,0,0,0,0,0,0, 1, 0,0,1,1,0, 0,1,0,0,1,0,0],
    ];

    for (int r = 0; r < matrix.length; r++) {
      for (int c = 0; c < matrix[r].length; c++) {
        if (matrix[r][c] == 1) {
          canvas.drawRect(
            Rect.fromLTWH(
              c * moduleSize,
              r * moduleSize,
              moduleSize + 0.3,
              moduleSize + 0.3,
            ),
            paint,
          );
        }
      }
    }
  }

  void _drawFinderPattern(Canvas canvas, double x, double y, double ms) {
    final paintDark = Paint()..color = Colors.black;
    final paintWhite = Paint()..color = Colors.white;

    // Outer 7x7 square
    canvas.drawRect(Rect.fromLTWH(x, y, 7 * ms, 7 * ms), paintDark);
    // Inner 5x5 white square
    canvas.drawRect(Rect.fromLTWH(x + ms, y + ms, 5 * ms, 5 * ms), paintWhite);
    // Center 3x3 dark square
    canvas.drawRect(Rect.fromLTWH(x + 2 * ms, y + 2 * ms, 3 * ms, 3 * ms), paintDark);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
