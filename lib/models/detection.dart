import 'package:flutter/material.dart';

class Detection {
  static const supportedLabels = {'pothole', 'crack', 'manhole'};

  final String label;
  final double confidence;
  final Rect box;

  Detection({
    required this.label,
    required this.confidence,
    required this.box,
  });

  static String? labelForClassId(int classId) {
    switch (classId) {
      case 0:
        return 'pothole';
      case 1:
        return 'crack';
      case 2:
        return 'manhole';
      default:
        return null;
    }
  }

  static bool isSupportedLabel(String? value) {
    return value != null &&
        supportedLabels.contains(value.trim().toLowerCase());
  }

  static bool hasSupportedDamage(Iterable<Detection> detections) {
    return detections.any((detection) => isSupportedLabel(detection.label));
  }

  Map<String, dynamic> toJson() {
    return {
      'label': label,
      'confidence': confidence,
      'box': {
        'left': box.left,
        'top': box.top,
        'right': box.right,
        'bottom': box.bottom,
      },
    };
  }

  factory Detection.fromJson(Map<String, dynamic> json) {
    final boxData = json['box'] as Map<String, dynamic>;
    return Detection(
      label: json['label'],
      confidence: json['confidence'].toDouble(),
      box: Rect.fromLTRB(
        boxData['left'].toDouble(),
        boxData['top'].toDouble(),
        boxData['right'].toDouble(),
        boxData['bottom'].toDouble(),
      ),
    );
  }
}
