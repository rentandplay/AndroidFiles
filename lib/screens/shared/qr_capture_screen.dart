import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../../services/scanner_camera_session.dart';
import '../../models/staff_scan.dart';

class QrCaptureScreen extends StatefulWidget {
  /// Guided verification returns the scanned String and has no mode switch.
  const QrCaptureScreen({super.key, required this.title})
      : switchModes = false,
        initialMode = null;

  /// General staff scanning returns a StaffScanResult, including its mode.
  const QrCaptureScreen.staff({super.key, this.initialMode})
      : title = 'Scan QR',
        switchModes = true;
  final String title;
  final bool switchModes;
  final StaffScanMode? initialMode;
  @override
  State<QrCaptureScreen> createState() => _QrCaptureScreenState();
}

class _QrCaptureScreenState extends State<QrCaptureScreen>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  late final ScannerCameraSession _camera;
  late final AnimationController _animationController;
  MobileScannerController get _controller => _camera.controller;
  bool _done = false;
  bool _manualEntry = false;
  late StaffScanMode _mode;

  bool get _isTestBinding =>
      WidgetsBinding.instance.runtimeType.toString().contains('Test');

  @override
  void initState() {
    super.initState();
    _mode = widget.initialMode ?? StaffScanSession.lastMode;
    if (widget.switchModes) StaffScanSession.lastMode = _mode;
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    );
    if (!_isTestBinding) {
      _animationController.repeat(reverse: true);
    } else {
      _animationController.value = 0.5;
    }

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
    _camera.lifecycle(state);
    if (!_done) {
      if (state == AppLifecycleState.resumed) {
        if (!_isTestBinding && !_animationController.isAnimating) {
          _animationController.repeat(reverse: true);
        }
      } else {
        _animationController.stop();
      }
    }
  }

  void _changeMode(StaffScanMode mode) {
    if (_done || _mode == mode) return;
    setState(() => _mode = mode);
    StaffScanSession.lastMode = mode;
  }

  Future<void> _finish(String value) async {
    if (_done || !mounted) return;
    final mode = _mode;
    setState(() => _done = true);
    _animationController.stop();
    await _camera.pause();
    if (!mounted) return;
    if (widget.switchModes) {
      Navigator.pop(context, StaffScanResult(code: value, mode: mode));
    } else {
      Navigator.pop(context, value);
    }
  }

  Future<void> _enterCode() async {
    if (_done) return;
    final mode = _mode;
    setState(() {
      _done = true;
      _manualEntry = true;
    });
    _animationController.stop();
    await _camera.pause();
    if (!mounted) return;
    final code = await showDialog<String>(
        context: context, builder: (_) => _PrintedCodeDialog(mode: mode));
    if (!mounted) return;
    if (code != null) {
      Navigator.pop(
          context, StaffScanResult(code: code, mode: mode, manual: true));
      return;
    }
    setState(() {
      _done = false;
      _manualEntry = false;
    });
    if (!_isTestBinding &&
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) {
      _animationController.repeat(reverse: true);
    }
    await _camera.resume();
  }

  Widget _modeControls() {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          for (final mode in StaffScanMode.values)
            Expanded(
              child: Padding(
                  padding: EdgeInsets.only(
                      right: mode == StaffScanMode.rental ? 8 : 0),
                  child: Semantics(
                    selected: mode == _mode,
                    child: OutlinedButton(
                      key: ValueKey('scan-mode-${mode.name}'),
                      onPressed: _done ? null : () => _changeMode(mode),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(48, 48),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 12),
                        backgroundColor:
                            mode == _mode ? scheme.primary : scheme.surface,
                        foregroundColor: mode == _mode
                            ? scheme.onPrimary
                            : scheme.onSurfaceVariant,
                        side: BorderSide(
                            color: mode == _mode
                                ? scheme.primary
                                : scheme.outlineVariant),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                      child: Text(mode.label, textAlign: TextAlign.center),
                    ),
                  )),
            )
        ]),
        const SizedBox(height: 10),
        Text(_mode.instruction,
            style: TextStyle(
                fontSize: 13, height: 1.4, color: scheme.onSurfaceVariant)),
      ]),
    );
  }

  @override
  void dispose() {
    _animationController.dispose();
    WidgetsBinding.instance.removeObserver(this);
    _camera.dispose();
    super.dispose();
  }

  bool _isBarcodeInWindow(
    Barcode barcode,
    Rect window,
    Size widgetSize,
    Size textureSize,
  ) {
    if (barcode.corners.isEmpty) return true;

    final effectiveTextureSize =
        textureSize.isEmpty ? _controller.value.size : textureSize;
    if (effectiveTextureSize.isEmpty || widgetSize.isEmpty) return true;

    final adjustedSize =
        applyBoxFit(BoxFit.cover, effectiveTextureSize, widgetSize);
    double verticalPadding =
        (widgetSize.height - adjustedSize.destination.height) / 2;
    double horizontalPadding =
        (widgetSize.width - adjustedSize.destination.width) / 2;
    if (verticalPadding < 0) verticalPadding = 0;
    if (horizontalPadding < 0) horizontalPadding = 0;

    final double ratioWidth =
        effectiveTextureSize.width / adjustedSize.destination.width;
    final double ratioHeight =
        effectiveTextureSize.height / adjustedSize.destination.height;

    final adjustedCorners = [
      for (final offset in barcode.corners)
        Offset(
          offset.dx / ratioWidth + horizontalPadding,
          offset.dy / ratioHeight + verticalPadding,
        ),
    ];

    if (adjustedCorners.isEmpty) return true;

    final centerX = adjustedCorners.map((p) => p.dx).reduce((a, b) => a + b) /
        adjustedCorners.length;
    final centerY = adjustedCorners.map((p) => p.dy).reduce((a, b) => a + b) /
        adjustedCorners.length;
    final center = Offset(centerX, centerY);

    // Restrict scanning to within the viewfinder guide box (with a slight 12% margin)
    final allowedBounds = window.inflate(window.width * 0.12);
    return allowedBounds.contains(center);
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
                  onPressed: _done ||
                          !value.isRunning ||
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
                  onPressed: !_done &&
                          value.isRunning &&
                          (value.availableCameras ?? 2) > 1
                      ? _camera.switchCamera
                      : null,
                  icon: const Icon(Icons.cameraswitch_outlined))),
        ]),
        body: Column(children: [
          if (widget.switchModes) _modeControls(),
          Expanded(child: LayoutBuilder(builder: (context, size) {
            final side = math.min(size.maxWidth * .72, size.maxHeight * .65);
            final window = Rect.fromCenter(
                center: Offset(size.maxWidth / 2, size.maxHeight / 2),
                width: side,
                height: side);
            final widgetSize = Size(size.maxWidth, size.maxHeight);

            return Stack(
              fit: StackFit.expand,
              children: [
                MobileScanner(
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
                          ? widget.switchModes
                              ? 'Allow camera access in your phone settings, or tap Enter code instead.'
                              : 'Allow camera access in your phone settings, or go back and enter the printed code.'
                          : widget.switchModes
                              ? 'Try the camera again, or tap Enter code instead.'
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
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    AnimatedBuilder(
                      animation: _animationController,
                      builder: (context, _) => CustomPaint(
                        size: widgetSize,
                        painter: _ScannerOverlayPainter(
                          scanWindow: window,
                          scanProgress: _animationController.value,
                          isSuccess: _done && !_manualEntry,
                        ),
                      ),
                    ),
                    Positioned(
                      top: math.max(16, window.top - 54),
                      left: 20,
                      right: 20,
                      child: Center(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 7),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.75),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                                color: _done
                                    ? Colors.greenAccent.withValues(alpha: 0.6)
                                    : Colors.white24,
                                width: 1),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 8,
                                height: 8,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: _done
                                      ? Colors.greenAccent
                                      : const Color(0xFFFF963E),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Flexible(
                                  child: Text(
                                _manualEntry
                                    ? 'Entering printed code'
                                    : _done
                                        ? 'QR captured'
                                        : 'Align QR code inside the frame',
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w600,
                                ),
                              )),
                            ],
                          ),
                        ),
                      ),
                    ),
                    if (!widget.switchModes)
                      Positioned(
                        top: window.bottom + 18,
                        left: 20,
                        right: 20,
                        child: Center(
                          child: Text(
                            'Center one QR code inside the frame.\nKeep the camera steady.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.85),
                              fontSize: 12.5,
                              height: 1.4,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              onDetect: (capture) async {
                if (_done || !mounted) return;
                for (final barcode in capture.barcodes) {
                  final value = barcode.rawValue?.trim();
                  if (value != null && value.isNotEmpty) {
                    if (!_isBarcodeInWindow(
                      barcode,
                      window,
                      widgetSize,
                      capture.size,
                    )) {
                      continue;
                    }
                    await _finish(value);
                    break;
                  }
                }
              },
            ),
                ValueListenableBuilder<MobileScannerState>(
                  valueListenable: _controller,
                  builder: (context, value, _) {
                    if (!value.isRunning ||
                        value.error != null ||
                        value.torchState == TorchState.unavailable) {
                      return const SizedBox.shrink();
                    }
                    final torchOn = value.torchState == TorchState.on;
                    return Positioned(
                      bottom: 14,
                      left: 16,
                      right: 16,
                      child: Center(
                        child: Semantics(
                          toggled: torchOn,
                          button: true,
                          child: OutlinedButton.icon(
                            key: const ValueKey('scanner-torch-pill'),
                            onPressed: _done ? null : _camera.toggleTorch,
                            style: OutlinedButton.styleFrom(
                              minimumSize: const Size(160, 42),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 10),
                              backgroundColor: torchOn
                                  ? const Color(0xFFF59E0B)
                                  : Colors.black.withValues(alpha: 0.72),
                              foregroundColor:
                                  torchOn ? Colors.black : Colors.white,
                              side: BorderSide(
                                color: torchOn
                                    ? const Color(0xFFFDE68A)
                                    : Colors.white30,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(999),
                              ),
                            ),
                            icon: Icon(
                              torchOn
                                  ? Icons.flashlight_on_rounded
                                  : Icons.flashlight_off_rounded,
                              size: 18,
                            ),
                            label: Text(
                              torchOn
                                  ? 'Flashlight on · Tap to turn off'
                                  : 'Low light? Tap for flashlight',
                              style: const TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ],
            );
          })),
          SafeArea(
              top: false,
              child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: SizedBox(
                      width: double.infinity,
                      child: TextButton.icon(
                          onPressed: _done
                              ? null
                              : widget.switchModes
                                  ? _enterCode
                                  : () => Navigator.pop(context),
                          icon: const Icon(Icons.keyboard_outlined),
                          label: Text(widget.switchModes
                              ? 'Enter code instead'
                              : 'Go back and enter code'))))),
        ]),
      );
}

class _PrintedCodeDialog extends StatefulWidget {
  const _PrintedCodeDialog({required this.mode});
  final StaffScanMode mode;
  @override
  State<_PrintedCodeDialog> createState() => _PrintedCodeDialogState();
}

class _PrintedCodeDialogState extends State<_PrintedCodeDialog> {
  final _code = TextEditingController();
  final _form = GlobalKey<FormState>();
  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  void _submit() {
    if (_form.currentState!.validate()) {
      Navigator.pop(context, _code.text.trim());
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(widget.mode == StaffScanMode.rental
            ? 'Find rental'
            : 'Find equipment'),
        content: SingleChildScrollView(
            child: Form(
                key: _form,
                child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                          'This finds the record. Handoff and return verification are completed separately.'),
                      const SizedBox(height: 16),
                      TextFormField(
                          controller: _code,
                          autofocus: true,
                          textInputAction: TextInputAction.search,
                          onFieldSubmitted: (_) => _submit(),
                          maxLength: 256,
                          validator: (value) => value?.trim().isEmpty != false
                              ? 'Enter the printed code.'
                              : null,
                          decoration: InputDecoration(
                              labelText: widget.mode == StaffScanMode.rental
                                  ? 'Rental code'
                                  : 'Equipment code')),
                    ]))),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          FilledButton(onPressed: _submit, child: const Text('Find'))
        ],
      );
}

class _ScannerOverlayPainter extends CustomPainter {
  _ScannerOverlayPainter({
    required this.scanWindow,
    required this.scanProgress,
    required this.isSuccess,
  });

  final Rect scanWindow;
  final double scanProgress;
  final bool isSuccess;

  @override
  void paint(Canvas canvas, Size size) {
    final screenPath = Path()
      ..addRect(Rect.fromLTWH(0, 0, size.width, size.height));
    final rrect =
        RRect.fromRectAndRadius(scanWindow, const Radius.circular(20));
    final windowPath = Path()..addRRect(rrect);

    final maskPath =
        Path.combine(PathOperation.difference, screenPath, windowPath);
    final maskPaint = Paint()..color = Colors.black.withValues(alpha: 0.65);
    canvas.drawPath(maskPath, maskPaint);

    final borderPaint = Paint()
      ..color = isSuccess
          ? Colors.greenAccent.withValues(alpha: 0.8)
          : Colors.white.withValues(alpha: 0.25)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawRRect(rrect, borderPaint);

    final cornerColor =
        isSuccess ? Colors.greenAccent : const Color(0xFFFF963E);
    final cornerPaint = Paint()
      ..color = cornerColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4.0
      ..strokeCap = StrokeCap.round;

    const cornerLength = 28.0;
    const cornerRadius = 16.0;

    // Top-Left
    final tl = Path()
      ..moveTo(scanWindow.left, scanWindow.top + cornerLength)
      ..lineTo(scanWindow.left, scanWindow.top + cornerRadius)
      ..arcToPoint(
        Offset(scanWindow.left + cornerRadius, scanWindow.top),
        radius: const Radius.circular(cornerRadius),
      )
      ..lineTo(scanWindow.left + cornerLength, scanWindow.top);
    canvas.drawPath(tl, cornerPaint);

    // Top-Right
    final tr = Path()
      ..moveTo(scanWindow.right - cornerLength, scanWindow.top)
      ..lineTo(scanWindow.right - cornerRadius, scanWindow.top)
      ..arcToPoint(
        Offset(scanWindow.right, scanWindow.top + cornerRadius),
        radius: const Radius.circular(cornerRadius),
      )
      ..lineTo(scanWindow.right, scanWindow.top + cornerLength);
    canvas.drawPath(tr, cornerPaint);

    // Bottom-Left
    final bl = Path()
      ..moveTo(scanWindow.left, scanWindow.bottom - cornerLength)
      ..lineTo(scanWindow.left, scanWindow.bottom - cornerRadius)
      ..arcToPoint(
        Offset(scanWindow.left + cornerRadius, scanWindow.bottom),
        radius: const Radius.circular(cornerRadius),
        clockwise: false,
      )
      ..lineTo(scanWindow.left + cornerLength, scanWindow.bottom);
    canvas.drawPath(bl, cornerPaint);

    // Bottom-Right
    final br = Path()
      ..moveTo(scanWindow.right - cornerLength, scanWindow.bottom)
      ..lineTo(scanWindow.right - cornerRadius, scanWindow.bottom)
      ..arcToPoint(
        Offset(scanWindow.right, scanWindow.bottom - cornerRadius),
        radius: const Radius.circular(cornerRadius),
        clockwise: false,
      )
      ..lineTo(scanWindow.right, scanWindow.bottom - cornerLength);
    canvas.drawPath(br, cornerPaint);

    if (!isSuccess) {
      final lineY =
          scanWindow.top + 14 + (scanWindow.height - 28) * scanProgress;
      final lineRect = Rect.fromLTWH(
        scanWindow.left + 12,
        lineY - 1.5,
        scanWindow.width - 24,
        3.0,
      );
      final linePaint = Paint()
        ..shader = const LinearGradient(
          colors: [
            Colors.transparent,
            Color(0xFFFF963E),
            Colors.white,
            Color(0xFFFF963E),
            Colors.transparent,
          ],
          stops: [0.0, 0.25, 0.5, 0.75, 1.0],
        ).createShader(lineRect);
      canvas.drawRRect(
          RRect.fromRectAndRadius(lineRect, const Radius.circular(2)),
          linePaint);

      final glowPaint = Paint()
        ..shader = RadialGradient(
          colors: [
            const Color(0xFFFF963E).withValues(alpha: 0.35),
            Colors.transparent,
          ],
        ).createShader(Rect.fromCenter(
          center: Offset(scanWindow.center.dx, lineY),
          width: scanWindow.width * 0.8,
          height: 18,
        ));
      canvas.drawRect(
        Rect.fromCenter(
          center: Offset(scanWindow.center.dx, lineY),
          width: scanWindow.width * 0.8,
          height: 18,
        ),
        glowPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _ScannerOverlayPainter oldDelegate) =>
      oldDelegate.scanProgress != scanProgress ||
      oldDelegate.isSuccess != isSuccess ||
      oldDelegate.scanWindow != scanWindow;
}
