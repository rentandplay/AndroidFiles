import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
      'Glass shader refracts the rim while keeping the face undistorted',
      (tester) async {
    await tester.runAsync(() async {
      const width = 256, height = 128;
      final backgroundRecorder = ui.PictureRecorder();
      final background = Canvas(backgroundRecorder);
      for (var x = 0; x < width; x += 8) {
        background.drawRect(
            Rect.fromLTWH(x.toDouble(), 0, 8, height.toDouble()),
            Paint()..color = (x ~/ 8).isEven ? Colors.orange : Colors.blue);
      }
      final sourcePicture = backgroundRecorder.endRecording();
      final source = await sourcePicture.toImage(width, height);
      final program =
          await ui.FragmentProgram.fromAsset('shaders/liquid_glass.frag');

      Future<Uint8List> draw({required double refraction}) async {
        final shader = program.fragmentShader()
          ..setFloat(0, width.toDouble())
          ..setFloat(1, height.toDouble())
          ..setFloat(2, width.toDouble())
          ..setFloat(3, 26)
          ..setFloat(4, refraction)
          ..setFloat(5, .65)
          ..setFloat(6, 10)
          ..setFloat(7, 0)
          ..setFloat(8, 0)
          ..setFloat(9, width.toDouble())
          ..setFloat(10, height.toDouble())
          ..setFloat(11, width.toDouble())
          ..setFloat(12, height.toDouble())
          ..setImageSampler(0, source);
        final recorder = ui.PictureRecorder();
        Canvas(recorder).drawRect(
            const Rect.fromLTWH(0, 0, 256, 128), Paint()..shader = shader);
        final picture = recorder.endRecording();
        final image = await picture.toImage(width, height);
        final bytes =
            (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!
                .buffer
                .asUint8List();
        image.dispose();
        picture.dispose();
        shader.dispose();
        return bytes;
      }

      final flat = await draw(refraction: 0);
      final lens = await draw(refraction: 11);
      int difference(int x, int y) {
        final offset = (y * width + x) * 4;
        return List.generate(
                3,
                (channel) =>
                    (flat[offset + channel] - lens[offset + channel]).abs())
            .reduce(math.max);
      }

      expect(difference(128, 64), lessThanOrEqualTo(2),
          reason: 'The flat face must leave the background unchanged.');
      final rimChange =
          List.generate(12, (x) => difference(x + 1, 64)).reduce(math.max);
      expect(rimChange, greaterThan(20),
          reason: 'The bevel must sample different background pixels.');
      source.dispose();
      sourcePicture.dispose();
    });
  });
}
