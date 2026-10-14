import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:crashless_mobile/models/detection.dart';

void main() {
  Detection detection(String label) => Detection(
        label: label,
        confidence: 0.9,
        box: const Rect.fromLTWH(0, 0, 10, 10),
      );

  test('accepts pothole, crack, and manhole detections', () {
    expect(
      Detection.hasSupportedDamage([
        detection('pothole'),
        detection('crack'),
        detection('manhole'),
      ]),
      isTrue,
    );
  });

  test('rejects empty and unsupported detections', () {
    expect(Detection.hasSupportedDamage([]), isFalse);
    expect(Detection.hasSupportedDamage([detection('road')]), isFalse);
  });

  test(
      'maps all trained model classes without treating unknown classes as crack',
      () {
    expect(Detection.labelForClassId(0), 'pothole');
    expect(Detection.labelForClassId(1), 'crack');
    expect(Detection.labelForClassId(2), 'manhole');
    expect(Detection.labelForClassId(3), isNull);
  });
}
