import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../models/item_model.dart';

import '../../services/mobile_api_service.dart';
import '../user/item_details_screen.dart';
import '../user/catalog_screen.dart';
import '../user/active_rentals_screen.dart';
import '../rental/rental_history_screen.dart';
import '../profile/profile_screen.dart';
import '../user/return_equipment_screen.dart';

class QRScannerScreen extends StatefulWidget {
  final String initialMode; // "Rent" or "Return"

  const QRScannerScreen({
    super.key,
    this.initialMode = 'Rent',
  });

  @override
  State<QRScannerScreen> createState() => _QRScannerScreenState();
}

class _QRScannerScreenState extends State<QRScannerScreen> {
  late String _mode;
  final MobileScannerController _controller = MobileScannerController();
  bool _isProcessing = false;
  final int _currentIndex = 1; // Scan tab

  @override
  void initState() {
    super.initState();
    _mode = widget.initialMode;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onNavTap(int index) {
    if (index == _currentIndex) return;
    Widget target;
    switch (index) {
      case 0:
        target = const CatalogScreen();
        break;
      case 1:
        return;
      case 2:
        target = const ActiveRentalsScreen();
        break;
      case 3:
        target = const RentalHistoryScreen();
        break;
      case 4:
        target = const ProfileScreen();
        break;
      default:
        return;
    }
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => target),
    );
  }

  void _onDetect(BarcodeCapture capture) async {
    if (_isProcessing) return;

    final List<Barcode> barcodes = capture.barcodes;
    if (barcodes.isEmpty) return;

    final String? scannedCode = barcodes.first.rawValue;
    if (scannedCode == null || scannedCode.trim().isEmpty) return;

    setState(() => _isProcessing = true);

    try {
      final code = scannedCode.trim();
      final api = MobileApiService.instance;
      final record = await api.resolveEquipment(code);
      if (!mounted) return;
      if (_mode == 'Rent') {
        final item = ItemModel.fromMap(record, id: record['id'].toString());
        Navigator.pushReplacement(context,
            MaterialPageRoute(builder: (_) => ItemDetailsScreen(item: item)));
      } else {
        final rentals = await api.listRentals();
        final matches = rentals
            .where((rental) => rental.isActive && rental.itemId == record['id'])
            .toList();
        if (!mounted) return;
        if (matches.length != 1)
          throw const MobileApiException(
              'No active rental for this unit belongs to your account.');
        Navigator.pushReplacement(
            context,
            MaterialPageRoute(
                builder: (_) => ReturnEquipmentScreen(rental: matches.single)));
      }
    } catch (e) {
      debugPrint('QR Code Scan / Firestore Error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Scanner error: $e'), backgroundColor: Colors.red),
        );
        setState(() => _isProcessing = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title:
            const Text('Scan', style: TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: false,
        actions: [
          IconButton(
            icon: ValueListenableBuilder(
              valueListenable: _controller,
              builder: (context, state, child) {
                return Icon(
                  state.torchState == TorchState.on
                      ? Icons.flash_on
                      : Icons.flash_off,
                );
              },
            ),
            onPressed: () => _controller.toggleTorch(),
          ),
          IconButton(
            icon: const Icon(Icons.cameraswitch),
            onPressed: () => _controller.switchCamera(),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Scan Equipment QR',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: Color(0xFF0F172A),
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'Use the camera to find the correct equipment record.',
              style: TextStyle(color: Colors.grey, fontSize: 13),
            ),
            const SizedBox(height: 16),

            // Scanner Box Preview
            Container(
              height: 280,
              width: double.infinity,
              decoration: BoxDecoration(
                color: const Color(0xFF0F172A),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Stack(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: MobileScanner(
                      controller: _controller,
                      onDetect: _onDetect,
                    ),
                  ),
                  // Orange brackets / overlay frame
                  Center(
                    child: Container(
                      width: 230,
                      height: 230,
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.transparent),
                      ),
                      child: Stack(
                        children: [
                          // Top-left bracket
                          Positioned(
                              top: 0,
                              left: 0,
                              child: _buildBracket(true, true)),
                          // Top-right bracket
                          Positioned(
                              top: 0,
                              right: 0,
                              child: _buildBracket(true, false)),
                          // Bottom-left bracket
                          Positioned(
                              bottom: 0,
                              left: 0,
                              child: _buildBracket(false, true)),
                          // Bottom-right bracket
                          Positioned(
                              bottom: 0,
                              right: 0,
                              child: _buildBracket(false, false)),

                          // Center scanner UI
                          Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Text(
                                  'ALIGN QR CODE',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 1.2,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Container(
                                  height: 2,
                                  width: 160,
                                  color: Colors.red,
                                ),
                                const SizedBox(height: 16),
                                Container(
                                  width: 50,
                                  height: 50,
                                  decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: 0.15),
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Center(
                                    child: Icon(Icons.qr_code_scanner,
                                        color: Colors.white, size: 26),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // Transaction Type Header & Buttons
            const Text(
              'Transaction type',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 48,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _mode == 'Rent'
                            ? const Color(0xFFF57C00)
                            : Colors.white,
                        foregroundColor:
                            _mode == 'Rent' ? Colors.white : Colors.black87,
                        elevation: _mode == 'Rent' ? 2 : 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(
                            color: _mode == 'Rent'
                                ? const Color(0xFFF57C00)
                                : Colors.grey.shade300,
                          ),
                        ),
                      ),
                      onPressed: () => setState(() => _mode = 'Rent'),
                      child: const Text(
                        'Rent',
                        style: TextStyle(
                            fontSize: 15, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: SizedBox(
                    height: 48,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _mode == 'Return'
                            ? const Color(0xFFF57C00)
                            : Colors.white,
                        foregroundColor:
                            _mode == 'Return' ? Colors.white : Colors.black87,
                        elevation: _mode == 'Return' ? 2 : 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(
                            color: _mode == 'Return'
                                ? const Color(0xFFF57C00)
                                : Colors.grey.shade300,
                          ),
                        ),
                      ),
                      onPressed: () => setState(() => _mode = 'Return'),
                      child: const Text(
                        'Return',
                        style: TextStyle(
                            fontSize: 15, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 20),

            // QR Scan Note Card
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.blue.shade200),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.info_outline,
                          size: 18, color: Colors.blue.shade800),
                      const SizedBox(width: 8),
                      Text(
                        'QR scan note',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                          color: Colors.blue.shade800,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Scan to view equipment or request its return. The admin confirms physical release and receipt.',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.blue.shade900,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: _onNavTap,
        type: BottomNavigationBarType.fixed,
        selectedItemColor: const Color(0xFFF57C00),
        unselectedItemColor: Colors.grey,
        selectedFontSize: 11,
        unselectedFontSize: 11,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.home_outlined),
            activeIcon: Icon(Icons.home),
            label: 'Home',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.qr_code_scanner_outlined),
            activeIcon: Icon(Icons.qr_code_scanner),
            label: 'Scan',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.swap_horiz),
            activeIcon: Icon(Icons.swap_horiz),
            label: 'Rentals',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.article_outlined),
            activeIcon: Icon(Icons.article),
            label: 'History',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.person_outline),
            activeIcon: Icon(Icons.person),
            label: 'Profile',
          ),
        ],
      ),
    );
  }

  Widget _buildBracket(bool isTop, bool isLeft) {
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        border: Border(
          top: isTop
              ? const BorderSide(color: Color(0xFFF57C00), width: 3.5)
              : BorderSide.none,
          bottom: !isTop
              ? const BorderSide(color: Color(0xFFF57C00), width: 3.5)
              : BorderSide.none,
          left: isLeft
              ? const BorderSide(color: Color(0xFFF57C00), width: 3.5)
              : BorderSide.none,
          right: !isLeft
              ? const BorderSide(color: Color(0xFFF57C00), width: 3.5)
              : BorderSide.none,
        ),
      ),
    );
  }
}
