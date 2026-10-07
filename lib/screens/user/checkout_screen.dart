import 'package:flutter/material.dart';
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
  int _selectedHours = 1;
  String _deliveryLocation = 'ASRI Hotspring Resort';
  final _customResortController = TextEditingController();
  String _paymentMethod = 'QR';
  bool _isSubmitting = false, _quoteLoading = true;
  Map<String, dynamic>? _quote;
  String _quoteError = '';
  int _quoteVersion = 0;
  String _requestKey = MobileApiService.operationKey();
  MobileApiService get _api => widget.api ?? MobileApiService.instance;

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
  }

  Future<void> _loadQuote() async {
    final version = ++_quoteVersion;
    setState(() {
      _quoteLoading = true;
      _quoteError = '';
      _quote = null;
    });
    try {
      final quote = await _api.quoteRental(widget.item.id, _selectedHours * 60);
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
    super.dispose();
  }

  num? get _baseFee => _quote?['rental_fee'] as num?;
  num? get _deposit => _quote?['deposit_amount'] as num?;
  num? get _total =>
      _baseFee == null || _deposit == null ? null : _baseFee! + _deposit!;
  int get _billedMinutes =>
      (_quote?['billed_minutes'] as num?)?.toInt() ?? _selectedHours * 60;
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
            'Please sign in again to book equipment.');
      await _api.createRentalRequest(
        itemId: widget.item.id,
        itemName: widget.item.name,
        itemCode: widget.item.qrCode,
        durationMinutes: _selectedHours * 60,
        deliveryLocation: _deliveryLocation == 'Other / Custom Resort'
            ? _customResortController.text.trim()
            : _deliveryLocation,
        paymentMethod: _paymentMethod,
        requestKey: _requestKey,
        expectedQuote: {
          'rentalFee': _baseFee,
          'depositAmount': _deposit,
          'billedMinutes': _quote!['billed_minutes']
        },
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Booking sent. Track approval in My Rentals.')));
      Navigator.pushReplacement(context,
          MaterialPageRoute(builder: (_) => const ActiveRentalsScreen()));
    } catch (error) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Could not send your booking. $error')));
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
        appBar: AppBar(title: const Text('Review booking')),
        bottomNavigationBar: RentalActionBar(
          summaryLabel: 'Due at handoff',
          summaryValue: _quoteLoading ? 'Updating…' : rentalMoney(_total),
          label: 'Send booking request',
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
                  for (final hours in [1, 2, 3, 5, 8])
                    ChoiceChip(
                        label: Text('$hours hr${hours == 1 ? '' : 's'}'),
                        selected: hours == _selectedHours,
                        onSelected: _isSubmitting
                            ? null
                            : (_) {
                                setState(() {
                                  _selectedHours = hours;
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
                    'Choose pickup or your resort. The admin will confirm the handoff arrangements.',
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
                            'Rental fee covers $_packageLength.${_billedMinutes > _selectedHours * 60 ? ' This item has a minimum package duration.' : ''}',
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
                subtitle:
                    'Pay at handoff. Choosing a method does not mark this booking as paid.',
                child: RadioGroup<String>(
                  groupValue: _paymentMethod,
                  onChanged: (value) {
                    if (value != null && !_isSubmitting)
                      setState(() => _paymentMethod = value);
                  },
                  child: Column(children: [
                    RadioListTile<String>(
                        value: 'QR',
                        title: const Text('QR payment'),
                        subtitle: const Text(
                            'Ask the admin for payment instructions.'),
                        contentPadding: EdgeInsets.zero),
                    RadioListTile<String>(
                        value: 'Cash',
                        title: const Text('Cash'),
                        subtitle: const Text(
                            'Pay the admin when receiving the item.'),
                        contentPadding: EdgeInsets.zero),
                  ]),
                ),
              ),
              const RentalNotice(
                  title: 'Bring a valid ID',
                  icon: Icons.badge_outlined,
                  message:
                      'After approval, show your booking QR and one physical valid ID to the admin. Check the equipment together before handoff.'),
              const SizedBox(height: 16),
            ]),
          ),
        ),
      ),
    );
  }
}
