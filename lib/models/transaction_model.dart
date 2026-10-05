import 'package:cloud_firestore/cloud_firestore.dart';

enum TransactionStatus {
  pendingHardwareConfirmation,
  rented,
  pendingReturnVerification,
  completed,
  cancelled,
}

extension TransactionStatusExtension on TransactionStatus {
  String toShortString() {
    switch (this) {
      case TransactionStatus.pendingHardwareConfirmation:
        return 'PENDING_HARDWARE_CONFIRMATION';
      case TransactionStatus.rented:
        return 'RENTED';
      case TransactionStatus.pendingReturnVerification:
        return 'PENDING_RETURN_VERIFICATION';
      case TransactionStatus.completed:
        return 'COMPLETED';
      case TransactionStatus.cancelled:
        return 'CANCELLED';
    }
  }

  static TransactionStatus fromString(String status) {
    switch (status.toUpperCase()) {
      case 'PENDING_HARDWARE_CONFIRMATION':
      case 'PENDING_ESP32_RENT':
        return TransactionStatus.pendingHardwareConfirmation;
      case 'RENTED':
      case 'ACTIVE':
        return TransactionStatus.rented;
      case 'PENDING_RETURN_VERIFICATION':
      case 'PENDING_ESP32_RETURN':
        return TransactionStatus.pendingReturnVerification;
      case 'COMPLETED':
        return TransactionStatus.completed;
      case 'CANCELLED':
      case 'REJECTED':
      default:
        return TransactionStatus.cancelled;
    }
  }
}

class TransactionModel {
  final String transactionId;
  final String itemId;
  final String itemName;
  final String customerId;
  final String customerName;
  final String terminalId;
  final bool hardwareConfirmed;
  final String status;
  final double rateFee;
  final double deposit;
  final DateTime createdAt;
  final DateTime updatedAt;

  TransactionModel({
    required this.transactionId,
    required this.itemId,
    required this.itemName,
    required this.customerId,
    required this.customerName,
    required this.terminalId,
    this.hardwareConfirmed = false,
    required this.status,
    required this.rateFee,
    required this.deposit,
    required this.createdAt,
    required this.updatedAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'transactionId': transactionId,
      'itemId': itemId,
      'itemName': itemName,
      'customerId': customerId,
      'customerName': customerName,
      'terminalId': terminalId,
      'hardwareConfirmed': hardwareConfirmed,
      'status': status,
      'rateFee': rateFee,
      'deposit': deposit,
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': Timestamp.fromDate(updatedAt),
    };
  }

  factory TransactionModel.fromMap(Map<String, dynamic> map, {String? id}) {
    DateTime parseDate(dynamic val) {
      if (val is Timestamp) return val.toDate();
      if (val is String) return DateTime.tryParse(val) ?? DateTime.now();
      return DateTime.now();
    }

    return TransactionModel(
      transactionId: id ?? map['transactionId'] ?? '',
      itemId: map['itemId'] ?? '',
      itemName: map['itemName'] ?? '',
      customerId: map['customerId'] ?? '',
      customerName: map['customerName'] ?? '',
      terminalId: map['terminalId'] ?? 'TERM-01',
      hardwareConfirmed: map['hardwareConfirmed'] ?? false,
      status: map['status'] ?? 'PENDING_HARDWARE_CONFIRMATION',
      rateFee: (map['rateFee'] ?? 0.0).toDouble(),
      deposit: (map['deposit'] ?? 0.0).toDouble(),
      createdAt: parseDate(map['createdAt']),
      updatedAt: parseDate(map['updatedAt']),
    );
  }

  TransactionModel copyWith({
    String? transactionId,
    String? itemId,
    String? itemName,
    String? customerId,
    String? customerName,
    String? terminalId,
    bool? hardwareConfirmed,
    String? status,
    double? rateFee,
    double? deposit,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return TransactionModel(
      transactionId: transactionId ?? this.transactionId,
      itemId: itemId ?? this.itemId,
      itemName: itemName ?? this.itemName,
      customerId: customerId ?? this.customerId,
      customerName: customerName ?? this.customerName,
      terminalId: terminalId ?? this.terminalId,
      hardwareConfirmed: hardwareConfirmed ?? this.hardwareConfirmed,
      status: status ?? this.status,
      rateFee: rateFee ?? this.rateFee,
      deposit: deposit ?? this.deposit,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? DateTime.now(),
    );
  }
}
