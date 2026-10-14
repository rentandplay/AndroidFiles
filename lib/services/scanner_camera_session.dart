import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

/// Serializes camera changes so pause/resume, scanning and closing cannot race.
class ScannerCameraSession {
  ScannerCameraSession({this.onError})
      : controller = MobileScannerController(
            autoStart: false, formats: const [BarcodeFormat.qrCode]);
  final MobileScannerController controller;
  final VoidCallback? onError;
  Future<void> _pending = Future.value();
  bool _closed = false, _wanted = true, _foreground = true;

  Future<void> _run(Future<void> Function() action, {bool report = true}) {
    final task = _pending.then((_) async {
      try {
        await action();
      } catch (_) {
        if (report && !_closed) onError?.call();
      }
    });
    _pending = task;
    return task;
  }

  Future<void> _sync() => _run(() async {
        if (_closed) return;
        if (_wanted && _foreground) {
          // This plugin version retains a permission error while stopped and
          // start() otherwise exits early even after permission is allowed.
          if (!controller.value.isRunning && controller.value.error != null) {
            controller.value = controller.value.copyWith(error: null);
          }
          try {
            await controller.start();
          } catch (_) {
            controller.value = controller.value.copyWith(
                isInitialized: true,
                isRunning: false,
                error: const MobileScannerException(
                    errorCode: MobileScannerErrorCode.genericError));
            rethrow;
          }
        } else {
          await controller.stop();
        }
      });

  Future<void> resume() {
    _wanted = true;
    return _sync();
  }

  Future<void> pause() {
    _wanted = false;
    return _sync();
  }

  void lifecycle(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    unawaited(_sync());
  }

  Future<void> toggleTorch() => _run(() async {
        if (!_closed &&
            controller.value.isInitialized &&
            controller.value.isRunning) {
          await controller.toggleTorch();
        }
      });
  Future<void> switchCamera() => _run(() async {
        if (!_closed &&
            _wanted &&
            _foreground &&
            controller.value.isInitialized &&
            controller.value.isRunning) {
          await controller.switchCamera();
        }
      });
  Future<void> dispose() {
    _closed = true;
    return _run(() async {
      try {
        await controller.stop();
      } catch (_) {/* Still release native resources. */}
      await controller.dispose();
    }, report: false);
  }
}
