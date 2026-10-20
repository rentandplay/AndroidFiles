import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import '../../services/admin_api_service.dart';
import '../../utils/maintenance_state.dart';
import '../../utils/record_codes.dart';
import '../../widgets/rental_ui.dart';

List<Map<String, dynamic>> _rows(dynamic value) => value is List
    ? value
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList()
    : [];
String _text(dynamic value) => value?.toString() ?? '';
bool _open(Map row) =>
    ['OPEN', 'IN_PROGRESS'].contains(_text(row['status']).toUpperCase());
String _stage(Map row) => _open(row)
    ? _text(row['workflow_stage']).isNotEmpty
        ? _text(row['workflow_stage']).toUpperCase()
        : _text(row['status']).toUpperCase() == 'OPEN'
            ? 'REPORTED'
            : 'IN_REPAIR'
    : _text(row['status']).toUpperCase();
String _date(dynamic value) {
  final text = _text(value);
  if (text.isEmpty) return 'Not recorded';
  if (text.length == 10) return text;
  final zoned = RegExp(r'Z$|[+-]\d\d:\d\d$').hasMatch(text)
      ? text
      : '${text.replaceAll(' ', 'T')}+08:00';
  final parsed = DateTime.tryParse(zoned);
  return parsed == null
      ? text
      : DateFormat('MMM d, y · h:mm a')
          .format(parsed.toUtc().add(const Duration(hours: 8)));
}

String _cost(dynamic value) =>
    value is num ? '₱${value.toStringAsFixed(2)}' : 'Not recorded';

/// Resize locally to the same photo limits enforced by the shared backend.
Future<String> encodeMaintenancePhoto(Uint8List bytes) async {
  if (bytes.isEmpty || bytes.length > 10 * 1024 * 1024) {
    throw const FormatException('Choose an image smaller than 10 MB.');
  }
  final original = await ui.instantiateImageCodec(bytes);
  final frame = await original.getNextFrame();
  final width = frame.image.width, height = frame.image.height;
  frame.image.dispose();
  original.dispose();
  var longest = 1000;
  while (longest >= 100) {
    final scale = longest / (width > height ? width : height);
    final codec = await ui.instantiateImageCodec(bytes,
        targetWidth: (width * scale).round().clamp(1, width),
        targetHeight: (height * scale).round().clamp(1, height));
    final resized = await codec.getNextFrame();
    final data = await resized.image.toByteData(format: ui.ImageByteFormat.png);
    resized.image.dispose();
    codec.dispose();
    if (data != null) {
      final encoded =
          'data:image/png;base64,${base64Encode(data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes))}';
      if (encoded.length <= 200000) return encoded;
    }
    longest = (longest * .7).floor();
  }
  throw const FormatException(
      'This photo is too detailed. Choose a smaller image.');
}

class MaintenanceScreen extends StatefulWidget {
  const MaintenanceScreen({super.key, this.api, this.onChanged});
  final AdminFirestoreService? api;
  final Future<void> Function()? onChanged;
  @override
  State<MaintenanceScreen> createState() => _MaintenanceScreenState();
}

class _MaintenanceScreenState extends State<MaintenanceScreen> {
  AdminFirestoreService get _api =>
      widget.api ?? AdminFirestoreService.instance;
  List<Map<String, dynamic>> _tickets = [];
  bool _loading = true;
  String _error = '', _filter = 'Open', _query = '';
  String? _cursor;
  bool _moreBusy = false;
  Future<void> _more() async {
    if (_cursor == null || _moreBusy) return;
    setState(() => _moreBusy = true);
    try {
      final data =
          await _api.getMap('/records/maintenance?${Uri(queryParameters: {
            'limit': '5',
            'status': _filter == 'Open'
                ? 'OPEN'
                : _filter == 'History'
                    ? 'CLOSED'
                    : 'ALL',
            'cursor': _cursor!
          }).query}');
      if (mounted) {
        setState(() {
          _tickets = [..._tickets, ..._rows(data['records'])];
          _cursor = data['nextCursor'];
        });
      }
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _moreBusy = false);
    }
  }

  StreamSubscription<Map<String, dynamic>>? _eventSubscription;

  @override
  void initState() {
    super.initState();
    _load();
    _eventSubscription = _api.watchRentalEvents().listen((event) {
      if (!mounted) return;
      final type = (event['event'] ?? '').toString();
      if (type == 'ready' || type.endsWith('.changed')) {
        _load();
      }
    });
  }

  @override
  void dispose() {
    _eventSubscription?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final data = await _api.getMap(
          '/records/maintenance?${Uri(queryParameters: {
                'limit': '5',
                'status': _filter == 'Open'
                    ? 'OPEN'
                    : _filter == 'History'
                        ? 'CLOSED'
                        : 'ALL'
              }).query}',
          forceRefresh: true);
      if (!mounted) return;
      setState(() {
        _tickets = _rows(data['records']);
        _cursor = data['nextCursor'];
        _loading = false;
        _error = '';
      });
    } catch (error) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = '$error';
        });
      }
    }
  }

  Future<void> _changed() async {
    await _load();
    try {
      await widget.onChanged?.call();
    } catch (_) {
      if (mounted) {
        setState(() =>
            _error = 'Saved. Refresh the staff counter for the latest stock.');
      }
    }
  }

  Future<void> _report() async {
    final saved = await Navigator.push<bool>(context,
        MaterialPageRoute(builder: (_) => MaintenanceEditScreen(api: _api)));
    if (saved == true) await _changed();
  }

  @override
  Widget build(BuildContext context) {
    final open = _tickets.where(_open).toList();
    final visible = _tickets.where((row) {
      if (_filter == 'Open' && !_open(row) ||
          _filter == 'History' && _open(row)) {
        return false;
      }
      return '${recordReference(row, 'maintenance')} ${row['item_code']} ${row['item_name']} ${row['reason']} ${row['assigned_name']}'
          .toLowerCase()
          .contains(_query.toLowerCase());
    }).toList()
      ..sort((a, b) => _text(b['updated_at'] ?? b['started_at'])
          .compareTo(_text(a['updated_at'] ?? a['started_at'])));
    return Scaffold(
      appBar: AppBar(title: const Text('Maintenance')),
      bottomNavigationBar: SafeArea(
          child: Padding(
              padding: const EdgeInsets.all(12),
              child: FilledButton.icon(
                  onPressed: _report,
                  icon: const Icon(Icons.add),
                  label: const Text('Report issue')))),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.all(16),
                  children: [
                    Text(
                        'One ticket for the exact physical unit. Other healthy stock stays available.',
                        style: Theme.of(context).textTheme.bodyMedium),
                    const SizedBox(height: 12),
                    RentalSection(
                        child: Column(children: [
                      RentalValueRow('Units unavailable',
                          '${open.map((row) => row['item_id']).toSet().length}'),
                      RentalValueRow('For inspection',
                          '${open.where((row) => _stage(row) == 'AWAITING_INSPECTION').length}'),
                    ])),
                    if (_error.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      RentalNotice(
                          title: 'Could not refresh maintenance',
                          message: _error,
                          isError: true),
                      TextButton(
                          onPressed: _load, child: const Text('Try again')),
                    ],
                    const SizedBox(height: 16),
                    Wrap(
                        spacing: 8,
                        children: ['Open', 'History', 'All']
                            .map((filter) => ChoiceChip(
                                label: Text(filter),
                                selected: _filter == filter,
                                onSelected: (_) {
                                  setState(() => _filter = filter);
                                  _load();
                                }))
                            .toList()),
                    const SizedBox(height: 12),
                    TextField(
                        decoration: const InputDecoration(
                            labelText: 'Search ticket, unit or issue',
                            prefixIcon: Icon(Icons.search)),
                        onChanged: (value) => setState(() => _query = value)),
                    const SizedBox(height: 12),
                    if (visible.isEmpty)
                      const Padding(
                          padding: EdgeInsets.all(24),
                          child: Text('No maintenance tickets in this view.')),
                    if (_cursor != null)
                      OutlinedButton(
                          onPressed: _moreBusy ? null : _more,
                          child: Text(
                              _moreBusy ? 'Loading…' : 'Load more tickets')),
                    for (final ticket in visible)
                      Card(
                          child: ListTile(
                        contentPadding: const EdgeInsets.all(14),
                        title: Text(
                            '${recordReference(ticket, 'maintenance')} · ${ticket['item_name'] ?? 'Equipment'}'),
                        subtitle: Text(
                            '${ticket['item_code'] ?? 'Unit code not recorded'} · ${maintenanceStageLabel(ticket)}\n'
                            '${ticket['reason'] ?? 'Issue not recorded'}\n'
                            '${ticket['assigned_name'] ?? 'Unassigned'} · Target ${_date(ticket['target_date'])}'),
                        isThreeLine: true,
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) => MaintenanceTicketScreen(
                                    id: _text(ticket['id']),
                                    api: _api,
                                    onChanged: _changed))),
                      )),
                  ]),
            ),
    );
  }
}

class MaintenanceTicketScreen extends StatefulWidget {
  const MaintenanceTicketScreen(
      {super.key, required this.id, this.api, this.onChanged});
  final String id;
  final AdminFirestoreService? api;
  final Future<void> Function()? onChanged;
  @override
  State<MaintenanceTicketScreen> createState() =>
      _MaintenanceTicketScreenState();
}

class _MaintenanceTicketScreenState extends State<MaintenanceTicketScreen> {
  AdminFirestoreService get _api =>
      widget.api ?? AdminFirestoreService.instance;
  late Future<Map<String, dynamic>> _detail;
  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    _detail = _api.getMap('/maintenance/${Uri.encodeComponent(widget.id)}',
        forceRefresh: true);
  }

  Future<void> _edit(Map<String, dynamic> ticket, String action) async {
    final saved = await Navigator.push<bool>(
        context,
        MaterialPageRoute(
            builder: (_) => MaintenanceEditScreen(
                api: _api, ticket: ticket, action: action)));
    if (!mounted) return;
    setState(_reload);
    if (saved != true) return;
    try {
      await widget.onChanged?.call();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Saved. Refresh the list for the latest stock.')));
      }
    }
  }

  Future<void> _photo(Map photo) async {
    try {
      final data = await _api.getMap(
          '/maintenance/${Uri.encodeComponent(widget.id)}/photos/${Uri.encodeComponent(_text(photo['id']))}');
      if (!mounted) return;
      await showDialog<void>(
          context: context,
          builder: (context) => AlertDialog(
                title: Text(_text(data['caption']).isEmpty
                    ? 'Maintenance photo'
                    : _text(data['caption'])),
                content: Image.memory(
                    base64Decode(_text(data['image_data']).split(',').last)),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Close'))
                ],
              ));
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Could not load photo. $error')));
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Maintenance ticket'), actions: [
          IconButton(
              onPressed: () => setState(_reload),
              icon: const Icon(Icons.refresh),
              tooltip: 'Refresh ticket')
        ]),
        body: FutureBuilder<Map<String, dynamic>>(
            future: _detail,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                return Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(children: [
                      RentalNotice(
                          title: 'Ticket unavailable',
                          message: '${snapshot.error}',
                          isError: true),
                      TextButton(
                          onPressed: () => setState(_reload),
                          child: const Text('Try again'))
                    ]));
              }
              final ticket = Map<String, dynamic>.from(
                  snapshot.data!['maintenance'] as Map);
              final stage = _stage(ticket), open = _open(ticket);
              return ListView(padding: const EdgeInsets.all(16), children: [
                Text(recordReference(ticket, 'maintenance'),
                    style: Theme.of(context).textTheme.headlineSmall),
                const SizedBox(height: 8),
                RentalSection(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      Text('${ticket['item_name']} · ${ticket['item_code']}',
                          style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 8),
                      RentalValueRow('Stage', maintenanceStageLabel(ticket)),
                      RentalValueRow(
                          'Priority',
                          _text(ticket['priority']).isEmpty
                              ? 'Normal'
                              : _text(ticket['priority'])),
                      RentalValueRow(
                          'Assigned staff',
                          _text(ticket['assigned_name']).isEmpty
                              ? 'Unassigned'
                              : _text(ticket['assigned_name'])),
                      RentalValueRow(
                          'Target date', _date(ticket['target_date'])),
                      RentalValueRow(
                          'Total repair cost', _cost(ticket['repair_cost'])),
                      RentalValueRow('Reported',
                          _date(ticket['reported_at'] ?? ticket['started_at'])),
                      const SizedBox(height: 12),
                      Text(_text(ticket['reason']),
                          style: const TextStyle(fontWeight: FontWeight.w700)),
                      if (_text(ticket['details'] ?? ticket['description'])
                          .isNotEmpty)
                        Text(_text(ticket['details'] ?? ticket['description'])),
                      if (_text(ticket['inspection_notes']).isNotEmpty)
                        Text(_text(ticket['inspection_notes'])),
                      if (_text(ticket['retirement_reason']).isNotEmpty)
                        Text('Retirement: ${ticket['retirement_reason']}'),
                    ])),
                const SizedBox(height: 16),
                if (open)
                  RentalNotice(
                      title: 'This unit is unavailable for rental',
                      message: stage == 'AWAITING_INSPECTION'
                          ? 'Check function, safety and completeness before returning this unit to available stock.'
                          : 'Record the repair, then send it for a separate final inspection. Other healthy units stay available.'),
                const SizedBox(height: 12),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  OutlinedButton(
                      onPressed: () => _edit(ticket, 'update'),
                      child: Text(
                          open ? 'Update details' : 'Update cost / notes')),
                  if (stage == 'REPORTED')
                    FilledButton(
                        onPressed: () => _edit(ticket, 'start-repair'),
                        child: const Text('Start repair')),
                  if (stage == 'IN_REPAIR')
                    FilledButton(
                        onPressed: () => _edit(ticket, 'send-inspection'),
                        child: const Text('Send for inspection')),
                  if (stage == 'AWAITING_INSPECTION') ...[
                    FilledButton(
                        onPressed: () => _edit(ticket, 'complete'),
                        child: const Text('Complete inspection')),
                    OutlinedButton(
                        onPressed: () => _edit(ticket, 'inspection-failed'),
                        child: const Text('Inspection failed')),
                  ],
                  if (open)
                    TextButton(
                        onPressed: () => _edit(ticket, 'retire'),
                        child: const Text('Retire this unit')),
                ]),
                if (_rows(ticket['photos']).isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Text('Photos',
                      style: Theme.of(context).textTheme.titleMedium),
                  for (final photo in _rows(ticket['photos']))
                    ListTile(
                        leading: const Icon(Icons.photo_outlined),
                        title: Text(_text(photo['caption']).isEmpty
                            ? 'View photo'
                            : _text(photo['caption'])),
                        onTap: () => _photo(photo)),
                ],
                const SizedBox(height: 16),
                Text('Work history',
                    style: Theme.of(context).textTheme.titleMedium),
                for (final event in _rows(ticket['activity']).reversed)
                  ListTile(
                      title: Text(_text(event['note']).isEmpty
                          ? _text(event['kind']).replaceAll('_', ' ')
                          : _text(event['note'])),
                      subtitle: Text(
                          '${event['actor_name'] ?? 'Staff'} · ${_date(event['at'])}')),
              ]);
            }),
      );
}

class MaintenanceEditScreen extends StatefulWidget {
  const MaintenanceEditScreen(
      {super.key, this.api, this.unitId, this.ticket, this.action = 'report'});
  final AdminFirestoreService? api;
  final String? unitId;
  final Map<String, dynamic>? ticket;
  final String action;
  @override
  State<MaintenanceEditScreen> createState() => _MaintenanceEditScreenState();
}

class _MaintenanceEditScreenState extends State<MaintenanceEditScreen> {
  AdminFirestoreService get _api =>
      widget.api ?? AdminFirestoreService.instance;
  final _form = GlobalKey<FormState>();
  final _reason = TextEditingController(),
      _note = TextEditingController(),
      _costInput = TextEditingController(),
      _target = TextEditingController();
  List<Map<String, dynamic>> _units = [], _staff = [];
  final List<Map<String, dynamic>> _photos = [];
  Map<String, dynamic>? _unit;
  String? _unitId, _assignedTo;
  String _priority = 'NORMAL', _condition = 'NEEDS_INSPECTION', _error = '';
  bool _loading = true,
      _saving = false,
      _processingPhoto = false,
      _stale = false,
      _contextReady = false,
      _contextFailed = false;
  final _checks = {'functional': false, 'safe': false, 'complete': false};
  bool get _report => widget.action == 'report';
  bool get _metadata =>
      _report || widget.action == 'update' && _open(widget.ticket!);
  String get _title => const {
        'report': 'Report issue',
        'update': 'Update maintenance',
        'start-repair': 'Start repair',
        'send-inspection': 'Send for inspection',
        'inspection-failed': 'Inspection failed',
        'complete': 'Complete inspection',
        'retire': 'Retire this unit',
      }[widget.action]!;
  @override
  void initState() {
    super.initState();
    final ticket = widget.ticket;
    if (ticket != null) {
      _priority = _text(ticket['priority']).isEmpty
          ? 'NORMAL'
          : _text(ticket['priority']);
      _assignedTo = ticket['assigned_to']?.toString();
      _target.text = _text(ticket['target_date']);
      _costInput.text = ticket['repair_cost'] is num
          ? (ticket['repair_cost'] as num).toStringAsFixed(2)
          : '';
      _condition = 'GOOD';
    }
    _load();
  }

  @override
  void dispose() {
    _reason.dispose();
    _note.dispose();
    _costInput.dispose();
    _target.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final results = await Future.wait([
        if (_metadata) _api.getMap('/maintenance-staff', forceRefresh: true),
        if (_report) _api.getMap('/mobile/admin-workspace', forceRefresh: true),
      ]);
      if (!mounted) return;
      var resultIndex = 0;
      if (_metadata) _staff = _rows(results[resultIndex++]['staff']);
      if (_report) {
        final workspace = results[resultIndex++];
        final tickets = _rows(workspace['maintenance']);
        _units = _rows(workspace['items'])
            .where((item) =>
                item['is_active'] != false &&
                ['AVAILABLE', 'UNDER_MAINTENANCE'].contains(
                    _text(item['effective_status'] ?? item['status'])
                        .toUpperCase()) &&
                item['reserved_rental_id'] == null &&
                item['current_rental_id'] == null &&
                !tickets.any((ticket) =>
                    ticket['item_id'] == item['id'] && _open(ticket)))
            .toList();
      }
      if (_report && !_units.any((item) => item['id'] == _unitId)) {
        _unitId = null;
        _unit = null;
      }
      if (_metadata &&
          _assignedTo != null &&
          !_staff.any((staff) => staff['id'] == _assignedTo)) {
        _assignedTo = null;
      }
      if (_report &&
          widget.unitId != null &&
          _units.any((item) => item['id'] == widget.unitId)) {
        await _selectUnit(widget.unitId!, rethrowOnFailure: true);
      }
      if (mounted) {
        setState(() {
          _loading = false;
          _contextReady = true;
          _contextFailed = false;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _loading = false;
          _contextReady = false;
          _contextFailed = true;
          _error = '$error';
        });
      }
    }
  }

  Future<void> _selectUnit(String id, {bool rethrowOnFailure = false}) async {
    setState(() {
      _unitId = id;
      _unit = null;
      _error = '';
      _contextFailed = false;
    });
    try {
      final detail = await _api.getMap('/inventory/${Uri.encodeComponent(id)}',
          forceRefresh: true);
      if (mounted && _unitId == id) {
        setState(
            () => _unit = Map<String, dynamic>.from(detail['item'] as Map));
      }
    } catch (error) {
      if (mounted && _unitId == id) {
        setState(() {
          _error = '$error';
          _contextFailed = true;
        });
      }
      if (rethrowOnFailure) rethrow;
    }
  }

  Future<void> _retryContext() async {
    final selectedUnit = _unitId;
    setState(() {
      _loading = true;
      _error = '';
      _stale = false;
      _contextReady = false;
      _contextFailed = false;
    });
    await _load();
    if (_report &&
        widget.unitId == null &&
        selectedUnit != null &&
        mounted &&
        _contextReady &&
        _units.any((unit) => unit['id'] == selectedUnit)) {
      await _selectUnit(selectedUnit);
    }
  }

  Future<void> _addPhoto() async {
    if (_processingPhoto) return;
    final existing = _rows(widget.ticket?['photos']).length;
    if (_photos.length >= 3 || _photos.length + existing >= 6) {
      setState(() =>
          _error = 'Up to three new photos per update and six per ticket.');
      return;
    }
    final source = await showModalBottomSheet<ImageSource>(
        context: context,
        builder: (context) => SafeArea(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
              ListTile(
                  leading: const Icon(Icons.camera_alt_outlined),
                  title: const Text('Take a photo'),
                  onTap: () => Navigator.pop(context, ImageSource.camera)),
              ListTile(
                  leading: const Icon(Icons.photo_library_outlined),
                  title: const Text('Choose from photos'),
                  onTap: () => Navigator.pop(context, ImageSource.gallery)),
            ])));
    if (source == null || !mounted) return;
    setState(() => _processingPhoto = true);
    try {
      final photo = await ImagePicker()
          .pickImage(source: source, maxWidth: 1600, maxHeight: 1600);
      if (photo != null) {
        final data = await encodeMaintenancePhoto(await photo.readAsBytes());
        if (mounted) {
          setState(() => _photos.add({'imageData': data, 'caption': ''}));
        }
      }
    } catch (error) {
      if (mounted) {
        setState(() => _error = 'Could not prepare the photo. $error');
      }
    } finally {
      if (mounted) setState(() => _processingPhoto = false);
    }
  }

  Future<void> _save() async {
    if (_saving || _processingPhoto || !_form.currentState!.validate()) return;
    if (_report && _unit == null) {
      setState(
          () => _error = 'Choose a physical unit and wait for its details.');
      return;
    }
    if (widget.action == 'complete' &&
        _checks.values.any((passed) => !passed)) {
      setState(
          () => _error = 'Function, safety and completeness must all pass.');
      return;
    }
    final code = _report
        ? _text(_unit!['item_code'])
        : _text(widget.ticket!['item_code']);
    final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
              title: Text(_title),
              content: Text(widget.action == 'retire'
                  ? 'Retire ${code.isEmpty ? 'this exact unit' : code}? This removes it from active stock and preserves its QR and history.'
                  : widget.action == 'complete'
                      ? 'Confirm all inspection checks for $code? This unit returns to rental availability when no other open issue remains.'
                      : 'Save $_title for ${code.isEmpty ? 'this physical unit' : code}?'),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('Back')),
                FilledButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('Confirm')),
              ],
            ));
    if (confirmed != true || !mounted) return;
    setState(() {
      _saving = true;
      _error = '';
    });
    try {
      final body = <String, dynamic>{
        if (_report) ...{
          'itemId': _unitId,
          'version': _unit!['updated_at'],
          'reason': _reason.text.trim(),
          'notes': _note.text.trim(),
          'condition': _condition
        } else ...{
          'action': widget.action,
          'revision': widget.ticket!['revision'] ?? 0,
          'note': _note.text.trim(),
          'repairCost': _costInput.text.trim().isEmpty
              ? null
              : double.parse(_costInput.text.trim())
        },
        if (_metadata) ...{
          'priority': _priority,
          'assignedTo': _assignedTo,
          'targetDate': _target.text.trim().isEmpty ? null : _target.text.trim()
        },
        if (widget.action == 'complete') ...{
          'condition': _condition,
          'checks': Map<String, bool>.from(_checks)
        },
        'photos': _photos,
      };
      if (_report) {
        await _api.post('/maintenance', body: body);
      } else {
        await _api.patch(
            '/maintenance/${Uri.encodeComponent(_text(widget.ticket!['id']))}',
            body: body);
      }
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = '$error';
          _stale = error is AdminApiException && error.statusCode == 409;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(_title)),
        bottomNavigationBar: SafeArea(
            child: Padding(
                padding: const EdgeInsets.all(12),
                child: FilledButton(
                    onPressed: _loading ||
                            _saving ||
                            _processingPhoto ||
                            _stale ||
                            _metadata && (!_contextReady || _contextFailed)
                        ? null
                        : _save,
                    child: Text(_saving ? 'Saving…' : _title)))),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : Form(
                key: _form,
                child: ListView(padding: const EdgeInsets.all(16), children: [
                  if (_error.isNotEmpty) ...[
                    RentalNotice(
                        title: 'Check the maintenance details',
                        message: _error,
                        isError: true),
                    TextButton(
                        onPressed: _saving
                            ? null
                            : _stale
                                ? () => Navigator.pop(context)
                                : _contextFailed
                                    ? _retryContext
                                    : () => Navigator.pop(context),
                        child: Text(_stale
                            ? 'Back to refreshed ticket'
                            : _contextFailed
                                ? 'Retry loading'
                                : 'Back to refreshed ticket')),
                    const SizedBox(height: 12),
                  ],
                  if (_report) ...[
                    if (_units.isEmpty)
                      const RentalNotice(
                          title: 'No eligible units',
                          message:
                              'Rented or reserved units must be resolved in Rentals or Returns. Open maintenance tickets stay under their existing ticket.'),
                    DropdownButtonFormField<String>(
                        key: ValueKey(_unitId),
                        initialValue: _unitId,
                        isExpanded: true,
                        decoration: const InputDecoration(
                            labelText: 'Physical equipment unit'),
                        items: _units
                            .map((unit) => DropdownMenuItem(
                                value: _text(unit['id']),
                                child: Text(
                                    '${unit['item_code']} · ${unit['name']}',
                                    overflow: TextOverflow.ellipsis)))
                            .toList(),
                        onChanged: _saving
                            ? null
                            : (id) {
                                if (id != null) _selectUnit(id);
                              },
                        validator: (value) => value == null
                            ? 'Select the exact unit code.'
                            : null),
                    const SizedBox(height: 12),
                    TextFormField(
                        controller: _reason,
                        enabled: !_saving,
                        maxLength: 255,
                        decoration:
                            const InputDecoration(labelText: 'Issue summary'),
                        validator: (value) =>
                            value == null || value.trim().isEmpty
                                ? 'Describe the equipment issue.'
                                : null),
                  ] else
                    Text(
                        '${recordReference(widget.ticket!, 'maintenance')} · ${widget.ticket!['item_code']}'),
                  if (_report || widget.action == 'complete') ...[
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                        initialValue: _condition,
                        decoration:
                            const InputDecoration(labelText: 'Unit condition'),
                        items: (widget.action == 'complete'
                                ? ['GOOD', 'FAIR']
                                : [
                                    'GOOD',
                                    'FAIR',
                                    'DAMAGED',
                                    'NEEDS_INSPECTION'
                                  ])
                            .map((value) => DropdownMenuItem(
                                value: value,
                                child: Text(value.replaceAll('_', ' '))))
                            .toList(),
                        onChanged: _saving
                            ? null
                            : (value) => setState(() => _condition = value!)),
                  ],
                  if (_metadata) ...[
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                        initialValue: _priority,
                        decoration:
                            const InputDecoration(labelText: 'Priority'),
                        items: ['LOW', 'NORMAL', 'HIGH', 'URGENT']
                            .map((value) => DropdownMenuItem(
                                value: value, child: Text(value)))
                            .toList(),
                        onChanged: _saving
                            ? null
                            : (value) => setState(() => _priority = value!)),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                        initialValue: _assignedTo,
                        isExpanded: true,
                        decoration:
                            const InputDecoration(labelText: 'Assigned staff'),
                        items: [
                          const DropdownMenuItem<String>(
                              value: null, child: Text('Unassigned')),
                          ..._staff.map((staff) => DropdownMenuItem(
                              value: _text(staff['id']),
                              child: Text(_text(staff['full_name']),
                                  overflow: TextOverflow.ellipsis)))
                        ],
                        onChanged: _saving
                            ? null
                            : (value) => setState(() => _assignedTo = value)),
                    const SizedBox(height: 12),
                    TextFormField(
                        controller: _target,
                        enabled: !_saving,
                        decoration: const InputDecoration(
                            labelText: 'Target date (optional)',
                            hintText: 'YYYY-MM-DD'),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return null;
                          }
                          final text = value.trim(),
                              date = DateTime.tryParse(text);
                          return RegExp(r'^\d{4}-\d{2}-\d{2}$')
                                      .hasMatch(text) &&
                                  date != null &&
                                  date.toIso8601String().substring(0, 10) ==
                                      text
                              ? null
                              : 'Enter a valid date as YYYY-MM-DD.';
                        }),
                  ],
                  if (!_report) ...[
                    const SizedBox(height: 12),
                    TextFormField(
                        controller: _costInput,
                        enabled: !_saving,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        decoration: const InputDecoration(
                            labelText: 'Total repair cost (PHP)',
                            helperText:
                                'Full ticket total. Blank is unknown; zero means no cost.'),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return null;
                          }
                          final amount = double.tryParse(value.trim());
                          return amount != null &&
                                  amount.isFinite &&
                                  amount >= 0 &&
                                  amount <= 9999999999.99 &&
                                  (amount * 100 - (amount * 100).round())
                                          .abs() <
                                      .0001
                              ? null
                              : 'Enter a nonnegative amount with up to two decimals.';
                        }),
                  ],
                  const SizedBox(height: 12),
                  TextFormField(
                      controller: _note,
                      enabled: !_saving,
                      minLines: 3,
                      maxLines: 6,
                      maxLength: 2000,
                      decoration: InputDecoration(
                          labelText: widget.action == 'retire'
                              ? 'Retirement reason'
                              : _report
                                  ? 'Issue details (optional)'
                                  : 'Work / inspection notes'),
                      validator: (value) => !_report &&
                              !['update', 'start-repair']
                                  .contains(widget.action) &&
                              (value == null || value.trim().isEmpty)
                          ? 'Record the work or inspection findings.'
                          : null),
                  if (widget.action == 'complete') ...[
                    const SizedBox(height: 8),
                    for (final check in {
                      'functional': 'Function tested and working',
                      'safe': 'Safe to rent',
                      'complete': 'Required parts and accessories complete'
                    }.entries)
                      CheckboxListTile(
                          value: _checks[check.key],
                          title: Text(check.value),
                          contentPadding: EdgeInsets.zero,
                          onChanged: _saving
                              ? null
                              : (value) => setState(
                                  () => _checks[check.key] = value ?? false)),
                  ],
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                      onPressed: _saving || _processingPhoto ? null : _addPhoto,
                      icon: const Icon(Icons.add_a_photo_outlined),
                      label: Text(_processingPhoto
                          ? 'Preparing photo…'
                          : 'Add damage / repair photo')),
                  for (var index = 0; index < _photos.length; index++)
                    ListTile(
                        leading: Image.memory(
                            base64Decode(_text(_photos[index]['imageData'])
                                .split(',')
                                .last),
                            width: 48,
                            height: 48,
                            fit: BoxFit.cover),
                        title: Text('Photo ${index + 1}'),
                        trailing: IconButton(
                            tooltip: 'Remove photo',
                            onPressed: _saving
                                ? null
                                : () => setState(() => _photos.removeAt(index)),
                            icon: const Icon(Icons.close))),
                  const SizedBox(height: 20),
                ]),
              ),
      );
}
