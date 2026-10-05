import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../models/rental_model.dart';
import '../../services/rental_service.dart';
import '../../services/esp32_service.dart';
import '../user/catalog_screen.dart';
import 'connection_error_screen.dart';

class WaitingEsp32Screen extends StatefulWidget {
  final RentalModel rental;
  final bool isReturn;

  const WaitingEsp32Screen({
    super.key,
    required this.rental,
    this.isReturn = false,
  });

  @override
  State<WaitingEsp32Screen> createState() => _WaitingEsp32ScreenState();
}

class _WaitingEsp32ScreenState extends State<WaitingEsp32Screen> {
  bool _isProcessingSuccess = false;
  int _secondsRemaining = 60; // 60-second countdown timer for ESP32 hardware verification
  Timer? _countdownTimer;
  StreamSubscription? _connectionSub;

  @override
  void initState() {
    super.initState();
    _start60SecondCountdown();
    _initiateHardwareSync();
    _listenToConnectionStatus();
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _connectionSub?.cancel();
    super.dispose();
  }

  // 60-Second Countdown Timer for Terminal Confirmation
  void _start60SecondCountdown() {
    _countdownTimer?.cancel();
    setState(() => _secondsRemaining = 60);

    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      if (_secondsRemaining > 1) {
        setState(() => _secondsRemaining--);
      } else {
        _countdownTimer?.cancel();
        _handleTimeoutCancel();
      }
    });
  }

  // Handle 60s Timeout Failure
  void _handleTimeoutCancel() async {
    if (_isProcessingSuccess) return;

    final rentalService = Provider.of<RentalService>(context, listen: false);
    await rentalService.cancelTransaction(widget.rental.rentalId, '60-second ESP32 hardware timeout');

    if (!mounted) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.error_outline, color: Colors.red, size: 28),
            SizedBox(width: 8),
            Text('Verification Timed Out'),
          ],
        ),
        content: const Text(
          'The ESP32 operator terminal did not confirm the request within 60 seconds. The transaction has been cancelled safely.',
        ),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            onPressed: () {
              Navigator.of(ctx).pop();
              Navigator.pushAndRemoveUntil(
                context,
                MaterialPageRoute(builder: (_) => const CatalogScreen()),
                (route) => false,
              );
            },
            child: const Text('Return to Catalog'),
          ),
        ],
      ),
    );
  }

  void _listenToConnectionStatus() {
    final esp32Service = Provider.of<Esp32Service>(context, listen: false);
    _connectionSub = esp32Service.streamConnectionStatus().listen((event) {
      final isConnected = (event.snapshot.value as bool?) ?? false;
      if (!isConnected && mounted && !_isProcessingSuccess) {
        _navigateToConnectionError('Realtime Database Disconnected');
      }
    });
  }

  void _navigateToConnectionError([String? reason]) {
    _countdownTimer?.cancel();
    if (!mounted) return;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ConnectionErrorScreen(
          terminalId: widget.rental.terminalId,
          onRetry: () {
            Navigator.pop(context);
            _handleTransactionSuccess(); // Bypass offline terminal and complete transaction locally
          },
          onBack: () {
            Navigator.pushAndRemoveUntil(
              context,
              MaterialPageRoute(builder: (_) => const CatalogScreen()),
              (route) => false,
            );
          },
        ),
      ),
    );
  }

  void _initiateHardwareSync() async {
    final esp32Service = Provider.of<Esp32Service>(context, listen: false);

    bool success;
    if (widget.isReturn) {
      success = await esp32Service.initiateReturnHardwareVerification(
        widget.rental.terminalId,
        widget.rental.rentalId,
      );
    } else {
      success = await esp32Service.initiateRentalHardwareVerification(
        widget.rental.terminalId,
        widget.rental.rentalId,
      );
    }

    if (!success && mounted) {
      _navigateToConnectionError('Failed to sync state with ESP32 terminal');
    }
  }

  // Handle Hardware Confirmation Success (Triggered when Firestore status becomes RENTED or COMPLETED)
  Future<void> _handleTransactionSuccess() async {
    if (_isProcessingSuccess) return;
    _countdownTimer?.cancel();
    setState(() => _isProcessingSuccess = true);

    // Audio & Haptic Feedback on Success
    try {
      await HapticFeedback.vibrate();
      await HapticFeedback.lightImpact();
    } catch (_) {}

    if (!mounted) return;

    try {
      final esp32Service = Provider.of<Esp32Service>(context, listen: false);
      final rentalService = Provider.of<RentalService>(context, listen: false);

      await rentalService.confirmHardwareTransaction(
        transactionId: widget.rental.rentalId,
        itemId: widget.rental.itemId,
        isReturn: widget.isReturn,
      );

      await esp32Service.resetTerminal(widget.rental.terminalId);

      if (!mounted) return;

      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              const Icon(Icons.check_circle, color: Colors.green, size: 28),
              const SizedBox(width: 8),
              Text(widget.isReturn ? 'Return Confirmed!' : 'Rental Success!'),
            ],
          ),
          content: Text(
            widget.isReturn
                ? 'Return Summary: The ESP32 locker cabinet has locked securely. Equipment return completed successfully.'
                : 'Rental Success: The ESP32 cabinet door is unlocked. Please retrieve your ${widget.rental.itemName}.',
          ),
          actions: [
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).primaryColor,
                foregroundColor: Colors.white,
              ),
              onPressed: () {
                Navigator.of(ctx).pop();
                Navigator.pushAndRemoveUntil(
                  context,
                  MaterialPageRoute(builder: (_) => const CatalogScreen()),
                  (route) => false,
                );
              },
              child: const Text('OK'),
            ),
          ],
        ),
      );
    } catch (e) {
      debugPrint('Error completing transaction: $e');
    } finally {
      if (mounted) setState(() => _isProcessingSuccess = false);
    }
  }

  void _simulatePhysicalButtonPress() {
    _countdownTimer?.cancel();
    final esp32Service = Provider.of<Esp32Service>(context, listen: false);
    esp32Service.confirmHardwareTransaction(
      widget.rental.terminalId,
      widget.rental.rentalId,
    );
    _handleTransactionSuccess();
  }

  @override
  Widget build(BuildContext context) {
    final rentalService = Provider.of<RentalService>(context);
    final headerColor = widget.isReturn ? Colors.red.shade700 : const Color(0xFFF57C00);

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isReturn ? 'Return Hardware Sync' : 'Rental Hardware Sync'),
        centerTitle: true,
        automaticallyImplyLeading: false,
      ),
      // Real-time Firestore document listener (snapshots())
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: rentalService.streamTransaction(widget.rental.rentalId),
        builder: (context, snapshot) {
          // ESP32 HARDWARE TRIGGER:
          // App listens in real-time to the Firestore transaction document.
          // When the status field transitions to RENTED or COMPLETED, or hardwareConfirmed becomes true,
          // the app triggers success navigation with haptic feedback.
          if (snapshot.hasData && snapshot.data != null && snapshot.data!.data() != null) {
            final data = snapshot.data!.data()!;
            final String status = (data['status'] ?? '').toString().toUpperCase();
            final bool hardwareConfirmed = data['hardwareConfirmed'] ?? false;

            if (status == 'RENTED' || status == 'COMPLETED' || status == 'ACTIVE' || hardwareConfirmed) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                _handleTransactionSuccess();
              });
            } else if (status == 'CANCELLED' || status == 'REJECTED') {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                _handleTimeoutCancel();
              });
            }
          }

          return SingleChildScrollView(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Banner Header & 60s Live Countdown Timer
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: headerColor,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    children: [
                      const Icon(Icons.hardware, color: Colors.white, size: 44),
                      const SizedBox(height: 10),
                      Text(
                        widget.isReturn
                            ? 'Please hand equipment to operator for terminal inspection.'
                            : 'Waiting for operator terminal confirmation...',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          'Time Remaining: $_secondsRemaining s',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 20),

                // Transaction Details Card
                Card(
                  elevation: 2,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Transaction Details',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                        ),
                        const Divider(height: 20),
                        _buildRow('Item Name', widget.rental.itemName),
                        _buildRow('Rental ID', widget.rental.rentalId.substring(0, 8).toUpperCase()),
                        _buildRow('Terminal ID', widget.rental.terminalId),
                        _buildRow('Customer Name', widget.rental.customerName),
                        _buildRow(
                          'Due Date',
                          DateFormat('yyyy-MM-dd HH:mm').format(widget.rental.dueDate),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 28),

                // Demo Simulation Button
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    side: BorderSide(color: headerColor, width: 1.5),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: _isProcessingSuccess ? null : _simulatePhysicalButtonPress,
                  icon: Icon(Icons.touch_app, color: headerColor),
                  label: Text(
                    'Simulate ESP32 Hardware Confirmation (Demo)',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: headerColor,
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.grey, fontSize: 13)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
        ],
      ),
    );
  }
}
