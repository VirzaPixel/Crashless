import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:geolocator/geolocator.dart';

import '../models/detection.dart';
import '../services/ml_service.dart';
import '../services/location_service.dart';
import '../services/supabase_service.dart';
import '../services/image_processor.dart';
import '../services/auth_service.dart';
import '../screens/profile_screen.dart';
import '../widgets/detection_painter.dart';
import '../widgets/loading_overlay.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  File? _imageFile;
  List<Detection> _detections = [];
  bool _isProcessing = false;
  bool _isSaving = false;
  ui.Image? _uiImage;
  Position? _location;
  String? _address;
  int _selectionGeneration = 0;

  @override
  void initState() {
    super.initState();
    MLService.initialize();
    LocationService.requestPermission();
  }

  @override
  void dispose() {
    _selectionGeneration++;
    _uiImage?.dispose();
    super.dispose();
  }

  void _clearSelection() {
    _selectionGeneration++;
    final previousImage = _uiImage;
    if (mounted) {
      setState(() {
        _imageFile = null;
        _detections = [];
        _uiImage = null;
        _location = null;
        _address = null;
        _isProcessing = false;
      });
    }
    previousImage?.dispose();
  }

  Future<void> _pickImage(ImageSource source) async {
    final picker = ImagePicker();
    XFile? pickedFile;

    try {
      pickedFile = await picker.pickImage(
        source: source,
        maxWidth: 1920,
        maxHeight: 1920,
        imageQuality: 85,
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Gagal mengambil gambar: $error'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    if (pickedFile == null || !mounted) return;

    final generation = ++_selectionGeneration;
    final imageFile = File(pickedFile.path);

    setState(() {
      _imageFile = imageFile;
      _detections = [];
      _isProcessing = true;
      _location = null;
      _address = null;
      _uiImage = null;
    });

    await Future.wait([
      _getLocation(generation),
      _detectObjects(imageFile, generation),
    ]);
  }

  Future<void> _getLocation(int generation) async {
    final position = await LocationService.getCurrentLocation();
    if (position == null || !mounted || generation != _selectionGeneration) {
      return;
    }

    final address = await LocationService.getAddressFromCoordinates(
      position.latitude,
      position.longitude,
    );

    if (mounted && generation == _selectionGeneration) {
      setState(() {
        _location = position;
        _address = address;
      });
    }
  }

  Future<void> _detectObjects(File imageFile, int generation) async {
    ui.Image? decodedImage;

    try {
      final stopwatch = Stopwatch()..start();
      final bytes = await imageFile.readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      decodedImage = frame.image;

      debugPrint('⏱️ Image decode: ${stopwatch.elapsedMilliseconds}ms');
      debugPrint(
          '📐 UI Image size: ${decodedImage.width}x${decodedImage.height}');
      stopwatch.reset();

      final detections = await MLService.detectObjects(imageFile);
      final supportedDetections = detections
          .where((detection) => Detection.isSupportedLabel(detection.label))
          .toList(growable: false);

      debugPrint('⏱️ ML detection: ${stopwatch.elapsedMilliseconds}ms');
      debugPrint('✅ Found ${supportedDetections.length} supported detections');

      if (mounted && generation == _selectionGeneration) {
        setState(() {
          _uiImage = decodedImage;
          _detections = supportedDetections;
          _isProcessing = false;
        });
        decodedImage = null;
      }
    } catch (error) {
      debugPrint('❌ Detection error: $error');
      if (mounted && generation == _selectionGeneration) {
        setState(() => _isProcessing = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Gagal memeriksa gambar: $error'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      decodedImage?.dispose();
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
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 20),
            ListTile(
              leading:
                  const Icon(Icons.camera_alt, color: Colors.blue, size: 30),
              title: const Text('Kamera', style: TextStyle(fontSize: 16)),
              onTap: () {
                Navigator.pop(context);
                _pickImage(ImageSource.camera);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library,
                  color: Colors.green, size: 30),
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

  Future<void> _saveToSupabase() async {
    if (_isSaving) return;

    final selectedImage = _imageFile;
    final selectedUiImage = _uiImage;
    final detections = _detections
        .where((detection) => Detection.isSupportedLabel(detection.label))
        .toList(growable: false);

    if (selectedImage == null || selectedUiImage == null) return;
    if (!Detection.hasSupportedDamage(detections)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Foto tidak dapat dikirim karena pothole, crack, atau manhole tidak terdeteksi.',
          ),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() => _isSaving = true);

    try {
      final stopwatch = Stopwatch()..start();
      var imageToUpload = selectedImage;
      var hasTemporaryImage = false;

      debugPrint('🎨 Drawing bounding boxes on image...');
      imageToUpload = await ImageProcessor.drawBoundingBoxesOnImage(
        originalImage: selectedImage,
        detections: detections,
        uiImage: selectedUiImage,
      );
      hasTemporaryImage = imageToUpload.path != selectedImage.path;
      debugPrint('⏱️ Annotation time: ${stopwatch.elapsedMilliseconds}ms');
      stopwatch.reset();

      debugPrint('📤 Uploading image...');
      final imageUrl = await SupabaseService.uploadImage(imageToUpload);
      if (imageUrl == null) {
        throw Exception('Gagal mengunggah gambar');
      }

      debugPrint('⏱️ Upload time: ${stopwatch.elapsedMilliseconds}ms');
      stopwatch.reset();

      final potholesCount =
          detections.where((detection) => detection.label == 'pothole').length;
      final cracksCount =
          detections.where((detection) => detection.label == 'crack').length;
      final detectionsJson =
          detections.map((detection) => detection.toJson()).toList();

      debugPrint('💾 Saving to database...');
      final success = await SupabaseService.saveDetection(
        imageUrl: imageUrl,
        imagePath: imageToUpload.path,
        latitude: _location?.latitude,
        longitude: _location?.longitude,
        address: _address,
        totalDetections: detections.length,
        potholesCount: potholesCount,
        cracksCount: cracksCount,
        detections: detectionsJson,
      );

      debugPrint('⏱️ Database save time: ${stopwatch.elapsedMilliseconds}ms');
      if (!success) {
        throw Exception('Gagal menyimpan laporan ke database');
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                '✅ Berhasil disimpan dengan ${detections.length} deteksi!'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 2),
          ),
        );
        _clearSelection();
      }

      if (hasTemporaryImage) {
        try {
          if (await imageToUpload.exists()) {
            await imageToUpload.delete();
            debugPrint('🗑️ Temp file deleted');
          }
        } catch (error) {
          debugPrint('⚠️ Could not delete temp file: $error');
        }
      }
    } catch (error) {
      debugPrint('❌ Save error: $error');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Gagal menyimpan: $error'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Crashless',
            style: TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: true,
        elevation: 0,
        backgroundColor: Colors.transparent,
        actions: [
          // Profile Avatar Button
          Padding(
            padding: const EdgeInsets.only(right: 12.0),
            child: GestureDetector(
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (context) => const ProfileScreen(),
                  ),
                );
              },
              child: CircleAvatar(
                backgroundColor: const Color(0xFF8B5CF6),
                child: FutureBuilder(
                  future: AuthService.getUserProfile(),
                  builder: (context, snapshot) {
                    if (snapshot.hasData && snapshot.data != null) {
                      return Text(
                        snapshot.data!.getInitials(),
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      );
                    }
                    return const Icon(Icons.person, color: Colors.white);
                  },
                ),
              ),
            ),
          ),
        ],
      ),
      body: LoadingOverlay(
        isLoading: _isSaving,
        message: 'Menyimpan dengan bounding box...',
        child: _imageFile == null ? _buildWelcomeScreen() : _buildResultView(),
      ),
      floatingActionButton: _buildFABs(),
    );
  }

  Widget? _buildFABs() {
    if (_imageFile == null || _isProcessing) return null;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (!_isSaving && Detection.hasSupportedDamage(_detections))
          FloatingActionButton(
            heroTag: 'save',
            onPressed: _saveToSupabase,
            backgroundColor: Colors.green,
            child: const Icon(Icons.cloud_upload),
          ),
        if (!_isSaving && Detection.hasSupportedDamage(_detections))
          const SizedBox(height: 10),
        FloatingActionButton(
          heroTag: 'clear',
          onPressed: _isSaving ? null : _clearSelection,
          backgroundColor: Colors.red,
          child: const Icon(Icons.close),
        ),
      ],
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
              child: const Icon(Icons.route, size: 100, color: Colors.blue),
            ),
            const SizedBox(height: 40),
            const Text(
              'Deteksi Kerusakan Jalan',
              style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            Text(
              'Ambil foto jalan untuk mendeteksi lubang dan retakan secara otomatis',
              style:
                  TextStyle(fontSize: 16, color: Colors.grey[400], height: 1.5),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 50),
            ElevatedButton.icon(
              onPressed: _showImageSourceOptions,
              icon: const Icon(Icons.add_a_photo, size: 28),
              label: const Text('Mulai Deteksi',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              style: ElevatedButton.styleFrom(
                padding:
                    const EdgeInsets.symmetric(horizontal: 40, vertical: 20),
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(30)),
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
                                  Text('Mendeteksi kerusakan...',
                                      style: TextStyle(fontSize: 16)),
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
                        const Text('Lokasi',
                            style: TextStyle(fontSize: 12, color: Colors.grey)),
                        const SizedBox(height: 4),
                        Text(_address!,
                            style: const TextStyle(fontSize: 14),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis),
                      ],
                    ),
                  ),
                ],
              ),
            ),

          const SizedBox(height: 16),

          // Detection results
          if (!_isProcessing && _detections.isNotEmpty) _buildDetectionList(),

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
                      'Pothole, crack, atau manhole tidak terdeteksi. '
                      'Foto ini tidak dapat dikirim.',
                      style: TextStyle(fontSize: 16, color: Colors.orange),
                    ),
                  ),
                ],
              ),
            ),

          const SizedBox(height: 100),
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
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.green.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.check_circle,
                    color: Colors.greenAccent, size: 24),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Hasil Deteksi',
                        style: TextStyle(fontSize: 12, color: Colors.grey)),
                    Text('${_detections.length} Kerusakan Terdeteksi',
                        style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.greenAccent)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: _buildSummaryCard('Jalan Berlubang', potholesCount,
                    Colors.blue, Icons.warning),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildSummaryCard(
                    'Retakan', cracksCount, Colors.orange, Icons.trending_down),
              ),
            ],
          ),
          const SizedBox(height: 20),
          const Divider(color: Colors.grey),
          const SizedBox(height: 12),
          ..._detections.asMap().entries.map((entry) {
            final idx = entry.key + 1;
            final det = entry.value;
            final labelText = switch (det.label) {
              'pothole' => 'Jalan Berlubang',
              'manhole' => 'Manhole',
              _ => 'Retakan',
            };
            final confidenceText =
                '${(det.confidence * 100).toStringAsFixed(1)}%';
            final color = switch (det.label) {
              'pothole' => Colors.blue,
              'manhole' => Colors.purple,
              _ => Colors.orange,
            };

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
                      child: Text('$idx',
                          style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 18,
                              color: color)),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(labelText,
                            style: const TextStyle(
                                fontSize: 16, fontWeight: FontWeight.w600)),
                        const SizedBox(height: 4),
                        Text('Confidence: $confidenceText',
                            style: TextStyle(
                                fontSize: 13, color: Colors.grey[400])),
                      ],
                    ),
                  ),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.greenAccent.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(confidenceText,
                        style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: Colors.greenAccent)),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildSummaryCard(
      String label, int count, Color color, IconData icon) {
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
          Text('$count',
              style: TextStyle(
                  fontSize: 24, fontWeight: FontWeight.bold, color: color)),
          const SizedBox(height: 4),
          Text(label,
              style: TextStyle(fontSize: 12, color: Colors.grey[400]),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }
}
