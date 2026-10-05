import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/esp32_service.dart';

class ConnectionErrorScreen extends StatefulWidget {
  final String terminalId;
  final VoidCallback? onRetry;
  final VoidCallback? onBack;

  const ConnectionErrorScreen({
    super.key,
    this.terminalId = 'TERM-01',
    this.onRetry,
    this.onBack,
  });

  @override
  State<ConnectionErrorScreen> createState() => _ConnectionErrorScreenState();
}

class _ConnectionErrorScreenState extends State<ConnectionErrorScreen> {
  bool _isCheckingConnection = false;

  Future<void> _handleRetryConnection() async {
    setState(() => _isCheckingConnection = true);

    try {
      final esp32Service = Provider.of<Esp32Service>(context, listen: false);
      final isConnected = await esp32Service.checkConnection();

      if (!mounted) return;

      if (isConnected) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Connection restored! Re-synchronizing hardware...'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
          ),
        );
        if (widget.onRetry != null) {
          widget.onRetry!();
        } else {
          Navigator.pop(context);
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Terminal still offline. Please verify Wi-Fi / API connection.'),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 3),
          ),
        );
        if (widget.onRetry != null) {
          widget.onRetry!();
        }
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Connection test error: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _isCheckingConnection = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Connection Status'),
        centerTitle: true,
        automaticallyImplyLeading: false,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Dark Blue Status Header Container
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: const Color(0xFF0D47A1), // Dark Blue
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Column(
                children: [
                  Icon(Icons.warning_amber_rounded, color: Colors.amber, size: 52),
                  SizedBox(height: 12),
                  Text(
                    'Connection Problem',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  SizedBox(height: 6),
                  Text(
                    'The transaction cannot be confirmed right now.',
                    style: TextStyle(color: Colors.white70, fontSize: 13),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // Status Details Card
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Terminal Status',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.red.shade100,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Text(
                            'API / WIFI ERROR',
                            style: TextStyle(
                              color: Colors.red,
                              fontWeight: FontWeight.bold,
                              fontSize: 10,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const Divider(height: 20),
                    _buildRow('Transaction Status', 'Pending Verification', isPending: true),
                    _buildRow('Terminal ID', '${widget.terminalId} Offline'),
                    _buildRow('Local Confirmation', 'Not allowed', isDenied: true),
                    _buildRow('Retry Status', 'Available', isAvailable: true),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            // Warning box (Safe Behavior Notice)
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.amber.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.amber.shade300),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.shield_outlined, color: Colors.amber.shade900, size: 24),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Safe behavior: The request stays pending until the backend and terminal reconnect. No local confirmation. This prevents false transaction completion.',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.amber.shade900,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 28),

            // Primary Blue Button: "Retry Connection"
            SizedBox(
              height: 50,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1E88E5), // Primary Blue
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  elevation: 2,
                ),
                onPressed: _isCheckingConnection ? null : _handleRetryConnection,
                icon: _isCheckingConnection
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.refresh),
                label: Text(
                  _isCheckingConnection ? 'Testing Connection...' : 'Retry Connection',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
            ),

            const SizedBox(height: 12),

            // Proceed Locally Button (Bypass Offline Terminal)
            SizedBox(
              height: 50,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green.shade700,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: () {
                  if (widget.onRetry != null) {
                    widget.onRetry!();
                  } else {
                    Navigator.pop(context);
                  }
                },
                icon: const Icon(Icons.check_circle_outline),
                label: const Text(
                  'Proceed Locally (Bypass Offline)',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                ),
              ),
            ),

            const SizedBox(height: 12),

            // Secondary Button: "Back to transaction"
            SizedBox(
              height: 50,
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  side: BorderSide(color: Colors.grey.shade400),
                ),
                onPressed: () {
                  if (widget.onBack != null) {
                    widget.onBack!();
                  } else {
                    Navigator.pop(context);
                  }
                },
                child: const Text(
                  'Back to transaction',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: Colors.black87,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRow(String label, String value,
      {bool isPending = false, bool isDenied = false, bool isAvailable = false}) {
    Color valueColor = Colors.black87;
    if (isPending) valueColor = Colors.orange.shade800;
    if (isDenied) valueColor = Colors.red.shade800;
    if (isAvailable) valueColor = Colors.green.shade800;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.grey, fontSize: 13)),
          Text(
            value,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 13,
              color: valueColor,
            ),
          ),
        ],
      ),
    );
  }
}
