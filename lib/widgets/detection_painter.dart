import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../models/detection.dart';

class DetectionPainter extends CustomPainter {
  final List<Detection> detections;
  final ui.Image image;
  DetectionPainter(this.detections, this.image);

  @override
  void paint(Canvas canvas, Size size) {
    if (detections.isEmpty) {
      debugPrint('⚠️ DetectionPainter: No detections to draw');
      return;
    }

    // Calculate how the image is scaled to fit the canvas
    final imageAspect = image.width / image.height;
    final canvasAspect = size.width / size.height;

    double scale;
    double offsetX = 0;
    double offsetY = 0;

    if (canvasAspect > imageAspect) {
      // Image is narrower than canvas (letterbox on sides)
      scale = size.height / image.height;
      offsetX = (size.width - image.width * scale) / 2;
    } else {
      // Image is wider than canvas (letterbox on top/bottom)
      scale = size.width / image.width;
      offsetY = (size.height - image.height * scale) / 2;
    }

    debugPrint('🎨 DetectionPainter:');
    debugPrint('   Image: ${image.width}x${image.height}');
    debugPrint('   Canvas: ${size.width}x${size.height}');
    debugPrint('   Scale: $scale');
    debugPrint('   Offset: ($offsetX, $offsetY)');
    debugPrint('   Drawing ${detections.length} boxes...');

    for (int i = 0; i < detections.length; i++) {
      final det = detections[i];

      // Box coordinates are already in pixels relative to the original image
      // We need to scale them to match the displayed size
      final left = det.box.left * scale + offsetX;
      final top = det.box.top * scale + offsetY;
      final right = det.box.right * scale + offsetX;
      final bottom = det.box.bottom * scale + offsetY;

      debugPrint('   Box $i (${det.label}):');
      debugPrint(
          '      Original: ${det.box.left.toStringAsFixed(1)}, ${det.box.top.toStringAsFixed(1)}, ${det.box.right.toStringAsFixed(1)}, ${det.box.bottom.toStringAsFixed(1)}');
      debugPrint(
          '      Scaled: ${left.toStringAsFixed(1)}, ${top.toStringAsFixed(1)}, ${right.toStringAsFixed(1)}, ${bottom.toStringAsFixed(1)}');
      debugPrint(
          '      Visible: ${left >= 0 && right <= size.width && top >= 0 && bottom <= size.height}');

      final rect = Rect.fromLTRB(left, top, right, bottom);

      final color = switch (det.label) {
        'pothole' => Colors.blue,
        'manhole' => Colors.purple,
        _ => Colors.orange,
      };

      // Draw semi-transparent fill
      canvas.drawRect(
        rect,
        Paint()
          ..color = color.withOpacity(0.2)
          ..style = PaintingStyle.fill,
      );

      // Draw thick outline (VERY VISIBLE)
      canvas.drawRect(
        rect,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 5, // ✅ Lebih tebal
      );

      // Prepare label text
      final labelText = switch (det.label) {
        'pothole' => 'LUBANG',
        'manhole' => 'MANHOLE',
        _ => 'RETAKAN',
      };
      final confidence = (det.confidence * 100).toStringAsFixed(0);
      final fullText = '$labelText $confidence%';

      final textSpan = TextSpan(
        text: fullText,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 16, // ✅ Lebih besar
          fontWeight: FontWeight.bold,
          shadows: [
            Shadow(
              color: Colors.black,
              offset: Offset(2, 2),
              blurRadius: 5,
            ),
          ],
        ),
      );

      final textPainter = TextPainter(
        text: textSpan,
        textDirection: TextDirection.ltr,
      );
      textPainter.layout();

      // Position label above the box if there's space, otherwise inside
      final labelY = top > 40 ? top - 35 : top + 8;
      final labelRect = Rect.fromLTWH(
        left,
        labelY,
        textPainter.width + 16,
        28,
      );

      // Draw label background
      canvas.drawRRect(
        RRect.fromRectAndRadius(labelRect, const Radius.circular(6)),
        Paint()..color = color,
      );

      // Draw text
      textPainter.paint(canvas, Offset(left + 8, labelY + 5));
    }

    debugPrint('✅ Finished drawing ${detections.length} boxes');
  }

  @override
  bool shouldRepaint(covariant DetectionPainter oldDelegate) {
    return detections != oldDelegate.detections || image != oldDelegate.image;
  }
}
