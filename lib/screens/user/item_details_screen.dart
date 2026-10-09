import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/item_model.dart';
import '../../models/user_model.dart';
import '../../services/auth_service.dart';
import '../../widgets/rental_ui.dart';
import '../../widgets/sign_in_prompt.dart';
import '../auth/id_verification_screen.dart';
import 'checkout_screen.dart';

class ItemDetailsScreen extends StatelessWidget {
  const ItemDetailsScreen({super.key, required this.item});

  final ItemModel item;

  Future<void> _showRentalGuide(BuildContext context) =>
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (sheetContext) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Icon(Icons.route_outlined,
                          color: Theme.of(sheetContext).colorScheme.primary),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text('How renting works',
                            style: Theme.of(sheetContext)
                                .textTheme
                                .titleLarge
                                ?.copyWith(fontWeight: FontWeight.w700)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Your rental time starts at handoff.',
                    style: TextStyle(
                        color: Theme.of(sheetContext)
                            .colorScheme
                            .onSurfaceVariant),
                  ),
                  const SizedBox(height: 14),
                  const _RentalStep(
                    number: '1',
                    title: 'Choose your rental options',
                    message:
                        'Select the duration, location, and payment method.',
                  ),
                  const _RentalStep(
                    number: '2',
                    title: 'Send your request',
                    message:
                        'Staff reviews it. If you choose QR payment, they also check your receipt.',
                  ),
                  const _RentalStep(
                    number: '3',
                    title: 'Show your QR and valid ID',
                    message:
                        'The rental timer starts after the operator confirms the handoff.',
                  ),
                  const SizedBox(height: 12),
                  const RentalNotice(
                    title: 'Bring a physical valid ID',
                    message:
                        'The operator will check your ID when the equipment is handed over.',
                    icon: Icons.badge_outlined,
                  ),
                ],
              ),
            ),
          ),
        ),
      );

  Future<void> _continueToRental(BuildContext context) async {
    final authService = Provider.of<AuthService>(context, listen: false);
    if (authService.currentUser == null) {
      await showSignInPrompt(context);
      return;
    }

    UserModel? userModel;
    try {
      userModel = await authService.getCurrentUserModel();
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content:
              Text('Could not check your renter profile. Please try again.'),
        ));
      }
      return;
    }
    if (!context.mounted) return;

    if (userModel == null ||
        userModel.validIdUrl?.trim().isNotEmpty != true ||
        !userModel.hasAcceptedTerms) {
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => IdVerificationScreen(userModel: userModel),
        ),
      );
      return;
    }

    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => CheckoutScreen(item: item)),
    );
  }

  String get _availabilityLabel => switch (item.status.toUpperCase()) {
        'AVAILABLE' => 'Available now',
        'RESERVED_PENDING' => 'Temporarily on hold',
        'RENTED' => 'Currently rented',
        _ => 'Unavailable right now',
      };

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isAvailable = item.status.toLowerCase() == 'available';
    final statusColor = isAvailable
        ? Theme.of(context).brightness == Brightness.dark
            ? const Color(0xFF86EFAC)
            : const Color(0xFF166534)
        : scheme.onSurfaceVariant;
    final rate = item.rateText.trim().isEmpty
        ? 'See rental price in the next step'
        : item.rateText.trim();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Equipment details'),
        actions: [
          IconButton(
            tooltip: 'How renting works',
            onPressed: () => _showRentalGuide(context),
            icon: const Icon(Icons.help_outline_rounded),
          ),
        ],
      ),
      bottomNavigationBar: RentalActionBar(
        label: isAvailable ? 'Choose rental options' : 'Unavailable right now',
        onPressed: isAvailable ? () => _continueToRental(context) : null,
      ),
      body: SingleChildScrollView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 680),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                RentalSection(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(14),
                        child: Container(
                          height: 220,
                          width: double.infinity,
                          color: scheme.surfaceContainerHighest,
                          child: item.buildImage(
                            fit: BoxFit.contain,
                            height: 220,
                          ),
                        ),
                      ),
                      const SizedBox(height: 18),
                      Text(
                        item.category,
                        style: TextStyle(
                          color: scheme.onSurfaceVariant,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        item.name,
                        style: Theme.of(context)
                            .textTheme
                            .headlineSmall
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 11, vertical: 7),
                        decoration: BoxDecoration(
                          color: statusColor.withValues(alpha: .10),
                          border: Border.all(
                              color: statusColor.withValues(alpha: .25)),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              isAvailable
                                  ? Icons.check_circle_rounded
                                  : Icons.schedule_rounded,
                              size: 17,
                              color: statusColor,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              _availabilityLabel,
                              style: TextStyle(
                                color: statusColor,
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                if (!isAvailable) ...[
                  RentalNotice(
                    title: _availabilityLabel,
                    message:
                        'You can still browse this item, but a rental request is not available right now.',
                    icon: Icons.inventory_2_outlined,
                  ),
                  const SizedBox(height: 16),
                ],
                if (item.description.trim().isNotEmpty)
                  RentalSection(
                    title: 'About this equipment',
                    icon: Icons.info_outline_rounded,
                    child: Text(
                      item.description.trim(),
                      style: TextStyle(
                        color: scheme.onSurface,
                        height: 1.5,
                      ),
                    ),
                  ),
                RentalSection(
                  title: 'Rental price and terms',
                  icon: Icons.receipt_long_outlined,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      RentalValueRow('Rental rate', rate),
                      RentalValueRow('Refundable security deposit',
                          rentalMoney(item.deposit)),
                      RentalValueRow(
                        'Late return fee',
                        '${rentalMoney(item.latePenalty)} per hour overdue',
                      ),
                      if (item.category == 'Board Games' ||
                          item.category == 'Cards')
                        const RentalValueRow(
                            'Missing piece fee', '₱50 per lost piece'),
                      if (item.isForSale && item.salePrice != null)
                        RentalValueRow('Also available to buy',
                            rentalMoney(item.salePrice)),
                      const Divider(height: 24),
                      Text(
                        'The exact rental fee and deposit will be confirmed before you send your request.',
                        style: TextStyle(
                          color: scheme.onSurfaceVariant,
                          fontSize: 13,
                          height: 1.4,
                        ),
                      ),
                      if (item.isForSale && item.salePrice != null) ...[
                        const SizedBox(height: 10),
                        Text(
                          'This flow is for rentals. Ask the operator about buying this item.',
                          style: TextStyle(
                            color: scheme.onSurfaceVariant,
                            fontSize: 13,
                            height: 1.4,
                          ),
                        ),
                      ],
                    ],
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

class _RentalStep extends StatelessWidget {
  const _RentalStep({
    required this.number,
    required this.title,
    required this.message,
  });

  final String number;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              radius: 14,
              backgroundColor:
                  Theme.of(context).colorScheme.primary.withValues(alpha: .12),
              child: Text(
                number,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.primary,
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 3),
                  Text(
                    message,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontSize: 13,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
}
