import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rent_and_play_app/widgets/liquid_glass.dart';
import 'package:rent_and_play_app/widgets/liquid_glass_optics.dart';

const _tabs = [
  LiquidGlassTab(
      label: 'Home', icon: Icons.home_outlined, activeIcon: Icons.home),
  LiquidGlassTab(label: 'Browse', icon: Icons.storefront_outlined),
  LiquidGlassTab(label: 'Rentals', icon: Icons.shopping_bag_outlined),
  LiquidGlassTab(label: 'History', icon: Icons.history),
  LiquidGlassTab(label: 'Profile', icon: Icons.person_outline),
];

Future<Uint8List> _pixels(WidgetTester tester, GlobalKey key) async {
  late Uint8List result;
  await tester.runAsync(() async {
    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage();
    final data = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
    result = Uint8List.fromList(
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes));
    image.dispose();
  });
  return result;
}

List<int> _rgb(Uint8List pixels, int x, int y) =>
    pixels.sublist((y * 360 + x) * 4, (y * 360 + x) * 4 + 3);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
      'Dock keeps a faint warm tint and moves the stronger orange glass lens',
      (tester) async {
    tester.view.physicalSize = const Size(360, 200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    if (ui.ImageFilter.isShaderFilterSupported) {
      // Asset IO must finish outside the widget test's virtual event clock.
      await tester.runAsync(
          () => ui.FragmentProgram.fromAsset('shaders/liquid_glass.frag'));
    }
    for (final (brightness, background) in [
      (Brightness.dark, const Color(0xFF101C2A)),
      (Brightness.dark, Colors.white),
      (Brightness.light, const Color(0xFFF4F6F8)),
      (Brightness.light, Colors.black),
    ]) {
      final key = GlobalKey();
      var selected = 0;
      await tester.pumpWidget(MaterialApp(
        theme: ThemeData(brightness: brightness),
        home: RepaintBoundary(
            key: key,
            child: Scaffold(
              body: ColoredBox(
                color: background,
                child: StatefulBuilder(
                    builder: (context, update) => Stack(children: [
                          Positioned(
                            left: 14,
                            right: 14,
                            top: 100,
                            child: LiquidGlassScope(
                                child: LiquidGlassBottomNavBar(
                              selectedIndex: selected,
                              tabs: _tabs,
                              onTabSelected: (index) =>
                                  update(() => selected = index),
                            )),
                          ),
                        ])),
              ),
            )),
      ));
      await tester.pumpAndSettle();
      final homeSelected = await _pixels(tester, key);
      final left = _rgb(homeSelected, 50, 153);
      final right = _rgb(homeSelected, 310, 153);
      int warmth(List<int> rgb) => rgb[0] - rgb[2];
      expect(warmth(left), greaterThan(120),
          reason: 'The selected blob must have a visible orange fill.');
      expect(warmth(right).abs(), lessThan(65),
          reason: 'The dock itself needs only a faint orange cast.');
      final inactiveLabel = tester.widget<Text>(find.text('Profile'));
      final backdrop = Color.fromARGB(255, right[0], right[1], right[2]);
      final ink = inactiveLabel.style!.color!;
      final luminances = [ink.computeLuminance(), backdrop.computeLuminance()]
        ..sort();
      if (background != Colors.white && background != Colors.black) {
        expect((luminances.last + .05) / (luminances.first + .05),
            greaterThanOrEqualTo(4.5),
            reason: 'Inactive labels must remain readable in both modes.');
      }
      final original = [background.r, background.g, background.b];
      final transmitted = _rgb(homeSelected, 280, 131);
      for (var channel = 0; channel < 3; channel++) {
        expect((transmitted[channel] - original[channel] * 255).abs(),
            lessThan(50),
            reason: 'The unselected bar must transmit most of its backdrop.');
      }
      final browse = _rgb(homeSelected, 116, 153);
      final history = _rgb(homeSelected, 244, 153);
      for (var channel = 0; channel < 3; channel++) {
        expect((browse[channel] - history[channel]).abs(), lessThanOrEqualTo(2),
            reason: 'Unselected material must have a uniform tint.');
      }
      await tester.tap(find.text('Profile'));
      await tester.pumpAndSettle();
      expect(selected, 4);
      final profileSelected = await _pixels(tester, key);
      expect(warmth(_rgb(profileSelected, 310, 153)), greaterThan(120));
      expect(warmth(_rgb(profileSelected, 50, 153)).abs(), lessThan(65));
      for (final pair in [
        [left, _rgb(profileSelected, 310, 153)],
        [right, _rgb(profileSelected, 50, 153)],
      ]) {
        for (var channel = 0; channel < 3; channel++) {
          expect(
              (pair[0][channel] - pair[1][channel]).abs(), lessThanOrEqualTo(3),
              reason:
                  'The material and selected fill must match at either end.');
        }
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });

  testWidgets(
      'Live backdrop refraction aligns with the local rounded glass edge',
      (tester) async {
    tester.view.physicalSize = const Size(360, 200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    // Finish the GPU program load before measuring the filtered scene.
    await tester.runAsync(
        () => ui.FragmentProgram.fromAsset('shaders/liquid_glass.frag'));

    Future<Uint8List> render(bool refractive) async {
      final key = GlobalKey();
      await tester.pumpWidget(Directionality(
        textDirection: TextDirection.ltr,
        child: RepaintBoundary(
            key: key,
            child: Stack(children: [
              const Positioned.fill(child: CustomPaint(painter: _Stripes())),
              Positioned(
                left: 35,
                top: 80,
                width: 290,
                height: 62,
                child: LiquidGlassOptics(
                    borderRadius: 31,
                    blurSigma: 0,
                    refraction: 11,
                    bevelWidth: 10,
                    dispersion: .65,
                    refractive: refractive,
                    child: const SizedBox.expand()),
              ),
            ])),
      ));
      if (refractive) {
        await tester.runAsync(
            () => ui.FragmentProgram.fromAsset('shaders/liquid_glass.frag'));
      }
      await tester.pumpAndSettle();
      // The test clock doesn't advance the GPU's asynchronous pipeline work.
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pump(const Duration(milliseconds: 16));
      return _pixels(tester, key);
    }

    final flat = await render(false);
    await tester.pumpWidget(const SizedBox.shrink());
    final lens = await render(true);
    int difference(int x, int y) {
      final a = _rgb(flat, x, y), b = _rgb(lens, x, y);
      return List.generate(3, (i) => (a[i] - b[i]).abs())
          .reduce((a, b) => a > b ? a : b);
    }

    expect(difference(180, 111), lessThanOrEqualTo(2));
    final edgeDifference = List.generate(12, (i) => difference(36 + i, 111))
        .reduce((a, b) => a > b ? a : b);
    expect(edgeDifference, greaterThan(20),
        reason: 'Bending must occur at the glass edge, not the screen edge.');
    await tester.pumpWidget(const SizedBox.shrink());
  }, skip: !ui.ImageFilter.isShaderFilterSupported);
}

class _Stripes extends CustomPainter {
  const _Stripes();
  @override
  void paint(Canvas canvas, Size size) {
    for (var x = 0.0; x < size.width; x += 8) {
      canvas.drawRect(Rect.fromLTWH(x, 0, 8, size.height),
          Paint()..color = (x ~/ 8).isEven ? Colors.orange : Colors.blue);
    }
    // An asymmetric marker catches a vertically reversed backdrop, which plain
    // vertical stripes would hide on another rendering backend.
    canvas.drawRect(
        const Rect.fromLTWH(80, 106, 200, 10), Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(_Stripes oldDelegate) => false;
}
