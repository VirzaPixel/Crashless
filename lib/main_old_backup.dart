import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'config/supabase_config.dart';
import 'services/location_service.dart';
import 'services/supabase_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Load .env file
  await dotenv.load(fileName: "assets/.env");
  
  // Initialize Supabase
  await Supabase.initialize(
    url: SupabaseConfig.supabaseUrl,
    anonKey: SupabaseConfig.supabaseAnonKey,
  );
  
  runApp(const CrashlessApp());
}

class CrashlessApp extends StatelessWidget {
  const CrashlessApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Crashless Detector',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF2196F3),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFF121212),
      ),
      home: const DetectorScreen(),
    );
  }
}

class DetectorScreen extends StatefulWidget {
  const DetectorScreen({super.key});

  @override
  State<DetectorScreen> createState() => _DetectorScreenState();
}

class _DetectorScreenState extends State<DetectorScreen> {
  File? _imageFile;
  List<Detection> _detections = [];
  bool _isProcessing = false;
  bool _isSaving = false;
  Interpreter? _interpreter;
  ui.Image? _uiImage;
  Position? _location;
  String? _address;

  @override
  void initState() {
    super.initState();
    _loadModel();
    _requestPermissions();
  }

  Future<void> _requestPermissions() async {
    await LocationService.requestPermission();
  }

  Future<void> _loadModel() async {
    try {
      _interpreter = await Interpreter.fromAsset('assets/models/crashless_model.tflite');
      debugPrint('✅ Model loaded');
    } catch (e) {
      debugPrint('❌ Model load error: $e');
    }
  }

  Future<void> _pickImage(ImageSource source) async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(
      source: source,
      maxWidth: 1920,
      maxHeight: 1920,
      imageQuality: 85,
    );
    
    if (pickedFile == null) return;

    DetectionPainter.resetLogFlag();

    setState(() {
      _imageFile = File(pickedFile.path);
      _detections = [];
      _isProcessing = true;
      _location = null;
      _address = null;
    });

    // Run location and detection in parallel
    Future.wait([
      _getLocation(),
      _detectObjects(),
    ]);
  }

  Future<void> _getLocation() async {
    final position = await LocationService.getCurrentLocation();
    if (position != null) {
      final address = await LocationService.getAddressFromCoordinates(
        position.latitude,
        position.longitude,
      );
      
      setState(() {
        _location = position;
        _address = address;
      });
      
      debugPrint('📍 Location: ${position.latitude}, ${position.longitude}');
      debugPrint('📍 Address: $address');
    }
  }

  void _showImageSourceOptions() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.grey[900],
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Container(
        padding: const EdgeInsets.symmetric(vertical: 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[700],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'Pilih Sumber Foto',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 20),
            ListTile(
              leading: const Icon(Icons.camera_alt, color: Colors.blue, size: 30),
              title: const Text('Kamera', style: TextStyle(fontSize: 16)),
              onTap: () {
                Navigator.pop(context);
                _pickImage(ImageSource.camera);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library, color: Colors.green, size: 30),
              title: const Text('Galeri', style: TextStyle(fontSize: 16)),
              onTap: () {
                Navigator.pop(context);
                _pickImage(ImageSource.gallery);
              },
            ),
            const SizedBox(height: 10),
          ],
        ),
      ),
    );
  }

  Future<void> _detectObjects() async {
    if (_imageFile == null || _interpreter == null) return;

    try {
      final bytes = await _imageFile!.readAsBytes();
      final image = img.decodeImage(bytes);
      
      if (image == null) {
        throw Exception('Failed to decode image');
      }

      debugPrint('🖼️ Image size: ${image.width}x${image.height}');

      // Convert to ui.Image
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      _uiImage = frame.image;

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
      final detections = _postprocess(output, outputShape, image.width, image.height);

      debugPrint('✅ Found ${detections.length} detections');
      for (var i = 0; i < detections.length; i++) {
        final det = detections[i];
        debugPrint('   Detection $i: ${det.label} ${(det.confidence * 100).toStringAsFixed(1)}%');
      }

      setState(() {
        _detections = detections;
        _isProcessing = false;
      });

    } catch (e, stackTrace) {
      debugPrint('❌ Detection error: $e');
      debugPrint('Stack: $stackTrace');
      setState(() {
        _isProcessing = false;
      });
    }
  }

  List<List<List<List<double>>>> _preprocessImage(img.Image image) {
    const size = 640;
    
    // Enhance image for better detection in low-light
    var enhanced = img.adjustColor(
      image,
      brightness: 1.2,  // Increase brightness
      contrast: 1.3,    // Increase contrast
      saturation: 1.1,  // Slight saturation boost
    );
    
    final resized = img.copyResize(
      enhanced, 
      width: size, 
      height: size,
      interpolation: img.Interpolation.linear,
    );

    final input = List.generate(1, (_) => 
      List.generate(size, (y) => 
        List.generate(size, (x) {
          final pixel = resized.getPixel(x, y);
          return [
            pixel.r / 255.0,
            pixel.g / 255.0,
            pixel.b / 255.0,
          ];
        })
      )
    );

    return input;
  }

  List<List<List<double>>> _createOutputBuffer(List<int> shape) {
    return List.generate(
      1,
      (_) => List.generate(
        shape[1],
        (_) => List.filled(shape[2], 0.0),
      ),
    );
  }

  List<Detection> _postprocess(
    List<List<List<double>>> output,
    List<int> shape,
    int originalWidth,
    int originalHeight,
  ) {
    final detections = <Detection>[];
    
    debugPrint('📊 ===== POSTPROCESSING =====');
    debugPrint('📊 Raw output shape: $shape');
    
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
      debugPrint('📊 Format: YOLOv8 [1, $dim1, $dim2] with $numClasses classes');
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
        
        if (bestScore >= 0.10) {
          parsed.add([xc, yc, w, h, bestScore, bestClass.toDouble()]);
          validBoxes++;
        }
      }
      debugPrint('📊 Valid boxes with score >= 0.10: $validBoxes');
    }

    // Check if normalized
    bool isNormalized = false;
    if (parsed.isNotEmpty && parsed[0].length >= 4) {
      final maxVal = [parsed[0][0], parsed[0][1], parsed[0][2], parsed[0][3]].reduce((a, b) => a > b ? a : b);
      isNormalized = maxVal <= 1.5;
      debugPrint('📊 Model output format: ${isNormalized ? "NORMALIZED (0-1)" : "PIXEL (0-640)"}');
    }

    final scaleX = originalWidth / 640.0;
    final scaleY = originalHeight / 640.0;
    
    int beforeFilter = 0;
    for (final det in parsed) {
      if (det.length < 6) continue;

      final confidence = det[4];
      if (confidence < 0.05) continue; // Ultra low threshold for testing (5%)

      beforeFilter++;
      
      final classId = det[5].round();
      final label = classId == 0 ? 'pothole' : 'crack';

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
    
    debugPrint('📊 After confidence filter (>= 0.05): $beforeFilter detections');

    final afterNMS = _nonMaxSuppression(detections, 0.15); // Lower IoU for more detections
    debugPrint('📊 After NMS (IoU 0.15): ${afterNMS.length} detections');
    
    return afterNMS;
  }

  List<Detection> _nonMaxSuppression(List<Detection> detections, double iouThreshold) {
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

  double _iou(Rect a, Rect b) {
    final intersection = a.intersect(b);
    if (intersection.isEmpty) return 0.0;

    final intersectionArea = intersection.width * intersection.height;
    final unionArea = a.width * a.height + b.width * b.height - intersectionArea;

    return unionArea <= 0 ? 0.0 : intersectionArea / unionArea;
  }

  Future<void> _saveToSupabase() async {
    if (_imageFile == null || _detections.isEmpty) return;

    setState(() => _isSaving = true);

    try {
      // 1. Upload image to Supabase Storage
      debugPrint('📤 Uploading image...');
      final imageUrl = await SupabaseService.uploadImage(_imageFile!);
      
      if (imageUrl == null) {
        throw Exception('Failed to upload image');
      }

      // 2. Count detections by type
      int potholesCount = _detections.where((d) => d.label == 'pothole').length;
      int cracksCount = _detections.where((d) => d.label == 'crack').length;

      // 3. Convert detections to JSON
      List<Map<String, dynamic>> detectionsJson = _detections.map((d) => {
        'label': d.label,
        'confidence': d.confidence,
        'box': {
          'left': d.box.left,
          'top': d.box.top,
          'right': d.box.right,
          'bottom': d.box.bottom,
        },
      }).toList();

      // 4. Save to database
      debugPrint('💾 Saving to database...');
      final success = await SupabaseService.saveDetection(
        imageUrl: imageUrl,
        imagePath: _imageFile!.path,
        latitude: _location?.latitude,
        longitude: _location?.longitude,
        address: _address,
        totalDetections: _detections.length,
        potholesCount: potholesCount,
        cracksCount: cracksCount,
        detections: detectionsJson,
      );

      if (success) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('✅ Laporan berhasil disimpan!'),
              backgroundColor: Colors.green,
              duration: Duration(seconds: 2),
            ),
          );
        }
      } else {
        throw Exception('Failed to save to database');
      }

    } catch (e) {
      debugPrint('❌ Save error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Gagal menyimpan: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  @override
  void dispose() {
    _interpreter?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        title: const Text(
          'Crashless',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        elevation: 0,
        backgroundColor: Colors.transparent,
      ),
      body: _imageFile == null ? _buildWelcomeScreen() : _buildResultView(),
      floatingActionButton: _imageFile != null && !_isProcessing
          ? Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_detections.isNotEmpty && !_isSaving)
                  FloatingActionButton(
                    heroTag: 'save',
                    onPressed: _saveToSupabase,
                    backgroundColor: Colors.green,
                    child: const Icon(Icons.cloud_upload),
                  ),
                if (_detections.isNotEmpty && !_isSaving) const SizedBox(height: 10),
                FloatingActionButton(
                  heroTag: 'clear',
                  onPressed: () {
                    setState(() {
                      _imageFile = null;
                      _detections = [];
                      _uiImage = null;
                      _location = null;
                      _address = null;
                    });
                  },
                  backgroundColor: Colors.red,
                  child: const Icon(Icons.close),
                ),
              ],
            )
          : null,
    );
  }

  Widget _buildWelcomeScreen() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(40),
              decoration: BoxDecoration(
                color: Colors.blue.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.route,
                size: 100,
                color: Colors.blue,
              ),
            ),
            const SizedBox(height: 40),
            const Text(
              'Deteksi Kerusakan Jalan',
              style: TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            Text(
              'Ambil foto jalan untuk mendeteksi lubang dan retakan secara otomatis',
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey[400],
                height: 1.5,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 50),
            ElevatedButton.icon(
              onPressed: _showImageSourceOptions,
              icon: const Icon(Icons.add_a_photo, size: 28),
              label: const Text(
                'Mulai Deteksi',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 20),
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(30),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildResultView() {
    return SingleChildScrollView(
      child: Column(
        children: [
          // Image with detections
          Container(
            margin: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey[800]!, width: 2),
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.3),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: _isProcessing
                  ? AspectRatio(
                      aspectRatio: 1,
                      child: Stack(
                        children: [
                          Image.file(_imageFile!, fit: BoxFit.contain),
                          Container(
                            color: Colors.black54,
                            child: const Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  CircularProgressIndicator(),
                                  SizedBox(height: 16),
                                  Text(
                                    'Mendeteksi kerusakan...',
                                    style: TextStyle(fontSize: 16),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    )
                  : LayoutBuilder(
                      builder: (context, constraints) {
                        final image = _uiImage;
                        return Stack(
                          children: [
                            Image.file(_imageFile!, fit: BoxFit.contain),
                            if (_detections.isNotEmpty && image != null)
                              Positioned.fill(
                                child: CustomPaint(
                                  painter: DetectionPainter(_detections, image),
                                ),
                              ),
                          ],
                        );
                      },
                    ),
            ),
          ),
          
          // Location info
          if (_location != null && _address != null)
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.grey[850],
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey[700]!, width: 1),
              ),
              child: Row(
                children: [
                  const Icon(Icons.location_on, color: Colors.red, size: 24),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Lokasi',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _address!,
                          style: const TextStyle(fontSize: 14),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          
          const SizedBox(height: 16),
          
          // Detection results
          if (!_isProcessing && _detections.isNotEmpty)
            _buildDetectionList(),
          
          if (!_isProcessing && _detections.isEmpty)
            Container(
              margin: const EdgeInsets.all(16),
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.orange.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.orange, width: 1),
              ),
              child: const Row(
                children: [
                  Icon(Icons.info_outline, color: Colors.orange, size: 24),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Tidak terdeteksi kerusakan jalan',
                      style: TextStyle(fontSize: 16, color: Colors.orange),
                    ),
                  ),
                ],
              ),
            ),
          
          const SizedBox(height: 100), // Space for FAB
        ],
      ),
    );
  }

  Widget _buildDetectionList() {
    final potholesCount = _detections.where((d) => d.label == 'pothole').length;
    final cracksCount = _detections.where((d) => d.label == 'crack').length;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.grey[850],
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey[700]!, width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.green.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.check_circle, color: Colors.greenAccent, size: 24),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Hasil Deteksi',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey,
                      ),
                    ),
                    Text(
                      '${_detections.length} Kerusakan Terdeteksi',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.greenAccent,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          
          const SizedBox(height: 20),
          
          // Summary cards
          Row(
            children: [
              Expanded(
                child: _buildSummaryCard(
                  'Jalan Berlubang',
                  potholesCount,
                  Colors.blue,
                  Icons.warning,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildSummaryCard(
                  'Retakan',
                  cracksCount,
                  Colors.orange,
                  Icons.trending_down,
                ),
              ),
            ],
          ),
          
          const SizedBox(height: 20),
          const Divider(color: Colors.grey),
          const SizedBox(height: 12),
          
          // Detection items
          ..._detections.asMap().entries.map((entry) {
            final idx = entry.key + 1;
            final det = entry.value;
            final labelText = det.label == 'pothole' ? 'Jalan Berlubang' : 'Retakan';
            final confidenceText = '${(det.confidence * 100).toStringAsFixed(1)}%';
            final color = det.label == 'pothole' ? Colors.blue : Colors.orange;
            
            return Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.grey[800],
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: color.withOpacity(0.3), width: 1),
              ),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: color.withOpacity(0.2),
                      shape: BoxShape.circle,
                      border: Border.all(color: color, width: 2),
                    ),
                    child: Center(
                      child: Text(
                        '$idx',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                          color: color,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          labelText,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Confidence: $confidenceText',
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey[400],
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.greenAccent.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      confidenceText,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Colors.greenAccent,
                      ),
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildSummaryCard(String label, int count, Color color, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3), width: 1),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 28),
          const SizedBox(height: 8),
          Text(
            '$count',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey[400],
            ),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

// Detection data class
class Detection {
  final String label;
  final double confidence;
  final Rect box;

  Detection({
    required this.label,
    required this.confidence,
    required this.box,
  });
}

// Custom painter for bounding boxes
class DetectionPainter extends CustomPainter {
  final List<Detection> detections;
  final ui.Image image;
  static bool _hasLoggedOnce = false;

  DetectionPainter(this.detections, this.image);

  static void resetLogFlag() {
    _hasLoggedOnce = false;
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (detections.isEmpty) return;

    // Calculate how the image is displayed (BoxFit.contain logic)
    final imageAspect = image.width / image.height;
    final canvasAspect = size.width / size.height;
    
    double scale;
    double offsetX = 0;
    double offsetY = 0;
    
    if (canvasAspect > imageAspect) {
      scale = size.height / image.height;
      offsetX = (size.width - image.width * scale) / 2;
    } else {
      scale = size.width / image.width;
      offsetY = (size.height - image.height * scale) / 2;
    }

    for (int i = 0; i < detections.length; i++) {
      final det = detections[i];
      
      // Transform box coordinates from image space to canvas space
      final left = det.box.left * scale + offsetX;
      final top = det.box.top * scale + offsetY;
      final right = det.box.right * scale + offsetX;
      final bottom = det.box.bottom * scale + offsetY;
      
      final rect = Rect.fromLTRB(left, top, right, bottom);

      final color = det.label == 'pothole' 
          ? Colors.blue.withOpacity(0.8)
          : Colors.orange.withOpacity(0.8);

      // Draw semi-transparent fill
      canvas.drawRect(
        rect,
        Paint()
          ..color = color.withOpacity(0.2)
          ..style = PaintingStyle.fill,
      );

      // Draw thick border
      canvas.drawRect(
        rect,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 4,
      );

      // Draw label
      final labelText = '${det.label == 'pothole' ? 'Lubang' : 'Retak'} ${(det.confidence * 100).toStringAsFixed(0)}%';
      final textSpan = TextSpan(
        text: labelText,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 16,
          fontWeight: FontWeight.bold,
          shadows: [
            Shadow(
              color: Colors.black,
              offset: Offset(1, 1),
              blurRadius: 3,
            ),
          ],
        ),
      );
      
      final textPainter = TextPainter(
        text: textSpan,
        textDirection: TextDirection.ltr,
      );
      textPainter.layout();

      // Draw label background
      final labelY = top > 30 ? top - 28 : top + 4;
      final labelRect = Rect.fromLTWH(
        left,
        labelY,
        textPainter.width + 12,
        26,
      );

      canvas.drawRRect(
        RRect.fromRectAndRadius(labelRect, const Radius.circular(4)),
        Paint()..color = color,
      );

      // Draw label text
      textPainter.paint(canvas, Offset(left + 6, labelY + 5));
    }
  }

  @override
  bool shouldRepaint(covariant DetectionPainter oldDelegate) {
    return detections != oldDelegate.detections;
  }
}
