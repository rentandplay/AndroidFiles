import 'dart:convert';
import 'dart:async';
import '../../services/business_settings.dart';
import '../../services/server_clock.dart';
import '../../services/payment_proof_image.dart';
import '../../widgets/live_business_settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../models/item_model.dart';
import '../../services/auth_service.dart';
import '../../services/mobile_api_service.dart';
import '../../services/rental_offline_cache.dart';
import '../../widgets/glass_app_bar.dart';
import '../../widgets/liquid_glass.dart';
import '../../widgets/rental_ui.dart';
import 'active_rentals_screen.dart';
import '../../utils/error_sanitizer.dart';

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
  bool _isCustomDuration = false;
  int _customDays = 2;
  int _customHours = 0;
  Timer? _customQuoteDebounce;
  String _selectedResort = '';
  DateTime? _scheduledStartAt;
  final _customResortController = TextEditingController();
  final _phoneController = TextEditingController();
  String _customerName = '';
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
  String? _dynamicRentalTermsText;
  bool _termsLoaded = false;
  String _termsError = '';
  int _termsLoadVersion = 0, _paymentLoadVersion = 0;
  String _currentRentalTermsVersion = mobileRentalTermsVersion;
  MobileApiService get _api => widget.api ?? MobileApiService.instance;

  late final BusinessSettings _business;
  StreamSubscription<Map<String, dynamic>>? _settingsEvents;
  bool get _cashAllowed => _paymentInstructions?['accept_cash'] != false;
  bool get _qrAvailable => (_paymentInstructions?['instapay_qr_data_url'] ??
          _paymentInstructions?['gcash_qr_data_url'] ??
          '')
      .toString()
      .trim()
      .isNotEmpty;
  bool get _paymentAvailable =>
      _paymentInstructions != null && (_cashAllowed || _qrAvailable);
  bool get _isScheduleWindowValid {
    if (_scheduledStartAt == null) return true;
    final nowUtc = ServerClock.instance.now.toUtc();
    final startUtc = _scheduledStartAt!.toUtc();
    if (startUtc.isBefore(nowUtc.add(const Duration(minutes: 4)))) {
      return false;
    }
    if (startUtc.isAfter(nowUtc.add(const Duration(days: 180)))) {
      return false;
    }
    return true;
  }

  String? get _scheduleValidationError {
    if (_scheduledStartAt == null) return null;
    final nowUtc = ServerClock.instance.now.toUtc();
    final startUtc = _scheduledStartAt!.toUtc();
    if (startUtc.isBefore(nowUtc.add(const Duration(minutes: 4)))) {
      return 'Start time must be at least 5 minutes from now. Pick a later time or tap X to rent now.';
    }
    if (startUtc.isAfter(nowUtc.add(const Duration(days: 180)))) {
      return 'Schedule start time within the next 180 days.';
    }
    if (_business.loaded && !_business.isOpen(_scheduledStartAt!)) {
      final opens =
          formatBusinessTime(_business.values['opens_at'] ?? '08:00');
      final closes =
          formatBusinessTime(_business.values['closes_at'] ?? '20:00');
      return 'Start time must be within store hours ($opens – $closes).';
    }
    return null;
  }

  bool get _handoffAllowed =>
      _business.loaded &&
      _business.isOpen(_scheduledStartAt ?? ServerClock.instance.now) &&
      _isScheduleWindowValid;

  void _businessUpdated() {
    if (mounted) setState(() {});
  }

  bool get _hasDailyBaseRate =>
      widget.item.rateOptions.any((rate) => rate['id'] == 'admin-base-daily');

  int get _customDurationMinutes => (_customDays * 24 + _customHours) * 60;

  String? get _customDurationError {
    if (!_isCustomDuration) return null;
    final mins = _customDurationMinutes;
    if (mins < 60) {
      return 'Minimum rental duration is 1 hour.';
    }
    if (mins > 10080) {
      return 'Maximum rental duration is 7 days (168 hours). Contact resort staff for longer stays.';
    }
    return null;
  }

  bool get _isDurationValid =>
      _selectedDurationMinutes >= 60 &&
      _selectedDurationMinutes <= 10080 &&
      _customDurationError == null;

  DateTime get _estimatedReturnAt {
    final start = _scheduledStartAt ?? ServerClock.instance.now;
    return start.add(Duration(minutes: _selectedDurationMinutes));
  }

  bool get _returnDuringStoreHours {
    if (!_business.loaded) return true;
    return _business.isOpen(_estimatedReturnAt);
  }

  List<int> get _durationChoices {
    final minutes = _hasDailyBaseRate
        ? <int>{1320, 1440}
        : <int>{60, 120, 180, 300, 480, 1320, 1440};
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
    if (minutes == 1320) return '22 hrs (Whole day)';
    if (minutes == 1440) return '24 hrs (1 day)';
    final hours = minutes ~/ 60;
    final remainingMinutes = minutes % 60;
    if (hours == 0) return '$minutes min${minutes == 1 ? '' : 's'}';
    if (remainingMinutes == 0) {
      if (hours > 24) {
        final days = hours ~/ 24;
        final extraH = hours % 24;
        if (extraH == 0) {
          return '$hours hrs ($days day${days == 1 ? '' : 's'})';
        }
        return '$hours hrs ($days d $extraH hr${extraH == 1 ? '' : 's'})';
      }
      return '$hours hr${hours == 1 ? '' : 's'}';
    }
    if (hours >= 24) {
      final days = hours ~/ 24;
      final extraH = hours % 24;
      return '$days d $extraH hr $remainingMinutes min';
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
    _business = BusinessSettings(_api)..addListener(_businessUpdated);
    _settingsEvents = _api.watchRentalEvents().listen((event) {
      if (event['event'] == 'ready' || event['event'] == 'settings.changed') {
        _loadPaymentInstructions();
        _loadTerms();
        if (!_isSubmitting) _loadQuote();
      }
    });
    _loadQuote();
    _loadPaymentInstructions();
    _loadTerms();
    _loadUserProfile();
  }

  Future<void> _loadTerms() async {
    final version = ++_termsLoadVersion;
    try {
      final res = await _api.terms();
      if (mounted && version == _termsLoadVersion) {
        setState(() {
          final previousVersion = _currentRentalTermsVersion;
          final rentalText = res['rental_terms'] as String?;
          if (rentalText != null && rentalText.trim().isNotEmpty) {
            _dynamicRentalTermsText = rentalText.trim();
          }
          final rentalVer = res['rental_terms_version'] as String?;
          if (rentalVer != null && rentalVer.trim().isNotEmpty) {
            _currentRentalTermsVersion = rentalVer.trim();
          }
          _termsLoaded = rentalText != null &&
              rentalText.trim().isNotEmpty &&
              rentalVer != null &&
              rentalVer.trim().isNotEmpty;
          _termsError = _termsLoaded
              ? ''
              : 'Could not load the current rental agreement. Please retry.';
          if (previousVersion != _currentRentalTermsVersion) {
            _acceptedRentalTerms = false;
          }
        });
      }
    } catch (_) {
      if (mounted && version == _termsLoadVersion) {
        setState(() {
          _termsLoaded = false;
          _termsError =
              'Could not load the current rental agreement. Please retry.';
        });
      }
    }
  }

  Future<void> _loadPaymentInstructions() async {
    final version = ++_paymentLoadVersion;
    try {
      final result = await _api.paymentInstructions();
      if (mounted && version == _paymentLoadVersion) {
        setState(() {
          _paymentInstructions = result;
          if (!_cashAllowed && _paymentMethod == 'CASH') {
            _paymentMethod = 'QR';
            _acceptedRentalTerms = false;
          } else if (!_qrAvailable && _cashAllowed) {
            _paymentMethod = 'CASH';
          }
        });
      }
    } catch (_) {
      if (mounted && version == _paymentLoadVersion) {
        setState(() => _paymentInstructions = null);
      }
    }
  }

  Future<void> _loadUserProfile() async {
    try {
      final authService = Provider.of<AuthService>(context, listen: false);
      final uid = authService.currentUser?.uid;
      if (uid != null && uid.isNotEmpty) {
        final savedResort = await RentalOfflineCache.loadPreferredResort(uid);
        if (savedResort != null && mounted && _selectedResort.isEmpty) {
          final resort = savedResort['resort'] ?? '';
          if (privateResorts.contains(resort)) {
            setState(() {
              _selectedResort = resort;
              if (resort == 'Other / Custom Resort' &&
                  _customResortController.text.isEmpty &&
                  savedResort['customResort'] != null) {
                _customResortController.text = savedResort['customResort']!;
              }
            });
          }
        }
      }
      final user = await authService.getCurrentUserModel();
      if (user != null && mounted) {
        setState(() {
          _customerName = user.name;
          if (_phoneController.text.isEmpty && user.phone.isNotEmpty) {
            _phoneController.text = user.phone;
          }
        });
      }
    } catch (_) {}
  }

  Future<void> _showReceiptLightbox() {
    if (_paymentProofImage == null) return Future.value();
    HapticFeedback.selectionClick();
    return showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.88),
      builder: (dialogContext) => Dialog.fullscreen(
        backgroundColor: Colors.transparent,
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Payment receipt preview',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 17,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          Text(
                            'Expected ${rentalMoney(_total)} · Pinch to zoom',
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Close receipt preview',
                      onPressed: () => Navigator.pop(dialogContext),
                      icon: const Icon(Icons.close_rounded,
                          color: Colors.white, size: 26),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: InteractiveViewer(
                  minScale: 1.0,
                  maxScale: 4.0,
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Image.memory(
                        base64Decode(_paymentProofImage!.split(',').last),
                        fit: BoxFit.contain,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _normalizedPhone(String value) {
    final digits = value.replaceAll(RegExp(r'\D'), '');
    final mobile = digits.startsWith('63')
        ? digits.substring(2)
        : digits.startsWith('0')
            ? digits.substring(1)
            : digits;
    return '+63$mobile';
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
      final imageDataUrl = await paymentProofDataUrl(await file.readAsBytes());
      if (mounted) {
        setState(() {
          _paymentProofImage = imageDataUrl;
          _paymentProofName = file.name;
        });
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(ErrorSanitizer.format(error))));
      }
    }
  }

  Future<void> _loadQuote() async {
    final version = ++_quoteVersion;
    if (!_isDurationValid || !_isScheduleWindowValid) {
      setState(() {
        _quoteLoading = false;
        _quote = null;
        _acceptedRentalTerms = false;
        _quoteError = _customDurationError ??
            _scheduleValidationError ??
            'Choose a valid rental time and duration.';
      });
      return;
    }
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
    _customQuoteDebounce?.cancel();
    _settingsEvents?.cancel();
    _business.removeListener(_businessUpdated);
    _business.dispose();
    _quoteVersion++;
    _customResortController.dispose();
    _phoneController.dispose();
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

  String get _packageLength {
    if (_billedMinutes == 1320) return '22 hours (Whole day)';
    if (_billedMinutes == 1440) return '24 hours (1 day)';
    if (_billedMinutes >= 2880 && _billedMinutes % 1440 == 0) {
      final days = _billedMinutes ~/ 1440;
      return '${_billedMinutes ~/ 60} hours ($days days)';
    }
    return _billedMinutes % 60 == 0
        ? '${_billedMinutes ~/ 60} hour${_billedMinutes == 60 ? '' : 's'}'
        : '$_billedMinutes minutes';
  }

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
                RentalValueRow(
                    'Payment',
                    _paymentMethod == 'QR'
                        ? 'InstaPay / GCash'
                        : 'Cash at handoff'),
                const SizedBox(height: 12),
                if (_dynamicRentalTermsText != null &&
                    _dynamicRentalTermsText!.isNotEmpty)
                  Text(
                    _dynamicRentalTermsText!,
                    style: const TextStyle(height: 1.45),
                  )
                else ...[
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
                    'Show one physical Government or Student ID at handoff. For InstaPay or GCash, upload the successful transfer receipt; staff must verify the payment before approving the request.',
                    style: TextStyle(height: 1.45),
                  ),
                ],
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

  void _setCustomDuration(int days, int hours, {bool immediateQuote = false}) {
    final clampedDays = days.clamp(0, 7);
    int clampedHours = hours.clamp(0, 23);
    if (clampedDays == 7) {
      clampedHours = 0;
    } else if (clampedDays == 0 && clampedHours < 1) {
      clampedHours = 1;
    }
    final totalMinutes = (clampedDays * 24 + clampedHours) * 60;
    setState(() {
      _isCustomDuration = true;
      _customDays = clampedDays;
      _customHours = clampedHours;
      _selectedDurationMinutes = totalMinutes;
      _requestKey = MobileApiService.operationKey();
      _acceptedRentalTerms = false;
    });
    _customQuoteDebounce?.cancel();
    if (immediateQuote) {
      _loadQuote();
    } else {
      _customQuoteDebounce = Timer(const Duration(milliseconds: 350), () {
        if (mounted) _loadQuote();
      });
    }
  }

  Future<void> _showExactHoursDialog() async {
    final currentHours = (_selectedDurationMinutes ~/ 60).clamp(1, 168);
    final result = await showDialog<int>(
      context: context,
      builder: (_) => _ExactHoursDialog(initialHours: currentHours),
    );
    if (result != null && mounted) {
      _setCustomDuration(result ~/ 24, result % 24, immediateQuote: true);
    }
  }

  Future<void> _pickScheduledStartTime() async {
    final nowManila =
        ServerClock.instance.now.toUtc().add(const Duration(hours: 8));
    final firstDay = DateTime(nowManila.year, nowManila.month, nowManila.day);
    final lastDay = firstDay.add(const Duration(days: 180));
    final rawInitial = (_scheduledStartAt ?? ServerClock.instance.now)
        .toUtc()
        .add(const Duration(hours: 8));
    var initialDate =
        DateTime(rawInitial.year, rawInitial.month, rawInitial.day);
    if (initialDate.isBefore(firstDay)) {
      initialDate = firstDay;
    } else if (initialDate.isAfter(lastDay)) {
      initialDate = lastDay;
    }
    final day = await showDatePicker(
      context: context,
      helpText: 'Select rental start date',
      initialDate: initialDate,
      firstDate: firstDay,
      lastDate: lastDay,
    );
    if (day == null || !mounted) {
      return;
    }

    final storeHoursHint = _business.loaded &&
            _business.values['opens_at'] != _business.values['closes_at']
        ? 'Store hours: ${formatBusinessTime(_business.values['opens_at'] ?? '08:00')} – ${formatBusinessTime(_business.values['closes_at'] ?? '20:00')}'
        : 'Select handoff time';

    DateTime defaultManilaTime =
        (_scheduledStartAt ?? ServerClock.instance.now.add(const Duration(minutes: 15)))
            .toUtc()
            .add(const Duration(hours: 8));
    if (_scheduledStartAt == null && day.isAfter(firstDay) && _business.loaded) {
      final candidateUtc = DateTime.parse(
          '${DateFormat('yyyy-MM-dd').format(day)}T${defaultManilaTime.hour.toString().padLeft(2, '0')}:${defaultManilaTime.minute.toString().padLeft(2, '0')}:00+08:00');
      if (!_business.isOpen(candidateUtc)) {
        final opensParts =
            (_business.values['opens_at'] ?? '08:00').toString().split(':');
        final openHour = int.tryParse(opensParts.first) ?? 8;
        final openMin =
            opensParts.length > 1 ? (int.tryParse(opensParts[1]) ?? 0) : 0;
        defaultManilaTime = DateTime(
            day.year, day.month, day.day, openHour, openMin);
      }
    }

    final time = await showTimePicker(
      context: context,
      helpText: storeHoursHint,
      initialTime: TimeOfDay.fromDateTime(defaultManilaTime),
    );
    if (time == null || !mounted) {
      return;
    }
    final selected = DateTime.parse(
        '${DateFormat('yyyy-MM-dd').format(day)}T${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}:00+08:00');

    setState(() {
      _scheduledStartAt = selected;
      _requestKey = MobileApiService.operationKey();
      _acceptedRentalTerms = false;
    });

    if (selected
        .toUtc()
        .isBefore(ServerClock.instance.now.toUtc().add(const Duration(minutes: 5)))) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text(
              'Start time must be at least 5 minutes from now. Choose a later time or tap X to rent now.')));
    } else if (_business.loaded && !_business.isOpen(selected)) {
      final opens =
          formatBusinessTime(_business.values['opens_at'] ?? '08:00');
      final closes =
          formatBusinessTime(_business.values['closes_at'] ?? '20:00');
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
              'Start time must be within store hours ($opens – $closes).')));
    }
    _loadQuote();
  }

  Future<void> _submitRentalRequest() async {
    if (!_isDurationValid) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(_customDurationError ??
              'Please choose a valid rental duration (1 hour to 7 days).')));
      return;
    }
    if (_scheduleValidationError != null) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_scheduleValidationError!)));
      return;
    }
    if (!_acceptedRentalTerms) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Review and accept the rental terms first.')));
      return;
    }
    if (_quote == null ||
        !_form.currentState!.validate() ||
        !_paymentAvailable ||
        !_handoffAllowed ||
        !_termsLoaded) {
      return;
    }
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
            'Confirm that the InstaPay / GCash transfer succeeded.');
      }
      if (_paymentMethod == 'QR' && _paymentProofImage == null) {
        throw const MobileApiException(
            'Upload a screenshot of the successful InstaPay / GCash transfer.');
      }
      final normalizedPhone = _normalizedPhone(_phoneController.text);
      try {
        final authService = Provider.of<AuthService>(context, listen: false);
        await authService.updateCustomerProfile(
          name: _customerName.isNotEmpty
              ? _customerName
              : (user.displayName ?? 'Customer'),
          phone: normalizedPhone,
        );
      } catch (e) {
        debugPrint('Could not update customer phone on checkout: $e');
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
        rentalTermsVersion: _currentRentalTermsVersion,
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

  Widget _buildCustomDurationPanel(
      BuildContext context, ColorScheme scheme) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final error = _customDurationError;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: dark
            ? const Color(0xFF1F2735).withValues(alpha: 0.7)
            : scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: error != null
              ? scheme.error
              : scheme.outlineVariant.withValues(alpha: 0.7),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.schedule_rounded, size: 17, color: scheme.primary),
              const SizedBox(width: 6),
              const Expanded(
                child: Text(
                  'Custom duration (1 hr – 7 days)',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                ),
              ),
              TextButton.icon(
                onPressed: _isSubmitting ? null : _showExactHoursDialog,
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                ),
                icon: const Icon(Icons.edit_outlined, size: 14),
                label: const Text('Type hours', style: TextStyle(fontSize: 12)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final preset in const [
                (36, '36 hrs (1.5d)'),
                (48, '2 days (48h)'),
                (72, '3 days (72h)'),
                (120, '5 days'),
                (168, '7 days (Max)'),
              ])
                ActionChip(
                  visualDensity: VisualDensity.compact,
                  label: Text(preset.$2, style: const TextStyle(fontSize: 12)),
                  backgroundColor: _selectedDurationMinutes == preset.$1 * 60
                      ? scheme.primaryContainer
                      : null,
                  onPressed: _isSubmitting
                      ? null
                      : () {
                          HapticFeedback.selectionClick();
                          _setCustomDuration(
                            preset.$1 ~/ 24,
                            preset.$1 % 24,
                            immediateQuote: true,
                          );
                        },
                ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _DurationStepper(
                  label: 'Days',
                  value: _customDays,
                  min: 0,
                  max: 7,
                  enabled: !_isSubmitting,
                  onChanged: (nextDays) {
                    _setCustomDuration(nextDays, _customHours);
                  },
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _DurationStepper(
                  label: 'Hours',
                  value: _customHours,
                  min: _customDays == 0 ? 1 : 0,
                  max: _customDays >= 7 ? 0 : 23,
                  enabled: !_isSubmitting && _customDays < 7,
                  onChanged: (nextHours) {
                    _setCustomDuration(_customDays, nextHours);
                  },
                ),
              ),
            ],
          ),
          if (error != null) ...[
            const SizedBox(height: 8),
            Text(
              error,
              style: TextStyle(
                color: scheme.error,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildReturnSchedulePreview(
      BuildContext context, ColorScheme scheme) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final returnLocal = _estimatedReturnAt.toUtc().add(const Duration(hours: 8));
    final returnLabel = DateFormat('EEE, MMM d · h:mm a').format(returnLocal);
    final opens = formatBusinessTime(_business.values['opens_at'] ?? '08:00');
    final closes = formatBusinessTime(_business.values['closes_at'] ?? '20:00');
    final withinHours = _returnDuringStoreHours;
    final warnText = dark ? const Color(0xFFFBBF24) : Colors.amber.shade900;
    final warnBg = const Color(0xFFF59E0B).withValues(alpha: 0.14);
    final warnBorder = dark
        ? const Color(0xFFF59E0B).withValues(alpha: 0.38)
        : Colors.amber.shade700.withValues(alpha: 0.35);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: withinHours
            ? scheme.primaryContainer.withValues(alpha: 0.35)
            : warnBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: withinHours
              ? scheme.primary.withValues(alpha: 0.25)
              : warnBorder,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                withinHours
                    ? Icons.event_available_rounded
                    : Icons.info_outline_rounded,
                size: 15,
                color: withinHours ? scheme.primary : warnText,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Estimated return: $returnLabel',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: withinHours ? scheme.onSurface : warnText,
                  ),
                ),
              ),
            ],
          ),
          if (!withinHours) ...[
            const SizedBox(height: 3),
            Text(
              'Note: Return falls outside store hours ($opens – $closes). Consider choosing a duration (like 22 hrs) so return fits store hours, or coordinate drop-off with staff.',
              style: TextStyle(
                fontSize: 11.5,
                color: warnText,
                height: 1.35,
              ),
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return PopScope(
      canPop: !_isSubmitting,
      child: Scaffold(
        appBar: const GlassAppBar(titleText: 'Review request'),
        bottomNavigationBar: RentalActionBar(
          summaryLabel:
              _paymentMethod == 'QR' ? 'Transfer total' : 'Due at handoff',
          summaryValue: _quoteLoading ? 'Updating…' : rentalMoney(_total),
          label: 'Send rental request',
          busy: _isSubmitting,
          onPressed: !_quoteLoading &&
                  _quote != null &&
                  _acceptedRentalTerms &&
                  _paymentAvailable &&
                  _handoffAllowed &&
                  _termsLoaded &&
                  _isDurationValid &&
                  _scheduleValidationError == null
              ? _submitRentalRequest
              : null,
        ),
        body: LiquidAmbientBackdrop(
          child: Center(
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
                        LiveAnnouncementBanner(settings: _business.values),
                        if (_termsError.isNotEmpty)
                          TextButton(
                              onPressed: _loadTerms, child: Text(_termsError)),
                        if (_business.loaded &&
                            !_business.openNow &&
                            _scheduledStartAt == null)
                          RentalNotice(
                              message:
                                  'Shop is currently closed. Staff handoff resumes at ${formatBusinessTime(_business.values['opens_at'] ?? '08:00')}. Tap "Rent now" below to schedule a start within operating hours.'),
                        if (_business.loaded &&
                            _scheduledStartAt != null &&
                            _scheduleValidationError != null)
                          RentalNotice(
                              isError: true,
                              message: _scheduleValidationError!),
                        if (_business.error.isNotEmpty)
                          RentalNotice(message: _business.error),
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
                                                .add(
                                                    const Duration(hours: 8)))),
                                    subtitle: const Text(
                                        'Delivery within Lakewood Subdivision only · Tap to schedule'),
                                    trailing: _scheduledStartAt == null
                                        ? Icon(Icons.chevron_right_rounded,
                                            color: scheme.onSurfaceVariant)
                                        : IconButton(
                                            tooltip: 'Switch to Rent now',
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
                                    onTap: _isSubmitting
                                        ? null
                                        : _pickScheduledStartTime),
                                if (_scheduleValidationError != null) ...[
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 10),
                                    child: Text(
                                      _scheduleValidationError!,
                                      style: TextStyle(
                                        color: scheme.error,
                                        fontSize: 12.5,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ],
                                Wrap(spacing: 8, runSpacing: 8, children: [
                                  for (final minutes in _durationChoices)
                                    ChoiceChip(
                                        label: Text(_durationLabel(minutes)),
                                        selected: !_isCustomDuration &&
                                            minutes == _selectedDurationMinutes,
                                        onSelected: _isSubmitting
                                            ? null
                                            : (_) {
                                                HapticFeedback.selectionClick();
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
                                      avatar: const Icon(Icons.tune_rounded,
                                          size: 15),
                                      label: Text(_isCustomDuration
                                          ? 'Custom: ${_durationLabel(_selectedDurationMinutes)}'
                                          : 'Custom time...'),
                                      selected: _isCustomDuration,
                                      onSelected: _isSubmitting
                                          ? null
                                          : (_) {
                                              HapticFeedback.selectionClick();
                                              if (!_isCustomDuration) {
                                                final initialHours =
                                                    _selectedDurationMinutes >
                                                            1440
                                                        ? _selectedDurationMinutes ~/
                                                            60
                                                        : 48;
                                                _setCustomDuration(
                                                    initialHours ~/ 24,
                                                    initialHours % 24,
                                                    immediateQuote: true);
                                              }
                                            }),
                                ]),
                                if (_isCustomDuration) ...[
                                  const SizedBox(height: 12),
                                  _buildCustomDurationPanel(context, scheme),
                                ],
                                if (_isDurationValid) ...[
                                  const SizedBox(height: 10),
                                  _buildReturnSchedulePreview(context, scheme),
                                ],
                                const SizedBox(height: 14),
                                Text('Which resort are you staying at?',
                                    style: TextStyle(
                                        color: scheme.onSurfaceVariant,
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600)),
                                const SizedBox(height: 8),
                                DropdownButtonFormField<String>(
                                  key: ValueKey('resort-dropdown-$_selectedResort'),
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
                                            HapticFeedback.selectionClick();
                                            setState(() {
                                              _selectedResort = place;
                                              _acceptedRentalTerms = false;
                                            });
                                            try {
                                              final uid = Provider.of<AuthService>(
                                                      context,
                                                      listen: false)
                                                  .currentUser
                                                  ?.uid;
                                              unawaited(RentalOfflineCache
                                                  .savePreferredResort(
                                                uid,
                                                place,
                                                customResort:
                                                    _customResortController.text,
                                              ));
                                            } catch (_) {}
                                          }
                                        },
                                ),
                                if (_selectedResort.isNotEmpty) ...[
                                  const SizedBox(height: 8),
                                  RentalNotice(
                                    icon: Icons.delivery_dining_outlined,
                                    title: _selectedResort ==
                                            'Other / Custom Resort'
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
                                          : value == null ||
                                                  value.trim().isEmpty
                                              ? 'Enter the resort name.'
                                              : null,
                                    ),
                                  ],
                                ],
                              ]),
                        ),
                        RentalSection(
                          title: 'Delivery contact',
                          icon: Icons.phone_android_outlined,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Staff will call or text this number upon arrival at your resort.',
                                style: TextStyle(
                                  color: scheme.onSurfaceVariant,
                                  fontSize: 13,
                                  height: 1.4,
                                ),
                              ),
                              const SizedBox(height: 12),
                              TextFormField(
                                controller: _phoneController,
                                enabled: !_isSubmitting,
                                keyboardType: TextInputType.phone,
                                textInputAction: TextInputAction.next,
                                inputFormatters: [
                                  FilteringTextInputFormatter.allow(
                                    RegExp(r'[+0-9() .-]'),
                                  ),
                                  LengthLimitingTextInputFormatter(20),
                                ],
                                decoration: const InputDecoration(
                                  labelText: 'Contact phone number *',
                                  hintText: '0912 345 6789',
                                  prefixIcon: Icon(Icons.phone_outlined),
                                ),
                                validator: (value) {
                                  final phone = (value ?? '').trim();
                                  if (phone.isEmpty) {
                                    return 'Enter a contact number for delivery.';
                                  }
                                  final clean =
                                      phone.replaceAll(RegExp(r'[\s().-]'), '');
                                  if (!RegExp(r'^(?:\+?63|0)?9\d{9}$')
                                      .hasMatch(clean)) {
                                    return 'Enter a valid Philippine number (e.g. 0912 345 6789).';
                                  }
                                  return null;
                                },
                              ),
                            ],
                          ),
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
                              if (_paymentInstructions != null)
                                SegmentedButton<String>(
                                  expandedInsets: EdgeInsets.zero,
                                  segments: [
                                    if (_cashAllowed)
                                      const ButtonSegment<String>(
                                          value: 'CASH',
                                          icon: Icon(Icons.payments_outlined),
                                          label: Text('Cash')),
                                    ButtonSegment<String>(
                                        value: 'QR',
                                        enabled: _qrAvailable,
                                        icon: Icon(Icons.qr_code_2_rounded),
                                        label: Text('InstaPay / GCash')),
                                  ],
                                  selected: {_paymentMethod},
                                  showSelectedIcon: false,
                                  onSelectionChanged: _isSubmitting
                                      ? null
                                      : (values) {
                                          final value = values.first;
                                          if (value == 'QR' && !_qrAvailable) {
                                            return;
                                          }
                                          setState(() {
                                            _paymentMethod = value;
                                            _paymentConfirmed = false;
                                            _paymentProofImage = null;
                                            _paymentProofName = null;
                                            _acceptedRentalTerms = false;
                                          });
                                        },
                                ),
                              if (_paymentInstructions == null)
                                TextButton(
                                    onPressed: _loadPaymentInstructions,
                                    child: const Text(
                                        'Retry loading payment options')),
                              if (_paymentInstructions != null &&
                                  _paymentInstructions?['instapay_qr_data_url']
                                      is! String &&
                                  _paymentInstructions?['gcash_qr_data_url']
                                      is! String)
                                Padding(
                                  padding: const EdgeInsets.only(top: 10),
                                  child: Text(
                                      _cashAllowed
                                          ? 'Online QR payment is not set up yet. Choose cash for now.'
                                          : 'Electronic checkout is temporarily disabled. Please contact counter staff.',
                                      style: TextStyle(
                                          color: scheme.onSurfaceVariant,
                                          fontSize: 12)),
                                ),
                            ],
                          ),
                        ),
                        if (_paymentMethod == 'QR') ...[
                          RentalSection(
                              title: 'Pay via InstaPay / GCash',
                              icon: Icons.qr_code_2,
                              subtitle:
                                  'Scan to transfer, then upload your receipt.',
                              child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    if ((_paymentInstructions?['instapay_qr_data_url']
                                                    as String?)
                                                ?.startsWith('data:image/') ==
                                            true ||
                                        (_paymentInstructions?['gcash_qr_data_url']
                                                    as String?)
                                                ?.startsWith('data:image/') ==
                                            true)
                                      Center(
                                          child: Container(
                                              constraints: const BoxConstraints(
                                                  maxWidth: 240),
                                              padding: const EdgeInsets.all(12),
                                              decoration: BoxDecoration(
                                                  color: Colors.white,
                                                  borderRadius:
                                                      BorderRadius.circular(
                                                          12)),
                                              child: Image.memory(
                                                  base64Decode(((_paymentInstructions!['instapay_qr_data_url'] ?? _paymentInstructions!['gcash_qr_data_url']) as String).split(',').last)))),
                                    if ((_paymentInstructions?[
                                                'account_name'] ??
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
                                    if ((_paymentInstructions?[
                                                'instructions'] ??
                                            '')
                                        .toString()
                                        .isNotEmpty)
                                      Text((_paymentInstructions![
                                              'instructions'])
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
                                      GestureDetector(
                                        key: const ValueKey(
                                            'checkout-receipt-preview-tap'),
                                        onTap: _showReceiptLightbox,
                                        child: Column(
                                          children: [
                                            ClipRRect(
                                              borderRadius:
                                                  BorderRadius.circular(12),
                                              child: Image.memory(
                                                base64Decode(_paymentProofImage!
                                                    .split(',')
                                                    .last),
                                                height: 170,
                                                fit: BoxFit.contain,
                                              ),
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                              'Selected: $_paymentProofName · Tap to zoom',
                                              textAlign: TextAlign.center,
                                              style: TextStyle(
                                                fontSize: 12,
                                                color: scheme.primary,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
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
                                            'I completed this InstaPay / GCash transfer')),
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
                                controlAffinity:
                                    ListTileControlAffinity.leading,
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
                                    style:
                                        TextStyle(fontSize: 12, height: 1.4)),
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
      ),
    );
  }
}

class _DurationStepper extends StatelessWidget {
  const _DurationStepper({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.enabled,
    required this.onChanged,
  });

  final String label;
  final int value;
  final int min;
  final int max;
  final bool enabled;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.7)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            onPressed: enabled && value > min ? () => onChanged(value - 1) : null,
            icon: const Icon(Icons.remove_circle_outline_rounded, size: 20),
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 26, minHeight: 28),
          ),
          Expanded(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '$value',
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 11,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
          IconButton(
            onPressed: enabled && value < max ? () => onChanged(value + 1) : null,
            icon: const Icon(Icons.add_circle_outline_rounded, size: 20),
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 26, minHeight: 28),
          ),
        ],
      ),
    );
  }
}

class _ExactHoursDialog extends StatefulWidget {
  const _ExactHoursDialog({required this.initialHours});
  final int initialHours;

  @override
  State<_ExactHoursDialog> createState() => _ExactHoursDialogState();
}

class _ExactHoursDialogState extends State<_ExactHoursDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _controller =
      TextEditingController(text: widget.initialHours.toString());

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Custom rental hours'),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Enter total rental hours (minimum 1 hour, maximum 7 days / 168 hours).',
                  style: TextStyle(fontSize: 13),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _controller,
                  autofocus: true,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(
                    labelText: 'Total hours',
                    hintText: 'e.g. 22, 36, 48, 72',
                    suffixText: 'hours',
                    errorMaxLines: 3,
                  ),
                  validator: (value) {
                    final parsed = int.tryParse((value ?? '').trim());
                    if (parsed == null) {
                      return 'Enter a valid whole number of hours.';
                    }
                    if (parsed < 1) {
                      return 'Minimum rental duration is 1 hour.';
                    }
                    if (parsed > 168) {
                      return 'Maximum is 168 hours (7 days). Contact resort staff for longer stays.';
                    }
                    return null;
                  },
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            if (_formKey.currentState?.validate() == true) {
              Navigator.pop(context, int.parse(_controller.text.trim()));
            }
          },
          child: const Text('Apply'),
        ),
      ],
    );
  }
}
