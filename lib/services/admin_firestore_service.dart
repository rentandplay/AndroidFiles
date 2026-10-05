import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

class AdminApiException implements Exception {
  const AdminApiException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}

/// Direct Firebase access for the owner workspace.
///
/// The path-shaped method arguments are local screen actions only. This class
/// never builds a URI or contacts the website's HTTP API; each action maps to
/// the shared Firestore collections used by the website.
class AdminFirestoreService {
  AdminFirestoreService._();

  static final AdminFirestoreService instance = AdminFirestoreService._();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final Random _random = Random.secure();

  Map<String, dynamic>? _user;

  bool get hasSession => _auth.currentUser != null;
  Map<String, dynamic>? get currentUser => _user;

  Future<Map<String, dynamic>> signIn({
    required String email,
    required String password,
    bool remember = false,
  }) async {
    try {
      final normalizedEmail = email.trim().toLowerCase();
      final credential = await _auth.signInWithEmailAndPassword(
        email: normalizedEmail,
        password: password,
      );
      final user = credential.user;
      if (user == null) {
        throw const AdminApiException(
            'Sign in again to open the admin workspace.',
            statusCode: 401);
      }
      return await _loadAdminProfile(user);
    } on AdminApiException {
      rethrow;
    } on FirebaseAuthException catch (error) {
      throw AdminApiException(_authMessage(error), statusCode: 401);
    } on FirebaseException catch (error) {
      throw AdminApiException(_firestoreMessage(error),
          statusCode: _statusFor(error));
    } catch (error) {
      throw AdminApiException(
          'Could not sign in to the admin workspace: $error');
    }
  }

  Future<Map<String, dynamic>> restoreAdminSession() async {
    final user = _auth.currentUser;
    if (user == null) {
      throw const AdminApiException('Sign in with an active admin account.',
          statusCode: 401);
    }
    try {
      return await _loadAdminProfile(user);
    } on AdminApiException {
      rethrow;
    } on FirebaseException catch (error) {
      throw AdminApiException(_firestoreMessage(error),
          statusCode: _statusFor(error));
    }
  }

  Future<Map<String, dynamic>> _loadAdminProfile(User user) async {
    final snapshot = await _firestore.collection('users').doc(user.uid).get();
    if (!snapshot.exists || snapshot.data() == null) {
      _user = null;
      throw const AdminApiException(
        'This Firebase account has no admin workspace profile. Ask an administrator to activate it.',
        statusCode: 403,
      );
    }
    final profile = snapshot.data()!;
    final role = _string(profile['role']).toUpperCase();
    if (role != 'ADMIN' || profile['is_active'] != true) {
      _user = null;
      throw const AdminApiException(
        'This account is not an active administrator.',
        statusCode: 403,
      );
    }
    _user = <String, dynamic>{
      ..._serializeMap(profile),
      'id': user.uid,
      'name': profile['full_name'] ??
          profile['name'] ??
          user.displayName ??
          user.email?.split('@').first ??
          'Admin',
      'full_name': profile['full_name'] ??
          profile['name'] ??
          user.displayName ??
          'Admin',
      'email': profile['email'] ?? user.email ?? '',
      'role': 'ADMIN',
    };
    return Map<String, dynamic>.from(_user!);
  }

  Future<void> signOut() async {
    _user = null;
    await _auth.signOut();
  }

  Future<Map<String, dynamic>> loadWorkspace() => _guard(_loadWorkspace);

  Map<String, dynamic> dashboardFromWorkspace(
    Map<String, dynamic> workspace,
  ) =>
      _dashboardFromWorkspace(workspace);

  Map<String, dynamic> inventoryFromWorkspace(
    Map<String, dynamic> workspace,
  ) =>
      {
        'items': workspace['items'],
        'categories': workspace['categories'],
      };

  Future<T> _guard<T>(Future<T> Function() action) async {
    try {
      await restoreAdminSession();
      return await action();
    } on AdminApiException {
      rethrow;
    } on FirebaseAuthException catch (error) {
      throw AdminApiException(_authMessage(error), statusCode: 401);
    } on FirebaseException catch (error) {
      throw AdminApiException(_firestoreMessage(error),
          statusCode: _statusFor(error));
    } catch (error) {
      debugPrint('Admin Firestore operation failed: $error');
      throw AdminApiException(
          'Could not complete the workspace operation. Please refresh and try again.');
    }
  }

  Future<Map<String, dynamic>> getMap(String path) => _guard(() async {
        if (path == '/auth/me')
          return {'user': Map<String, dynamic>.from(_user!)};
        if (path == '/workspace') return _loadWorkspace();
        if (path == '/dashboard') return _loadDashboard();
        if (path == '/inventory') return _loadInventory();
        final qr = RegExp(r'^/inventory/([^/]+)/qr$').firstMatch(path);
        if (qr != null) return _loadQr(qr.group(1)!);
        final detail = RegExp(r'^/inventory/([^/]+)$').firstMatch(path);
        if (detail != null) return _loadInventoryDetail(detail.group(1)!);
        throw AdminApiException(
            'This admin workspace screen is not connected to Firebase yet.');
      });

  Future<Map<String, dynamic>> post(
    String path, {
    Map<String, dynamic> body = const {},
  }) =>
      _guard(() async {
        if (path == '/inventory') return _createItem(body);
        if (path == '/item-categories') return _createCategory(body);
        if (path == '/customers') return _createCustomer(body);
        if (path == '/rates') return _createRate(body);
        if (path == '/pricing/quote') return {'quote': await _quote(body)};
        if (path == '/rentals') return _createRentalRequest(body);
        if (path == '/returns') return _createReturnRequest(body);
        if (path == '/users') return _createWorkspaceUser(body);
        if (path == '/auth/password-reset') {
          final email = _string(body['email']).trim();
          if (email.isEmpty)
            throw const AdminApiException('Signed-in email is unavailable.');
          await _auth.sendPasswordResetEmail(email: email);
          return {'success': true};
        }
        final action = RegExp(r'^/inventory/([^/]+)/actions$').firstMatch(path);
        if (action != null) return _itemAction(action.group(1)!, body);
        throw AdminApiException(
            'This admin workspace action is not connected to Firebase yet.');
      });

  Future<Map<String, dynamic>> put(
    String path, {
    Map<String, dynamic> body = const {},
  }) =>
      _guard(() async {
        if (path == '/pricing') return _savePricing(body);
        final inspection =
            RegExp(r'^/verification-requests/([^/]+)/inspection$')
                .firstMatch(path);
        if (inspection != null)
          return _saveInspection(inspection.group(1)!, body);
        throw AdminApiException(
            'This admin workspace action is not connected to Firebase yet.');
      });

  Future<Map<String, dynamic>> patch(
    String path, {
    Map<String, dynamic> body = const {},
  }) =>
      _guard(() async {
        if (path == '/settings') return _saveBusinessSettings(body);
        if (path == '/profile') return _saveProfile(body);
        final user = RegExp(r'^/users/([^/]+)$').firstMatch(path);
        if (user != null) return _updateWorkspaceUser(user.group(1)!, body);
        final customer = RegExp(r'^/customers/([^/]+)$').firstMatch(path);
        if (customer != null) return _updateCustomer(customer.group(1)!, body);
        final item = RegExp(r'^/inventory/([^/]+)$').firstMatch(path);
        if (item != null) return _updateItem(item.group(1)!, body);
        throw AdminApiException(
            'This admin workspace action is not connected to Firebase yet.');
      });

  Future<Map<String, dynamic>> delete(
    String path, {
    Map<String, dynamic> body = const {},
  }) =>
      _guard(() async {
        final item = RegExp(r'^/inventory/([^/]+)$').firstMatch(path);
        if (item != null) {
          await _firestore.collection('items').doc(item.group(1)).set({
            'is_active': false,
            'updated_at': DateTime.now(),
          }, SetOptions(merge: true));
          return {'success': true};
        }
        final category = RegExp(r'^/item-categories/([^/]+)$').firstMatch(path);
        if (category != null) return _deleteCategory(category.group(1)!);
        throw AdminApiException(
            'This admin workspace action is not connected to Firebase yet.');
      });

  Future<Map<String, dynamic>> _loadWorkspace() async {
    final raw = await _loadRawWorkspace();
    final items = raw['items'] as List<Map<String, dynamic>>;
    final categories = raw['categories'] as List<Map<String, dynamic>>;
    final customers = raw['customers'] as List<Map<String, dynamic>>;
    final rentals = raw['rentals'] as List<Map<String, dynamic>>;
    final rates = raw['rates'] as List<Map<String, dynamic>>;
    final maintenance = raw['maintenance'] as List<Map<String, dynamic>>;
    final terminals = raw['terminals'] as List<Map<String, dynamic>>;
    final verification = raw['verification'] as List<Map<String, dynamic>>;
    final itemById = {for (final item in items) _string(item['id']): item};
    final customerById = {
      for (final customer in customers) _string(customer['id']): customer
    };
    final terminalById = {
      for (final terminal in terminals) _string(terminal['id']): terminal
    };

    final transactions = rentals.map((rental) {
      final item =
          itemById[_string(rental['item_id'])] ?? const <String, dynamic>{};
      final customer = customerById[_string(rental['customer_id'])] ??
          const <String, dynamic>{};
      return <String, dynamic>{
        ...rental,
        'item_name': item['name'] ?? 'Unknown equipment',
        'item_code': item['item_code'] ?? '',
        'customer_name': customer['full_name'] ?? 'Unknown customer',
        'customer': customer['full_name'] ?? 'Unknown customer',
      };
    }).toList()
      ..sort(
          (a, b) => _date(b['created_at']).compareTo(_date(a['created_at'])));

    final ratesWithItems = rates.map((rate) {
      final item =
          itemById[_string(rate['item_id'])] ?? const <String, dynamic>{};
      return <String, dynamic>{
        ...rate,
        'item_name': item['name'] ?? 'Unknown equipment',
        'item_code': item['item_code'] ?? ''
      };
    }).toList()
      ..sort((a, b) =>
          _date(b['effective_from']).compareTo(_date(a['effective_from'])));

    final maintenanceWithItems = maintenance.map((record) {
      final item =
          itemById[_string(record['item_id'])] ?? const <String, dynamic>{};
      return <String, dynamic>{
        ...record,
        'item_name': item['name'] ?? 'Unknown equipment',
        'item_code': item['item_code'] ?? ''
      };
    }).toList()
      ..sort(
          (a, b) => _date(b['started_at']).compareTo(_date(a['started_at'])));

    final verificationWithNames = verification.map((request) {
      final rental = rentals.cast<Map<String, dynamic>?>().firstWhere(
                (row) => _string(row?['id']) == _string(request['rental_id']),
                orElse: () => null,
              ) ??
          const <String, dynamic>{};
      final item = itemById[_string(request['item_id'] ?? rental['item_id'])] ??
          const <String, dynamic>{};
      final customer = customerById[_string(rental['customer_id'])] ??
          const <String, dynamic>{};
      final terminal = terminalById[_string(request['terminal_id'])] ??
          const <String, dynamic>{};
      return <String, dynamic>{
        ...request,
        'terminal_code':
            request['terminal_code'] ?? terminal['terminal_code'] ?? '',
        'item_code': item['item_code'] ?? '',
        'item_name': item['name'] ?? 'Unknown equipment',
        'customer_name': customer['full_name'] ?? 'Unknown customer',
        'transaction_type':
            request['transaction_type'] ?? request['type'] ?? '',
      };
    }).toList()
      ..sort((a, b) =>
          _date(b['requested_at']).compareTo(_date(a['requested_at'])));

    final itemRates = ratesWithItems;
    final decoratedItems = items
        .map((item) => _decorateItem(
              item,
              categories,
              itemRates,
              transactions,
              maintenanceWithItems,
            ))
        .toList()
      ..sort((a, b) => _string(a['name'])
          .toLowerCase()
          .compareTo(_string(b['name']).toLowerCase()));

    final settings = raw['settings'] as Map<String, dynamic>;
    final pricing = raw['pricing'] as Map<String, dynamic>;
    final users = (raw['users'] as List<Map<String, dynamic>>)
        .where(
            (user) => const ['ADMIN', 'admin'].contains(_string(user['role'])))
        .toList()
      ..sort((a, b) => _string(a['full_name'] ?? a['name'])
          .toLowerCase()
          .compareTo(_string(b['full_name'] ?? b['name']).toLowerCase()));
    return {
      'customers': customers
        ..sort((a, b) => _string(a['full_name'])
            .toLowerCase()
            .compareTo(_string(b['full_name']).toLowerCase())),
      'transactions': transactions,
      'maintenance': maintenanceWithItems,
      'rates': ratesWithItems,
      'items': decoratedItems,
      'categories': categories
        ..sort((a, b) => _string(a['name']).compareTo(_string(b['name']))),
      'terminals': terminals,
      'verification': verificationWithNames,
      'conditionRecords': raw['conditionRecords'],
      'statusHistory': raw['statusHistory'],
      'settings': settings,
      'pricing': pricing,
      'users': users,
      'refreshedAt': DateTime.now().toIso8601String(),
    };
  }

  Future<Map<String, dynamic>> _loadRawWorkspace() async {
    const names = <String>[
      'customers',
      'rentals',
      'items',
      'item_categories',
      'item_rates',
      'maintenance_records',
      'terminals',
      'verification_requests',
      'item_status_history',
      'item_condition_records',
    ];
    final snapshots = await Future.wait<QuerySnapshot<Map<String, dynamic>>>(
      names.map((name) => _firestore.collection(name).get()),
    );
    final source = <String, List<Map<String, dynamic>>>{};
    for (var index = 0; index < names.length; index++) {
      source[names[index]] = _docRows(snapshots[index]);
    }
    final settingRefs = await Future.wait([
      _firestore.collection('settings').doc('business').get(),
      _firestore.collection('settings').doc('pricing').get(),
      _firestore
          .collection('users')
          .where('role', whereIn: ['ADMIN', 'admin']).get(),
    ]);
    final businessDoc =
        settingRefs[0] as DocumentSnapshot<Map<String, dynamic>>;
    final pricingDoc = settingRefs[1] as DocumentSnapshot<Map<String, dynamic>>;
    final usersSnap = settingRefs[2] as QuerySnapshot<Map<String, dynamic>>;
    return {
      'customers': source['customers']!,
      'rentals': source['rentals']!,
      'items': source['items']!,
      'categories': source['item_categories']!,
      'rates': source['item_rates']!,
      'maintenance': source['maintenance_records']!,
      'terminals': source['terminals']!.map(_publicTerminal).toList(),
      'verification': source['verification_requests']!,
      'statusHistory': source['item_status_history']!,
      'conditionRecords': source['item_condition_records']!,
      'settings': businessDoc.exists
          ? _serializeMap(businessDoc.data()!)
          : <String, dynamic>{
              'business_name': 'Rent & Play',
              'location': 'Los Baños, Laguna',
              'currency': 'PHP',
              'timezone': 'Asia/Manila',
              'default_late_grace_hours': 0
            },
      'pricing': pricingDoc.exists
          ? _serializeMap(pricingDoc.data()!)
          : _defaultPricing(),
      'users': _docRows(usersSnap),
    };
  }

  Future<Map<String, dynamic>> _loadDashboard() async {
    final workspace = await _loadWorkspace();
    return _dashboardFromWorkspace(workspace);
  }

  Map<String, dynamic> _dashboardFromWorkspace(
    Map<String, dynamic> workspace,
  ) {
    final now = DateTime.now();
    final rentals = _rows(workspace['transactions']);
    final items = _rows(workspace['items']);
    final checks = _rows(workspace['verification']);
    final terminals = _rows(workspace['terminals']).map((terminal) {
      final lastSeen = _date(terminal['last_seen_at']);
      final online = _string(terminal['status']).toUpperCase() == 'ONLINE' &&
          terminal['last_seen_at'] != null &&
          now.difference(lastSeen).inSeconds < 90 &&
          !now.isBefore(lastSeen);
      return <String, dynamic>{...terminal, 'online': online};
    }).toList();
    final open = rentals
        .where((row) => const ['ACTIVE', 'PENDING_VERIFICATION']
            .contains(_string(row['status']).toUpperCase()))
        .toList()
      ..sort((a, b) => _date(a['due_at']).compareTo(_date(b['due_at'])));
    final active = rentals
        .where((row) => _string(row['status']).toUpperCase() == 'ACTIVE')
        .toList();
    final today = DateTime(now.year, now.month, now.day);
    final available = items
        .where((item) =>
            item['is_active'] != false &&
            _string(item['status']).toUpperCase() == 'AVAILABLE' &&
            (item['reserved_rental_id'] == null ||
                _string(item['reserved_rental_id']).isEmpty))
        .length;
    final weekStart =
        today.subtract(Duration(days: today.weekday - DateTime.monday));
    final revenue = List<double>.filled(7, 0);
    for (final rental in rentals) {
      if (!const ['ACTIVE', 'COMPLETED']
          .contains(_string(rental['status']).toUpperCase())) continue;
      final confirmed = rental['confirmed_rental_at'];
      if (confirmed == null) continue;
      final day = _date(confirmed).toLocal();
      final index =
          DateTime(day.year, day.month, day.day).difference(weekStart).inDays;
      if (index >= 0 && index < 7)
        revenue[index] += _number(rental['rental_fee']);
    }
    final overdue =
        active.where((row) => _date(row['due_at']).isBefore(now)).length;
    final dueToday = active.where((row) {
      final due = _date(row['due_at']).toLocal();
      return due.year == today.year &&
          due.month == today.month &&
          due.day == today.day;
    }).length;
    final pending = checks
        .where((row) => _string(row['status']).toUpperCase() == 'PENDING')
        .toList();
    return {
      'stats': {
        'active': active.length,
        'available': available,
        'dueToday': dueToday,
        'overdue': overdue,
        'fees': active.fold<double>(
            0, (sum, row) => sum + _number(row['rental_fee'])),
      },
      'revenue': {'This week': revenue, 'Last week': List<double>.filled(7, 0)},
      'rentals': open,
      'terminals': terminals,
      'pending': pending,
    };
  }

  Future<Map<String, dynamic>> _loadInventory() async {
    final workspace = await _loadWorkspace();
    return {'items': workspace['items'], 'categories': workspace['categories']};
  }

  Map<String, dynamic> _decorateItem(
    Map<String, dynamic> item,
    List<Map<String, dynamic>> categories,
    List<Map<String, dynamic>> rates,
    List<Map<String, dynamic>> rentals,
    List<Map<String, dynamic>> maintenance,
  ) {
    final itemId = _string(item['id']);
    final category = categories
        .where((row) => _string(row['id']) == _string(item['category_id']))
        .firstOrNull;
    final currentRates = rates
        .where((row) =>
            _string(row['item_id']) == itemId &&
            row['is_active'] != false &&
            !_date(row['effective_from']).isAfter(DateTime.now()) &&
            (row['effective_to'] == null ||
                _date(row['effective_to']).isAfter(DateTime.now())))
        .toList()
      ..sort((a, b) =>
          _date(b['effective_from']).compareTo(_date(a['effective_from'])));
    final rate =
        currentRates.isEmpty ? const <String, dynamic>{} : currentRates.first;
    final openRentals = rentals
        .where((row) =>
            _string(row['item_id']) == itemId &&
            const ['ACTIVE', 'PENDING_VERIFICATION']
                .contains(_string(row['status']).toUpperCase()))
        .length;
    final openMaintenance = maintenance
        .where((row) =>
            _string(row['item_id']) == itemId &&
            const ['OPEN', 'IN_PROGRESS']
                .contains(_string(row['status']).toUpperCase()))
        .length;
    return {
      ...item,
      'category': category?['name'] ?? 'Uncategorized',
      'rate_type': rate['rate_type'],
      'rental_rate': rate['rental_rate'],
      'deposit_amount': rate['deposit_amount'],
      'late_penalty_rate': rate['late_penalty_rate'],
      'pricing_product_id': item['pricing_product_id'],
      'open_rentals': openRentals,
      'open_maintenance': openMaintenance,
      'effective_status': item['is_active'] == false
          ? 'INACTIVE'
          : _string(item['status']).toUpperCase() == 'AVAILABLE' &&
                  openRentals > 0
              ? 'RESERVED_PENDING'
              : item['status'],
    };
  }

  Future<Map<String, dynamic>> _loadInventoryDetail(String id) async {
    final snapshot = await _firestore.collection('items').doc(id).get();
    if (!snapshot.exists || snapshot.data() == null)
      throw const AdminApiException('Equipment not found.', statusCode: 404);
    final item = <String, dynamic>{
      ..._serializeMap(snapshot.data()!),
      'id': snapshot.id
    };
    final workspace = await _loadWorkspace();
    final decorated =
        _rows(workspace['items']).where((row) => row['id'] == id).firstOrNull ??
            item;
    return {
      'item': decorated,
      'history': _rows(workspace['statusHistory'])
          .where((row) => _string(row['item_id']) == id)
          .toList(),
      'maintenance': _rows(workspace['maintenance'])
          .where((row) => _string(row['item_id']) == id)
          .toList(),
      'rates': _rows(workspace['rates'])
          .where((row) => _string(row['item_id']) == id)
          .toList(),
    };
  }

  Future<Map<String, dynamic>> _loadQr(String id) async {
    final ref = _firestore.collection('items').doc(id);
    final snapshot = await ref.get();
    if (!snapshot.exists || snapshot.data() == null)
      throw const AdminApiException('Equipment not found.', statusCode: 404);
    var token = _string(snapshot.data()!['qr_token']);
    if (token.isEmpty) {
      token = _newQrToken();
      await ref.set({'qr_token': token, 'updated_at': DateTime.now()},
          SetOptions(merge: true));
    }
    return {
      'id': id,
      'name': snapshot.data()!['name'],
      'code': snapshot.data()!['item_code'],
      'token': token
    };
  }

  Future<Map<String, dynamic>> _createCategory(
      Map<String, dynamic> body) async {
    final name = _string(body['name']).trim().replaceAll(RegExp(r'\s+'), ' ');
    if (name.isEmpty || name.length > 60)
      throw const AdminApiException(
          'Category name is required (maximum 60 characters).');
    final existing = await _firestore.collection('item_categories').get();
    if (existing.docs.any((doc) =>
        _string(doc.data()['name']).trim().toLowerCase() ==
        name.toLowerCase())) {
      throw const AdminApiException(
          'A category with this name already exists.');
    }
    final ref = _firestore.collection('item_categories').doc();
    final now = DateTime.now();
    final batch = _firestore.batch();
    batch.set(ref, {'name': name, 'created_at': now, 'created_by': _actorId});
    _audit(batch, 'ITEM_CATEGORY_CREATED', 'ITEM_CATEGORY', ref.id,
        newValues: {'name': name}, now: now);
    await batch.commit();
    return {
      'success': true,
      'category': {'id': ref.id, 'name': name}
    };
  }

  Future<Map<String, dynamic>> _deleteCategory(String id) async {
    final ref = _firestore.collection('item_categories').doc(id);
    final category = await ref.get();
    if (!category.exists)
      throw const AdminApiException('Category not found.', statusCode: 404);
    final used = await _firestore
        .collection('items')
        .where('category_id', isEqualTo: id)
        .limit(1)
        .get();
    if (used.docs.isNotEmpty)
      throw const AdminApiException(
          'Move the equipment in this category before deleting it.');
    final all = await _firestore.collection('item_categories').get();
    if (all.size <= 1)
      throw const AdminApiException('Keep at least one equipment category.');
    final now = DateTime.now();
    final batch = _firestore.batch()..delete(ref);
    _audit(batch, 'ITEM_CATEGORY_DELETED', 'ITEM_CATEGORY', id,
        oldValues: {'name': category.data()?['name']},
        newValues: {'deleted': true},
        now: now);
    await batch.commit();
    return {'success': true, 'id': id, 'deleted': true};
  }

  Future<Map<String, dynamic>> _createItem(Map<String, dynamic> body) async {
    final input = _validateItem(body);
    if (!const ['GOOD', 'FAIR'].contains(input['condition']))
      throw const AdminApiException(
          'New equipment must be in good or fair condition.');
    final categoryRef = _firestore
        .collection('item_categories')
        .doc(input['categoryId'] as String);
    final itemRef = _firestore.collection('items').doc();
    final rateRef = _firestore.collection('item_rates').doc();
    final counterRef = _firestore
        .collection('counters')
        .doc('item_codes_${input['categoryId']}');
    final codeBase = _firestore.collection('item_codes');
    final now = DateTime.now();
    var generatedCode = '';
    await _firestore.runTransaction((transaction) async {
      final categoryDoc = await transaction.get(categoryRef);
      final counterDoc = await transaction.get(counterRef);
      if (!categoryDoc.exists)
        throw const AdminApiException('The selected category does not exist.');
      final prefix = _itemCodePrefix(_string(categoryDoc.data()?['name']));
      final start = max(1, _int(counterDoc.data()?['next_sequence']));
      DocumentReference<Map<String, dynamic>>? codeRef;
      var sequence = start;
      for (var offset = 0; offset < 25; offset++) {
        final candidate =
            '$prefix-${(start + offset).toString().padLeft(4, '0')}';
        final candidateRef = codeBase.doc(candidate);
        final candidateDoc = await transaction.get(candidateRef);
        if (!candidateDoc.exists) {
          generatedCode = candidate;
          sequence = start + offset;
          codeRef = candidateRef;
          break;
        }
      }
      if (codeRef == null)
        throw const AdminApiException(
            'Could not allocate an equipment code. Try again.');
      final itemData = <String, dynamic>{
        'item_code': generatedCode,
        'category_id': input['categoryId'],
        'name': input['name'],
        'description': input['description'],
        'pricing_product_id': input['pricingProductId'],
        if (input['imageData'] != null &&
            _string(input['imageData']).isNotEmpty)
          'image_data': input['imageData'],
        'qr_token': _newQrToken(),
        'condition_status': input['condition'],
        'status': 'AVAILABLE',
        'is_active': true,
        'created_at': now,
        'updated_at': now,
      };
      transaction.set(codeRef, {'item_id': itemRef.id, 'created_at': now});
      transaction.set(
          counterRef,
          {'next_sequence': sequence + 1, 'updated_at': now},
          SetOptions(merge: true));
      transaction.set(itemRef, itemData);
      transaction.set(rateRef, _rateRecord(itemRef.id, input, now));
      final historyRef = _firestore.collection('item_status_history').doc();
      transaction.set(historyRef, {
        'item_id': itemRef.id,
        'old_status': null,
        'new_status': 'AVAILABLE',
        'source': 'WEB',
        'reference_type': 'CREATED',
        'changed_by': _actorId,
        'changed_at': now
      });
      final auditRef = _firestore.collection('audit_logs').doc();
      transaction.set(
          auditRef,
          _auditRecord(
              'ITEM_CREATED',
              'ITEM',
              itemRef.id,
              null,
              {
                'item_code': generatedCode,
                'name': input['name'],
                'category_id': input['categoryId'],
                'condition_status': input['condition'],
                'pricing_product_id': input['pricingProductId'],
                'rate_type': input['rateType'],
                'rental_rate': input['rentalRate'],
                'deposit_amount': input['deposit'],
              },
              now));
    });
    return {'success': true, 'id': itemRef.id, 'code': generatedCode};
  }

  Future<Map<String, dynamic>> _updateItem(
      String id, Map<String, dynamic> body) async {
    final next = _validateItem(body);
    final itemRef = _firestore.collection('items').doc(id);
    final itemSnap = await itemRef.get();
    if (!itemSnap.exists || itemSnap.data() == null)
      throw const AdminApiException('Equipment not found.', statusCode: 404);
    final current = _serializeMap(itemSnap.data()!);
    if (current['is_active'] == false)
      throw const AdminApiException(
          'Restore archived equipment before editing it.');
    if (body.containsKey('version') &&
        !_matchesVersion(current['updated_at'], body['version'])) {
      throw const AdminApiException(
          'This equipment changed since you opened it. Refresh and try again.');
    }
    final categorySnap = await _firestore
        .collection('item_categories')
        .doc(_string(next['categoryId']))
        .get();
    if (!categorySnap.exists)
      throw const AdminApiException('The selected category does not exist.');
    final results = await Future.wait([
      _firestore.collection('rentals').where('item_id', isEqualTo: id).get(),
      _firestore.collection('item_rates').where('item_id', isEqualTo: id).get(),
    ]);
    final rentalRows = _docRows(results[0]);
    final rateRows = _docRows(results[1]);
    final openCount = rentalRows
        .where((row) => const ['ACTIVE', 'PENDING_VERIFICATION']
            .contains(_string(row['status']).toUpperCase()))
        .length;
    if (openCount > 0 &&
        next['pricingProductId'] != (current['pricing_product_id'] ?? '')) {
      throw const AdminApiException(
          'Wait until the open rental is returned before changing its rate sheet product.');
    }
    if (openCount > 0 && next['condition'] != current['condition_status']) {
      throw const AdminApiException(
          'Equipment with an active or pending rental cannot have its condition changed.');
    }
    if (_string(current['status']).toUpperCase() == 'AVAILABLE' &&
        !const ['GOOD', 'FAIR'].contains(next['condition'])) {
      throw const AdminApiException(
          'Start maintenance before marking equipment damaged or needing inspection.');
    }
    final active = rateRows.where((row) => row['is_active'] != false).toList();
    final rate = active.isEmpty ? const <String, dynamic>{} : active.first;
    final rateChanged = rate['rate_type'] != next['rateType'] ||
        _number(rate['rental_rate']) != _number(next['rentalRate']) ||
        _number(rate['deposit_amount']) != _number(next['deposit']) ||
        _number(rate['late_penalty_rate']) != _number(next['latePenalty']);
    final now = DateTime.now();
    final batch = _firestore.batch();
    if (rateChanged) {
      for (final old in active) {
        batch.set(_firestore.collection('item_rates').doc(_string(old['id'])),
            {'is_active': false, 'effective_to': now}, SetOptions(merge: true));
      }
      batch.set(_firestore.collection('item_rates').doc(),
          _rateRecord(id, next, now));
    }
    final changes = <String, dynamic>{
      'category_id': next['categoryId'],
      'name': next['name'],
      'description': next['description'],
      'pricing_product_id': next['pricingProductId'],
      'condition_status': next['condition'],
      'updated_at': now,
      if (next.containsKey('imageData')) 'image_data': next['imageData'],
    };
    batch.set(itemRef, changes, SetOptions(merge: true));
    _audit(batch, 'ITEM_UPDATED', 'ITEM', id,
        oldValues: current,
        newValues: {...changes, 'rate_changed': rateChanged},
        now: now);
    await batch.commit();
    return {'success': true, 'id': id};
  }

  Future<Map<String, dynamic>> _itemAction(
      String id, Map<String, dynamic> body) async {
    final action = _string(body['action']);
    if (!const ['maintenance', 'complete-maintenance', 'archive', 'restore']
        .contains(action))
      throw const AdminApiException('Choose a valid inventory action.');
    final ref = _firestore.collection('items').doc(id);
    final snap = await ref.get();
    if (!snap.exists || snap.data() == null)
      throw const AdminApiException('Equipment not found.');
    final item = _serializeMap(snap.data()!);
    final now = DateTime.now();
    if (body.containsKey('version') &&
        !_matchesVersion(item['updated_at'], body['version'])) {
      throw const AdminApiException(
          'This equipment changed since you opened it. Refresh and try again.');
    }
    final all = await Future.wait([
      _firestore.collection('rentals').where('item_id', isEqualTo: id).get(),
      _firestore
          .collection('maintenance_records')
          .where('item_id', isEqualTo: id)
          .get(),
    ]);
    final openRentals = _docRows(all[0])
        .where((row) => const ['ACTIVE', 'PENDING_VERIFICATION']
            .contains(_string(row['status']).toUpperCase()))
        .toList();
    final maintenanceRows = _docRows(all[1]);
    final openMaintenance = maintenanceRows
        .where((row) => const ['OPEN', 'IN_PROGRESS']
            .contains(_string(row['status']).toUpperCase()))
        .toList();
    if (openRentals.isNotEmpty ||
        const ['RENTED', 'RESERVED_PENDING']
            .contains(_string(item['status']).toUpperCase())) {
      throw const AdminApiException(
          'Equipment with an active or pending rental cannot change availability.');
    }
    if (action == 'maintenance' &&
        (item['is_active'] == false ||
            item['status'] != 'AVAILABLE' ||
            openMaintenance.isNotEmpty)) {
      throw const AdminApiException(
          'Only available equipment without open maintenance can enter maintenance.');
    }
    if (action == 'complete-maintenance' &&
        (item['is_active'] == false || item['status'] != 'UNDER_MAINTENANCE')) {
      throw const AdminApiException('This equipment is not under maintenance.');
    }
    final condition = _string(body['condition']).toUpperCase();
    if (action == 'complete-maintenance' &&
        !const ['GOOD', 'FAIR'].contains(condition)) {
      throw const AdminApiException(
          'Equipment must be in good or fair condition before becoming available.');
    }
    if (action == 'maintenance' &&
        !const ['GOOD', 'FAIR', 'DAMAGED', 'NEEDS_INSPECTION']
            .contains(condition)) {
      throw const AdminApiException('Choose a valid condition.');
    }
    final reason = _string(body['reason']).trim();
    if ((action == 'maintenance' || action == 'complete-maintenance') &&
        reason.isEmpty) {
      throw const AdminApiException(
          'Add a maintenance reason or inspection note.');
    }
    final beforeStatus = _string(item['status']);
    var nextStatus = beforeStatus;
    final batch = _firestore.batch();
    if (action == 'maintenance') {
      nextStatus = 'UNDER_MAINTENANCE';
      batch.set(_firestore.collection('maintenance_records').doc(), {
        'item_id': id,
        'status': 'IN_PROGRESS',
        'reason': reason,
        'details': null,
        'started_at': now,
        'completed_at': null,
        'created_by': _actorId,
      });
      batch.set(
          ref,
          {
            'condition_status': condition,
            'status': nextStatus,
            'updated_at': now
          },
          SetOptions(merge: true));
    } else if (action == 'complete-maintenance') {
      nextStatus = 'AVAILABLE';
      if (openMaintenance.isEmpty) {
        batch.set(_firestore.collection('maintenance_records').doc(), {
          'item_id': id,
          'status': 'COMPLETED',
          'reason': 'Equipment inspection',
          'details': reason,
          'started_at': now,
          'completed_at': now,
          'created_by': _actorId,
        });
      } else {
        for (final record in openMaintenance) {
          batch.set(
              _firestore
                  .collection('maintenance_records')
                  .doc(_string(record['id'])),
              {'status': 'COMPLETED', 'completed_at': now, 'details': reason},
              SetOptions(merge: true));
        }
      }
      batch.set(
          ref,
          {
            'condition_status': condition,
            'status': nextStatus,
            'updated_at': now
          },
          SetOptions(merge: true));
    } else if (action == 'archive') {
      batch.set(ref, {'is_active': false, 'updated_at': now},
          SetOptions(merge: true));
    } else {
      batch.set(
          ref, {'is_active': true, 'updated_at': now}, SetOptions(merge: true));
    }
    if (beforeStatus != nextStatus) {
      final history = _firestore.collection('item_status_history').doc();
      batch.set(history, {
        'item_id': id,
        'old_status': beforeStatus,
        'new_status': nextStatus,
        'source': 'WEB',
        'reference_type': action.toUpperCase(),
        'changed_by': _actorId,
        'changed_at': now
      });
    }
    _audit(
        batch, 'ITEM_${action.toUpperCase().replaceAll('-', '_')}', 'ITEM', id,
        oldValues: {'status': beforeStatus},
        newValues: {
          'status': nextStatus,
          'is_active': action == 'archive'
              ? false
              : action == 'restore'
                  ? true
                  : item['is_active'],
          'reason': reason
        },
        now: now);
    await batch.commit();
    return {'success': true};
  }

  Future<Map<String, dynamic>> _createCustomer(
      Map<String, dynamic> body) async {
    final customer = _validateCustomer(body);
    final duplicate = await _firestore
        .collection('customers')
        .where('customer_code', isEqualTo: customer['customer_code'])
        .limit(1)
        .get();
    if (duplicate.docs.isNotEmpty)
      throw const AdminApiException('That customer code is already in use.');
    final ref = _firestore.collection('customers').doc();
    final now = DateTime.now();
    final data = {
      ...customer,
      'is_active': true,
      'created_at': now,
      'updated_at': now,
      'created_by': _actorId
    };
    await ref.set(data);
    return {
      'success': true,
      'id': ref.id,
      'customer': {'id': ref.id, ..._serializeMap(data)}
    };
  }

  Future<Map<String, dynamic>> _updateCustomer(
      String id, Map<String, dynamic> body) async {
    final ref = _firestore.collection('customers').doc(id);
    final snap = await ref.get();
    if (!snap.exists) throw const AdminApiException('Customer not found.');
    if (body['action'] == 'archive' || body['action'] == 'restore') {
      final active = body['action'] == 'restore';
      await ref.update({'is_active': active, 'updated_at': DateTime.now()});
      return {
        'success': true,
        'customer': {'id': id, 'is_active': active}
      };
    }
    final customer = _validateCustomer(body);
    final dupes = await _firestore
        .collection('customers')
        .where('customer_code', isEqualTo: customer['customer_code'])
        .get();
    if (dupes.docs.any((doc) => doc.id != id))
      throw const AdminApiException('That customer code is already in use.');
    final now = DateTime.now();
    await ref.update({...customer, 'updated_at': now});
    return {
      'success': true,
      'customer': {
        'id': id,
        ..._serializeMap(snap.data()!),
        ...customer,
        'updated_at': now.toIso8601String()
      }
    };
  }

  Future<Map<String, dynamic>> _createRate(Map<String, dynamic> body) async {
    final itemId = _string(body['itemId']);
    final type = _string(body['rateType']).toUpperCase();
    final rental = _amount(body['rentalRate'], 'Rental rate');
    final deposit = _amount(body['deposit'] ?? 0, 'Deposit');
    final late = _amount(body['latePenalty'] ?? 0, 'Late penalty');
    if (itemId.isEmpty || !const ['DAILY', 'HOURLY', 'FLAT'].contains(type))
      throw const AdminApiException('Choose equipment and a valid rate basis.');
    final item = await _firestore.collection('items').doc(itemId).get();
    if (!item.exists) throw const AdminApiException('Equipment not found.');
    final existing = await _firestore
        .collection('item_rates')
        .where('item_id', isEqualTo: itemId)
        .get();
    final now = DateTime.now();
    final rateRef = _firestore.collection('item_rates').doc();
    final batch = _firestore.batch();
    for (final doc
        in existing.docs.where((doc) => doc.data()['is_active'] != false)) {
      batch.update(doc.reference, {'is_active': false, 'effective_to': now});
    }
    final data = {
      'item_id': itemId,
      'rate_type': type,
      'rental_rate': rental,
      'deposit_amount': deposit,
      'late_penalty_rate': late,
      'is_active': true,
      'effective_from': now,
      'effective_to': null,
      'created_by': _actorId
    };
    batch.set(rateRef, data);
    _audit(batch, 'ITEM_RATE_CREATED', 'ITEM_RATE', rateRef.id,
        newValues: data, now: now);
    await batch.commit();
    return {
      'success': true,
      'id': rateRef.id,
      'rate': {'id': rateRef.id, ...data}
    };
  }

  Future<Map<String, dynamic>> _savePricing(Map<String, dynamic> body) async {
    final validated = _validatePricing(body);
    final now = DateTime.now();
    await _firestore.collection('settings').doc('pricing').set(
        {...validated, 'updated_at': now, 'updated_by': _actorId},
        SetOptions(merge: true));
    return {'success': true, 'pricing': validated};
  }

  Future<Map<String, dynamic>> _saveBusinessSettings(
      Map<String, dynamic> body) async {
    final name = _string(body['businessName']).trim();
    final location = _string(body['location']).trim();
    final currency = _string(body['currency']).trim().toUpperCase();
    final timezone = _string(body['timezone']).trim();
    final grace = _number(body['defaultLateGraceHours']);
    if (name.isEmpty ||
        location.isEmpty ||
        !RegExp(r'^[A-Z]{3}$').hasMatch(currency) ||
        timezone.isEmpty ||
        grace < 0 ||
        grace > 168) {
      throw const AdminApiException('Enter valid business settings.');
    }
    final value = {
      'business_name': name,
      'location': location,
      'currency': currency,
      'timezone': timezone,
      'default_late_grace_hours': grace,
      'updated_at': DateTime.now()
    };
    await _firestore
        .collection('settings')
        .doc('business')
        .set(value, SetOptions(merge: true));
    return {'success': true, 'settings': _serializeMap(value)};
  }

  Future<Map<String, dynamic>> _createWorkspaceUser(
      Map<String, dynamic> body) async {
    final name = _string(body['fullName']).trim();
    final email = _string(body['email']).trim().toLowerCase();
    final password = _string(body['password']);
    if (name.length < 2 ||
        !RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email) ||
        password.length < 12) {
      throw const AdminApiException(
          'Enter a valid name, email, and temporary password of at least 12 characters.');
    }
    FirebaseApp? secondaryApp;
    UserCredential? created;
    try {
      secondaryApp = await Firebase.initializeApp(
          name: 'admin-provision-${DateTime.now().microsecondsSinceEpoch}',
          options: Firebase.app().options);
      created = await FirebaseAuth.instanceFor(app: secondaryApp)
          .createUserWithEmailAndPassword(email: email, password: password);
      final createdUser = created.user;
      if (createdUser == null)
        throw const AdminApiException(
            'Firebase did not create the administrator account.');
      await _firestore.collection('users').doc(createdUser.uid).set({
        'full_name': name,
        'email': email,
        'role': 'ADMIN',
        'is_active': true,
        'created_at': DateTime.now(),
        'last_login_at': null,
      });
      return {
        'success': true,
        'user': {
          'id': createdUser.uid,
          'full_name': name,
          'email': email,
          'role': 'ADMIN',
          'is_active': true
        }
      };
    } on FirebaseAuthException catch (error) {
      if (created?.user != null)
        await created!.user!.delete().catchError((_) {});
      throw AdminApiException(_authMessage(error));
    } catch (_) {
      if (created?.user != null)
        await created!.user!.delete().catchError((_) {});
      rethrow;
    } finally {
      await secondaryApp?.delete();
    }
  }

  Future<Map<String, dynamic>> _updateWorkspaceUser(
      String id, Map<String, dynamic> body) async {
    final active = body['isActive'] != false;
    if (id == _auth.currentUser?.uid && !active)
      throw const AdminApiException('You cannot deactivate your own account.');
    final ref = _firestore.collection('users').doc(id);
    final snapshot = await ref.get();
    if (!snapshot.exists) throw const AdminApiException('User not found.');
    final role = _string(snapshot.data()?['role']);
    if (role.toUpperCase() != 'ADMIN')
      throw const AdminApiException('Only admin accounts can be changed here.');
    await ref.update({'is_active': active, 'updated_at': DateTime.now()});
    return {
      'success': true,
      'user': {'id': id, 'role': role, 'is_active': active}
    };
  }

  Future<Map<String, dynamic>> _createRentalRequest(
      Map<String, dynamic> body) async {
    final itemId = _string(body['itemId']);
    final customerId = _string(body['customerId']);
    final terminalId = _string(body['terminalId']);
    if (itemId.isEmpty || customerId.isEmpty || terminalId.isEmpty)
      throw const AdminApiException(
          'Equipment, customer, and terminal are required.');
    final itemRef = _firestore.collection('items').doc(itemId);
    final customerRef = _firestore.collection('customers').doc(customerId);
    final terminalRef = _firestore.collection('terminals').doc(terminalId);
    final pricingRef = _firestore.collection('settings').doc('pricing');
    final businessRef = _firestore.collection('settings').doc('business');
    final rateDocs = await _firestore
        .collection('item_rates')
        .where('item_id', isEqualTo: itemId)
        .get();
    final now = DateTime.now();
    final quoteData = await _frozenQuote(body, itemId, _docRows(rateDocs), now);
    final rentalRef = _firestore.collection('rentals').doc();
    final requestRef = _firestore.collection('verification_requests').doc();
    final requestCode = (100000 + _random.nextInt(900000)).toString();
    Map<String, dynamic>? rentalRecord;
    Map<String, dynamic>? requestRecord;
    await _firestore.runTransaction((transaction) async {
      final docs = await Future.wait([
        transaction.get(itemRef),
        transaction.get(customerRef),
        transaction.get(terminalRef),
        transaction.get(pricingRef),
        transaction.get(businessRef),
      ]);
      final itemDoc = docs[0];
      final customerDoc = docs[1];
      final terminalDoc = docs[2];
      if (!itemDoc.exists || !customerDoc.exists || !terminalDoc.exists)
        throw const AdminApiException(
            'Equipment, customer, or terminal not found.');
      final item = itemDoc.data()!;
      final customer = customerDoc.data()!;
      final terminal = terminalDoc.data()!;
      if (item['is_active'] == false ||
          item['status'] != 'AVAILABLE' ||
          _string(item['reserved_rental_id']).isNotEmpty)
        throw const AdminApiException(
            'This equipment is already reserved or unavailable.');
      if (customer['is_active'] == false || terminal['is_active'] == false)
        throw const AdminApiException(
            'Select an active customer and terminal.');
      if (!RegExp(r'^[a-f0-9]{64}$')
          .hasMatch(_string(terminal['auth_token_hash'])))
        throw const AdminApiException(
            'Configure the terminal device credential before requesting a handoff.');
      final inspection = _validateInspection(body['inspection'], 'RENTAL');
      final rental = <String, dynamic>{
        'rental_code':
            'R-${rentalRef.id.substring(0, min(10, rentalRef.id.length)).toUpperCase()}',
        'item_id': itemId,
        'customer_id': customerId,
        'status': 'PENDING_VERIFICATION',
        'due_at': quoteData['due_at'],
        'rental_fee': quoteData['rental_fee'],
        'deposit_amount': quoteData['deposit_amount'],
        'fee_breakdown': quoteData,
        'rental_request_id': requestRef.id,
        'release_condition': null,
        'return_condition': null,
        'confirmed_rental_at': null,
        'confirmed_return_at': null,
        'created_at': now,
        'updated_at': now,
        'created_by': _actorId,
      };
      final request = _verificationRecord(rentalRef.id, itemId, terminalId,
          terminal, 'RENTAL', now, requestCode)
        ..['requested_by'] = _actorId
        ..['inspection'] = inspection
        ..['inspection_revision'] = 1;
      rentalRecord = rental;
      requestRecord = request;
      transaction.set(rentalRef, rental);
      transaction.set(requestRef, request);
      transaction.set(
          itemRef,
          {'reserved_rental_id': rentalRef.id, 'updated_at': now},
          SetOptions(merge: true));
      final auditRef = _firestore.collection('audit_logs').doc();
      transaction.set(
          auditRef,
          _auditRecord('RENTAL_REQUESTED', 'VERIFICATION_REQUEST',
              requestRef.id, null, {'rental_id': rentalRef.id}, now));
    });
    return {
      'success': true,
      'rental': {'id': rentalRef.id, ..._serializeMap(rentalRecord!)},
      'request': {'id': requestRef.id, ..._serializeMap(requestRecord!)},
    };
  }

  Future<Map<String, dynamic>> _createReturnRequest(
      Map<String, dynamic> body) async {
    final rentalId = _string(body['rentalId']);
    final terminalId = _string(body['terminalId']);
    if (rentalId.isEmpty || terminalId.isEmpty)
      throw const AdminApiException('Rental and terminal are required.');
    final rentalRef = _firestore.collection('rentals').doc(rentalId);
    final terminalRef = _firestore.collection('terminals').doc(terminalId);
    final requestRef = _firestore.collection('verification_requests').doc();
    final pending = await _firestore
        .collection('verification_requests')
        .where('rental_id', isEqualTo: rentalId)
        .get();
    if (_docRows(pending).any(
        (row) => row['status'] == 'PENDING' && _requestType(row) == 'RETURN'))
      throw const AdminApiException(
          'This rental already has a pending return request.');
    final now = DateTime.now();
    final requestCode = (100000 + _random.nextInt(900000)).toString();
    Map<String, dynamic>? savedRequest;
    Map<String, dynamic>? rental;
    await _firestore.runTransaction((transaction) async {
      final rentalDoc = await transaction.get(rentalRef);
      final terminalDoc = await transaction.get(terminalRef);
      if (!rentalDoc.exists || !terminalDoc.exists)
        throw const AdminApiException('Rental or terminal not found.');
      final rentalData = rentalDoc.data()!;
      final terminal = terminalDoc.data()!;
      final itemRef =
          _firestore.collection('items').doc(_string(rentalData['item_id']));
      final itemDoc = await transaction.get(itemRef);
      if (rentalData['status'] != 'ACTIVE' ||
          !itemDoc.exists ||
          itemDoc.data()?['status'] != 'RENTED')
        throw const AdminApiException(
            'Only an active rental with rented equipment can be returned.');
      if (terminal['is_active'] == false)
        throw const AdminApiException('Choose an active terminal.');
      if (!RegExp(r'^[a-f0-9]{64}$')
          .hasMatch(_string(terminal['auth_token_hash'])))
        throw const AdminApiException(
            'Configure the terminal device credential before requesting a handoff.');
      final inspection = _validateInspection(body['inspection'], 'RETURN');
      final request = _verificationRecord(
          rentalId,
          _string(rentalData['item_id']),
          terminalId,
          terminal,
          'RETURN',
          now,
          requestCode)
        ..['requested_by'] = _actorId
        ..['inspection'] = inspection
        ..['inspection_revision'] = 1
        ..['actual_return_at'] = now
        ..['penalty_amount'] = _amount(body['penaltyAmount'] ?? 0, 'Penalty')
        ..['penalty_reason'] = _number(body['penaltyAmount']) > 0
            ? _string(body['penaltyReason']).trim()
            : null;
      savedRequest = request;
      rental = _serializeMap(rentalData);
      transaction.set(requestRef, request);
      transaction.set(
          rentalRef,
          {
            'latest_return_request_id': requestRef.id,
            'latest_return_request_status': 'PENDING',
            'updated_at': now
          },
          SetOptions(merge: true));
      final auditRef = _firestore.collection('audit_logs').doc();
      transaction.set(
          auditRef,
          _auditRecord('RETURN_REQUESTED', 'VERIFICATION_REQUEST',
              requestRef.id, null, {'rental_id': rentalId}, now));
    });
    final feePreview = _finalCharges(rental!, savedRequest!);
    return {
      'success': true,
      'request': {'id': requestRef.id, ..._serializeMap(savedRequest!)},
      'fee_preview': feePreview
    };
  }

  Future<Map<String, dynamic>> _saveInspection(
      String id, Map<String, dynamic> body) async {
    final ref = _firestore.collection('verification_requests').doc(id);
    final snap = await ref.get();
    if (!snap.exists || snap.data() == null)
      throw const AdminApiException('Verification request not found.');
    final request = _serializeMap(snap.data()!);
    final revision = _int(body['revision']);
    if (request['status'] != 'PENDING')
      throw const AdminApiException(
          'This request is closed. Refresh its final status.');
    if (revision != _int(request['inspection_revision']))
      throw const AdminApiException(
          'The inspection changed. Refresh before saving.');
    final type = _requestType(request);
    final inspection = _validateInspection(body, type);
    final changes = <String, dynamic>{
      'inspection': inspection,
      'inspection_revision': revision + 1
    };
    if (type == 'RETURN') {
      changes['penalty_amount'] = body['penaltyAmount'] == null
          ? null
          : _amount(body['penaltyAmount'], 'Penalty');
      changes['penalty_reason'] = _number(body['penaltyAmount']) > 0
          ? _string(body['penaltyReason']).trim()
          : null;
    }
    await ref.update(changes);
    return {
      'success': true,
      'request': {'id': id, ...request, ..._serializeMap(changes)}
    };
  }

  Future<Map<String, dynamic>> _saveProfile(Map<String, dynamic> body) async {
    final user = _auth.currentUser;
    if (user == null)
      throw const AdminApiException('Sign in again to update your profile.',
          statusCode: 401);
    final name = _string(body['fullName']).trim();
    final email = _string(body['email']).trim().toLowerCase();
    if (name.length < 2 ||
        !RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email))
      throw const AdminApiException('Enter a valid name and email.');
    if (email != (user.email ?? '').toLowerCase())
      await user.updateEmail(email);
    await user.updateDisplayName(name);
    await _firestore.collection('users').doc(user.uid).set(
        {'full_name': name, 'email': email, 'updated_at': DateTime.now()},
        SetOptions(merge: true));
    _user = {...?_user, 'name': name, 'full_name': name, 'email': email};
    return {'success': true, 'user': Map<String, dynamic>.from(_user!)};
  }

  Future<Map<String, dynamic>> _quote(Map<String, dynamic> body) async {
    final pricingSnap =
        await _firestore.collection('settings').doc('pricing').get();
    final pricing = pricingSnap.exists
        ? _serializeMap(pricingSnap.data()!)
        : _defaultPricing();
    return _quoteFromPricing(pricing, body);
  }

  Future<Map<String, dynamic>> _frozenQuote(
    Map<String, dynamic> body,
    String itemId,
    List<Map<String, dynamic>> rates,
    DateTime now,
  ) async {
    final itemSnap = await _firestore.collection('items').doc(itemId).get();
    if (!itemSnap.exists || itemSnap.data() == null)
      throw const AdminApiException('Equipment not found.');
    final item = itemSnap.data()!;
    final businessSnap =
        await _firestore.collection('settings').doc('business').get();
    final grace = _number(businessSnap.data()?['default_late_grace_hours']);
    if (grace < 0 || grace > 168)
      throw const AdminApiException(
          'Correct the business grace period before requesting a rental.');
    final startAt = _parseDate(body['startAt']) ?? now;
    Map<String, dynamic> base;
    final productId = _string(item['pricing_product_id']);
    if (productId.isNotEmpty) {
      final pricingSnap =
          await _firestore.collection('settings').doc('pricing').get();
      final pricing = pricingSnap.exists
          ? _serializeMap(pricingSnap.data()!)
          : _defaultPricing();
      base = _quoteFromPricing(pricing, {
        ...body,
        'productId': productId,
        'startAt': startAt.toIso8601String()
      });
      if (base['deposit_configured'] == false)
        throw const AdminApiException(
            'Configure the required refundable deposit before requesting this rental.');
      base = {
        'pricing_source': 'RATE_SHEET',
        'product_id': base['product_id'],
        'product_name': base['product_name'],
        'rate_id': base['rate_id'],
        'rate_label': base['rate_label'],
        'rate_kind': base['rate_kind'],
        'rate_components': base['rate_components'],
        'mode': body['mode'] == 'WHOLE_STAY' ? 'WHOLE_STAY' : 'TIMED',
        'requested_minutes': base['requested_minutes'],
        'billed_minutes': base['billed_minutes'],
        'rental_fee': base['rental_fee'],
        'deposit_amount': base['deposit_amount'],
        'start_at': startAt,
        'due_at': _parseDate(base['due_at'])!,
        'overtime_rate': base['overtime_rate_per_hour'],
        'overtime_unit_minutes': 60,
        'lost_piece_fee': base['lost_piece_fee'],
        'overtime_basis': base['overtime_basis'],
        'after_hours_return_note': base['after_hours_return_note'],
      };
    } else {
      final current = rates
          .where((rate) =>
              rate['is_active'] != false &&
              !_date(rate['effective_from']).isAfter(now) &&
              (rate['effective_to'] == null ||
                  _date(rate['effective_to']).isAfter(now)))
          .toList()
        ..sort((a, b) =>
            _date(b['effective_from']).compareTo(_date(a['effective_from'])));
      if (current.isEmpty)
        throw const AdminApiException(
            'Configure an equipment rate or link a rate sheet product.');
      final rate = current.first;
      final type = _string(rate['rate_type']).toUpperCase();
      final minutes = _int(body['durationMinutes']);
      if (!const ['HOURLY', 'DAILY', 'FLAT'].contains(type) ||
          minutes < 1 ||
          minutes > 10080 ||
          body['mode'] == 'WHOLE_STAY')
        throw const AdminApiException(
            'Choose a timed rental duration between 1 minute and 7 days.');
      final unit = type == 'DAILY'
          ? 1440
          : type == 'HOURLY'
              ? 60
              : minutes;
      final units = (minutes / unit).ceil();
      final billed = units * unit;
      base = {
        'pricing_source': 'ITEM_RATE',
        'product_id': null,
        'product_name': item['name'],
        'rate_id': rate['id'],
        'rate_label': '$type equipment rate',
        'rate_kind': type,
        'rate_components': [
          {
            'rate_id': rate['id'],
            'label': type,
            'kind': type,
            'units': units,
            'unit_amount': rate['rental_rate'],
            'duration_minutes': unit,
            'total_amount': _roundMoney(units * _number(rate['rental_rate']))
          }
        ],
        'mode': 'TIMED',
        'requested_minutes': minutes,
        'billed_minutes': billed,
        'rental_fee': _roundMoney(units * _number(rate['rental_rate'])),
        'deposit_amount': rate['deposit_amount'],
        'start_at': startAt,
        'due_at': startAt.add(Duration(minutes: billed)),
        'overtime_rate': rate['late_penalty_rate'],
        'overtime_unit_minutes': type == 'DAILY' ? 1440 : 60,
        'lost_piece_fee': null,
      };
    }
    final due = _date(base['due_at']);
    if (!due.isAfter(now) || startAt.difference(now).inMinutes.abs() > 5)
      throw const AdminApiException(
          'Rental starts must be within five minutes of now and due after now.');
    return {
      ...base,
      'snapshot_version': 1,
      'currency': 'PHP',
      'saved_at': now,
      'grace_minutes': grace * 60,
      'actual_return_at': null,
      'overtime_units': null,
      'overtime_fee': null,
      'penalty_amount': null,
      'penalty_reason': null,
      'final_rental_charges': null,
      'finalized_at': null,
    };
  }

  Map<String, dynamic> _quoteFromPricing(
      Map<String, dynamic> pricing, Map<String, dynamic> body) {
    final products = _rows(pricing['products']);
    final id = _string(body['productId']);
    final product =
        products.where((row) => _string(row['id']) == id).firstOrNull;
    if (product == null)
      throw const AdminApiException(
          'Choose a product from the Rent & Play rate sheet.');
    final rates = _rows(product['rate_options']);
    final start = _parseDate(body['startAt']) ?? DateTime.now();
    final mode = _string(body['mode']);
    var amount = 0.0;
    var billedMinutes = 0;
    var due = start;
    var rateLabel = '';
    var rateId = '';
    var rateKind = '';
    List<Map<String, dynamic>> components = [];
    if (mode == 'WHOLE_STAY') {
      final plan =
          rates.where((rate) => rate['kind'] == 'WHOLE_STAY').firstOrNull;
      final checkout = _parseDate(body['resortCheckoutAt']);
      if (plan == null || checkout == null || !checkout.isAfter(start))
        throw AdminApiException(
            '${product['name']} requires a valid checkout time after rental start.');
      amount = _number(plan['amount']);
      billedMinutes = (checkout.difference(start).inSeconds / 60).ceil();
      due = checkout;
      rateLabel = _string(plan['label']);
      rateId = _string(plan['id']);
      rateKind = _string(plan['kind']);
      components = [_rateComponent(plan, 1)];
    } else {
      final duration = _int(body['durationMinutes']);
      if (duration < 1 || duration > 10080)
        throw const AdminApiException(
            'Rental duration must be between 1 minute and 7 days.');
      final hourly =
          rates.where((rate) => rate['kind'] == 'HOURLY').firstOrNull;
      final choices = <Map<String, dynamic>>[];
      for (final rate in rates) {
        final kind = _string(rate['kind']);
        if (kind == 'HOURLY' || kind == 'BLOCK') {
          final block = max(1, _int(rate['duration_minutes']));
          final units = (duration / block).ceil();
          choices.add({
            'amount': units * _number(rate['amount']),
            'billed': units * block,
            'label': '${rate['label']}',
            'id': rate['id'],
            'kind': kind,
            'components': [_rateComponent(rate, units)]
          });
        } else if (kind == 'SHORT' &&
            duration <= _int(rate['duration_minutes'])) {
          choices.add({
            'amount': _number(rate['amount']),
            'billed': _int(rate['duration_minutes']),
            'label': rate['label'],
            'id': rate['id'],
            'kind': kind,
            'components': [_rateComponent(rate, 1)]
          });
        } else if (kind == 'PACKAGE' && hourly != null) {
          final hourlyMinutes = max(1, _int(hourly['duration_minutes']));
          final standard = (duration / hourlyMinutes).ceil();
          final package =
              (_int(rate['duration_minutes']) / hourlyMinutes).ceil();
          if (standard >= package) {
            final extra = standard - package;
            choices.add({
              'amount':
                  _number(rate['amount']) + extra * _number(hourly['amount']),
              'billed': standard * hourlyMinutes,
              'label':
                  '${rate['label']}${extra > 0 ? ' + $extra extra hour(s)' : ''}',
              'id': rate['id'],
              'kind': kind,
              'components': [
                _rateComponent(rate, 1),
                if (extra > 0) _rateComponent(hourly, extra)
              ]
            });
          }
        }
      }
      if (choices.isEmpty)
        throw AdminApiException(
            'No timed rental rate is configured for ${product['name']}.');
      choices
          .sort((a, b) => _number(a['amount']).compareTo(_number(b['amount'])));
      final best = choices.first;
      amount = _number(best['amount']);
      billedMinutes = _int(best['billed']);
      rateLabel = _string(best['label']);
      rateId = _string(best['id']);
      rateKind = _string(best['kind']);
      components = _rows(best['components']);
      due = start.add(Duration(minutes: billedMinutes));
    }
    final rules = _map(pricing['rules']);
    final deposit = _number(product['deposit_amount']);
    final highValue = product['high_value'] == true;
    final overtime = _number(product['overtime_rate_per_hour']);
    return {
      'product_id': id,
      'product_name': product['name'],
      'rate_label': rateLabel,
      'rate_id': rateId,
      'rate_kind': rateKind,
      'rate_components': components,
      'start_at': start.toIso8601String(),
      'requested_minutes':
          mode == 'WHOLE_STAY' ? billedMinutes : _int(body['durationMinutes']),
      'rental_fee': _roundMoney(amount),
      'overtime_blocks': 0,
      'overtime_rate_per_hour': overtime,
      'overtime_fee': 0,
      'rental_charge_total': _roundMoney(amount),
      'deposit_amount': deposit,
      'deposit_required':
          highValue && rules['high_value_deposit_required'] != false,
      'deposit_configured': !highValue ||
          rules['high_value_deposit_required'] == false ||
          deposit > 0,
      'valid_id_required': rules['valid_id_required'] != false,
      'billed_minutes': billedMinutes,
      'total_to_collect': _roundMoney(amount + deposit),
      'due_at': due.toIso8601String(),
      'actual_return_at': null,
      'after_hours_return_note': rules['after_hours_returns'],
      'overtime_basis': rules['overtime_basis'],
      'lost_piece_fee': _number(rules['lost_piece_fee']),
      'warnings': <String>[],
    };
  }

  Map<String, dynamic> _validatePricing(Map<String, dynamic> body) {
    final defaults = _rows(_defaultPricing()['products']);
    final inputProducts = _rows(body['products']);
    if (inputProducts.isEmpty)
      throw const AdminApiException(
          'Pricing setup is unavailable. Reload before saving.');
    final byId = {for (final row in inputProducts) _string(row['id']): row};
    final products = <Map<String, dynamic>>[];
    for (final base in defaults) {
      final submitted = byId[_string(base['id'])];
      if (submitted == null)
        throw AdminApiException('Pricing setup is missing ${base['name']}.');
      final rateMap = {
        for (final rate in _rows(submitted['rate_options']))
          _string(rate['id']): rate
      };
      final next = Map<String, dynamic>.from(base);
      next['rate_options'] = _rows(base['rate_options']).map((rate) {
        final input = rateMap[_string(rate['id'])];
        if (input == null)
          throw AdminApiException('A rate is missing for ${base['name']}.');
        return {
          ...rate,
          'amount': _amount(input['amount'], '${base['name']} ${rate['label']}')
        };
      }).toList();
      next['deposit_amount'] =
          _amount(submitted['deposit_amount'] ?? 0, '${base['name']} deposit');
      next['overtime_rate_per_hour'] = _amount(
          submitted['overtime_rate_per_hour'] ?? base['overtime_rate_per_hour'],
          '${base['name']} overtime rate');
      next['included_items'] = _rows(submitted['included_items']).isEmpty
          ? (submitted['included_items'] is List
              ? submitted['included_items']
              : base['included_items'])
          : submitted['included_items'];
      if (base['sale_price'] != null)
        next['sale_price'] = _amount(
            submitted['sale_price'] ?? base['sale_price'],
            '${base['name']} sale price');
      products.add(next);
    }
    final rules = {..._map(_defaultPricing()['rules']), ..._map(body['rules'])};
    final open = _string(rules['opens_at']);
    final close = _string(rules['closes_at']);
    if (!RegExp(r'^([01]\d|2[0-3]):[0-5]\d$').hasMatch(open) ||
        !RegExp(r'^([01]\d|2[0-3]):[0-5]\d$').hasMatch(close) ||
        open.compareTo(close) >= 0)
      throw const AdminApiException('Enter valid daily service hours.');
    rules['valid_id_required'] = rules['valid_id_required'] != false;
    rules['high_value_deposit_required'] =
        rules['high_value_deposit_required'] != false;
    rules['lost_piece_fee'] =
        _amount(rules['lost_piece_fee'] ?? 50, 'Lost piece fee');
    return {'products': products, 'rules': rules};
  }

  Map<String, dynamic> _validateItem(Map<String, dynamic> body) {
    final name = _string(body['name']).trim();
    final category = _string(body['categoryId']).trim();
    final description = _string(body['description']);
    final condition = _string(body['condition']).toUpperCase();
    final rateType = _string(body['rateType']).toUpperCase();
    final productId = _string(body['pricingProductId']).trim();
    if (name.isEmpty || name.length > 150 || category.isEmpty)
      throw const AdminApiException('Enter an equipment name and category.');
    if (description.length > 2000)
      throw const AdminApiException(
          'Description must be 2,000 characters or fewer.');
    if (!const ['GOOD', 'FAIR', 'DAMAGED', 'NEEDS_INSPECTION']
        .contains(condition))
      throw const AdminApiException('Choose a valid equipment condition.');
    if (!const ['DAILY', 'HOURLY', 'FLAT'].contains(rateType))
      throw const AdminApiException('Choose a valid rental rate type.');
    if (productId.isNotEmpty &&
        !_rows(_defaultPricing()['products'])
            .any((row) => _string(row['id']) == productId))
      throw const AdminApiException(
          'Choose a product from the client rate sheet.');
    if (body['imageData'] != null && _string(body['imageData']).length > 250000)
      throw const AdminApiException(
          'Equipment photo is too large. Choose a smaller image.');
    return {
      'name': name,
      'categoryId': category,
      'description': description.trim(),
      'condition': condition,
      'rateType': rateType,
      'rentalRate': _amount(body['rentalRate'], 'Rental rate'),
      'deposit': _amount(body['deposit'] ?? 0, 'Deposit'),
      'latePenalty': _amount(body['latePenalty'] ?? 0, 'Late penalty'),
      'pricingProductId': productId.isEmpty ? null : productId,
      if (body.containsKey('imageData')) 'imageData': body['imageData'],
    };
  }

  Map<String, dynamic> _validateCustomer(Map<String, dynamic> body) {
    final name = _string(body['fullName']).trim();
    final code = _string(body['code']).trim().toUpperCase();
    final email = _string(body['email']).trim().toLowerCase();
    final phone = _string(body['phone']).trim();
    final address = _string(body['address']).trim();
    if (name.length < 2 || name.length > 150)
      throw const AdminApiException('Enter the customer’s full name.');
    if (!RegExp(r'^[A-Z0-9][A-Z0-9_-]{1,49}$').hasMatch(code))
      throw const AdminApiException(
          'Customer code must use letters, numbers, dashes, or underscores.');
    if (email.isNotEmpty &&
        !RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email))
      throw const AdminApiException('Enter a valid customer email.');
    if (phone.length > 40 || address.length > 500)
      throw const AdminApiException('Phone or address is too long.');
    return {
      'full_name': name,
      'customer_code': code,
      'email': email.isEmpty ? null : email,
      'phone': phone.isEmpty ? null : phone,
      'address': address.isEmpty ? null : address
    };
  }

  Map<String, dynamic> _rateRecord(
          String itemId, Map<String, dynamic> item, DateTime now) =>
      {
        'item_id': itemId,
        'rate_type': item['rateType'],
        'rental_rate': item['rentalRate'],
        'deposit_amount': item['deposit'],
        'late_penalty_rate': item['latePenalty'],
        'created_by': _actorId,
        'is_active': true,
        'effective_from': now,
        'effective_to': null,
      };

  Map<String, dynamic> _verificationRecord(
          String rentalId,
          String itemId,
          String terminalId,
          Map<String, dynamic> terminal,
          String type,
          DateTime now,
          String code) =>
      {
        'rental_id': rentalId,
        'item_id': itemId,
        'terminal_id': terminalId,
        'terminal_code': terminal['terminal_code'] ?? terminalId,
        'transaction_type': type,
        'verification_code': code,
        'status': 'PENDING',
        'requested_at': now,
        'expires_at': now.add(const Duration(minutes: 10)),
        'confirmed_at': null,
        'rejected_at': null,
        'expired_at': null,
        'rejection_reason': null,
        'final_reason': null,
        'confirmed_terminal_id': null,
        'confirmed_terminal_code': null,
        'inspection': null,
        'inspection_revision': 0,
      };

  Map<String, dynamic> _validateInspection(dynamic value, String type) {
    final body = _map(value);
    final condition = _string(body['condition']).toUpperCase();
    final notes = _string(body['notes']).trim();
    final requestedResult = _string(body['result']).toUpperCase();
    if (!const ['GOOD', 'FAIR', 'DAMAGED', 'NEEDS_INSPECTION']
        .contains(condition))
      throw const AdminApiException('Choose a valid equipment condition.');
    if (type == 'RENTAL' && !const ['GOOD', 'FAIR'].contains(condition))
      throw const AdminApiException(
          'Release inspection must confirm good or fair condition.');
    final result = requestedResult.isEmpty
        ? (const ['GOOD', 'FAIR'].contains(condition)
            ? 'AVAILABLE'
            : 'UNDER_MAINTENANCE')
        : requestedResult;
    if (!const ['AVAILABLE', 'UNDER_MAINTENANCE'].contains(result) ||
        (type == 'RENTAL' && result != 'AVAILABLE') ||
        (const ['DAMAGED', 'NEEDS_INSPECTION'].contains(condition) &&
            result != 'UNDER_MAINTENANCE'))
      throw const AdminApiException(
          'Damaged equipment must return to Under Maintenance.');
    if (notes.isEmpty || notes.length > 2000)
      throw const AdminApiException(
          'Inspection notes are required (maximum 2,000 characters).');
    return {
      'condition': condition,
      'notes': notes,
      'inspected_by': _actorId,
      'inspected_by_name':
          _string(_user?['full_name'] ?? _user?['name'] ?? 'Admin'),
      'inspected_at': DateTime.now(),
      'result': result
    };
  }

  Map<String, dynamic> _finalCharges(
      Map<String, dynamic> rental, Map<String, dynamic> request) {
    final fee = _map(rental['fee_breakdown']);
    final due = _parseDate(fee['due_at'] ?? rental['due_at']);
    final actual = _parseDate(request['actual_return_at']);
    final rate = _number(fee['overtime_rate']);
    final unit = _int(fee['overtime_unit_minutes']);
    final grace = _int(fee['grace_minutes']);
    final known = due != null && actual != null && unit > 0;
    final late = known
        ? max(0, ((actual.difference(due).inSeconds / 60).ceil() - grace))
        : 0;
    final units = known ? (late / unit).ceil() : 0;
    final overtime = known ? _roundMoney(units * rate) : null;
    final penalty = request['penalty_amount'];
    final total = known
        ? _roundMoney(_number(fee['rental_fee'] ?? rental['rental_fee']) +
            _number(overtime) +
            _number(penalty))
        : null;
    return {
      ...fee,
      'rental_fee': fee['rental_fee'] ?? rental['rental_fee'],
      'deposit_amount': fee['deposit_amount'] ?? rental['deposit_amount'],
      'due_at': fee['due_at'] ?? rental['due_at'],
      'actual_return_at': request['actual_return_at'],
      'overtime_units': known ? units : null,
      'overtime_fee': overtime,
      'penalty_amount': penalty,
      'penalty_reason': request['penalty_reason'],
      'final_rental_charges': total
    };
  }

  Map<String, dynamic> _rateComponent(Map<String, dynamic> rate, int units) => {
        'rate_id': rate['id'],
        'label': rate['label'],
        'kind': rate['kind'],
        'units': units,
        'unit_amount': rate['amount'],
        'duration_minutes': rate['duration_minutes'],
        'total_amount': _roundMoney(units * _number(rate['amount'])),
      };

  String get _actorId => _auth.currentUser?.uid ?? '';

  Map<String, dynamic> _auditRecord(String action, String entity, String id,
          dynamic oldValues, dynamic newValues, DateTime now) =>
      {
        'actor_type': 'USER',
        'user_id': _actorId,
        'action': action,
        'entity_type': entity,
        'entity_id': id,
        'old_values': oldValues,
        'new_values': newValues,
        'created_at': now,
      };

  void _audit(WriteBatch batch, String action, String entity, String id,
      {dynamic oldValues, dynamic newValues, required DateTime now}) {
    batch.set(_firestore.collection('audit_logs').doc(),
        _auditRecord(action, entity, id, oldValues, newValues, now));
  }

  Map<String, dynamic> _publicTerminal(Map<String, dynamic> terminal) {
    final copy = Map<String, dynamic>.from(terminal)
      ..remove('auth_token_hash')
      ..remove('api_key')
      ..remove('token')
      ..remove('secret');
    copy['credentials_configured'] = RegExp(r'^[a-f0-9]{64}$')
        .hasMatch(_string(terminal['auth_token_hash']));
    return copy;
  }

  Map<String, dynamic> _defaultPricing() {
    Map<String, dynamic> rate(String id, String label, String kind,
            int? duration, double amount) =>
        {
          'id': id,
          'label': label,
          'kind': kind,
          'duration_minutes': duration,
          'amount': amount,
        };
    Map<String, dynamic> product(String id, String name, String group,
            List<Map<String, dynamic>> rates,
            {double deposit = 0,
            double overtime = 0,
            bool highValue = false,
            List<String> included = const [],
            double? salePrice,
            String? saleLabel}) =>
        {
          'id': id,
          'name': name,
          'group': group,
          'rate_options': rates,
          'deposit_amount': deposit,
          'overtime_rate_per_hour': overtime,
          'high_value': highValue,
          'included_items': included,
          'sale_price': salePrice,
          if (saleLabel != null) 'sale_label': saleLabel,
        };
    return {
      'products': [
        product(
            'bike',
            'Bike',
            'Active rentals',
            [
              rate('half-hour', '30 minutes', 'SHORT', 30, 150),
              rate('hour', 'Per hour', 'HOURLY', 60, 200),
              rate('three-hour-special', '3-hour special', 'PACKAGE', 180, 500)
            ],
            highValue: true,
            overtime: 200),
        product('pickleball-set', 'Pickleball set', 'Active rentals',
            [rate('hour', 'Per hour', 'HOURLY', 60, 120)],
            overtime: 120, included: ['2 paddles', 'Balls']),
        product('badminton-set', 'Badminton set', 'Active rentals',
            [rate('hour', 'Per hour', 'HOURLY', 60, 100)],
            overtime: 100, included: ['2 rackets', '1 shuttlecock']),
        product(
            'basketball-volleyball-ball',
            'Basketball / volleyball ball',
            'Active rentals',
            [
              rate('hour', 'Per hour', 'HOURLY', 60, 50),
              rate('five-hour-special', '5-hour special', 'PACKAGE', 300, 200)
            ],
            overtime: 50),
        product('ps4', 'PS4', 'Tech rentals',
            [rate('hour', 'Per hour', 'HOURLY', 60, 250)],
            highValue: true, overtime: 250),
        product('nintendo-switch', 'Nintendo Switch', 'Tech rentals',
            [rate('hour', 'Per hour', 'HOURLY', 60, 200)],
            highValue: true, overtime: 200),
        product('deck-of-cards', 'Deck of cards', 'Cards rent / sale',
            [rate('five-hour', '5 hours', 'BLOCK', 300, 50)],
            overtime: 10, salePrice: 150, saleLabel: 'Brand new'),
        product('uno-cards', 'UNO cards', 'Cards rent / sale',
            [rate('five-hour', '5 hours', 'BLOCK', 300, 100)],
            overtime: 20, salePrice: 300, saleLabel: 'Brand new'),
        product('bingo-cards', 'Bingo', 'Cards rent / sale',
            [rate('five-hour', '5 hours', 'BLOCK', 300, 150)],
            overtime: 30, salePrice: 450, saleLabel: 'Brand new'),
        for (final name in const ['Jenga', 'Scrabble', 'Chess'])
          product(
              name.toLowerCase(),
              name,
              'Board games',
              [
                rate('five-hour', '5 hours', 'BLOCK', 300, 150),
                rate('whole-stay', 'Whole stay until resort checkout',
                    'WHOLE_STAY', null, 250)
              ],
              overtime: 30),
      ],
      'rules': {
        'opens_at': '08:00',
        'closes_at': '20:00',
        'valid_id_required': true,
        'high_value_deposit_required': true,
        'lost_piece_fee': 50,
        'order_phone': '0992-768-5192',
        'order_channels': 'Call / Text / Viber',
        'order_method_note': 'You may also tell your resort caretaker.',
        'overtime_basis':
            'Each started hour after the due time, at the product hourly rate.',
        'after_hours_returns':
            'Returns after closing are accepted when service reopens at 8:00 AM. Overtime continues until the item is returned.',
        'whole_stay_basis': 'The guest’s resort checkout time.',
        'bike_safety':
            'Ride bikes at your own risk. Always check your surroundings.',
        'care_and_loss':
            'Handle items with care. Damage or lost pieces are charged to the guest.',
        'return_reminder': 'Return items on time to avoid overtime charges.',
      },
    };
  }

  List<Map<String, dynamic>> _rows(dynamic value) => value is List
      ? value
          .whereType<Map>()
          .map((row) =>
              _serializeMap(row.map((key, value) => MapEntry('$key', value))))
          .toList()
      : <Map<String, dynamic>>[];

  List<Map<String, dynamic>> _docRows(
          QuerySnapshot<Map<String, dynamic>> snapshot) =>
      snapshot.docs
          .map((doc) => {..._serializeMap(doc.data()), 'id': doc.id})
          .toList();

  Map<String, dynamic> _serializeMap(Map<String, dynamic> source) =>
      source.map((key, value) => MapEntry(key, _serialize(value)));

  dynamic _serialize(dynamic value) {
    if (value is Timestamp) return value.toDate().toIso8601String();
    if (value is DateTime) return value.toIso8601String();
    if (value is Map)
      return value.map((key, entry) => MapEntry('$key', _serialize(entry)));
    if (value is List) return value.map(_serialize).toList();
    return value;
  }

  DateTime _date(dynamic value) =>
      _parseDate(value) ?? DateTime.fromMillisecondsSinceEpoch(0);

  DateTime? _parseDate(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value.replaceFirst(' ', 'T'));
    return null;
  }

  bool _matchesVersion(dynamic actual, dynamic expected) {
    final actualDate = _parseDate(actual);
    final expectedDate = _parseDate(expected);
    return actualDate != null &&
        expectedDate != null &&
        actualDate.millisecondsSinceEpoch ==
            expectedDate.millisecondsSinceEpoch;
  }

  String _string(dynamic value) => value == null ? '' : value.toString();
  int _int(dynamic value) =>
      value is num ? value.toInt() : int.tryParse(_string(value)) ?? 0;
  double _number(dynamic value) =>
      value is num ? value.toDouble() : double.tryParse(_string(value)) ?? 0;
  double _roundMoney(double value) => (value * 100).roundToDouble() / 100;
  Map<String, dynamic> _map(dynamic value) => value is Map<String, dynamic>
      ? value
      : value is Map
          ? value.map((key, value) => MapEntry('$key', value))
          : <String, dynamic>{};

  double _amount(dynamic value, String label) {
    final amount = _number(value);
    if (!amount.isFinite ||
        amount < 0 ||
        amount > 9999999999.99 ||
        (amount * 100 - (amount * 100).round()).abs() > .0001)
      throw AdminApiException(
          '$label must be a nonnegative amount with at most two decimal places.');
    return amount;
  }

  String _itemCodePrefix(String name) {
    final words = name
        .toUpperCase()
        .split(RegExp(r'[^A-Z0-9]+'))
        .where((word) => word.isNotEmpty)
        .toList();
    final prefix = (words.length > 1
            ? words.map((word) => word[0]).join()
            : (words.isEmpty ? 'ITEM' : words.first))
        .substring(
            0,
            min(
                5,
                words.length > 1
                    ? words.map((word) => word[0]).join().length
                    : (words.isEmpty ? 4 : words.first.length)));
    return prefix.length >= 2 ? prefix : 'ITEM';
  }

  String _newQrToken() {
    final bytes = List<int>.generate(16, (_) => _random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final hex =
        bytes.map((value) => value.toRadixString(16).padLeft(2, '0')).join();
    return 'RENTPLAY:${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
  }

  String _requestType(Map<String, dynamic> request) =>
      _string(request['transaction_type'] ?? request['type']).toUpperCase();

  String _authMessage(FirebaseAuthException error) => switch (error.code) {
        'invalid-email' => 'Enter a valid email address.',
        'user-disabled' =>
          'This Firebase account is disabled. Contact an administrator.',
        'user-not-found' ||
        'wrong-password' ||
        'invalid-credential' =>
          'Email or password is incorrect.',
        'network-request-failed' =>
          'Could not reach Firebase Authentication. Check your connection and try again.',
        'requires-recent-login' =>
          'Sign out and sign in again before changing this account detail.',
        _ => error.message ??
            'Firebase Authentication could not complete this action.',
      };

  int? _statusFor(FirebaseException error) => switch (error.code) {
        'permission-denied' => 403,
        'unauthenticated' => 401,
        'not-found' => 404,
        'already-exists' => 409,
        _ => null,
      };

  String _firestoreMessage(FirebaseException error) => switch (error.code) {
        'permission-denied' =>
          'Firebase denied access. Confirm Firestore rules allow an authenticated active ADMIN account to use the workspace.',
        'unauthenticated' => 'Your Firebase session expired. Sign in again.',
        'unavailable' =>
          'Firebase Firestore is unavailable. Check your connection and try again.',
        'failed-precondition' =>
          'Firestore could not complete this query. Check that the required Firebase index is deployed.',
        _ =>
          error.message ?? 'Firebase Firestore could not complete this action.',
      };
}

extension<T> on Iterable<T> {
  T? get firstOrNull {
    final iterator = this.iterator;
    return iterator.moveNext() ? iterator.current : null;
  }
}
