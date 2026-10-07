import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../../models/item_model.dart';
import '../../services/auth_service.dart';
import '../../services/mobile_api_service.dart';
import '../../widgets/rental_ui.dart';
import 'active_rentals_screen.dart';

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
  String _deliveryLocation = 'Shop pickup';
  final _customResortController = TextEditingController();
  String _paymentMethod = 'CASH';
  bool _isSubmitting = false, _quoteLoading = true, _paymentConfirmed = false;
  Map<String, dynamic>? _quote;
  Map<String, dynamic>? _paymentInstructions;
  String? _paymentProofImage, _paymentProofName;
  final _paymentReferenceController = TextEditingController();
  String _quoteError = '';
  int _quoteVersion = 0;
  String _requestKey = MobileApiService.operationKey();
  MobileApiService get _api => widget.api ?? MobileApiService.instance;

  List<int> get _durationChoices {
    final minutes = <int>{60, 120, 180, 300, 480};
    for (final rate in widget.item.rateOptions) {
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
    'Shop pickup',
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

  Future<void> _choosePaymentProof() async {
    try {
      final file = await ImagePicker().pickImage(
          source: ImageSource.gallery, maxWidth: 1800, imageQuality: 75);
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
    });
    try {
      final quote = await _api.quoteRental(
          widget.item.id, _selectedDurationMinutes);
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
    _paymentReferenceController.dispose();
    super.dispose();
  }

  num? get _baseFee => _quote?['rental_fee'] as num?;
  num? get _deposit => _quote?['deposit_amount'] as num?;
  num? get _total =>
      _baseFee == null || _deposit == null ? null : _baseFee! + _deposit!;
  int get _billedMinutes =>
      (_quote?['billed_minutes'] as num?)?.toInt() ??
      _selectedDurationMinutes;
  String get _packageLength => _billedMinutes % 60 == 0
      ? '${_billedMinutes ~/ 60} hour${_billedMinutes == 60 ? '' : 's'}'
      : '$_billedMinutes minutes';
  Future<void> _submitRentalRequest() async {
    if (_quote == null || !_form.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() => _isSubmitting = true);
    try {
      final user = Provider.of<AuthService>(context, listen: false).currentUser;
      if (user == null)
        throw const MobileApiException(
            'Please sign in again to request equipment.');
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
        itemName: widget.item.name,
        itemCode: widget.item.qrCode,
        durationMinutes: _selectedDurationMinutes,
        deliveryLocation: _deliveryLocation == 'Other / Custom Resort'
            ? _customResortController.text.trim()
            : _deliveryLocation,
        paymentMethod: _paymentMethod,
        requestKey: _requestKey,
        paymentProofImageDataUrl: _paymentProofImage,
        paymentReference: _paymentReferenceController.text,
        expectedQuote: {
          'rentalFee': _baseFee,
          'depositAmount': _deposit,
          'billedMinutes': _quote!['billed_minutes']
        },
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Rental request sent. Track its review in My Rentals.')));
      Navigator.pushReplacement(context,
          MaterialPageRoute(builder: (_) => const ActiveRentalsScreen()));
    } catch (error) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Could not send your rental request. $error')));
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
        appBar: AppBar(title: const Text('Review rental request')),
        bottomNavigationBar: RentalActionBar(
          summaryLabel: _paymentMethod == 'QR' ? 'Pay now' : 'Due at handoff',
          summaryValue: _quoteLoading ? 'Updating…' : rentalMoney(_total),
          label: 'Send rental request',
          busy: _isSubmitting,
          onPressed:
              !_quoteLoading && _quote != null ? _submitRentalRequest : null,
        ),
        body: Form(
          key: _form,
          child: SingleChildScrollView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: const EdgeInsets.all(16),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
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
                                fit: BoxFit.cover, height: 72, width: 72))),
                    const SizedBox(width: 14),
                    Expanded(
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                          Text(widget.item.name,
                              style: const TextStyle(
                                  fontSize: 20, fontWeight: FontWeight.w800)),
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
                title: 'How long will you use it?',
                icon: Icons.schedule_outlined,
                subtitle:
                    'Your rental clock starts when the admin hands over the equipment.',
                child: Wrap(spacing: 8, runSpacing: 8, children: [
                  for (final minutes in _durationChoices)
                    ChoiceChip(
                        label: Text(_durationLabel(minutes)),
                        selected: minutes == _selectedDurationMinutes,
                        onSelected: _isSubmitting
                            ? null
                            : (_) {
                                setState(() {
                                  _selectedDurationMinutes = minutes;
                                  _requestKey = MobileApiService.operationKey();
                                });
                                _loadQuote();
                              }),
                ]),
              ),
              RentalSection(
                title: 'Where will you receive it?',
                icon: Icons.place_outlined,
                subtitle:
                    'Choose where you want to receive the equipment. The operator will bring it there, or meet you at the shop.',
                child: Column(children: [
                  DropdownButtonFormField<String>(
                    initialValue: _deliveryLocation,
                    isExpanded: true,
                    decoration:
                        const InputDecoration(labelText: 'Pickup / resort'),
                    items: privateResorts
                        .map((place) => DropdownMenuItem(
                            value: place,
                            child:
                                Text(place, overflow: TextOverflow.ellipsis)))
                        .toList(),
                    onChanged: _isSubmitting
                        ? null
                        : (place) {
                            if (place != null)
                              setState(() => _deliveryLocation = place);
                          },
                  ),
                  if (_deliveryLocation == 'Other / Custom Resort') ...[
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: _customResortController,
                      enabled: !_isSubmitting,
                      maxLength: 180,
                      textInputAction: TextInputAction.done,
                      decoration: const InputDecoration(
                          labelText: 'Resort name / location',
                          hintText: 'Enter the handoff location'),
                      validator: (value) =>
                          value == null || value.trim().isEmpty
                              ? 'Enter your resort or pickup location.'
                              : null,
                    ),
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
                        const Text('Checking the current rental price…'),
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
                        RentalValueRow('Rental fee', rentalMoney(_baseFee)),
                        RentalValueRow('Refundable security deposit',
                            rentalMoney(_deposit)),
                        const Divider(height: 22),
                        RentalValueRow('Due at handoff', rentalMoney(_total),
                            emphasis: true),
                        const SizedBox(height: 10),
                        Text(
                            'Rental fee covers $_packageLength.${_billedMinutes > _selectedDurationMinutes ? ' This item has a minimum package duration.' : ''}',
                            style: TextStyle(
                                fontSize: 13,
                                color: scheme.onSurfaceVariant,
                                height: 1.4)),
                        const SizedBox(height: 6),
                        Text(
                            'The deposit is refundable after inspection, subject to any outstanding charges.',
                            style: TextStyle(
                                fontSize: 12,
                                color: scheme.onSurfaceVariant,
                                height: 1.4)),
                      ],
                    ]),
              ),
              RentalSection(
                title: 'Payment preference',
                icon: Icons.payments_outlined,
                subtitle: _paymentMethod == 'QR'
                    ? 'Pay the full total to the owner’s InstaPay account, then upload the successful transfer screenshot.'
                    : 'Pay the rental fee and refundable deposit in cash when the equipment is handed over.',
                child: RadioGroup<String>(
                  groupValue: _paymentMethod,
                  onChanged: (value) {
                    if (value != null && !_isSubmitting) {
                      setState(() {
                        _paymentMethod = value;
                        _paymentConfirmed = false;
                        _paymentProofImage = null;
                        _paymentProofName = null;
                      });
                    }
                  },
                  child: Column(children: [
                    RadioListTile<String>(
                        value: 'CASH',
                        title: const Text('Cash'),
                        subtitle: const Text(
                            'Pay the operator at handoff.'),
                        contentPadding: EdgeInsets.zero),
                    if (_paymentInstructions?['instapay_qr_data_url'] is String)
                      const RadioListTile<String>(
                          value: 'QR',
                          title: Text('InstaPay QR'),
                          subtitle: Text('Pay now and upload your receipt.'),
                          contentPadding: EdgeInsets.zero)
                    else
                      const ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(Icons.info_outline),
                          title: Text('InstaPay QR not configured'),
                          subtitle: Text(
                              'The owner can add the QR in workspace settings. Choose cash for now.')),
                  ]),
                ),
              ),
              if (_paymentMethod == 'QR') ...[
                RentalSection(
                    title: 'Pay by InstaPay',
                    icon: Icons.qr_code_2,
                    subtitle:
                        'Send the exact total shown below. The owner will check your screenshot before approving the rental request.',
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
                                    constraints:
                                        const BoxConstraints(maxWidth: 240),
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
                          if ((_paymentInstructions?['account_name'] ?? '')
                              .toString()
                              .isNotEmpty)
                            Text('Account name: ${_paymentInstructions!['account_name']}'),
                          if ((_paymentInstructions?['account_number'] ?? '')
                              .toString()
                              .isNotEmpty)
                            Text('Account number: ${_paymentInstructions!['account_number']}'),
                          const SizedBox(height: 8),
                          RentalValueRow('Exact transfer total',
                              rentalMoney(_total),
                              emphasis: true),
                          if ((_paymentInstructions?['instructions'] ?? '')
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
                              onPressed:
                                  _isSubmitting ? null : _choosePaymentProof,
                              icon: const Icon(Icons.upload_file),
                              label: Text(_paymentProofName == null
                                  ? 'Upload payment screenshot'
                                  : 'Change screenshot')),
                          if (_paymentProofImage != null) ...[
                            const SizedBox(height: 8),
                            Center(
                                child: Image.memory(
                                    base64Decode(
                                        _paymentProofImage!.split(',').last),
                                    height: 170,
                                    fit: BoxFit.contain)),
                            Text('Selected: $_paymentProofName',
                                textAlign: TextAlign.center),
                          ],
                          CheckboxListTile(
                              contentPadding: EdgeInsets.zero,
                              value: _paymentConfirmed,
                              onChanged: _isSubmitting
                                  ? null
                                  : (value) => setState(() =>
                                      _paymentConfirmed = value ?? false),
                              title: const Text(
                                  'I completed this InstaPay transfer')),
                        ])),
              ],
              const RentalNotice(
                  title: 'Bring a valid ID',
                  icon: Icons.badge_outlined,
                  message:
                      'After approval, show your rental QR and one physical valid ID to the operator at your selected location. The rental timer starts when you receive the item.'),
              const SizedBox(height: 16),
            ]),
          ),
        ),
      ),
    );
  }
}
