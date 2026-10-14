import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/user_profile.dart';

class AuthService {
  static final SupabaseClient _client = Supabase.instance.client;

  // Get current user
  static User? get currentUser => _client.auth.currentUser;

  // Check if user is logged in
  static bool get isLoggedIn => currentUser != null;

  // Get user ID
  static String? get userId => currentUser?.id;

  // Register new user
  static Future<AuthResponse> signUp({
    required String email,
    required String password,
    required String fullName,
  }) async {
    try {
      final response = await _client.auth.signUp(
        email: email,
        password: password,
        data: {
          'full_name': fullName,
        },
        emailRedirectTo: 'io.supabase.crashless://login-callback',
      );

      debugPrint('✅ Sign up successful: ${response.user?.email}');
      return response;
    } catch (e) {
      debugPrint('❌ Sign up error: $e');
      rethrow;
    }
  }

  // Sign in
  static Future<AuthResponse> signIn({
    required String email,
    required String password,
  }) async {
    try {
      final response = await _client.auth.signInWithPassword(
        email: email,
        password: password,
      );

      debugPrint('✅ Sign in successful: ${response.user?.email}');
      return response;
    } catch (e) {
      debugPrint('❌ Sign in error: $e');
      rethrow;
    }
  }

  // Sign out
  static Future<void> signOut() async {
    try {
      await _client.auth.signOut();
      debugPrint('✅ Sign out successful');
    } catch (e) {
      debugPrint('❌ Sign out error: $e');
      rethrow;
    }
  }

  // Resend verification email
  static Future<void> resendVerificationEmail(String email) async {
    try {
      await _client.auth.resend(
        type: OtpType.signup,
        email: email,
      );
      debugPrint('✅ Verification email resent to: $email');
    } catch (e) {
      debugPrint('❌ Resend email error: $e');
      rethrow;
    }
  }

  // Reset password
  static Future<void> resetPassword(String email) async {
    try {
      await _client.auth.resetPasswordForEmail(
        email,
        redirectTo: 'io.supabase.crashless://reset-password',
      );
      debugPrint('✅ Password reset email sent to: $email');
    } catch (e) {
      debugPrint('❌ Reset password error: $e');
      rethrow;
    }
  }

  // Update password
  static Future<UserResponse> updatePassword(String newPassword) async {
    try {
      final response = await _client.auth.updateUser(
        UserAttributes(password: newPassword),
      );
      debugPrint('✅ Password updated');
      return response;
    } catch (e) {
      debugPrint('❌ Update password error: $e');
      rethrow;
    }
  }

  // Get user profile
  static Future<UserProfile?> getUserProfile() async {
    try {
      if (userId == null) return null;

      final response = await _client
          .from('user_profiles')
          .select()
          .eq('id', userId!)
          .single();

      return UserProfile.fromJson(response);
    } catch (e) {
      debugPrint('❌ Get profile error: $e');
      return null;
    }
  }

  // Update user profile
  static Future<bool> updateUserProfile({
    String? fullName,
    String? avatarUrl,
  }) async {
    try {
      if (userId == null) return false;

      final updates = <String, dynamic>{};
      if (fullName != null) updates['full_name'] = fullName;
      if (avatarUrl != null) updates['avatar_url'] = avatarUrl;
      updates['updated_at'] = DateTime.now().toIso8601String();

      await _client
          .from('user_profiles')
          .update(updates)
          .eq('id', userId!);

      debugPrint('✅ Profile updated');
      return true;
    } catch (e) {
      debugPrint('❌ Update profile error: $e');
      return false;
    }
  }

  // Listen to auth state changes
  static Stream<AuthState> get authStateChanges => _client.auth.onAuthStateChange;
}
