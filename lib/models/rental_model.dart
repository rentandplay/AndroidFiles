import 'package:cloud_firestore/cloud_firestore.dart';

const rentAndPlayPickupLocation =
    'Rent & Play · Lakewoods Subdivision, Los Baños, Laguna';

class RentalModel {
  final String rentalId;
  final String itemId;
  final String stockGroupId;
  final String itemName;
  final String? itemImageUrl;
  final String customerId;
  final String customerName;
  final String terminalId;
  final String terminalCode;
  String get displayReference =>
      rentalCode.trim().isEmpty ? 'Not assigned' : rentalCode.trim();
  String get terminalReference =>
      terminalCode.trim().isEmpty ? 'Not assigned' : terminalCode.trim();
  final String deliveryLocation; // Pickup point or resort delivery location
  final DateTime startDate;
  final DateTime dueDate;
  final DateTime? returnedDate;
  final DateTime? confirmedRentalAt;
  final DateTime? confirmedReturnAt;
  final double rateFee;
  final double? rentalPaidAmount;
  final double latePenalty;
  final double overtimeRate;
  final int overtimeUnitMinutes;
  final double? overtimeFee;
  final double? penaltyAmount;
  final String penaltyReason;
  final double? finalRentalCharges;
  final int? billedMinutes;
  final int? graceMinutes;
  final int? overtimeUnits;
  final String paymentMethod; // "QR", "Cash"
  final bool paymentConfirmedByAdmin;
  final String
      status; // "pending_esp32_rent", "active", "pending_esp32_return", "completed", "rejected"
  final String itemCode;
  final String customerPhone;
  final String returnCondition; // "Good", "Needs Check", "Damaged"
  final String conditionNotes;
  final String returnResult;
  final String inspectedByName;
  final String latestReturnRequestStatus;
  final String latestTerminalRequestStatus;
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
  final String fulfillmentMode;
  final DateTime? scheduledStartAt;
  final Map<String, dynamic> extensionRequest;
  final List<Map<String, dynamic>> extensionHistory;
  final int totalExtendedMinutes;
  final Map<String, dynamic> feeBreakdown;
  String get extensionStatus =>
      (extensionRequest['status']?.toString() ?? '').toUpperCase();
  bool get hasPendingExtensionRequest => extensionStatus == 'PENDING';
  int get extensionCount => extensionHistory.length;
  int get requestedExtensionMinutes {
    final quote = extensionRequest['quote'];
    final raw = quote is Map ? quote['billed_minutes'] : null;
    final parsed = _asIntOrNull(raw) ??
        _asIntOrNull(extensionRequest['additional_minutes']);
    return parsed ?? 0;
  }

  double get requestedExtensionFee {
    final raw = extensionRequest['additional_fee'];
    return raw is num ? raw.toDouble() : double.tryParse('$raw') ?? 0.0;
  }

  DateTime? get requestedExtensionDueDate =>
      parseAnyDate(extensionRequest['requested_due_at']);

  int get effectiveTotalExtendedMinutes {
    if (totalExtendedMinutes > 0) return totalExtendedMinutes;
    var sum = 0;
    for (final entry in extensionHistory) {
      final quote = entry['quote'];
      final raw = quote is Map ? quote['billed_minutes'] : null;
      sum += _asIntOrNull(raw) ?? _asIntOrNull(entry['additional_minutes']) ?? 0;
    }
    return sum;
  }

  static int? _asIntOrNull(dynamic value) =>
      value is num ? value.round() : int.tryParse(value?.toString() ?? '');

  static DateTime? parseAnyDate(dynamic value) {
    if (value is Timestamp) return value.toDate().toUtc();
    if (value is DateTime) return value.toUtc();
    if (value is! String || value.isEmpty) return null;
    final zoned = RegExp(r'(Z|[+-]\d\d:\d\d)$').hasMatch(value)
        ? value
        : '${value.replaceFirst(' ', 'T')}+08:00';
    return DateTime.tryParse(zoned);
  }

  bool get isAwaitingPickup => normalizedStatus == 'APPROVED';
  bool get isRentAndPlayPickup {
    if (fulfillmentMode.toUpperCase() == 'SHOP_HANDOVER') return true;
    if (fulfillmentMode.toUpperCase() == 'DELIVERY') return false;
    final location = deliveryLocation.trim().toLowerCase();
    return location.isEmpty ||
        location == 'shop pickup' ||
        location.startsWith('rent & play · lakewoods') ||
        location.startsWith('rent & play at asri hotspring resort') ||
        location.startsWith(rentAndPlayPickupLocation.toLowerCase());
  }

  String get customerHandoffLocation => isRentAndPlayPickup
      ? rentAndPlayPickupLocation
      : deliveryLocation.trim().isEmpty
          ? 'Delivery location not recorded'
          : deliveryLocation;
  bool get isAwaitingInspection =>
      normalizedStatus == 'RETURN_PENDING_INSPECTION';
  bool get canCancel =>
      (isPendingAdminReview || isAwaitingPickup) &&
      !const ['OUT_FOR_DELIVERY', 'DELIVERY_FAILED'].contains(deliveryStatus);

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
  bool get isReturnAwaitingTerminalConfirmation =>
      (latestTerminalRequestStatus.trim().toUpperCase() == 'PENDING' &&
          latestReturnRequestStatus.trim().toUpperCase() == 'PENDING') ||
      (isPendingVerification && normalizedStatus.contains('RETURN'));
  bool get isOpen =>
      isActive ||
      isPendingAdminReview ||
      isPendingVerification ||
      isAwaitingPickup ||
      isAwaitingInspection;

  String get statusLabel {
    if (isAwaitingPickup && deliveryStatus == 'OUT_FOR_DELIVERY') {
      return 'On the way · Lakewood';
    }
    if (isAwaitingPickup && deliveryStatus == 'DELIVERY_FAILED') {
      return 'Delivery needs attention';
    }
    if (isAwaitingPickup &&
        scheduledStartAt != null &&
        deliveryStatus == 'NOT_PREPARED') {
      return 'Scheduled';
    }
    if (isReturnAwaitingTerminalConfirmation) {
      return 'Receipt check · counter terminal';
    }
    if (isActive && hasPendingReturnRequest) return 'Return pending receipt';
    switch (normalizedStatus) {
      case 'APPROVED':
        return isRentAndPlayPickup
            ? (deliveryStatus == 'PREPARED'
                ? 'Ready for shop handover'
                : 'Approved · preparing your item')
            : (deliveryStatus == 'PREPARED'
                ? 'Ready for delivery'
                : 'Approved · preparing delivery');
      case 'RETURN_PENDING_INSPECTION':
        return 'Inspection in progress';
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
    this.stockGroupId = '',
    required this.itemName,
    this.itemImageUrl,
    required this.customerId,
    required this.customerName,
    required this.terminalId,
    this.terminalCode = '',
    this.deliveryLocation = rentAndPlayPickupLocation,
    required this.startDate,
    required this.dueDate,
    this.returnedDate,
    this.confirmedRentalAt,
    this.confirmedReturnAt,
    required this.rateFee,
    this.rentalPaidAmount,
    this.latePenalty = 0.0,
    this.overtimeRate = 0,
    this.overtimeUnitMinutes = 60,
    this.overtimeFee,
    this.penaltyAmount,
    this.penaltyReason = '',
    this.finalRentalCharges,
    this.billedMinutes,
    this.graceMinutes,
    this.overtimeUnits,
    required this.paymentMethod,
    this.paymentConfirmedByAdmin = false,
    required this.status,
    this.itemCode = '',
    this.customerPhone = '',
    this.returnCondition = 'Good',
    this.conditionNotes = '',
    this.returnResult = '',
    this.inspectedByName = '',
    this.latestReturnRequestStatus = '',
    this.latestTerminalRequestStatus = '',
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
    this.fulfillmentMode = '',
    this.scheduledStartAt,
    this.extensionRequest = const {},
    this.extensionHistory = const [],
    this.totalExtendedMinutes = 0,
    this.feeBreakdown = const {},
  });

  Map<String, dynamic> toReceiptMap() {
    final mergedFee = <String, dynamic>{
      ...feeBreakdown,
      'rental_fee': feeBreakdown['rental_fee'] ?? rateFee,
      'overtime_rate': feeBreakdown['overtime_rate'] ?? overtimeRate,
      'overtime_unit_minutes':
          feeBreakdown['overtime_unit_minutes'] ?? overtimeUnitMinutes,
      if (billedMinutes != null) 'billed_minutes': billedMinutes,
      if (graceMinutes != null) 'grace_minutes': graceMinutes,
      if (overtimeUnits != null) 'overtime_units': overtimeUnits,
      if (overtimeFee != null) 'overtime_fee': overtimeFee,
      if (penaltyAmount != null) 'penalty_amount': penaltyAmount,
      if (penaltyReason.isNotEmpty) 'penalty_reason': penaltyReason,
      if (finalRentalCharges != null)
        'final_rental_charges': finalRentalCharges,
    };
    return {
      'id': rentalId,
      if (rentalCode.isNotEmpty) 'rental_code': rentalCode,
      'customer_name': customerName,
      if (customerPhone.isNotEmpty) 'customer_phone': customerPhone,
      'item_name': itemName,
      if (itemCode.isNotEmpty) 'item_code': itemCode,
      if (fulfillmentMode.isNotEmpty) 'fulfillment_mode': fulfillmentMode,
      'delivery_location': customerHandoffLocation,
      if (confirmedRentalAt != null)
        'confirmed_rental_at': confirmedRentalAt!.toUtc().toIso8601String(),
      if (dueDate.millisecondsSinceEpoch > 0)
        'due_at': dueDate.toUtc().toIso8601String(),
      if (receivedAt != null)
        'received_at': receivedAt!.toUtc().toIso8601String(),
      if (confirmedReturnAt != null)
        'confirmed_return_at': confirmedReturnAt!.toUtc().toIso8601String(),
      'rental_fee': rateFee,
      if (rentalPaidAmount != null) 'rental_paid_amount': rentalPaidAmount,
      'payment_method': paymentMethod,
      if (paymentStatus.isNotEmpty) 'payment_status': paymentStatus,
      'balance_due': balanceDue,
      'refund_due': refundDue,
      'status': status,
      'return_condition': {
        'condition': returnCondition,
        if (conditionNotes.isNotEmpty) 'notes': conditionNotes,
        if (returnResult.isNotEmpty) 'result': returnResult,
        if (inspectedByName.isNotEmpty) 'inspected_by_name': inspectedByName,
      },
      'fee_breakdown': mergedFee,
    };
  }

  Map<String, dynamic> toMap() {
    return {
      'rentalId': rentalId,
      'itemId': itemId,
      if (itemCode.isNotEmpty) 'item_code': itemCode,
      'stock_group_id': stockGroupId,
      'itemName': itemName,
      'item_image_url': itemImageUrl,
      'customerId': customerId,
      'customerName': customerName,
      if (customerPhone.isNotEmpty) 'customer_phone': customerPhone,
      'terminalId': terminalId,
      if (terminalCode.isNotEmpty) 'terminal_code': terminalCode,
      'deliveryLocation': deliveryLocation,
      'startDate': Timestamp.fromDate(startDate),
      if (confirmedRentalAt != null)
        'confirmed_rental_at': Timestamp.fromDate(confirmedRentalAt!),
      'dueDate': Timestamp.fromDate(dueDate),
      'returnedDate':
          returnedDate != null ? Timestamp.fromDate(returnedDate!) : null,
      if (confirmedReturnAt != null)
        'confirmed_return_at': Timestamp.fromDate(confirmedReturnAt!),
      'rateFee': rateFee,
      if (rentalPaidAmount != null) 'rental_paid_amount': rentalPaidAmount,
      'latePenalty': latePenalty,
      if (overtimeFee != null) 'overtime_fee': overtimeFee,
      if (penaltyAmount != null) 'penalty_amount': penaltyAmount,
      if (penaltyReason.isNotEmpty) 'penalty_reason': penaltyReason,
      if (finalRentalCharges != null)
        'final_rental_charges': finalRentalCharges,
      'fee_breakdown': {
        ...feeBreakdown,
        'overtime_rate': overtimeRate,
        'overtime_unit_minutes': overtimeUnitMinutes,
        if (billedMinutes != null) 'billed_minutes': billedMinutes,
        if (graceMinutes != null) 'grace_minutes': graceMinutes,
        if (overtimeUnits != null) 'overtime_units': overtimeUnits,
        if (overtimeFee != null) 'overtime_fee': overtimeFee,
        if (penaltyAmount != null) 'penalty_amount': penaltyAmount,
        if (penaltyReason.isNotEmpty) 'penalty_reason': penaltyReason,
        if (finalRentalCharges != null)
          'final_rental_charges': finalRentalCharges,
      },
      'paymentMethod': paymentMethod,
      'paymentConfirmedByAdmin': paymentConfirmedByAdmin,
      'status': status,
      'returnCondition': returnCondition,
      'conditionNotes': conditionNotes,
      'return_condition': {
        'condition': returnCondition,
        if (conditionNotes.isNotEmpty) 'notes': conditionNotes,
        if (returnResult.isNotEmpty) 'result': returnResult,
        if (inspectedByName.isNotEmpty) 'inspected_by_name': inspectedByName,
      },
      'latest_return_request_status': latestReturnRequestStatus,
      'latest_terminal_request_status': latestTerminalRequestStatus,
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
      'fulfillment_mode': fulfillmentMode,
      'scheduled_start_at': scheduledStartAt?.toUtc().toIso8601String(),
      'extension_request': extensionRequest,
      'extension_history': extensionHistory,
      'total_extended_minutes': totalExtendedMinutes,
      if (feeBreakdown.isNotEmpty) 'fee_breakdown': feeBreakdown,
    };
  }

  factory RentalModel.fromMap(Map<String, dynamic> map, {String? id}) {
    DateTime? parseDate(dynamic value) {
      if (value is Timestamp) return value.toDate().toUtc();
      if (value is DateTime) return value.toUtc();
      if (value is! String || value.isEmpty) return null;
      final zoned = RegExp(r'(Z|[+-]\d\d:\d\d)$').hasMatch(value)
          ? value
          : '${value.replaceFirst(' ', 'T')}+08:00';
      return DateTime.tryParse(zoned);
    }

    double amount(dynamic value) => value is num
        ? value.toDouble()
        : double.tryParse(value?.toString() ?? '') ?? 0;
    double? optionalAmount(dynamic value) {
      if (value == null) return null;
      if (value is num && value.isFinite) return value.toDouble();
      final parsed = double.tryParse(value.toString().trim());
      return parsed != null && parsed.isFinite ? parsed : null;
    }

    int? optionalInt(dynamic value) {
      if (value == null) return null;
      if (value is num && value.isFinite) return value.toInt();
      return int.tryParse(value.toString().trim());
    }

    String text(dynamic value, [String fallback = '']) =>
        value?.toString() ?? fallback;
    String? optionalText(dynamic value) {
      final result = value?.toString().trim() ?? '';
      return result.isEmpty ? null : result;
    }

    final release = map['release_condition'];
    final returned = map['return_condition'];
    final fee = map['fee_breakdown'] is Map
        ? Map<String, dynamic>.from(map['fee_breakdown'] as Map)
        : const <String, dynamic>{};
    final fulfillment =
        text(map['fulfillment_mode'] ?? map['fulfillmentMode']).toUpperCase();
    return RentalModel(
      rentalId: id ?? text(map['id'] ?? map['rentalId']),
      itemId: text(map['item_id'] ?? map['itemId']),
      itemCode: text(map['item_code'] ?? map['itemCode']),
      stockGroupId: text(map['stock_group_id']),
      itemName: text(map['item_name'] ?? map['itemName'], 'Equipment'),
      itemImageUrl: optionalText(
          map['item_image_url'] ?? map['image_url'] ?? map['imageUrl']),
      customerId: text(map['customer_id'] ?? map['customerId']),
      customerName:
          text(map['customer_name'] ?? map['customerName'], 'Customer'),
      customerPhone: text(map['customer_phone'] ?? map['customerPhone']),
      terminalId: text(map['terminal_id'] ?? map['terminalId']),
      deliveryLocation: text(
          map['delivery_location'] ?? map['deliveryLocation'] ?? map['resort'],
          fulfillment == 'DELIVERY' ? '' : rentAndPlayPickupLocation),
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
      confirmedRentalAt: parseDate(map['confirmed_rental_at'] ?? fee['start_at']),
      confirmedReturnAt: parseDate(map['confirmed_return_at']),
      rateFee: amount(map['rental_fee'] ?? map['rateFee']),
      rentalPaidAmount:
          optionalAmount(map['rental_paid_amount'] ?? map['rentalPaidAmount']),
      latePenalty: amount(map['late_penalty'] ??
          map['latePenalty'] ??
          (amount(fee['overtime_fee']) + amount(fee['penalty_amount']))),
      overtimeRate: amount(fee['overtime_rate']),
      overtimeUnitMinutes: (fee['overtime_unit_minutes'] as num?)?.toInt() ?? 60,
      overtimeFee: optionalAmount(map['overtime_fee'] ?? fee['overtime_fee']),
      penaltyAmount:
          optionalAmount(map['penalty_amount'] ?? fee['penalty_amount']),
      penaltyReason: text(map['penalty_reason'] ?? fee['penalty_reason']),
      finalRentalCharges: optionalAmount(
          map['final_rental_charges'] ?? fee['final_rental_charges']),
      billedMinutes: optionalInt(fee['billed_minutes']),
      graceMinutes: optionalInt(fee['grace_minutes']),
      overtimeUnits: optionalInt(fee['overtime_units']),
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
      returnResult: text(returned is Map ? returned['result'] : ''),
      inspectedByName: text(returned is Map
          ? (returned['inspected_by_name'] ??
              returned['inspected_by_account_code'])
          : ''),
      latestReturnRequestStatus: text(map['latest_return_request_status'] ??
          map['latestReturnRequestStatus']),
      latestTerminalRequestStatus: text(
          map['latest_terminal_request_status'] ??
              map['latestTerminalRequestStatus']),
      rentalCode: text(map['rental_code']),
      terminalCode: text(map['terminal_code'] ?? map['terminalCode']),
      holdExpiresAt: parseDate(map['hold_expires_at']),
      receivedAt: parseDate(map['received_at']),
      balanceDue: amount(map['balance_due']),
      refundDue: amount(map['refund_due']),
      paymentStatus: text(map['payment_status']),
      paymentProofStatus: text(map['payment_proof_status']),
      paymentProofReference: text(map['payment_proof_reference']),
      paymentProofNote: text(map['payment_proof_note']),
      deliveryStatus: text(map['delivery_status']),
      fulfillmentMode: fulfillment,
      scheduledStartAt: parseDate(map['scheduled_start_at']),
      extensionRequest: map['extension_request'] is Map
          ? Map<String, dynamic>.from(map['extension_request'])
          : const {},
      extensionHistory: (map['extension_history'] as List? ?? const [])
          .whereType<Map>()
          .map((entry) => Map<String, dynamic>.from(entry))
          .toList(),
      totalExtendedMinutes: optionalInt(map['total_extended_minutes']) ?? 0,
      feeBreakdown: fee,
    );
  }

  RentalModel copyWith({
    String? rentalId,
    String? itemId,
    String? itemCode,
    String? stockGroupId,
    String? itemName,
    String? itemImageUrl,
    String? customerId,
    String? customerName,
    String? customerPhone,
    String? terminalId,
    String? terminalCode,
    String? deliveryLocation,
    DateTime? startDate,
    DateTime? dueDate,
    DateTime? returnedDate,
    DateTime? confirmedRentalAt,
    DateTime? confirmedReturnAt,
    double? rateFee,
    double? rentalPaidAmount,
    double? latePenalty,
    double? overtimeFee,
    double? penaltyAmount,
    String? penaltyReason,
    double? finalRentalCharges,
    int? billedMinutes,
    int? graceMinutes,
    int? overtimeUnits,
    String? paymentMethod,
    bool? paymentConfirmedByAdmin,
    String? status,
    String? returnCondition,
    String? conditionNotes,
    String? returnResult,
    String? inspectedByName,
    String? latestReturnRequestStatus,
    String? latestTerminalRequestStatus,
    String? paymentProofStatus,
    String? paymentProofReference,
    String? paymentProofNote,
    String? deliveryStatus,
    String? fulfillmentMode,
    DateTime? scheduledStartAt,
    Map<String, dynamic>? extensionRequest,
    List<Map<String, dynamic>>? extensionHistory,
    int? totalExtendedMinutes,
    Map<String, dynamic>? feeBreakdown,
  }) {
    return RentalModel(
      rentalId: rentalId ?? this.rentalId,
      itemId: itemId ?? this.itemId,
      itemCode: itemCode ?? this.itemCode,
      stockGroupId: stockGroupId ?? this.stockGroupId,
      itemName: itemName ?? this.itemName,
      itemImageUrl: itemImageUrl ?? this.itemImageUrl,
      customerId: customerId ?? this.customerId,
      customerName: customerName ?? this.customerName,
      customerPhone: customerPhone ?? this.customerPhone,
      terminalId: terminalId ?? this.terminalId,
      terminalCode: terminalCode ??
          (terminalId == null || terminalId == this.terminalId
              ? this.terminalCode
              : ''),
      deliveryLocation: deliveryLocation ?? this.deliveryLocation,
      startDate: startDate ?? this.startDate,
      dueDate: dueDate ?? this.dueDate,
      returnedDate: returnedDate ?? this.returnedDate,
      confirmedRentalAt: confirmedRentalAt ?? this.confirmedRentalAt,
      confirmedReturnAt: confirmedReturnAt ?? this.confirmedReturnAt,
      rateFee: rateFee ?? this.rateFee,
      rentalPaidAmount: rentalPaidAmount ?? this.rentalPaidAmount,
      latePenalty: latePenalty ?? this.latePenalty,
      overtimeFee: overtimeFee ?? this.overtimeFee,
      penaltyAmount: penaltyAmount ?? this.penaltyAmount,
      penaltyReason: penaltyReason ?? this.penaltyReason,
      finalRentalCharges: finalRentalCharges ?? this.finalRentalCharges,
      billedMinutes: billedMinutes ?? this.billedMinutes,
      graceMinutes: graceMinutes ?? this.graceMinutes,
      overtimeUnits: overtimeUnits ?? this.overtimeUnits,
      paymentMethod: paymentMethod ?? this.paymentMethod,
      paymentConfirmedByAdmin:
          paymentConfirmedByAdmin ?? this.paymentConfirmedByAdmin,
      status: status ?? this.status,
      returnCondition: returnCondition ?? this.returnCondition,
      conditionNotes: conditionNotes ?? this.conditionNotes,
      returnResult: returnResult ?? this.returnResult,
      inspectedByName: inspectedByName ?? this.inspectedByName,
      latestReturnRequestStatus:
          latestReturnRequestStatus ?? this.latestReturnRequestStatus,
      latestTerminalRequestStatus:
          latestTerminalRequestStatus ?? this.latestTerminalRequestStatus,
      rentalCode: rentalCode,
      holdExpiresAt: holdExpiresAt,
      receivedAt: receivedAt,
      balanceDue: balanceDue,
      refundDue: refundDue,
      overtimeRate: overtimeRate,
      overtimeUnitMinutes: overtimeUnitMinutes,
      paymentStatus: paymentStatus,
      paymentProofStatus: paymentProofStatus ?? this.paymentProofStatus,
      paymentProofReference:
          paymentProofReference ?? this.paymentProofReference,
      paymentProofNote: paymentProofNote ?? this.paymentProofNote,
      deliveryStatus: deliveryStatus ?? this.deliveryStatus,
      fulfillmentMode: fulfillmentMode ?? this.fulfillmentMode,
      scheduledStartAt: scheduledStartAt ?? this.scheduledStartAt,
      extensionRequest: extensionRequest ?? this.extensionRequest,
      extensionHistory: extensionHistory ?? this.extensionHistory,
      totalExtendedMinutes: totalExtendedMinutes ?? this.totalExtendedMinutes,
      feeBreakdown: feeBreakdown ?? this.feeBreakdown,
    );
  }
}
