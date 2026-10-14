import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;

import '../models/detection.dart';

class ImageProcessor {
  /// Draw bounding boxes on image and save to file
  static Future<File> drawBoundingBoxesOnImage({
    required File originalImage,
    required List<Detection> detections,
    required ui.Image uiImage,
  }) async {
    try {
      debugPrint('🎨 Starting image annotation...');
      debugPrint('📊 Detections to draw: ${detections.length}');

      // Read original image
      final bytes = await originalImage.readAsBytes();
      img.Image? image = img.decodeImage(bytes);

      if (image == null) {
        throw Exception('Failed to decode image');
      }

      final imageWidth = image.width;
      final imageHeight = image.height;
      debugPrint('📐 Image size: ${imageWidth}x$imageHeight');

      // Draw each detection on the image
      for (var i = 0; i < detections.length; i++) {
        final detection = detections[i];
        final box = detection.box;

        debugPrint(
            '🔍 Detection $i: ${detection.label} (${(detection.confidence * 100).toStringAsFixed(1)}%)');
        debugPrint(
            '   Box: L:${box.left} T:${box.top} R:${box.right} B:${box.bottom}');

        // Box coordinates are already in pixels (not normalized)
        final left = box.left.toInt().clamp(0, imageWidth - 1);
        final top = box.top.toInt().clamp(0, imageHeight - 1);
        final right = box.right.toInt().clamp(0, imageWidth - 1);
        final bottom = box.bottom.toInt().clamp(0, imageHeight - 1);

        debugPrint('   Pixel coords: L:$left T:$top R:$right B:$bottom');

        final color = switch (detection.label) {
          'pothole' => img.ColorRgb8(33, 150, 243),
          'manhole' => img.ColorRgb8(156, 39, 176),
          _ => img.ColorRgb8(255, 152, 0),
        };

        // Draw thick rectangle (bounding box)
        final thickness = (imageWidth * 0.01).toInt().clamp(4, 20);
        debugPrint('   Thickness: $thickness');

        // Draw solid outline
        for (int t = 0; t < thickness; t++) {
          // Top horizontal line
          img.drawLine(
            image,
            x1: left,
            y1: top + t,
            x2: right,
            y2: top + t,
            color: color,
          );

          // Bottom horizontal line
          img.drawLine(
            image,
            x1: left,
            y1: bottom - t,
            x2: right,
            y2: bottom - t,
            color: color,
          );

          // Left vertical line
          img.drawLine(
            image,
            x1: left + t,
            y1: top,
            x2: left + t,
            y2: bottom,
            color: color,
          );

          // Right vertical line
          img.drawLine(
            image,
            x1: right - t,
            y1: top,
            x2: right - t,
            y2: bottom,
            color: color,
          );
        }

        // Draw label background
        final labelText = switch (detection.label) {
          'pothole' => 'LUBANG',
          'manhole' => 'MANHOLE',
          _ => 'RETAKAN',
        };
        final confidence = (detection.confidence * 100).toStringAsFixed(0);
        final label = '$labelText $confidence%';

        // Calculate label background size
        final fontSize = (imageHeight * 0.03).toInt().clamp(20, 60);
        final labelWidth = (label.length * fontSize * 0.6).toInt();
        final labelHeight = (fontSize * 1.5).toInt();

        // Draw label background rectangle (above the box)
        final labelTop =
            (top - labelHeight - 5).clamp(0, imageHeight - labelHeight);
        img.fillRect(
          image,
          x1: left,
          y1: labelTop,
          x2: (left + labelWidth).clamp(0, imageWidth),
          y2: (labelTop + labelHeight).clamp(0, imageHeight),
          color: color,
        );

        debugPrint('   ✅ Box drawn successfully');
      }

      // Encode image back to bytes with high quality
      debugPrint('💾 Encoding image to JPEG...');
      final modifiedBytes = img.encodeJpg(image, quality: 95);

      // Create new file path
      final directory = originalImage.parent;
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final filename = 'annotated_$timestamp.jpg';
      final newPath = '${directory.path}/$filename';

      // Write to new file
      final newFile = File(newPath);
      await newFile.writeAsBytes(modifiedBytes);

      debugPrint('✅ Annotated image saved: $newPath');
      debugPrint(
          '📦 File size: ${(modifiedBytes.length / 1024).toStringAsFixed(1)} KB');
      return newFile;
    } catch (e) {
      debugPrint('❌ Error drawing bounding boxes: $e');
      debugPrint('📍 Stack trace: ${StackTrace.current}');
      // Return original image if annotation fails
      return originalImage;
    }
  }
}
