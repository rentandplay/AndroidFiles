import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

/// Compresses locally in an isolate before any payment proof leaves the device.
Future<String> paymentProofDataUrl(Uint8List bytes) async {
  final compressed = await compute(compressPaymentProof, bytes);
  return 'data:image/jpeg;base64,${base64Encode(compressed)}';
}

Uint8List compressPaymentProof(Uint8List bytes) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) {
    throw const FormatException('Choose a valid payment receipt image.');
  }
  img.Image image = img.bakeOrientation(decoded);
  if (image.width > 1600 || image.height > 1600) {
    image = image.width >= image.height
        ? img.copyResize(image, width: 1600)
        : img.copyResize(image, height: 1600);
  }
  for (final quality in [82, 70, 58, 46]) {
    final encoded = img.encodeJpg(image, quality: quality);
    if (encoded.length <= 300000) return encoded;
  }
  while (image.width > 320 && image.height > 320) {
    image = img.copyResize(image, width: (image.width * .8).round());
    final encoded = img.encodeJpg(image, quality: 50);
    if (encoded.length <= 300000) return encoded;
  }
  throw const FormatException(
      'This image is too large. Choose a cropped receipt screenshot.');
}
