class ScannerUser {
  final String id;
  final String email;
  final String? firstName;
  final String? lastName;
  final String role;

  ScannerUser({
    required this.id,
    required this.email,
    required this.role,
    this.firstName,
    this.lastName,
  });

  String get displayName => [firstName, lastName].whereType<String>().where((s) => s.isNotEmpty).join(' ').trim().isEmpty
      ? email
      : [firstName, lastName].whereType<String>().join(' ').trim();

  factory ScannerUser.fromJson(Map<String, dynamic> j) => ScannerUser(
        id: j['id'] as String,
        email: j['email'] as String,
        role: j['role'] as String,
        firstName: j['first_name'] as String?,
        lastName: j['last_name'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'email': email,
        'role': role,
        'first_name': firstName,
        'last_name': lastName,
      };
}
