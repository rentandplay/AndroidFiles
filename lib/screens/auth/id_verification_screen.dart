import 'package:flutter/material.dart';
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
  bool _acceptedTerms = false;
  bool _isSubmitting = false;

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

      // Staff verify the actual physical ID at handoff.
      await authService.acknowledgeIdRequirement(user.uid);
      await authService.updateTermsAcceptance(user.uid, true,
          termsVersion: rentalTermsVersion);

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Terms accepted successfully! Welcome to Rent & Play.'),
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
                'Review our rental policies and physical ID requirement to proceed with equipment rentals.',
                style: TextStyle(
                    color: scheme.onSurfaceVariant, fontSize: 13, height: 1.4),
              ),
              const SizedBox(height: 20),

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
                  onPressed:
                      (_acceptedTerms && !_isSubmitting) ? _handleSubmit : null,
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
    );
  }
}
