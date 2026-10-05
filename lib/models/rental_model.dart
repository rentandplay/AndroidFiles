import 'package:cloud_firestore/cloud_firestore.dart';

class RentalModel {
  final String rentalId;
  final String itemId;
  final String itemName;
  final String customerId;
  final String customerName;
  final String terminalId;
  final String deliveryLocation; // Private Resort delivery address
  final DateTime startDate;
  final DateTime dueDate;
  final DateTime? returnedDate;
  final double rateFee;
  final double deposit;
  final double latePenalty;
  final String paymentMethod; // "QR", "Cash"
  final bool paymentConfirmedByAdmin;
  final String status; // "pending_esp32_rent", "active", "pending_esp32_return", "completed", "rejected"
  final String returnCondition; // "Good", "Needs Check", "Damaged"
  final String conditionNotes;

  RentalModel({
    required this.rentalId,
    required this.itemId,
    required this.itemName,
    required this.customerId,
    required this.customerName,
    required this.terminalId,
    this.deliveryLocation = 'ASRI Hotspring Resort',
    required this.startDate,
    required this.dueDate,
    this.returnedDate,
    required this.rateFee,
    required this.deposit,
    this.latePenalty = 0.0,
    required this.paymentMethod,
    this.paymentConfirmedByAdmin = false,
    required this.status,
    this.returnCondition = 'Good',
    this.conditionNotes = '',
  });

  Map<String, dynamic> toMap() {
    return {
      'rentalId': rentalId,
      'itemId': itemId,
      'itemName': itemName,
      'customerId': customerId,
      'customerName': customerName,
      'terminalId': terminalId,
      'deliveryLocation': deliveryLocation,
      'startDate': Timestamp.fromDate(startDate),
      'dueDate': Timestamp.fromDate(dueDate),
      'returnedDate': returnedDate != null ? Timestamp.fromDate(returnedDate!) : null,
      'rateFee': rateFee,
      'deposit': deposit,
      'latePenalty': latePenalty,
      'paymentMethod': paymentMethod,
      'paymentConfirmedByAdmin': paymentConfirmedByAdmin,
      'status': status,
      'returnCondition': returnCondition,
      'conditionNotes': conditionNotes,
    };
  }

  factory RentalModel.fromMap(Map<String, dynamic> map, {String? id}) {
    DateTime parseDate(dynamic val) {
      if (val is Timestamp) return val.toDate();
      if (val is String) return DateTime.tryParse(val) ?? DateTime.now();
      return DateTime.now();
    }

    return RentalModel(
      rentalId: id ?? map['rentalId'] ?? '',
      itemId: map['itemId'] ?? '',
      itemName: map['itemName'] ?? '',
      customerId: map['customerId'] ?? '',
      customerName: map['customerName'] ?? '',
      terminalId: map['terminalId'] ?? 'ESP32_CABINET_01',
      deliveryLocation: map['deliveryLocation'] ?? map['resort'] ?? map['location'] ?? 'ASRI Hotspring Resort',
      startDate: parseDate(map['startDate']),
      dueDate: parseDate(map['dueDate']),
      returnedDate: map['returnedDate'] != null ? parseDate(map['returnedDate']) : null,
      rateFee: (map['rateFee'] ?? 0.0).toDouble(),
      deposit: (map['deposit'] ?? 0.0).toDouble(),
      latePenalty: (map['latePenalty'] ?? 0.0).toDouble(),
      paymentMethod: map['paymentMethod'] ?? 'Cash',
      paymentConfirmedByAdmin: map['paymentConfirmedByAdmin'] ?? false,
      status: map['status'] ?? 'pending_esp32_rent',
      returnCondition: map['returnCondition'] ?? 'Good',
      conditionNotes: map['conditionNotes'] ?? '',
    );
  }

  RentalModel copyWith({
    String? rentalId,
    String? itemId,
    String? itemName,
    String? customerId,
    String? customerName,
    String? terminalId,
    String? deliveryLocation,
    DateTime? startDate,
    DateTime? dueDate,
    DateTime? returnedDate,
    double? rateFee,
    double? deposit,
    double? latePenalty,
    String? paymentMethod,
    bool? paymentConfirmedByAdmin,
    String? status,
    String? returnCondition,
    String? conditionNotes,
  }) {
    return RentalModel(
      rentalId: rentalId ?? this.rentalId,
      itemId: itemId ?? this.itemId,
      itemName: itemName ?? this.itemName,
      customerId: customerId ?? this.customerId,
      customerName: customerName ?? this.customerName,
      terminalId: terminalId ?? this.terminalId,
      deliveryLocation: deliveryLocation ?? this.deliveryLocation,
      startDate: startDate ?? this.startDate,
      dueDate: dueDate ?? this.dueDate,
      returnedDate: returnedDate ?? this.returnedDate,
      rateFee: rateFee ?? this.rateFee,
      deposit: deposit ?? this.deposit,
      latePenalty: latePenalty ?? this.latePenalty,
      paymentMethod: paymentMethod ?? this.paymentMethod,
      paymentConfirmedByAdmin: paymentConfirmedByAdmin ?? this.paymentConfirmedByAdmin,
      status: status ?? this.status,
      returnCondition: returnCondition ?? this.returnCondition,
      conditionNotes: conditionNotes ?? this.conditionNotes,
    );
  }
}
