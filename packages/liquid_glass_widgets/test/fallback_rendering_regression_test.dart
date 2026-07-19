import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:liquid_glass_widgets/widgets/shared/glass_effect.dart';
import 'package:liquid_glass_widgets/widgets/shared/liquid_shape_shader_geometry.dart';

void main() {
  test('LiquidOval resolves to a circular shader radius', () {
    expect(
      resolveLiquidShapeCornerRadius(
        const LiquidOval(),
        const Size.square(40),
      ),
      20,
    );
  });

  test('rounded shader radii are clamped to the surface bounds', () {
    expect(
      resolveLiquidShapeCornerRadius(
        const LiquidRoundedSuperellipse(borderRadius: 999),
        const Size(40, 24),
      ),
      12,
    );
  });

  testWidgets('lightweight glass retains its backdrop layer across repaints',
      (tester) async {
    LightweightLiquidGlass.resetForTesting();
    await LightweightLiquidGlass.preWarm();
    final glow = ValueNotifier<double>(0);
    addTearDown(glow.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: ValueListenableBuilder<double>(
            valueListenable: glow,
            builder: (context, value, child) => SizedBox.square(
              dimension: 40,
              child: LightweightLiquidGlass(
                shape: const LiquidOval(),
                settings: const LiquidGlassSettings(blur: 6),
                glowIntensity: value,
                child: const SizedBox.expand(),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final firstLayer = _onlyBackdropLayer(tester);

    glow.value = 0.5;
    await tester.pump();
    final secondLayer = _onlyBackdropLayer(tester);

    expect(identical(firstLayer, secondLayer), isTrue);
  });

  testWidgets('interactive glass retains its backdrop layer across repaints',
      (tester) async {
    await GlassEffect.preWarm();
    final intensity = ValueNotifier<double>(0.25);
    final backgroundKey = GlobalKey();
    addTearDown(intensity.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Stack(
          children: [
            Positioned.fill(
              child: RepaintBoundary(
                key: backgroundKey,
                child: const ColoredBox(color: Colors.blue),
              ),
            ),
            Center(
              child: ValueListenableBuilder<double>(
                valueListenable: intensity,
                builder: (context, value, child) => SizedBox(
                  width: 120,
                  height: 36,
                  child: GlassEffect(
                    shape: const LiquidRoundedSuperellipse(borderRadius: 18),
                    settings: const LiquidGlassSettings(blur: 6),
                    interactionIntensity: value,
                    backgroundKey: backgroundKey,
                    child: const SizedBox.expand(),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    final firstLayer = _onlyBackdropLayer(tester);

    intensity.value = 0.75;
    await tester.pump();
    final secondLayer = _onlyBackdropLayer(tester);

    expect(identical(firstLayer, secondLayer), isTrue);
  });
}

BackdropFilterLayer _onlyBackdropLayer(WidgetTester tester) {
  final rootLayer = tester.binding.renderViews.single.debugLayer;
  expect(rootLayer, isNotNull);
  final allLayers = <Layer>[
    rootLayer!,
    ...rootLayer.depthFirstIterateChildren(),
  ];
  final layers = allLayers.whereType<BackdropFilterLayer>().toList();
  expect(layers, hasLength(1));
  return layers.single;
}
