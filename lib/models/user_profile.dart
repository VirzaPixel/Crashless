class UserProfile {
  final String id;
  final String fullName;
  final String email;
  final String? avatarUrl;
  final String role;
  final bool isActive;
  final DateTime createdAt;
  final DateTime updatedAt;

  UserProfile({
    required this.id,
    required this.fullName,
    required this.email,
    this.avatarUrl,
    this.role = 'user',
    this.isActive = true,
    required this.createdAt,
    required this.updatedAt,
  });

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    return UserProfile(
      id: json['id'],
      fullName: json['full_name'],
      email: json['email'],
      avatarUrl: json['avatar_url'],
      role: json['role'] ?? 'user',
      isActive: json['is_active'] ?? true,
      createdAt: DateTime.parse(json['created_at']),
      updatedAt: DateTime.parse(json['updated_at']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'full_name': fullName,
      'email': email,
      'avatar_url': avatarUrl,
      'role': role,
      'is_active': isActive,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  String getInitials() {
    final names = fullName.split(' ');
    if (names.isEmpty) return '?';
    if (names.length == 1) return names[0][0].toUpperCase();
    return '${names[0][0]}${names[1][0]}'.toUpperCase();
  }
}
