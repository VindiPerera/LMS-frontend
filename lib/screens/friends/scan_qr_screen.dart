import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../../services/friend_link_service.dart';
import '../../theme/app_colors.dart';
import 'friend_profile_screen.dart';

class ScanQRScreen extends StatefulWidget {
  const ScanQRScreen({super.key});

  @override
  State<ScanQRScreen> createState() => _ScanQRScreenState();
}

class _ScanQRScreenState extends State<ScanQRScreen> {
  bool _hasScanned = false;
  final MobileScannerController _scannerController = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
    facing: CameraFacing.back,
  );

  @override
  void dispose() {
    _scannerController.dispose();
    super.dispose();
  }

  void _handleBarcode(BarcodeCapture capture) {
    if (_hasScanned) return;

    final List<Barcode> barcodes = capture.barcodes;
    if (barcodes.isEmpty) return;

    final String? rawValue = barcodes.first.rawValue;
    if (rawValue == null || rawValue.isEmpty) return;

    _processQrData(rawValue);
  }

  void _processQrData(String rawData) {
    if (_hasScanned) return;

    final friendId = FriendLinkService.instance.extractFriendId(rawData);

    if (friendId == null || friendId.isEmpty) {
      _showSnackBar('Invalid QR code scanned');
      return;
    }

    // This screen is only reachable once signed in, so currentUser should
    // never be null here — but if Firebase Auth's session ever drops mid-scan,
    // fail with a real message rather than silently comparing against a
    // fabricated identity.
    final currentUid = FirebaseAuth.instance.currentUser?.uid;
    if (currentUid == null) {
      _showSnackBar('You were signed out. Please sign in again.');
      return;
    }

    if (friendId == currentUid) {
      _showSnackBar("That's your own code!");
      return;
    }

    setState(() => _hasScanned = true);

    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => FriendProfileScreen(
          friendId: friendId,
          source: 'qr',
        ),
      ),
    );
  }

  Future<void> _pickImageFromGallery() async {
    try {
      final ImagePicker picker = ImagePicker();
      final XFile? image = await picker.pickImage(source: ImageSource.gallery);
      if (image == null) return;

      final BarcodeCapture? capture = await _scannerController.analyzeImage(image.path);

      if (capture != null && capture.barcodes.isNotEmpty) {
        final String? rawValue = capture.barcodes.first.rawValue;
        if (rawValue != null && rawValue.isNotEmpty) {
          _processQrData(rawValue);
          return;
        }
      }

      _showSnackBar('No QR code found in image');
      setState(() => _hasScanned = false);
    } catch (_) {
      _showSnackBar('No QR code found in image');
      setState(() => _hasScanned = false);
    }
  }

  void _showSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          duration: const Duration(seconds: 2),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close_rounded, color: Colors.white, size: 26),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text(
          'Scan QR Code',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w700,
            fontSize: 18,
          ),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.flash_on_rounded, color: Colors.white),
            onPressed: () => _scannerController.toggleTorch(),
          ),
        ],
      ),
      body: Stack(
        children: [
          MobileScanner(
            controller: _scannerController,
            onDetect: _handleBarcode,
            errorBuilder: (context, error, child) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.camera_alt_outlined,
                        color: Colors.white70,
                        size: 56,
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'Camera permission needed to scan QR codes',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.white, fontSize: 16),
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: () => _scannerController.start(),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primaryPurple,
                        ),
                        child: const Text('Grant Permission'),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),

          // Scanning Overlay Frame
          Center(
            child: Container(
              width: 250,
              height: 250,
              decoration: BoxDecoration(
                border: Border.all(color: AppColors.primaryPurple, width: 3),
                borderRadius: BorderRadius.circular(24),
              ),
            ),
          ),

          // Bottom Action Bar (Gallery Upload)
          Positioned(
            bottom: 40,
            left: 0,
            right: 0,
            child: Column(
              children: [
                const Text(
                  'Align QR code within the frame',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 20),
                ElevatedButton.icon(
                  onPressed: _pickImageFromGallery,
                  icon: const Icon(Icons.photo_library_rounded, size: 20),
                  label: const Text(
                    'Upload from Gallery',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  style: ElevatedButton.styleFrom(
                    foregroundColor: Colors.white,
                    backgroundColor: Colors.white.withValues(alpha: 0.2),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 12,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(24),
                    ),
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
