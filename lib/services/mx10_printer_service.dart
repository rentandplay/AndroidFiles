import 'package:flutter/services.dart';

class Mx10PrinterService {
  Mx10PrinterService._();

  static final Mx10PrinterService instance = Mx10PrinterService._();
  static const _channel = MethodChannel('rent_and_play/mx10_printer');

  Future<List<Map<String, String>>> discoverPrinters() async {
    final result = await _channel.invokeListMethod<dynamic>('discoverPrinters');
    return (result ?? const [])
        .whereType<Map>()
        .map((printer) => printer.map(
              (key, value) => MapEntry('$key', value?.toString() ?? ''),
            ))
        .toList(growable: false);
  }

  Future<void> connect(String id) async {
    await _channel.invokeMapMethod<String, dynamic>(
      'connectPrinter',
      {'id': id},
    );
  }

  Future<bool> isConnected() async {
    return (await status())['connected'] == true;
  }

  Future<Map<String, dynamic>> status() async =>
      await _channel.invokeMapMethod<String, dynamic>('getPrinterStatus') ?? {};

  Future<void> printReceipt(List<Map<String, dynamic>> lines) =>
      _channel.invokeMethod<void>(
          'printRentalReceipt', {'lines': lines, 'paperMode': 'continuous'});

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
