import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../services/auth_service.dart';
import '../../models/user_model.dart';
import '../../widgets/glass_app_bar.dart';
import '../../widgets/liquid_glass.dart';
import '../../widgets/rental_ui.dart';
import '../shared/terms_dialog.dart';
import '../user/customer_home_screen.dart';

class IdVerificationScreen extends StatefulWidget {
  final UserModel? userModel;

  const IdVerificationScreen({
    super.key,
    this.userModel,
  });

  @override
  State<IdVerificationScreen> createState() => _IdVerificationScreenState();
}

class _IdVerificationScreenState extends State<IdVerificationScreen> {
  final _formKey = GlobalKey<FormState>();
  final _phoneController = TextEditingController();
  bool _acceptedTerms = false;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _acceptedTerms = widget.userModel?.hasAcceptedTerms ?? false;
    final initialPhone = widget.userModel?.phone ?? '';
    if (initialPhone.isNotEmpty) {
      _phoneController.text = initialPhone;
    }
  }

  @override
  void dispose() {
    _phoneController.dispose();
    super.dispose();
  }

  String? _validatePhone(String? value) {
    final phone = (value ?? '').trim();
    if (phone.isEmpty) return 'Enter your contact number.';
    final clean = phone.replaceAll(RegExp(r'[\s().-]'), '');
    if (!RegExp(r'^(?:\+?63|0)?9\d{9}$').hasMatch(clean)) {
      return 'Enter a valid Philippine number (e.g. 0912 345 6789).';
    }
    return null;
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

  void _showTermsDialog() {
    TermsDialog.show(
      context,
      onAccept: () {
        setState(() {
          _acceptedTerms = true;
        });
      },
    );
  }

  Future<void> _handleSubmit() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    if (!_acceptedTerms) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please accept the Terms & Conditions.')),
      );
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      final authService = Provider.of<AuthService>(context, listen: false);
      final user = authService.currentUser;

      if (user == null) {
        throw Exception('User is not authenticated.');
      }

      final normalizedPhone = _normalizedPhone(_phoneController.text);
      final currentName = widget.userModel?.name.isNotEmpty == true
          ? widget.userModel!.name
          : (user.displayName?.trim().isNotEmpty == true
              ? user.displayName!.trim()
              : 'Customer');

      // Save the customer's phone number to their profile
      await authService.updateCustomerProfile(
        name: currentName,
        phone: normalizedPhone,
      );

      // Staff verify the actual physical ID at handoff.
      await authService.acknowledgeIdRequirement(user.uid);
      await authService.updateTermsAcceptance(user.uid, true,
          termsVersion: rentalTermsVersion);

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Profile setup complete! Welcome to Rent & Play.'),
          backgroundColor: Colors.green,
        ),
      );

      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const CustomerHomeScreen()),
        (route) => false,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Setup failed: ${e.toString()}'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: const GlassAppBar(
        titleText: 'Rental Requirements & Terms',
        centerTitle: true,
      ),
      body: LiquidAmbientBackdrop(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20.0),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Header
                Text(
                  'Identity & Rental Policy',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: scheme.primary,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Complete your contact details and review our rental policies to proceed with equipment rentals.',
                  style: TextStyle(
                      color: scheme.onSurfaceVariant, fontSize: 13, height: 1.4),
                ),
                const SizedBox(height: 20),

                // Contact Phone Number Card
                GlassCard(
                  borderRadius: 18,
                  padding: const EdgeInsets.all(18.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: const Color(0xFFDF762D).withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(Icons.phone_android,
                                color: Color(0xFFDF762D), size: 20),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Contact Number',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'Required for delivery coordination and order updates.',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: scheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _phoneController,
                        enabled: !_isSubmitting,
                        keyboardType: TextInputType.phone,
                        textInputAction: TextInputAction.done,
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(
                            RegExp(r'[+0-9() .-]'),
                          ),
                          LengthLimitingTextInputFormatter(20),
                        ],
                        decoration: InputDecoration(
                          labelText: 'Mobile Number *',
                          hintText: '0912 345 6789',
                          prefixIcon: const Icon(Icons.phone_outlined),
                          filled: true,
                          fillColor:
                              scheme.surfaceContainerHighest.withValues(alpha: 0.35),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(color: scheme.outlineVariant),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(
                                color:
                                    scheme.outlineVariant.withValues(alpha: 0.6)),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(
                                color: Color(0xFFDF762D), width: 1.5),
                          ),
                        ),
                        validator: _validatePhone,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // Physical Valid ID Notice Banner
                const RentalNotice(
                  icon: Icons.badge_outlined,
                  title: 'Physical Valid ID Required',
                  message:
                      'Show one physical Government or Student ID to the operator when the item is handed over at your selected location.',
                ),

                const SizedBox(height: 20),

                // Terms & Conditions Card
                GlassCard(
                  borderRadius: 18,
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Checkbox(
                            value: _acceptedTerms,
                            activeColor: const Color(0xFFDF762D),
                            onChanged: (val) {
                              setState(() {
                                _acceptedTerms = val ?? false;
                              });
                            },
                          ),
                          Expanded(
                            child: Wrap(
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                const Text('I have read and accept the ',
                                    style: TextStyle(fontSize: 13)),
                                GestureDetector(
                                  onTap: _showTermsDialog,
                                  child: Text(
                                    'Terms & Conditions',
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.bold,
                                      color: scheme.primary,
                                      decoration: TextDecoration.underline,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 28),

                // Submit Button
                SizedBox(
                  height: 52,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFDF762D),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      elevation: 0,
                    ),
                    onPressed: (_acceptedTerms && !_isSubmitting)
                        ? _handleSubmit
                        : null,
                    child: _isSubmitting
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white),
                          )
                        : const Text(
                            'Continue to Catalog',
                            style: TextStyle(
                                fontSize: 16, fontWeight: FontWeight.w800),
                          ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
