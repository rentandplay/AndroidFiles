import 'package:cloud_firestore/cloud_firestore.dart';

const rentAndPlayPickupLocation = 'Rent & Play at ASRI Hotspring Resort';

class RentalModel {
  final String rentalId;
  final String itemId;
  final String itemName;
  final String? itemImageUrl;
  final String customerId;
  final String customerName;
  final String terminalId;
  final String deliveryLocation; // Pickup point or resort delivery location
  final DateTime startDate;
  final DateTime dueDate;
  final DateTime? returnedDate;
  final double rateFee;
  final double deposit;
  final double latePenalty;
  final String paymentMethod; // "QR", "Cash"
  final bool paymentConfirmedByAdmin;
  final String
      status; // "pending_esp32_rent", "active", "pending_esp32_return", "completed", "rejected"
  final String returnCondition; // "Good", "Needs Check", "Damaged"
  final String conditionNotes;
  final String latestReturnRequestStatus;
  final String rentalCode;
  final DateTime? holdExpiresAt;
  final DateTime? receivedAt;
  final double balanceDue;
  final double refundDue;
  final String paymentStatus;
  final String paymentProofStatus;
  final String paymentProofReference;
  final String paymentProofNote;
  final String deliveryStatus;
  bool get isAwaitingPickup => normalizedStatus == 'APPROVED';
  bool get isRentAndPlayPickup {
    final location = deliveryLocation.trim().toLowerCase();
    return location.isEmpty ||
        location == 'shop pickup' ||
        location.startsWith('asri hotspring resort') ||
        location.startsWith(rentAndPlayPickupLocation.toLowerCase());
  }

  String get customerHandoffLocation => isRentAndPlayPickup
      ? 'Rent & Play · ASRI Hotspring Resort'
      : deliveryLocation;
  bool get isAwaitingInspection =>
      normalizedStatus == 'RETURN_PENDING_INSPECTION';
  bool get canCancel => isPendingAdminReview || isAwaitingPickup;

  String get normalizedStatus => status.trim().toUpperCase();
  bool get isActive =>
      normalizedStatus == 'ACTIVE' || normalizedStatus == 'RENTED';
  bool get isPendingAdminReview =>
      normalizedStatus == 'PENDING_ADMIN_APPROVAL' ||
      normalizedStatus == 'PENDING_ESP32_RENT';
  bool get isPendingVerification =>
      normalizedStatus == 'PENDING_VERIFICATION' ||
      normalizedStatus == 'PENDING_RETURN_VERIFICATION' ||
      normalizedStatus == 'PENDING_ESP32_RETURN';
  bool get hasPendingReturnRequest =>
      latestReturnRequestStatus.trim().toUpperCase() ==
      'PENDING_ADMIN_APPROVAL';
  bool get isOpen =>
      isActive ||
      isPendingAdminReview ||
      isPendingVerification ||
      isAwaitingPickup ||
      isAwaitingInspection;

  String get statusLabel {
    if (isActive && hasPendingReturnRequest) return 'Return pending receipt';
    switch (normalizedStatus) {
      case 'APPROVED':
        return 'Approved · preparing delivery';
      case 'RETURN_PENDING_INSPECTION':
        return 'Received · inspection pending';
      case 'ACTIVE':
      case 'RENTED':
        return 'Active';
      case 'PENDING_ADMIN_APPROVAL':
      case 'PENDING_ESP32_RENT':
        return 'Pending admin review';
      case 'PENDING_VERIFICATION':
      case 'PENDING_RETURN_VERIFICATION':
      case 'PENDING_ESP32_RETURN':
        return 'Pending terminal confirmation';
      case 'COMPLETED':
        return 'Returned';
      default:
        return normalizedStatus.replaceAll('_', ' ');
    }
  }

  RentalModel({
    required this.rentalId,
    required this.itemId,
    required this.itemName,
    this.itemImageUrl,
    required this.customerId,
    required this.customerName,
    required this.terminalId,
    this.deliveryLocation = rentAndPlayPickupLocation,
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
    this.latestReturnRequestStatus = '',
    this.rentalCode = '',
    this.holdExpiresAt,
    this.receivedAt,
    this.balanceDue = 0,
    this.refundDue = 0,
    this.paymentStatus = '',
    this.paymentProofStatus = '',
    this.paymentProofReference = '',
    this.paymentProofNote = '',
    this.deliveryStatus = '',
  });

  Map<String, dynamic> toMap() {
    return {
      'rentalId': rentalId,
      'itemId': itemId,
      'itemName': itemName,
      'item_image_url': itemImageUrl,
      'customerId': customerId,
      'customerName': customerName,
      'terminalId': terminalId,
      'deliveryLocation': deliveryLocation,
      'startDate': Timestamp.fromDate(startDate),
      'dueDate': Timestamp.fromDate(dueDate),
      'returnedDate':
          returnedDate != null ? Timestamp.fromDate(returnedDate!) : null,
      'rateFee': rateFee,
      'deposit': deposit,
      'latePenalty': latePenalty,
      'paymentMethod': paymentMethod,
      'paymentConfirmedByAdmin': paymentConfirmedByAdmin,
      'status': status,
      'returnCondition': returnCondition,
      'conditionNotes': conditionNotes,
      'latest_return_request_status': latestReturnRequestStatus,
      'rental_code': rentalCode,
      'hold_expires_at':
          holdExpiresAt == null ? null : Timestamp.fromDate(holdExpiresAt!),
      'received_at':
          receivedAt == null ? null : Timestamp.fromDate(receivedAt!),
      'balance_due': balanceDue,
      'refund_due': refundDue,
      'payment_status': paymentStatus,
      'payment_proof_status': paymentProofStatus,
      'payment_proof_reference': paymentProofReference,
      'payment_proof_note': paymentProofNote,
      'delivery_status': deliveryStatus,
    };
  }

  factory RentalModel.fromMap(Map<String, dynamic> map, {String? id}) {
    DateTime? parseDate(dynamic value) {
      if (value is Timestamp) return value.toDate().toUtc();
      if (value is DateTime) return value.toUtc();
      if (value is! String || value.isEmpty) return null;
      final zoned = RegExp(r'(Z|[+-]\d\d:\d\d)$').hasMatch(value)
          ? value
          : value.replaceFirst(' ', 'T') + '+08:00';
      return DateTime.tryParse(zoned);
    }

    double amount(dynamic value) => value is num
        ? value.toDouble()
        : double.tryParse(value?.toString() ?? '') ?? 0;
    String text(dynamic value, [String fallback = '']) =>
        value?.toString() ?? fallback;
    String? optionalText(dynamic value) {
      final result = value?.toString().trim() ?? '';
      return result.isEmpty ? null : result;
    }

    final release = map['release_condition'];
    final returned = map['return_condition'];
    final fee =
        map['fee_breakdown'] is Map ? map['fee_breakdown'] as Map : const {};
    return RentalModel(
      rentalId: id ?? text(map['id'] ?? map['rentalId']),
      itemId: text(map['item_id'] ?? map['itemId']),
      itemName: text(map['item_name'] ?? map['itemName'], 'Equipment'),
      itemImageUrl: optionalText(
          map['item_image_url'] ?? map['image_url'] ?? map['imageUrl']),
      customerId: text(map['customer_id'] ?? map['customerId']),
      customerName:
          text(map['customer_name'] ?? map['customerName'], 'Customer'),
      terminalId: text(map['terminal_id'] ?? map['terminalId']),
      deliveryLocation: text(
          map['delivery_location'] ?? map['deliveryLocation'] ?? map['resort'],
          rentAndPlayPickupLocation),
      startDate: parseDate(map['confirmed_rental_at'] ??
              map['start_at'] ??
              map['startDate'] ??
              map['created_at']) ??
          DateTime.fromMillisecondsSinceEpoch(0),
      dueDate: parseDate(map['due_at'] ?? map['dueDate']) ??
          DateTime.fromMillisecondsSinceEpoch(0),
      returnedDate: parseDate(map['received_at'] ??
          map['returned_at'] ??
          map['returnedDate'] ??
          map['confirmed_return_at']),
      rateFee: amount(map['rental_fee'] ?? map['rateFee']),
      deposit: amount(map['deposit_amount'] ?? map['deposit']),
      latePenalty: amount(map['late_penalty'] ??
          map['latePenalty'] ??
          (amount(fee['overtime_fee']) + amount(fee['penalty_amount']))),
      paymentMethod:
          text(map['payment_method'] ?? map['paymentMethod'], 'Cash'),
      paymentConfirmedByAdmin: map['payment_confirmed_by_admin'] == true ||
          map['paymentConfirmedByAdmin'] == true,
      status: text(map['status'], 'PENDING_ADMIN_APPROVAL'),
      returnCondition: text(
          returned is Map
              ? returned['condition']
              : returned ??
                  map['returnCondition'] ??
                  (release is Map ? release['condition'] : release),
          'Good'),
      conditionNotes: text(returned is Map
          ? returned['notes']
          : map['condition_notes'] ?? map['conditionNotes']),
      latestReturnRequestStatus: text(map['latest_return_request_status'] ??
          map['latestReturnRequestStatus']),
      rentalCode: text(map['rental_code']),
      holdExpiresAt: parseDate(map['hold_expires_at']),
      receivedAt: parseDate(map['received_at']),
      balanceDue: amount(map['balance_due']),
      refundDue: amount(map['refund_due']),
      paymentStatus: text(map['payment_status']),
      paymentProofStatus: text(map['payment_proof_status']),
      paymentProofReference: text(map['payment_proof_reference']),
      paymentProofNote: text(map['payment_proof_note']),
      deliveryStatus: text(map['delivery_status']),
    );
  }

  RentalModel copyWith({
    String? rentalId,
    String? itemId,
    String? itemName,
    String? itemImageUrl,
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
    String? latestReturnRequestStatus,
    String? paymentProofStatus,
    String? paymentProofReference,
    String? paymentProofNote,
    String? deliveryStatus,
  }) {
    return RentalModel(
      rentalId: rentalId ?? this.rentalId,
      itemId: itemId ?? this.itemId,
      itemName: itemName ?? this.itemName,
      itemImageUrl: itemImageUrl ?? this.itemImageUrl,
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
      paymentConfirmedByAdmin:
          paymentConfirmedByAdmin ?? this.paymentConfirmedByAdmin,
      status: status ?? this.status,
      returnCondition: returnCondition ?? this.returnCondition,
      conditionNotes: conditionNotes ?? this.conditionNotes,
      latestReturnRequestStatus:
          latestReturnRequestStatus ?? this.latestReturnRequestStatus,
      rentalCode: this.rentalCode,
      holdExpiresAt: this.holdExpiresAt,
      receivedAt: this.receivedAt,
      balanceDue: this.balanceDue,
      refundDue: this.refundDue,
      paymentStatus: this.paymentStatus,
      paymentProofStatus: paymentProofStatus ?? this.paymentProofStatus,
      paymentProofReference:
          paymentProofReference ?? this.paymentProofReference,
      paymentProofNote: paymentProofNote ?? this.paymentProofNote,
      deliveryStatus: deliveryStatus ?? this.deliveryStatus,
    );
  }
}
