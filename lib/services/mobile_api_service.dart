import 'dart:convert';
import 'dart:math';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

import '../models/rental_model.dart';

class MobileApiException implements Exception {
  const MobileApiException(this.message, {this.statusCode, this.code});

  final String message;
  final int? statusCode;
  final String? code;

  String get userMessage {
    final diagnostic = '${code ?? ''} $message'.toLowerCase();
    final isFirebaseServiceFailure = (code ?? '').toUpperCase().startsWith(
              'FIREBASE_',
            ) ||
        diagnostic.contains('firestore_quota_exceeded') ||
        diagnostic.contains('resource_exhausted') ||
        diagnostic.contains('quota exceeded') ||
        diagnostic.contains('usage limit') ||
        diagnostic.contains('firebase usage');
    return isFirebaseServiceFailure
        ? 'The rental service is temporarily unavailable. Please try again later.'
        : message;
  }

  @override
  String toString() => userMessage;
}

class MobileApiService {
  MobileApiService({FirebaseAuth? auth, http.Client? client})
      : _auth = auth ?? FirebaseAuth.instance,
        _client = client ?? http.Client();

  static final MobileApiService instance = MobileApiService();

  static const String _configuredBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://10.0.2.2:3000/api',
  );

  final FirebaseAuth _auth;
  final http.Client _client;

  static String operationKey() => List.generate(16,
          (_) => Random.secure().nextInt(256).toRadixString(16).padLeft(2, '0'))
      .join();

  Future<Map<String, dynamic>> adminRequest(
    String path, {
    String method = 'GET',
    Map<String, dynamic>? body,
    bool forceRefresh = false,
  }) =>
      _request(path, method: method, body: body, forceRefresh: forceRefresh);

  Future<Map<String, dynamic>> notifications({String? before, String? since}) {
    final query = <String, String>{
      if (before != null) 'before': before,
      if (since != null && before == null) 'since': since,
    };
    return _request(Uri(
            path: '/notifications',
            queryParameters: query.isEmpty ? null : query)
        .toString());
  }

  Future<void> markNotificationsRead(List<String> ids) async {
    await _request('/notifications/read', method: 'POST', body: {'ids': ids});
  }

  Future<void> registerNotificationDevice(String token) async {
    await _request('/notifications/device',
        method: 'POST', body: {'token': token});
  }

  Future<void> unregisterNotificationDevice(String token) async {
    await _request('/notifications/device',
        method: 'DELETE', body: {'token': token});
  }

  Future<Map<String, dynamic>> rentalRecord(String id) async {
    Map<String, dynamic>? result;
    try {
      result = await _request('/mobile/rentals/${Uri.encodeComponent(id)}');
    } on MobileApiException catch (error) {
      if (error.statusCode != 404) rethrow;
    }
    final rental = result?['rental'];
    if (rental is Map) return Map<String, dynamic>.from(rental);
    final records = result?['rentals'] as List? ?? const [];
    for (final row in records.whereType<Map>()) {
      if ((row['id'] ?? row['rentalId']).toString() == id) {
        return Map<String, dynamic>.from(row);
      }
    }

    // Older API deployments returned an empty list for the detail route. Fall
    // back to the authenticated customer list so existing notifications still
    // open their matching rental instead of showing a false "not found" error.
    final rentals = await listRentals();
    for (final row in rentals) {
      if (row.rentalId == id) return row.toMap();
    }
    throw const MobileApiException('Rental request not found.',
        statusCode: 404);
  }

  Future<Map<String, dynamic>> quoteRental(String itemId, int minutes) async {
    final result = await _request('/mobile/quote',
        method: 'POST', body: {'itemId': itemId, 'durationMinutes': minutes});
    return Map<String, dynamic>.from(result['quote'] as Map);
  }

  Future<Map<String, dynamic>> rentalTicket(String id) async {
    final result =
        await _request('/mobile/rentals/${Uri.encodeComponent(id)}/ticket');
    return Map<String, dynamic>.from(result['ticket'] as Map);
  }

  Future<Map<String, dynamic>> paymentInstructions() async =>
      _request('/mobile/payment-instructions');

  Future<void> submitPaymentProof({
    required String rentalId,
    required String imageDataUrl,
    String? reference,
  }) async {
    await _request(
      '/mobile/rentals/${Uri.encodeComponent(rentalId)}/payment-proof',
      method: 'POST',
      body: {
        'imageDataUrl': imageDataUrl,
        if (reference != null && reference.trim().isNotEmpty)
          'reference': reference.trim(),
      },
    );
  }

  Future<void> cancelRental(String id) async {
    await _request('/mobile/rentals/${Uri.encodeComponent(id)}/cancel',
        method: 'POST', body: {});
  }

  Future<Map<String, dynamic>> resolveEquipment(String code) async {
    final result = await _request('/mobile/catalog/resolve',
        method: 'POST', body: {'code': code}, authenticated: false);
    return Map<String, dynamic>.from(result['item'] as Map);
  }

  Uri _uri(String path) => Uri.parse(
        '${_configuredBaseUrl.replaceAll(RegExp(r'/+$'), '')}$path',
      );

  Future<Map<String, dynamic>> _request(
    String path, {
    String method = 'GET',
    Map<String, dynamic>? body,
    bool authenticated = true,
    bool forceRefresh = false,
  }) async {
    final headers = <String, String>{'Accept': 'application/json'};
    if (forceRefresh) headers['Cache-Control'] = 'no-cache';
    if (authenticated) {
      final user = _auth.currentUser;
      if (user == null) {
        throw const MobileApiException('Please sign in again to continue.',
            statusCode: 401);
      }
      final token = await user.getIdToken();
      if (token == null || token.isEmpty) {
        throw const MobileApiException(
            'Could not verify your sign-in. Please sign in again.',
            statusCode: 401);
      }
      headers['Authorization'] = 'Bearer $token';
    }

    if (body != null) headers['Content-Type'] = 'application/json';
    final uri = _uri(path);
    final response = switch (method) {
      'PATCH' => await _client
          .patch(uri, headers: headers, body: jsonEncode(body))
          .timeout(const Duration(seconds: 90)),
      'PUT' => await _client
          .put(uri, headers: headers, body: jsonEncode(body))
          .timeout(const Duration(seconds: 90)),
      'DELETE' => await _client
          .delete(uri, headers: headers, body: jsonEncode(body))
          .timeout(const Duration(seconds: 90)),
      'POST' => await _client
          .post(uri, headers: headers, body: jsonEncode(body))
          .timeout(const Duration(seconds: 90)),
      _ => await _client
          .get(uri, headers: headers)
          .timeout(const Duration(seconds: 90)),
    };

    dynamic decoded;
    try {
      decoded = response.body.isEmpty
          ? <String, dynamic>{}
          : jsonDecode(response.body);
    } on FormatException {
      decoded = <String, dynamic>{};
    }
    final result = decoded is Map<String, dynamic>
        ? decoded
        : decoded is Map
            ? Map<String, dynamic>.from(decoded)
            : <String, dynamic>{};

    if (response.statusCode < 200 || response.statusCode >= 300) {
      final message = result['error'];
      throw MobileApiException(
        message is String && message.isNotEmpty
            ? message
            : 'The rental service could not complete the request. Please try again.',
        statusCode: response.statusCode,
        code: result['code']?.toString(),
      );
    }
    return result;
  }

  Future<Map<String, dynamic>> profile(
          {String method = 'GET', Map<String, dynamic>? body}) =>
      _request('/mobile/profile', method: method, body: body);

  Future<List<Map<String, dynamic>>> catalog() async {
    final result = await _request('/mobile/catalog', authenticated: false);
    return (result['items'] as List)
        .whereType<Map>()
        .map(Map<String, dynamic>.from)
        .toList();
  }

  Future<void> _ensureCustomerProfile() async {
    await _request('/mobile/profile', method: 'POST', body: const {});
  }

  Future<RentalModel> createRentalRequest({
    required String itemId,
    required String itemName,
    String? itemCode,
    required int durationMinutes,
    required String deliveryLocation,
    required String paymentMethod,
    required String requestKey,
    required Map<String, dynamic> expectedQuote,
    String? paymentProofImageDataUrl,
    String? paymentReference,
  }) async {
    await _ensureCustomerProfile();
    final result = await _request(
      '/mobile/rentals',
      method: 'POST',
      body: {
        'itemId': itemId,
        'durationMinutes': durationMinutes,
        'deliveryLocation': deliveryLocation,
        'paymentMethod': paymentMethod.toUpperCase(),
        'requestKey': requestKey,
        'expectedQuote': expectedQuote,
        if (paymentMethod.toUpperCase() == 'QR' &&
            paymentProofImageDataUrl != null)
          'paymentProof': {
            'imageDataUrl': paymentProofImageDataUrl,
            if (paymentReference != null && paymentReference.trim().isNotEmpty)
              'reference': paymentReference.trim(),
          },
      },
    );
    final rental = result['rental'];
    if (rental is! Map) {
      throw const MobileApiException(
          'The rental service returned an invalid request record.');
    }
    final record = Map<String, dynamic>.from(rental);
    return RentalModel.fromMap(record,
        id: (record['id'] ?? record['rentalId'])?.toString());
  }

  Future<List<RentalModel>> listRentals() async {
    final result = await _request('/mobile/rentals');
    final records = result['rentals'];
    if (records is! List) return const [];
    return records.whereType<Map>().map((record) {
      final map = Map<String, dynamic>.from(record);
      return RentalModel.fromMap(map,
          id: (map['id'] ?? map['rentalId'])?.toString());
    }).toList();
  }

  Future<void> requestReturn({
    required String rentalId,
    required String condition,
    required String notes,
  }) async {
    await _request(
      '/mobile/rentals/${Uri.encodeComponent(rentalId)}/return',
      method: 'POST',
      body: {
        'condition': condition,
        'notes': notes.trim(),
      },
    );
  }
}
