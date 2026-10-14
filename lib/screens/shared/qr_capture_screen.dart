import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../../services/scanner_camera_session.dart';

class QrCaptureScreen extends StatefulWidget {
  const QrCaptureScreen({super.key, required this.title});
  final String title;
  @override
  State<QrCaptureScreen> createState() => _QrCaptureScreenState();
}

class _QrCaptureScreenState extends State<QrCaptureScreen>
    with WidgetsBindingObserver {
  late final ScannerCameraSession _camera;
  MobileScannerController get _controller => _camera.controller;
  bool _done = false;
  @override
  void initState() {
    super.initState();
    _camera = ScannerCameraSession(onError: () {
      if (mounted && !_done) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text(
                'Could not change the camera. Retry or use the printed code.')));
      }
    });
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _camera.lifecycle(WidgetsBinding.instance.lifecycleState ??
            AppLifecycleState.resumed);
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_done) _camera.lifecycle(state);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _camera.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(widget.title), actions: [
          ValueListenableBuilder<MobileScannerState>(
              valueListenable: _controller,
              builder: (context, value, _) => IconButton(
                  tooltip: value.torchState == TorchState.on
                      ? 'Turn flash off'
                      : 'Turn flash on',
                  onPressed: !value.isRunning ||
                          value.torchState == TorchState.unavailable
                      ? null
                      : _camera.toggleTorch,
                  icon: Icon(value.torchState == TorchState.on
                      ? Icons.flash_on
                      : Icons.flash_off))),
          ValueListenableBuilder<MobileScannerState>(
              valueListenable: _controller,
              builder: (context, value, _) => IconButton(
                  tooltip: 'Switch camera',
                  onPressed:
                      value.isRunning && (value.availableCameras ?? 2) > 1
                          ? _camera.switchCamera
                          : null,
                  icon: const Icon(Icons.cameraswitch_outlined))),
        ]),
        body: Column(children: [
          Expanded(child: LayoutBuilder(builder: (context, size) {
            final side = math.min(size.maxWidth * .72, size.maxHeight * .65);
            final window = Rect.fromCenter(
                center: Offset(size.maxWidth / 2, size.maxHeight / 2),
                width: side,
                height: side);
            return MobileScanner(
              controller: _controller,
              scanWindow: window,
              errorBuilder: (context, error, _) => Center(
                  child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.no_photography_outlined, size: 42),
                  const SizedBox(height: 12),
                  Text(
                      error.errorCode == MobileScannerErrorCode.permissionDenied
                          ? 'Camera access is needed'
                          : 'Camera unavailable',
                      style: const TextStyle(
                          fontSize: 18, fontWeight: FontWeight.w700),
                      textAlign: TextAlign.center),
                  const SizedBox(height: 8),
                  Text(
                      error.errorCode == MobileScannerErrorCode.permissionDenied
                          ? 'Allow camera access in your phone settings, or go back and enter the printed code.'
                          : 'Try the camera again, or go back and use the printed code.',
                      textAlign: TextAlign.center),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                      onPressed: _camera.resume,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Retry camera')),
                ]),
              )),
              overlayBuilder: (context, _) => IgnorePointer(
                  child: Stack(children: [
                Positioned.fromRect(
                    rect: window,
                    child: Container(
                        decoration: BoxDecoration(
                            border: Border.all(color: Colors.white, width: 3),
                            borderRadius: BorderRadius.circular(18)))),
                Positioned(
                    left: 20,
                    right: 20,
                    bottom: 24,
                    child: Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: .7),
                            borderRadius: BorderRadius.circular(12)),
                        child: const Text(
                            'Center one QR code inside the frame.\nKeep the camera steady.',
                            textAlign: TextAlign.center,
                            style:
                                TextStyle(color: Colors.white, height: 1.5)))),
              ])),
              onDetect: (capture) async {
                if (_done || !mounted) return;
                for (final barcode in capture.barcodes) {
                  final value = barcode.rawValue?.trim();
                  if (value != null && value.isNotEmpty) {
                    _done = true;
                    await _camera.pause();
                    if (context.mounted) Navigator.pop(context, value);
                    break;
                  }
                }
              },
            );
          })),
          SafeArea(
              top: false,
              child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: SizedBox(
                      width: double.infinity,
                      child: TextButton.icon(
                          onPressed: () => Navigator.pop(context),
                          icon: const Icon(Icons.keyboard_outlined),
                          label: const Text('Go back and enter code'))))),
        ]),
      );
}
