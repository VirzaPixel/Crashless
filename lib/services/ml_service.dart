import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';

import '../models/detection.dart';

class MLService {
  static Interpreter? _interpreter;
  static bool _isInitialized = false;
  static Future<bool>? _initialization;

  // Initialize model
  static Future<bool> initialize() {
    if (_isInitialized) return Future.value(true);
    return _initialization ??= _loadModel();
  }

  static Future<bool> _loadModel() async {
    try {
      _interpreter = await Interpreter.fromAsset(
        'assets/models/crashless_model.tflite',
      );
      _isInitialized = true;
      debugPrint('✅ ML Model loaded successfully');
      return true;
    } catch (error) {
      debugPrint('❌ Failed to load model: $error');
      return false;
    } finally {
      _initialization = null;
    }
  }

  // Detect objects in image
  static Future<List<Detection>> detectObjects(File imageFile) async {
    if (!await initialize()) {
      throw StateError('Model deteksi tidak tersedia');
    }

    try {
      // Load and decode image
      final bytes = await imageFile.readAsBytes();
      final image = img.decodeImage(bytes);

      if (image == null) {
        throw Exception('Failed to decode image');
      }

      debugPrint('🖼️ Image size: ${image.width}x${image.height}');

      // Preprocess
      debugPrint('⚙️ Preprocessing image to 640x640...');
      final input = _preprocessImage(image);

      // Prepare output
      final outputShape = _interpreter!.getOutputTensors().first.shape;
      debugPrint('📊 Model output shape: $outputShape');

      final output = _createOutputBuffer(outputShape);

      // Run inference
      debugPrint('🤖 Running inference...');
      _interpreter!.run(input, output);

      // Postprocess
      debugPrint('🔍 Postprocessing detections...');
      final detections = _postprocess(
        output,
        outputShape,
        image.width,
        image.height,
      );

      debugPrint('✅ Found ${detections.length} detections');
      return detections;
    } catch (e, stackTrace) {
      debugPrint('❌ Detection error: $e');
      debugPrint('Stack: $stackTrace');
      rethrow;
    }
  }

  // Preprocess image
  static List<List<List<List<double>>>> _preprocessImage(img.Image image) {
    const size = 640;

    // More conservative enhancement for consistency
    var enhanced = img.adjustColor(
      image,
      brightness: 1.1, // Reduced from 1.2
      contrast: 1.2, // Reduced from 1.3
      saturation: 1.0, // Reduced from 1.1 - neutral saturation
    );

    final resized = img.copyResize(
      enhanced,
      width: size,
      height: size,
      interpolation: img.Interpolation.linear,
    );

    final input = List.generate(
        1,
        (_) => List.generate(
            size,
            (y) => List.generate(size, (x) {
                  final pixel = resized.getPixel(x, y);
                  return [
                    pixel.r / 255.0,
                    pixel.g / 255.0,
                    pixel.b / 255.0,
                  ];
                })));

    return input;
  }

  // Create output buffer
  static List<List<List<double>>> _createOutputBuffer(List<int> shape) {
    return List.generate(
      1,
      (_) => List.generate(
        shape[1],
        (_) => List.filled(shape[2], 0.0),
      ),
    );
  }

  // Postprocess detections
  static List<Detection> _postprocess(
    List<List<List<double>>> output,
    List<int> shape,
    int originalWidth,
    int originalHeight,
  ) {
    final detections = <Detection>[];

    debugPrint('📊 ===== POSTPROCESSING =====');

    final dim1 = shape[1];
    final dim2 = shape[2];

    List<List<double>> parsed;

    if (dim2 == 6) {
      debugPrint('📊 Format: Standard [1, $dim1, 6]');
      parsed = output[0];
    } else if (dim1 == 6 && dim2 > 1000) {
      debugPrint('📊 Format: Transposed [1, 6, $dim2]');
      parsed = List.generate(dim2, (col) {
        return List.generate(dim1, (row) => output[0][row][col]);
      });
    } else {
      // YOLOv8 format [1, 4+classes, N]
      final numClasses = dim1 - 4;
      debugPrint(
          '📊 Format: YOLOv8 [1, $dim1, $dim2] with $numClasses classes');
      parsed = [];

      int validBoxes = 0;

      for (int i = 0; i < dim2; i++) {
        final xc = output[0][0][i];
        final yc = output[0][1][i];
        final w = output[0][2][i];
        final h = output[0][3][i];

        double bestScore = 0;
        int bestClass = 0;
        for (int c = 0; c < numClasses; c++) {
          final score = output[0][4 + c][i];
          if (score > bestScore) {
            bestScore = score;
            bestClass = c;
          }
        }

        // Raised threshold from 0.10 to 0.15 for initial filtering
        if (bestScore >= 0.15) {
          parsed.add([xc, yc, w, h, bestScore, bestClass.toDouble()]);
          validBoxes++;
        }
      }
      debugPrint('📊 Valid boxes with score >= 0.15: $validBoxes');
    }

    // Check if normalized
    bool isNormalized = false;
    if (parsed.isNotEmpty && parsed[0].length >= 4) {
      final maxVal = [parsed[0][0], parsed[0][1], parsed[0][2], parsed[0][3]]
          .reduce((a, b) => a > b ? a : b);
      isNormalized = maxVal <= 1.5;
      debugPrint(
          '📊 Model output format: ${isNormalized ? "NORMALIZED (0-1)" : "PIXEL (0-640)"}');
    }

    final scaleX = originalWidth / 640.0;
    final scaleY = originalHeight / 640.0;

    int beforeFilter = 0;
    for (final det in parsed) {
      if (det.length < 6) continue;

      final confidence = det[4];
      if (confidence < 0.20) {
        continue; // Raised from 5% to 20% for better accuracy
      }

      beforeFilter++;

      final classId = det[5].round();
      final label = Detection.labelForClassId(classId);
      if (label == null) {
        debugPrint('⚠️ Skipping unsupported model class id: $classId');
        continue;
      }

      double xc, yc, w, h;
      if (isNormalized) {
        xc = det[0] * 640.0 * scaleX;
        yc = det[1] * 640.0 * scaleY;
        w = det[2] * 640.0 * scaleX;
        h = det[3] * 640.0 * scaleY;
      } else {
        xc = det[0] * scaleX;
        yc = det[1] * scaleY;
        w = det[2] * scaleX;
        h = det[3] * scaleY;
      }

      detections.add(Detection(
        label: label,
        confidence: confidence,
        box: Rect.fromCenter(
          center: Offset(xc, yc),
          width: w,
          height: h,
        ),
      ));
    }

    debugPrint(
        '📊 After confidence filter (>= 0.20): $beforeFilter detections');

    final afterNMS = _nonMaxSuppression(detections, 0.45);
    debugPrint('📊 After NMS (IoU 0.45): ${afterNMS.length} detections');

    return afterNMS;
  }

  // Non-Maximum Suppression
  static List<Detection> _nonMaxSuppression(
    List<Detection> detections,
    double iouThreshold,
  ) {
    if (detections.isEmpty) return detections;

    final sorted = List<Detection>.from(detections)
      ..sort((a, b) => b.confidence.compareTo(a.confidence));

    final selected = <Detection>[];
    final suppressed = List<bool>.filled(sorted.length, false);

    for (int i = 0; i < sorted.length; i++) {
      if (suppressed[i]) continue;
      selected.add(sorted[i]);

      for (int j = i + 1; j < sorted.length; j++) {
        if (suppressed[j]) continue;
        if (sorted[i].label != sorted[j].label) continue;
        if (_iou(sorted[i].box, sorted[j].box) >= iouThreshold) {
          suppressed[j] = true;
        }
      }
    }

    return selected;
  }

  // Calculate IoU (Intersection over Union)
  static double _iou(Rect a, Rect b) {
    final intersection = a.intersect(b);
    if (intersection.isEmpty) return 0.0;

    final intersectionArea = intersection.width * intersection.height;
    final unionArea =
        a.width * a.height + b.width * b.height - intersectionArea;

    return unionArea <= 0 ? 0.0 : intersectionArea / unionArea;
  }

  // Dispose resources
  static void dispose() {
    _interpreter?.close();
    _interpreter = null;
    _isInitialized = false;
  }
}
