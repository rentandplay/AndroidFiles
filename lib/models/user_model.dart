import 'package:cloud_firestore/cloud_firestore.dart';

class UserModel {
  final String uid;
  final String name;
  final String email;
  final String phone;
  final String role; // "user" or "admin"
  final String? validIdUrl;
  final bool hasAcceptedTerms;
  final DateTime? createdAt;

  UserModel({
    required this.uid,
    required this.name,
    required this.email,
    required this.phone,
    this.role = 'user',
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
      role: map['role'] ?? 'user',
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
      validIdUrl: validIdUrl ?? this.validIdUrl,
      hasAcceptedTerms: hasAcceptedTerms ?? this.hasAcceptedTerms,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
