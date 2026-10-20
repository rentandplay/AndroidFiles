import '../utils/record_codes.dart';
import 'dart:async';
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
        _client = client ?? http.Client() {
    try {
      _auth.authStateChanges().listen((_) => resetRentalEventStream());
    } catch (_) {}
  }

  static final MobileApiService instance = MobileApiService();

  static const String _configuredBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://192.168.1.35:3000/api',
  );

  static final List<String> _candidateBaseUrls = () {
    final list = <String>[
      _configuredBaseUrl,
      'http://192.168.1.35:3000/api',
      'http://127.0.0.1:3000/api',
      'http://10.0.2.2:3000/api',
    ];
    return list.toSet().toList();
  }();

  static String _activeBaseUrl = _configuredBaseUrl;


  final FirebaseAuth _auth;
  final http.Client _client;
  late final StreamController<Map<String, dynamic>> _rentalEventController =
      StreamController<Map<String, dynamic>>.broadcast(
    onListen: _startRentalEventStream,
    onCancel: _stopRentalEventStream,
  );
  StreamSubscription<Map<String, dynamic>>? _rentalEventTransport;
  int _rentalEventGeneration = 0;
  Timer? _retryTimer;
  Completer<void>? _retryCompleter;

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

  Future<Map<String, dynamic>> requestPasswordResetCode(String email) =>
      _request('/auth/password-reset/request',
          method: 'POST', authenticated: false, body: {'email': email});

  Future<Map<String, dynamic>> verifyPasswordResetCode(
          String email, String code) =>
      _request('/auth/password-reset/verify',
          method: 'POST',
          authenticated: false,
          body: {'email': email, 'code': code});

  Future<Map<String, dynamic>> completePasswordReset({
    required String email,
    required String verificationToken,
    required String requestKey,
    required String newPassword,
    required String confirmPassword,
  }) =>
      _request('/auth/password-reset/complete',
          method: 'POST',
          authenticated: false,
          body: {
            'email': email,
            'verificationToken': verificationToken,
            'requestKey': requestKey,
            'newPassword': newPassword,
            'confirmPassword': confirmPassword,
          });

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

  Future<Map<String, dynamic>> quoteRental(String itemId, int minutes,
      {String? stockGroupId, DateTime? scheduledStartAt}) async {
    final result = await _request('/mobile/quote', method: 'POST', body: {
      'itemId': itemId,
      if (stockGroupId != null && stockGroupId.isNotEmpty)
        'stockGroupId': stockGroupId,
      'durationMinutes': minutes,
      if (scheduledStartAt != null)
        'scheduledStartAt': scheduledStartAt.toUtc().toIso8601String()
    });
    return Map<String, dynamic>.from(result['quote'] as Map);
  }

  Future<Map<String, dynamic>> rentalTicket(String id) async {
    final result =
        await _request('/mobile/rentals/${Uri.encodeComponent(id)}/ticket');
    try {
      return validateRentalTicket(
          Map<String, dynamic>.from(result['ticket'] as Map), id);
    } on StateError catch (error) {
      throw MobileApiException(error.message.toString());
    }
  }

  Future<Map<String, dynamic>> paymentInstructions() async =>
      _request('/mobile/payment-instructions');

  Future<Map<String, dynamic>> terms() async =>
      _request('/mobile/terms', authenticated: false);

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

  Uri _uri(String path, [String? baseUrlOverride]) => Uri.parse(
        '${(baseUrlOverride ?? _activeBaseUrl).replaceAll(RegExp(r'/+$'), '')}$path',
      );

  Future<http.Response> _executeHttp(
    String method,
    Uri uri,
    Map<String, String> headers,
    Map<String, dynamic>? body,
  ) {
    return switch (method) {
      'PATCH' => _client
          .patch(uri, headers: headers, body: jsonEncode(body))
          .timeout(const Duration(seconds: 15)),
      'PUT' => _client
          .put(uri, headers: headers, body: jsonEncode(body))
          .timeout(const Duration(seconds: 15)),
      'DELETE' => _client
          .delete(uri, headers: headers, body: jsonEncode(body))
          .timeout(const Duration(seconds: 15)),
      'POST' => _client
          .post(uri, headers: headers, body: jsonEncode(body))
          .timeout(const Duration(seconds: 15)),
      _ => _client
          .get(uri, headers: headers)
          .timeout(const Duration(seconds: 15)),
    };
  }

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

    final candidateUrls = [
      _activeBaseUrl,
      ..._candidateBaseUrls.where((u) => u != _activeBaseUrl),
    ];

    http.Response? response;
    Object? lastError;

    for (final candidate in candidateUrls) {
      try {
        final uri = _uri(path, candidate);
        response = await _executeHttp(method, uri, headers, body);
        _activeBaseUrl = candidate;
        break;
      } catch (e) {
        lastError = e;
        final errStr = e.toString().toLowerCase();
        final isNetworkError = errStr.contains('socketexception') ||
            errStr.contains('no route to host') ||
            errStr.contains('connection refused') ||
            errStr.contains('failed host lookup') ||
            errStr.contains('clientexception') ||
            errStr.contains('timeoutexception');
        if (!isNetworkError) {
          rethrow;
        }
      }
    }

    if (response == null) {
      if (lastError != null) throw lastError;
      throw const MobileApiException(
          'Could not connect to the rental service. Please check your network.',
          statusCode: 503);
    }

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

  Future<void> sendRegistrationEmailCode(String email) async {
    await _request('/mobile/registration/email-code',
        method: 'POST', authenticated: false, body: {'email': email});
  }

  Future<String> verifyRegistrationEmailCode({
    required String email,
    required String code,
  }) async {
    final result = await _request('/mobile/registration/verify-email-code',
        method: 'POST',
        authenticated: false,
        body: {'email': email, 'code': code});
    final token = result['verificationToken'];
    if (token is! String || token.isEmpty) {
      throw const MobileApiException(
          'The verification service returned an invalid response.');
    }
    return token;
  }

  Future<Map<String, dynamic>> completeMobileRegistration({
    required String email,
    required String verificationToken,
    required String name,
    required String phone,
    required String termsVersion,
  }) =>
      _request('/mobile/registration/complete', method: 'POST', body: {
        'email': email,
        'verificationToken': verificationToken,
        'name': name,
        'phone': phone,
        'hasAcceptedTerms': true,
        'termsVersion': termsVersion,
      });

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
    String? stockGroupId,
    required String itemName,
    String? itemCode,
    required int durationMinutes,
    DateTime? scheduledStartAt,
    required String deliveryLocation,
    required String paymentMethod,
    required String requestKey,
    required Map<String, dynamic> expectedQuote,
    required bool acceptedRentalTerms,
    required String rentalTermsVersion,
    String? paymentProofImageDataUrl,
    String? paymentReference,
  }) async {
    await _ensureCustomerProfile();
    final result = await _request(
      '/mobile/rentals',
      method: 'POST',
      body: {
        'itemId': itemId,
        if (stockGroupId != null && stockGroupId.isNotEmpty)
          'stockGroupId': stockGroupId,
        'durationMinutes': durationMinutes,
        if (scheduledStartAt != null)
          'scheduledStartAt': scheduledStartAt.toUtc().toIso8601String(),
        'deliveryLocation': deliveryLocation,
        'paymentMethod': paymentMethod.toUpperCase(),
        'requestKey': requestKey,
        'expectedQuote': expectedQuote,
        'acceptedRentalTerms': acceptedRentalTerms,
        'rentalTermsVersion': rentalTermsVersion,
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

  String? nextRentalCursor;
  Future<({List<RentalModel> records, String? nextCursor})>
      listRentalHistoryPage(String cursor) async {
    final result = await _request('/mobile/rentals?${Uri(queryParameters: {
          'cursor': cursor,
          'limit': '5'
        }).query}');
    final records = (result['rentals'] as List)
        .whereType<Map>()
        .map((row) => RentalModel.fromMap(Map<String, dynamic>.from(row),
            id: row['id']?.toString()))
        .toList();
    return (records: records, nextCursor: result['nextCursor'] as String?);
  }

  Future<List<RentalModel>> listRentals() async {
    final result = await _request('/mobile/rentals');
    nextRentalCursor = result['nextCursor'] as String?;
    final records = result['rentals'];
    if (records is! List) return const [];
    return records.whereType<Map>().map((record) {
      final map = Map<String, dynamic>.from(record);
      return RentalModel.fromMap(map,
          id: (map['id'] ?? map['rentalId'])?.toString());
    }).toList();
  }

  Stream<Map<String, dynamic>> watchRentalEvents() {
    return _rentalEventController.stream;
  }

  void resetRentalEventStream() {
    final hasListeners = _rentalEventController.hasListener;
    _stopRentalEventStream();
    if (hasListeners) _startRentalEventStream();
  }

  void _startRentalEventStream() {
    if (_rentalEventTransport != null || !_rentalEventController.hasListener) {
      return;
    }
    final generation = ++_rentalEventGeneration;
    _rentalEventTransport = _readRentalEvents(generation).listen(
      (event) {
        if (generation == _rentalEventGeneration &&
            !_rentalEventController.isClosed) {
          _rentalEventController.add(event);
        }
      },
      onError: (Object _, StackTrace __) {},
      onDone: () {
        if (generation == _rentalEventGeneration) {
          _rentalEventTransport = null;
        }
      },
    );
  }

  void _stopRentalEventStream() {
    _rentalEventGeneration++;
    final transport = _rentalEventTransport;
    _rentalEventTransport = null;
    if (transport != null) unawaited(transport.cancel());
    _retryTimer?.cancel();
    _retryTimer = null;
    if (_retryCompleter != null && !_retryCompleter!.isCompleted) {
      _retryCompleter!.complete();
    }
    _retryCompleter = null;
  }

  Future<void> _delayRetry(int seconds, int generation) async {
    if (generation != _rentalEventGeneration ||
        !_rentalEventController.hasListener) {
      return;
    }
    final completer = Completer<void>();
    _retryCompleter = completer;
    _retryTimer = Timer(Duration(seconds: seconds), () {
      if (!completer.isCompleted) completer.complete();
    });
    await completer.future;
    if (_retryCompleter == completer) _retryCompleter = null;
    _retryTimer = null;
  }

  Stream<Map<String, dynamic>> _readRentalEvents(int generation) async* {
    var retrySeconds = 1;
    while (!_rentalEventController.isClosed &&
        generation == _rentalEventGeneration) {
      final user = _auth.currentUser;
      final connectedAt = DateTime.now();
      try {
        final token = user != null ? await user.getIdToken() : null;
        if (generation != _rentalEventGeneration) return;
        final request = http.Request('GET', _uri('/rental-events'))
          ..headers['Accept'] = 'text/event-stream'
          ..headers['Cache-Control'] = 'no-cache';
        if (token != null && token.isNotEmpty) {
          request.headers['Authorization'] = 'Bearer $token';
        }
        final response =
            await _client.send(request).timeout(const Duration(seconds: 30));
        if (response.statusCode == 204) {
          await response.stream.drain<void>();
          await _delayRetry(15, generation);
          continue;
        }
        if (response.statusCode == 401 || response.statusCode == 403) {
          await response.stream.drain<void>();
          await _delayRetry(10, generation);
          continue;
        }
        if (response.statusCode != 200 ||
            !(response.headers['content-type'] ?? '')
                .toLowerCase()
                .startsWith('text/event-stream')) {
          await response.stream.drain<void>();
          throw MobileApiException(
              'Live rental updates are temporarily unavailable.',
              statusCode: response.statusCode);
        }

        String? eventName;
        final dataLines = <String>[];
        await for (final line in response.stream
            .transform(utf8.decoder)
            .transform(const LineSplitter())) {
          if (generation != _rentalEventGeneration) return;
          if (line.isEmpty) {
            if (eventName != null && dataLines.isNotEmpty) {
              try {
                final decoded = jsonDecode(dataLines.join('\n'));
                if (decoded is Map) {
                  yield {
                    'event': eventName,
                    ...Map<String, dynamic>.from(decoded),
                  };
                }
              } on FormatException {
                // Ignore malformed frames and keep the connection alive.
              }
            }
            eventName = null;
            dataLines.clear();
            continue;
          }
          if (line.startsWith(':')) continue;
          if (line.startsWith('event:')) {
            eventName = line.substring(6).trim();
          } else if (line.startsWith('data:')) {
            dataLines.add(line.substring(5).trimLeft());
          }
        }
      } catch (_) {
        if (generation != _rentalEventGeneration) return;
      }
      if (generation != _rentalEventGeneration) return;
      if (DateTime.now().difference(connectedAt) > const Duration(minutes: 2)) {
        retrySeconds = 1;
      }
      await _delayRetry(retrySeconds, generation);
      retrySeconds = (retrySeconds * 2).clamp(1, 30).toInt();
    }
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
