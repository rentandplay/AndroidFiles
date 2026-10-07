import 'package:flutter/services.dart';

class Mx10PrinterService {
  Mx10PrinterService._();

  static final Mx10PrinterService instance = Mx10PrinterService._();
  static const _channel = MethodChannel('rent_and_play/mx10_printer');
  String? _connectedDeviceName;

  String? get connectedDeviceName => _connectedDeviceName;

  Future<List<Map<String, String>>> discoverPrinters() async {
    final result = await _channel.invokeListMethod<dynamic>('discoverPrinters');
    return (result ?? const [])
        .whereType<Map>()
        .map((printer) => printer.map(
              (key, value) => MapEntry('$key', value?.toString() ?? ''),
            ))
        .toList(growable: false);
  }

  Future<String> connect(String id) async {
    final result = await _channel.invokeMapMethod<String, dynamic>(
      'connectPrinter',
      {'id': id},
    );
    _connectedDeviceName = result?['name']?.toString() ?? 'MX10';
    return _connectedDeviceName!;
  }

  void clearConnection() {
    _connectedDeviceName = null;
  }

  Future<void> printLabel({
    required String code,
    required String name,
    required Map<String, dynamic> qrMatrix,
  }) =>
      _channel.invokeMethod<void>('printEquipmentLabel', {
        'code': code,
        'name': name,
        'matrix': qrMatrix,
      });
}
