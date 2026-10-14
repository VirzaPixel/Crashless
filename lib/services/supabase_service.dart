import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import '../config/supabase_config.dart';
import '../models/detection.dart';
import 'auth_service.dart';

class SupabaseService {
  static final SupabaseClient _client = Supabase.instance.client;

  // Upload image to Supabase Storage
  static Future<String?> uploadImage(File imageFile) async {
    try {
      final String fileName = '${const Uuid().v4()}.jpg';
      final String filePath = 'detections/$fileName';

      // Upload to storage
      await _client.storage
          .from(SupabaseConfig.storageBucket)
          .upload(filePath, imageFile);

      // Get public URL
      final String publicUrl = _client.storage
          .from(SupabaseConfig.storageBucket)
          .getPublicUrl(filePath);

      debugPrint('✅ Image uploaded: $publicUrl');
      return publicUrl;
    } catch (e) {
      debugPrint('❌ Error uploading image: $e');
      return null;
    }
  }

  // Save detection to database
  static Future<bool> saveDetection({
    required String imageUrl,
    required String imagePath,
    required double? latitude,
    required double? longitude,
    required String? address,
    required int totalDetections,
    required int potholesCount,
    required int cracksCount,
    required List<Map<String, dynamic>> detections,
    String? notes,
  }) async {
    final hasSupportedDetection = detections.any(
      (detection) => Detection.isSupportedLabel(detection['label']?.toString()),
    );
    if (!hasSupportedDetection) {
      debugPrint('⚠️ Refusing to save a report without supported damage');
      return false;
    }

    try {
      // Get current user info
      final userId = AuthService.userId;
      final user = AuthService.currentUser;

      // Calculate severity based on detections
      String severity = 'low';
      if (totalDetections >= 5) {
        severity = 'high';
      } else if (totalDetections >= 3) {
        severity = 'medium';
      }

      final data = {
        'image_url': imageUrl,
        'image_path': imagePath,
        'latitude': latitude,
        'longitude': longitude,
        'address': address,
        'total_detections': totalDetections,
        'potholes_count': potholesCount,
        'cracks_count': cracksCount,
        'detections': detections,
        'severity': severity,
        'status': 'pending',
        'notes': notes,
        'user_id': userId,
        'user_name':
            user?.userMetadata?['full_name'] ?? user?.email ?? 'Unknown',
      };

      await _client.from(SupabaseConfig.tableName).insert(data);

      debugPrint('✅ Detection saved to database');
      return true;
    } catch (e) {
      debugPrint('❌ Error saving detection: $e');
      return false;
    }
  }

  // Fetch recent detections (filtered by user if needed)
  static Future<List<Map<String, dynamic>>> getRecentDetections({
    int limit = 20,
    String? userId,
  }) async {
    try {
      // Build query based on userId filter
      final response = userId != null
          ? await _client
              .from(SupabaseConfig.tableName)
              .select()
              .eq('user_id', userId)
              .order('created_at', ascending: false)
              .limit(limit)
          : await _client
              .from(SupabaseConfig.tableName)
              .select()
              .order('created_at', ascending: false)
              .limit(limit);

      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      debugPrint('❌ Error fetching detections: $e');
      return [];
    }
  }
}
