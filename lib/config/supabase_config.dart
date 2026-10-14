import 'package:flutter_dotenv/flutter_dotenv.dart';

class SupabaseConfig {
  // Load dari .env file
  static String get supabaseUrl => dotenv.env['supabase_url'] ?? '';
  static String get supabaseAnonKey => dotenv.env['supabase_key'] ?? '';
  
  // Storage bucket name
  static const String storageBucket = 'road-damage-images';
  
  // Table name
  static const String tableName = 'road_damages';
}
