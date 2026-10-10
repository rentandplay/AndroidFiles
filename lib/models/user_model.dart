import 'package:cloud_firestore/cloud_firestore.dart';

class UserModel {
  final String uid;
  final String name;
  final String email;
  final String phone;
  final String
      role; // CUSTOMER, OPERATOR, or OWNER; legacy values are normalized.
  final bool mustChangePassword;
  bool get isStaff => const {'OWNER', 'OPERATOR', 'ADMIN', 'SUPER_ADMIN'}
      .contains(role.toUpperCase());
  final String? profileImageUrl;
  final String? validIdUrl;
  final bool hasAcceptedTerms;
  final DateTime? createdAt;

  UserModel({
    required this.uid,
    required this.name,
    required this.email,
    required this.phone,
    this.role = 'CUSTOMER',
    this.mustChangePassword = false,
    this.profileImageUrl,
    this.validIdUrl,
    this.hasAcceptedTerms = false,
    this.createdAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'uid': uid,
      'name': name,
      'email': email,
      'phone': phone,
      'role': role,
      'mustChangePassword': mustChangePassword,
      'profileImageUrl': profileImageUrl,
      'validIdUrl': validIdUrl,
      'hasAcceptedTerms': hasAcceptedTerms,
      'createdAt': createdAt != null
          ? Timestamp.fromDate(createdAt!)
          : FieldValue.serverTimestamp(),
    };
  }

  factory UserModel.fromMap(Map<String, dynamic> map, {String? uid}) {
    DateTime? parsedDate;
    if (map['createdAt'] is Timestamp) {
      parsedDate = (map['createdAt'] as Timestamp).toDate();
    } else if (map['createdAt'] is String) {
      parsedDate = DateTime.tryParse(map['createdAt']);
    }

    return UserModel(
      uid: uid ?? map['uid'] ?? '',
      name: map['name'] ?? map['full_name'] ?? '',
      email: map['email'] ?? '',
      phone: map['phone'] ?? '',
      role: switch ((map['role'] ?? 'CUSTOMER').toString().toUpperCase()) {
        'ADMIN' || 'OPERATOR' => 'OPERATOR',
        'SUPER_ADMIN' || 'OWNER' => 'OWNER',
        'USER' || 'CUSTOMER' => 'CUSTOMER',
        final value => value,
      },
      mustChangePassword: map['mustChangePassword'] == true ||
          map['must_change_password'] == true,
      profileImageUrl: map['profileImageUrl'] ?? map['profile_image_url'],
      validIdUrl: map['validIdUrl'] ?? map['valid_id_url'],
      hasAcceptedTerms: map['hasAcceptedTerms'] ?? false,
      createdAt: parsedDate,
    );
  }

  UserModel copyWith({
    String? uid,
    String? name,
    String? email,
    String? phone,
    String? role,
    bool? mustChangePassword,
    String? profileImageUrl,
    String? validIdUrl,
    bool? hasAcceptedTerms,
    DateTime? createdAt,
  }) {
    return UserModel(
      uid: uid ?? this.uid,
      name: name ?? this.name,
      email: email ?? this.email,
      phone: phone ?? this.phone,
      role: role ?? this.role,
      mustChangePassword: mustChangePassword ?? this.mustChangePassword,
      profileImageUrl: profileImageUrl ?? this.profileImageUrl,
      validIdUrl: validIdUrl ?? this.validIdUrl,
      hasAcceptedTerms: hasAcceptedTerms ?? this.hasAcceptedTerms,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
