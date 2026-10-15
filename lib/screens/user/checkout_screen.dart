import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../models/item_model.dart';
import '../../services/auth_service.dart';
import '../../services/mobile_api_service.dart';
import '../../widgets/rental_ui.dart';
import 'active_rentals_screen.dart';

const String mobileRentalTermsVersion = '2026-10-13-rental-v1';

class CheckoutScreen extends StatefulWidget {
  const CheckoutScreen({super.key, required this.item, this.api});
  final ItemModel item;
  final MobileApiService? api;
  @override
  State<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends State<CheckoutScreen> {
  final _form = GlobalKey<FormState>();
  int _selectedDurationMinutes = 60;
  String _selectedResort = '';
  DateTime? _scheduledStartAt;
  final _customResortController = TextEditingController();
  bool _isCustomDuration = false;
  final _customHoursController = TextEditingController(text: '22');
  String _paymentMethod = 'CASH';
  bool _isSubmitting = false, _quoteLoading = true, _paymentConfirmed = false;
  bool _acceptedRentalTerms = false;
  Map<String, dynamic>? _quote;
  Map<String, dynamic>? _paymentInstructions;
  String? _paymentProofImage, _paymentProofName;
  final _paymentReferenceController = TextEditingController();
  String _quoteError = '';
  int _quoteVersion = 0;
  String _requestKey = MobileApiService.operationKey();
  MobileApiService get _api => widget.api ?? MobileApiService.instance;

  bool get _hasDailyBaseRate =>
      widget.item.rateOptions.any((rate) => rate['id'] == 'admin-base-daily');

  List<int> get _durationChoices {
    final minutes =
        _hasDailyBaseRate ? <int>{1440} : <int>{60, 120, 180, 300, 480};
    for (final rate in widget.item.rateOptions) {
      if (rate['kind'] == 'FLAT') continue;
      final duration = rate['duration_minutes'];
      if (duration is num && duration > 0 && duration <= 10080) {
        minutes.add(duration.toInt());
      }
    }
    return minutes.toList()..sort();
  }

  String _durationLabel(int minutes) {
    final hours = minutes ~/ 60;
    final remainingMinutes = minutes % 60;
    if (hours == 0) return '$minutes min${minutes == 1 ? '' : 's'}';
    if (remainingMinutes == 0) {
      return '$hours hr${hours == 1 ? '' : 's'}';
    }
    return '$hours hr${hours == 1 ? '' : 's'} $remainingMinutes min';
  }

  static const privateResorts = [
    'ASRI Hotspring Resort',
    '23 Prime Resort',
    'Springcrest Villa',
    'Casa Argela Hotspring Resort',
    'Kumo Villa',
    'El Stefano Hotspring Resort',
    'The Bloomfield Villa',
    'MYJC Resort',
    'Victoria Arya Hotspring Resort',
    'The House at Bluestone',
    'One Pansol Hotspring Resort',
    'Kasaya Private Resort',
    'The Pines Villas',
    'Villa Alyssa Hotspring Resort',
    'Casa Fides',
    'Other / Custom Resort',
  ];

  @override
  void initState() {
    super.initState();
    _selectedDurationMinutes = _hasDailyBaseRate
        ? 1440
        : _durationChoices.contains(60)
            ? 60
            : _durationChoices.first;
    _loadQuote();
    _loadPaymentInstructions();
  }

  Future<void> _loadPaymentInstructions() async {
    try {
      final result = await _api.paymentInstructions();
      if (mounted) setState(() => _paymentInstructions = result);
    } catch (_) {
      if (mounted) setState(() => _paymentInstructions = const {});
    }
  }

  Future<ImageSource?> _selectPaymentProofSource() =>
      showModalBottomSheet<ImageSource>(
        context: context,
        builder: (sheetContext) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Add payment receipt',
                      style: Theme.of(sheetContext).textTheme.titleMedium),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.camera_alt_outlined),
                title: const Text('Take a photo'),
                onTap: () => Navigator.pop(sheetContext, ImageSource.camera),
              ),
              ListTile(
                leading: const Icon(Icons.photo_library_outlined),
                title: const Text('Upload from photos'),
                onTap: () => Navigator.pop(sheetContext, ImageSource.gallery),
              ),
            ],
          ),
        ),
      );

  Future<void> _choosePaymentProof() async {
    try {
      final source = await _selectPaymentProofSource();
      if (source == null || !mounted) return;
      final file = await ImagePicker()
          .pickImage(source: source, maxWidth: 1800, imageQuality: 75);
      if (file == null) return;
      final bytes = await file.readAsBytes();
      if (bytes.length > 350000) {
        throw const MobileApiException(
            'Choose a smaller screenshot. The limit is 350 KB.');
      }
      final isPng = bytes.length >= 8 &&
          bytes[0] == 137 &&
          bytes[1] == 80 &&
          bytes[2] == 78 &&
          bytes[3] == 71;
      final isJpeg = bytes.length >= 3 &&
          bytes[0] == 255 &&
          bytes[1] == 216 &&
          bytes[2] == 255;
      if (!isPng && !isJpeg) {
        throw const MobileApiException(
            'Choose a PNG or JPEG payment screenshot.');
      }
      if (mounted) {
        setState(() {
          _paymentProofImage =
              'data:image/${isPng ? 'png' : 'jpeg'};base64,${base64Encode(bytes)}';
          _paymentProofName = file.name;
        });
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$error')));
      }
    }
  }

  Future<void> _loadQuote() async {
    final version = ++_quoteVersion;
    setState(() {
      _quoteLoading = true;
      _quoteError = '';
      _quote = null;
      _acceptedRentalTerms = false;
    });
    try {
      final quote = await _api.quoteRental(
          widget.item.id, _selectedDurationMinutes,
          stockGroupId: widget.item.stockGroupId,
          scheduledStartAt: _scheduledStartAt);
      if (mounted && version == _quoteVersion) {
        setState(() {
          _quote = quote;
          _quoteLoading = false;
        });
      }
    } catch (error) {
      if (mounted && version == _quoteVersion) {
        setState(() {
          _quoteError = error.toString();
          _quoteLoading = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _quoteVersion++;
    _customResortController.dispose();
    _customHoursController.dispose();
    _paymentReferenceController.dispose();
    super.dispose();
  }

  num? get _baseFee => _quote?['rental_fee'] as num?;
  num? get _total => _baseFee;
  int get _billedMinutes =>
      (_quote?['billed_minutes'] as num?)?.toInt() ?? _selectedDurationMinutes;
  String get _estimatedDueText {
    final value = _quote?['due_at'];
    final parsed = value is String ? DateTime.tryParse(value)?.toLocal() : null;
    return parsed == null
        ? 'Set at handoff'
        : DateFormat('EEE, MMM d, yyyy · h:mm a').format(parsed);
  }

  String get _lateRateText {
    final rate = _quote?['overtime_rate'];
    if (rate is! num) return 'See rate details';
    final unit = (_quote?['overtime_unit_minutes'] as num?)?.toInt() ?? 60;
    return '${rentalMoney(rate)} per started late ${unit >= 1440 ? 'day' : 'hour'}';
  }

  String get _packageLength => _billedMinutes % 60 == 0
      ? '${_billedMinutes ~/ 60} hour${_billedMinutes == 60 ? '' : 's'}'
      : '$_billedMinutes minutes';

  Future<void> _showRentalTerms() async {
    if (_quote == null || _quoteLoading) return;
    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Rental terms for this request'),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                RentalValueRow('Equipment', widget.item.name),
                RentalValueRow('Requested duration',
                    _durationLabel(_selectedDurationMinutes)),
                RentalValueRow('Billed duration', _packageLength),
                RentalValueRow('Estimated return', _estimatedDueText),
                RentalValueRow('Rental fee', rentalMoney(_baseFee)),
                RentalValueRow('Late rate', _lateRateText),
                RentalValueRow(
                    'Handoff location',
                    _selectedResort == 'Other / Custom Resort'
                        ? _customResortController.text.trim()
                        : _selectedResort),
                RentalValueRow('Payment',
                    _paymentMethod == 'QR' ? 'InstaPay' : 'Cash at handoff'),
                const SizedBox(height: 12),
                const Text(
                  'Your request must be approved by the admin. The rental timer starts when staff verifies and hands over the equipment. The return time above is an estimate based on a handoff now; My Rentals will show the confirmed due time after handoff.',
                  style: TextStyle(height: 1.45),
                ),
                const SizedBox(height: 10),
                const Text(
                  'Return the same equipment and all included accessories by the confirmed due time. A return request alone does not stop the timer; staff must record receipt of the item. Late fees use the rate shown above. Damage, loss, or missing accessories may result in recorded charges after inspection.',
                  style: TextStyle(height: 1.45),
                ),
                const SizedBox(height: 10),
                const Text(
                  'Show one physical Government or Student ID at handoff. For InstaPay, upload the successful transfer receipt; staff must verify the payment before approving the request.',
                  style: TextStyle(height: 1.45),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Review later')),
          FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Agree to these terms')),
        ],
      ),
    );
    if (accepted == true && mounted) {
      setState(() => _acceptedRentalTerms = true);
    }
  }

  Future<void> _submitRentalRequest() async {
    if (!_acceptedRentalTerms) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Review and accept the rental terms first.')));
      return;
    }
    if (_quote == null || !_form.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() => _isSubmitting = true);
    try {
      final user = Provider.of<AuthService>(context, listen: false).currentUser;
      if (user == null) {
        throw const MobileApiException(
            'Please sign in again to request equipment.');
      }
      if (_paymentMethod == 'QR' && !_paymentConfirmed) {
        throw const MobileApiException(
            'Confirm that the InstaPay transfer succeeded.');
      }
      if (_paymentMethod == 'QR' && _paymentProofImage == null) {
        throw const MobileApiException(
            'Upload a screenshot of the successful InstaPay transfer.');
      }
      await _api.createRentalRequest(
        itemId: widget.item.id,
        stockGroupId: widget.item.stockGroupId,
        scheduledStartAt: _scheduledStartAt,
        itemName: widget.item.name,
        itemCode: widget.item.qrCode,
        durationMinutes: _selectedDurationMinutes,
        deliveryLocation: _selectedResort == 'Other / Custom Resort'
            ? _customResortController.text.trim()
            : _selectedResort,
        paymentMethod: _paymentMethod,
        requestKey: _requestKey,
        paymentProofImageDataUrl: _paymentProofImage,
        paymentReference: _paymentReferenceController.text,
        expectedQuote: {
          'rentalFee': _baseFee,
          'billedMinutes': _quote!['billed_minutes'],
          if (_quote!['overtime_rate'] is num)
            'overtimeRate': _quote!['overtime_rate'],
        },
        acceptedRentalTerms: true,
        rentalTermsVersion: mobileRentalTermsVersion,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content:
              Text('Rental request sent. Track its review in My Rentals.')));
      Navigator.pushReplacement(context,
          MaterialPageRoute(builder: (_) => ActiveRentalsScreen(api: _api)));
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Could not send your rental request. $error')));
        if (error is MobileApiException &&
            error.statusCode == 409 &&
            error.message.toLowerCase().contains('rates changed')) {
          _loadQuote();
        }
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return PopScope(
      canPop: !_isSubmitting,
      child: Scaffold(
        appBar: AppBar(title: const Text('Review request')),
        bottomNavigationBar: RentalActionBar(
          summaryLabel:
              _paymentMethod == 'QR' ? 'Transfer total' : 'Due at handoff',
          summaryValue: _quoteLoading ? 'Updating…' : rentalMoney(_total),
          label: 'Send rental request',
          busy: _isSubmitting,
          onPressed: !_quoteLoading && _quote != null && _acceptedRentalTerms
              ? _submitRentalRequest
              : null,
        ),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 712),
            child: Form(
              key: _form,
              child: SingleChildScrollView(
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                padding: const EdgeInsets.all(16),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      RentalSection(
                          child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                            ClipRRect(
                                borderRadius: BorderRadius.circular(12),
                                child: SizedBox(
                                    height: 72,
                                    width: 72,
                                    child: widget.item.buildImage(
                                        fit: BoxFit.cover,
                                        height: 72,
                                        width: 72))),
                            const SizedBox(width: 14),
                            Expanded(
                                child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                  Text(widget.item.name,
                                      style: const TextStyle(
                                          fontSize: 20,
                                          fontWeight: FontWeight.w800)),
                                  const SizedBox(height: 4),
                                  Text(widget.item.category,
                                      style: TextStyle(
                                          color: scheme.onSurfaceVariant,
                                          fontSize: 13)),
                                  const SizedBox(height: 6),
                                  Text(widget.item.rateText,
                                      style: TextStyle(
                                          color: scheme.primary,
                                          fontWeight: FontWeight.w600)),
                                ])),
                          ])),
                      RentalSection(
                        title: 'Rental details',
                        icon: Icons.edit_calendar_outlined,
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('How long?',
                                  style: TextStyle(
                                      color: scheme.onSurfaceVariant,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600)),
                              const SizedBox(height: 8),
                              ListTile(
                                  contentPadding: EdgeInsets.zero,
                                  leading: const Icon(Icons.event_outlined),
                                  title: Text(_scheduledStartAt == null
                                      ? 'Rent now'
                                      : DateFormat('MMM d, yyyy · h:mm a')
                                          .format(_scheduledStartAt!
                                              .toUtc()
                                              .add(const Duration(hours: 8)))),
                                  subtitle: const Text(
                                      'Delivery within Lakewood Subdivision only'),
                                  trailing: _scheduledStartAt == null
                                      ? null
                                      : IconButton(
                                          icon: const Icon(Icons.close),
                                          onPressed: () {
                                            setState(() {
                                              _scheduledStartAt = null;
                                              _requestKey = MobileApiService
                                                  .operationKey();
                                              _acceptedRentalTerms = false;
                                            });
                                            _loadQuote();
                                          }),
                                  onTap: () async {
                                    final day = await showDatePicker(
                                        context: context,
                                        initialDate: DateTime.now()
                                            .toUtc()
                                            .add(const Duration(hours: 8)),
                                        firstDate: DateTime.now()
                                            .toUtc()
                                            .add(const Duration(hours: 8)),
                                        lastDate: DateTime.now()
                                            .toUtc()
                                            .add(const Duration(hours: 8))
                                            .add(const Duration(days: 180)));
                                    if (day == null || !context.mounted) return;
                                    final time = await showTimePicker(
                                        context: context,
                                        initialTime: TimeOfDay.fromDateTime(
                                            DateTime.now()
                                                .toUtc()
                                                .add(const Duration(hours: 8))
                                                .add(const Duration(
                                                    minutes: 15))));
                                    if (time == null || !context.mounted) {
                                      return;
                                    }
                                    setState(() {
                                      _scheduledStartAt = DateTime.parse(
                                          '${DateFormat('yyyy-MM-dd').format(day)}T${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}:00+08:00');
                                      _requestKey =
                                          MobileApiService.operationKey();
                                      _acceptedRentalTerms = false;
                                    });
                                    _loadQuote();
                                  }),
                              Wrap(spacing: 8, runSpacing: 8, children: [
                                for (final minutes in _durationChoices)
                                  ChoiceChip(
                                      label: Text(_durationLabel(minutes)),
                                      selected: !_isCustomDuration &&
                                          minutes == _selectedDurationMinutes,
                                      onSelected: _isSubmitting
                                          ? null
                                          : (_) {
                                              setState(() {
                                                _isCustomDuration = false;
                                                _selectedDurationMinutes =
                                                    minutes;
                                                _requestKey = MobileApiService
                                                    .operationKey();
                                              });
                                              _loadQuote();
                                            }),
                                ChoiceChip(
                                  label: const Text('Custom hours'),
                                  selected: _isCustomDuration,
                                  onSelected: _isSubmitting
                                      ? null
                                      : (_) {
                                          setState(() {
                                            _isCustomDuration = true;
                                            final hours = int.tryParse(
                                                    _customHoursController
                                                        .text) ??
                                                22;
                                            _selectedDurationMinutes =
                                                hours * 60;
                                            _requestKey = MobileApiService
                                                .operationKey();
                                          });
                                          _loadQuote();
                                        },
                                ),
                              ]),
                              if (_isCustomDuration) ...[
                                const SizedBox(height: 12),
                                TextFormField(
                                  controller: _customHoursController,
                                  enabled: !_isSubmitting,
                                  keyboardType: TextInputType.number,
                                  inputFormatters: [
                                    FilteringTextInputFormatter.digitsOnly
                                  ],
                                  decoration: const InputDecoration(
                                    labelText: 'Number of hours',
                                    hintText: 'e.g. 22',
                                    prefixIcon:
                                        Icon(Icons.access_time_rounded),
                                  ),
                                  onChanged: (value) {
                                    final hours = int.tryParse(value) ?? 0;
                                    if (hours > 0 && hours <= 168) {
                                      setState(() {
                                        _selectedDurationMinutes = hours * 60;
                                        _requestKey = MobileApiService
                                            .operationKey();
                                      });
                                      _loadQuote();
                                    }
                                  },
                                ),
                              ],
                              const SizedBox(height: 14),
                              Text('Which resort are you staying at?',
                                  style: TextStyle(
                                      color: scheme.onSurfaceVariant,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600)),
                              const SizedBox(height: 8),
                              DropdownButtonFormField<String>(
                                initialValue: _selectedResort.isEmpty
                                    ? null
                                    : _selectedResort,
                                isExpanded: true,
                                decoration: const InputDecoration(
                                    labelText: 'Select a resort'),
                                items: privateResorts
                                    .map((place) => DropdownMenuItem(
                                        value: place,
                                        child: Text(place,
                                            overflow: TextOverflow.ellipsis)))
                                    .toList(),
                                validator: (place) => place == null ||
                                        place.isEmpty
                                    ? 'Select the resort where you are staying.'
                                    : null,
                                onChanged: _isSubmitting
                                    ? null
                                    : (place) {
                                        if (place != null) {
                                          setState(() {
                                            _selectedResort = place;
                                            _acceptedRentalTerms = false;
                                          });
                                        }
                                      },
                              ),
                              if (_selectedResort.isNotEmpty) ...[
                                const SizedBox(height: 8),
                                RentalNotice(
                                  icon: Icons.delivery_dining_outlined,
                                  title:
                                      _selectedResort == 'Other / Custom Resort'
                                          ? 'Delivery to your resort'
                                          : 'Delivery to $_selectedResort',
                                  message:
                                      'Have your rental QR code ready so staff can confirm the handoff.',
                                ),
                                if (_selectedResort ==
                                    'Other / Custom Resort') ...[
                                  const SizedBox(height: 10),
                                  TextFormField(
                                    controller: _customResortController,
                                    enabled: !_isSubmitting,
                                    maxLength: 120,
                                    textInputAction: TextInputAction.next,
                                    decoration: const InputDecoration(
                                        labelText: 'Resort name',
                                        hintText: 'Enter a resort'),
                                    onChanged: (_) => setState(
                                        () => _acceptedRentalTerms = false),
                                    validator: (value) => _selectedResort !=
                                            'Other / Custom Resort'
                                        ? null
                                        : value == null || value.trim().isEmpty
                                            ? 'Enter the resort name.'
                                            : null,
                                  ),
                                ],
                              ],
                            ]),
                      ),
                      RentalSection(
                        title: 'Price summary',
                        icon: Icons.receipt_long_outlined,
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (_quoteLoading) ...[
                                const LinearProgressIndicator(),
                                const SizedBox(height: 12),
                                const Text('Updating price…'),
                              ] else if (_quoteError.isNotEmpty)
                                RentalNotice(
                                  isError: true,
                                  title: 'Price unavailable',
                                  message: _quoteError,
                                  action: TextButton.icon(
                                      onPressed: _loadQuote,
                                      icon: const Icon(Icons.refresh),
                                      label: const Text('Retry price')),
                                )
                              else ...[
                                RentalValueRow(
                                    'Rental fee', rentalMoney(_baseFee)),
                                const SizedBox(height: 8),
                                Text(
                                    'Billed for $_packageLength${_billedMinutes > _selectedDurationMinutes ? ' (minimum package)' : ''}.',
                                    style: TextStyle(
                                        fontSize: 13,
                                        color: scheme.onSurfaceVariant,
                                        height: 1.4)),
                              ],
                            ]),
                      ),
                      RentalSection(
                        title: 'Payment',
                        icon: Icons.payments_outlined,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SegmentedButton<String>(
                              segments: [
                                const ButtonSegment<String>(
                                    value: 'CASH',
                                    icon: Icon(Icons.payments_outlined),
                                    label: Text('Cash')),
                                if (_paymentInstructions?[
                                    'instapay_qr_data_url'] is String)
                                  const ButtonSegment<String>(
                                      value: 'QR',
                                      icon: Icon(Icons.qr_code_2_rounded),
                                      label: Text('InstaPay')),
                              ],
                              selected: {_paymentMethod},
                              showSelectedIcon: false,
                              onSelectionChanged: _isSubmitting
                                  ? null
                                  : (values) {
                                      final value = values.first;
                                      setState(() {
                                        _paymentMethod = value;
                                        _paymentConfirmed = false;
                                        _paymentProofImage = null;
                                        _paymentProofName = null;
                                        _acceptedRentalTerms = false;
                                      });
                                    },
                            ),
                            if (_paymentInstructions != null &&
                                _paymentInstructions?['instapay_qr_data_url']
                                    is! String)
                              Padding(
                                padding: const EdgeInsets.only(top: 10),
                                child: Text(
                                    'InstaPay is not set up yet. Choose cash for now.',
                                    style: TextStyle(
                                        color: scheme.onSurfaceVariant,
                                        fontSize: 12)),
                              ),
                          ],
                        ),
                      ),
                      if (_paymentMethod == 'QR') ...[
                        RentalSection(
                            title: 'Pay by InstaPay',
                            icon: Icons.qr_code_2,
                            subtitle:
                                'Scan to transfer, then upload your receipt.',
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  if (_paymentInstructions?['instapay_qr_data_url']
                                          is String &&
                                      (_paymentInstructions!['instapay_qr_data_url']
                                              as String)
                                          .startsWith('data:image/'))
                                    Center(
                                        child: Container(
                                            constraints: const BoxConstraints(
                                                maxWidth: 240),
                                            padding: const EdgeInsets.all(12),
                                            decoration: BoxDecoration(
                                                color: Colors.white,
                                                borderRadius:
                                                    BorderRadius.circular(12)),
                                            child: Image.memory(base64Decode(
                                                (_paymentInstructions![
                                                            'instapay_qr_data_url']
                                                        as String)
                                                    .split(',')
                                                    .last)))),
                                  if ((_paymentInstructions?['account_name'] ??
                                          '')
                                      .toString()
                                      .isNotEmpty)
                                    Text(
                                        'Account name: ${_paymentInstructions!['account_name']}'),
                                  if ((_paymentInstructions?[
                                              'account_number'] ??
                                          '')
                                      .toString()
                                      .isNotEmpty)
                                    Text(
                                        'Account number: ${_paymentInstructions!['account_number']}'),
                                  const SizedBox(height: 8),
                                  RentalValueRow('Exact transfer total',
                                      rentalMoney(_total),
                                      emphasis: true),
                                  if ((_paymentInstructions?['instructions'] ??
                                          '')
                                      .toString()
                                      .isNotEmpty)
                                    Text((_paymentInstructions!['instructions'])
                                        .toString()),
                                  const SizedBox(height: 10),
                                  TextField(
                                      controller: _paymentReferenceController,
                                      enabled: !_isSubmitting,
                                      maxLength: 100,
                                      decoration: const InputDecoration(
                                          labelText:
                                              'Transfer reference (optional)')),
                                  OutlinedButton.icon(
                                      onPressed: _isSubmitting
                                          ? null
                                          : _choosePaymentProof,
                                      icon: const Icon(Icons.upload_file),
                                      label: Text(_paymentProofName == null
                                          ? 'Upload payment receipt'
                                          : 'Change payment receipt')),
                                  if (_paymentProofImage != null) ...[
                                    const SizedBox(height: 8),
                                    Center(
                                        child: Image.memory(
                                            base64Decode(_paymentProofImage!
                                                .split(',')
                                                .last),
                                            height: 170,
                                            fit: BoxFit.contain)),
                                    Text('Selected: $_paymentProofName',
                                        textAlign: TextAlign.center),
                                  ],
                                  CheckboxListTile(
                                      contentPadding: EdgeInsets.zero,
                                      dense: true,
                                      value: _paymentConfirmed,
                                      onChanged: _isSubmitting
                                          ? null
                                          : (value) => setState(() =>
                                              _paymentConfirmed =
                                                  value ?? false),
                                      title: const Text(
                                          'I completed this InstaPay transfer')),
                                ])),
                      ],
                      RentalSection(
                        title: 'Rental agreement',
                        icon: Icons.fact_check_outlined,
                        subtitle: 'Review before sending your request.',
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            RentalValueRow(
                                'Estimated return', _estimatedDueText),
                            RentalValueRow('Late rate', _lateRateText),
                            const SizedBox(height: 8),
                            CheckboxListTile(
                              key: const ValueKey('rental-terms-acceptance'),
                              contentPadding: EdgeInsets.zero,
                              controlAffinity: ListTileControlAffinity.leading,
                              titleAlignment: ListTileTitleAlignment.top,
                              value: _acceptedRentalTerms,
                              onChanged: _isSubmitting ||
                                      _quoteLoading ||
                                      _quote == null
                                  ? null
                                  : (value) => setState(() =>
                                      _acceptedRentalTerms = value ?? false),
                              title: const Text('I agree to the rental terms',
                                  style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600)),
                              subtitle: const Text(
                                  'Read the terms for this request.',
                                  style: TextStyle(fontSize: 12, height: 1.4)),
                            ),
                            Align(
                              alignment: Alignment.centerLeft,
                              child: TextButton.icon(
                                onPressed: _isSubmitting ||
                                        _quoteLoading ||
                                        _quote == null
                                    ? null
                                    : _showRentalTerms,
                                icon: const Icon(Icons.description_outlined),
                                label: const Text('Read rental terms'),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                    ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
