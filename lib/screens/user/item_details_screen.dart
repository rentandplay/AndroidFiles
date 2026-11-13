import '../../widgets/glass_app_bar.dart';
import '../../widgets/liquid_glass.dart';
import '../../widgets/premium_animations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
      showFrostedModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        builder: (sheetContext) => Padding(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 24),
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
      );

  Future<void> _showImageLightbox(BuildContext context) {
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
                          Text(
                            item.name,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 17,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          Text(
                            '${item.category} · Pinch or double-tap to zoom',
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Close image preview',
                      onPressed: () => Navigator.pop(dialogContext),
                      icon: const Icon(Icons.close_rounded,
                          color: Colors.white, size: 26),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: InteractiveViewer(
                  key: const ValueKey('item-details-interactive-viewer'),
                  minScale: 1.0,
                  maxScale: 4.0,
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: item.buildImage(
                        fit: BoxFit.contain,
                        height: 360,
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

  Future<void> _shareEquipmentDetails(BuildContext context) async {
    HapticFeedback.selectionClick();
    final rate = item.rateText.trim().isEmpty
        ? 'Contact store for rates'
        : item.rateText.trim();
    final summary =
        'Rent & Play · ${item.name} (${item.category})\nRate: $rate\nStatus: $_availabilityLabel';
    await Clipboard.setData(ClipboardData(text: summary));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Equipment details copied to clipboard to share.'),
      ),
    );
  }

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
        !userModel.hasAcknowledgedIdRequirement ||
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

  static Color _categoryAccent(String category) => switch (category) {
        'Board Games' => const Color(0xFF27876B),
        'Cards' => const Color(0xFF8062B5),
        'Tech Rentals' => const Color(0xFF4678B3),
        _ => const Color(0xFFDF762D),
      };

  static (IconData, String) _experienceVibe(String category) =>
      switch (category) {
        'Board Games' => (Icons.groups_rounded, 'Group & Barkada'),
        'Cards' => (Icons.style_rounded, 'Tabletop Party'),
        'Tech Rentals' => (Icons.sports_esports_rounded, 'Plug & Play'),
        _ => (Icons.emoji_events_rounded, 'Outdoor Ready'),
      };

  Widget _highlightChip(
    BuildContext context, {
    required IconData icon,
    required String label,
    required Color accent,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: isDark ? 0.16 : 0.09),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: accent.withValues(alpha: isDark ? 0.34 : 0.24),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: accent),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              color: isDark ? Colors.white : const Color(0xFF1E293B),
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  String get _availabilityLabel => switch (item.status.toUpperCase()) {
        'AVAILABLE' => item.totalQuantity > 1
            ? '${item.availableQuantity} of ${item.totalQuantity} available'
            : 'Available now',
        'RESERVED_PENDING' => 'Temporarily on hold',
        'RENTED' => 'Currently rented',
        'UNDER_MAINTENANCE' => 'All units are under maintenance',
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

    final topPadding = MediaQuery.of(context).padding.top + kToolbarHeight;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final categoryAccent = _categoryAccent(item.category);
    final vibe = _experienceVibe(item.category);

    return Scaffold(
      extendBodyBehindAppBar: true,
      extendBody: true,
      appBar: GlassAppBar(
        leading: HeaderActionPod(
          icon: Icons.arrow_back_rounded,
          tooltip: 'Back',
          onTap: () => Navigator.pop(context),
        ),
        titleText: 'Equipment details',
        actions: [
          HeaderActionPod(
            icon: Icons.ios_share_rounded,
            tooltip: 'Share equipment details',
            onTap: () => _shareEquipmentDetails(context),
          ),
          HeaderActionPod(
            icon: Icons.help_outline_rounded,
            tooltip: 'How renting works',
            onTap: () => _showRentalGuide(context),
          ),
        ],
      ),
      bottomNavigationBar: RentalActionBar(
        label: isAvailable
            ? 'Rent now or schedule'
            : 'Check scheduled availability',
        onPressed: () => _continueToRental(context),
      ),
      body: LiquidAmbientBackdrop(
        child: SingleChildScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: EdgeInsets.fromLTRB(16, topPadding + 14, 16, 100),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 680),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  StaggeredSlideFade(
                    index: 0,
                    child: RentalSection(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        GestureDetector(
                          key: const ValueKey('item-details-image-zoom-tap'),
                          onTap: () => _showImageLightbox(context),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(16),
                            child: Stack(
                              children: [
                                Container(
                                  height: 236,
                                  width: double.infinity,
                                  padding: const EdgeInsets.all(18),
                                  decoration: BoxDecoration(
                                    gradient: RadialGradient(
                                      center: Alignment.center,
                                      radius: 0.88,
                                      colors: isDark
                                          ? [
                                              categoryAccent.withValues(
                                                  alpha: 0.28),
                                              const Color(0xFF151F2E),
                                            ]
                                          : [
                                              categoryAccent.withValues(
                                                  alpha: 0.16),
                                              const Color(0xFFF6EFE6),
                                            ],
                                    ),
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(
                                      color: isDark
                                          ? Colors.white.withValues(alpha: 0.10)
                                          : const Color(0xFFE8E0D5),
                                    ),
                                  ),
                                  child: Hero(
                                    tag: 'item-image-${item.id}',
                                    child: item.buildImage(
                                      fit: BoxFit.contain,
                                      height: 196,
                                    ),
                                  ),
                                ),
                                if (item.isPopular)
                                  Positioned(
                                    left: 10,
                                    top: 10,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 9, vertical: 4.5),
                                      decoration: BoxDecoration(
                                        gradient: const LinearGradient(
                                          colors: [
                                            Color(0xFFFF8A3D),
                                            Color(0xFFDF762D),
                                          ],
                                        ),
                                        borderRadius: BorderRadius.circular(16),
                                        boxShadow: [
                                          BoxShadow(
                                            color: const Color(0xFFDF762D)
                                                .withValues(alpha: 0.35),
                                            blurRadius: 8,
                                            offset: const Offset(0, 2),
                                          ),
                                        ],
                                      ),
                                      child: const Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            Icons.local_fire_department_rounded,
                                            size: 13,
                                            color: Colors.white,
                                          ),
                                          SizedBox(width: 4),
                                          Text(
                                            'POPULAR CHOICE',
                                            style: TextStyle(
                                              color: Colors.white,
                                              fontSize: 10,
                                              fontWeight: FontWeight.w800,
                                              letterSpacing: 0.5,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                Positioned(
                                  right: 10,
                                  bottom: 10,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 10, vertical: 5),
                                    decoration: BoxDecoration(
                                      color:
                                          Colors.black.withValues(alpha: 0.48),
                                      borderRadius: BorderRadius.circular(20),
                                      border: Border.all(
                                        color: Colors.white
                                            .withValues(alpha: 0.22),
                                      ),
                                    ),
                                    child: const Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(Icons.zoom_in_rounded,
                                            size: 14, color: Colors.white),
                                        SizedBox(width: 4),
                                        Text(
                                          'Tap to zoom',
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontSize: 11,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      const SizedBox(height: 18),
                      Text(
                        item.category,
                        style: TextStyle(
                          color: categoryAccent,
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.2,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        item.name,
                        style: Theme.of(context)
                            .textTheme
                            .headlineSmall
                            ?.copyWith(
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.4,
                            ),
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
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
                          _highlightChip(
                            context,
                            icon: vibe.$1,
                            label: vibe.$2,
                            accent: categoryAccent,
                          ),
                          _highlightChip(
                            context,
                            icon: Icons.qr_code_scanner_rounded,
                            label: 'QR Handoff',
                            accent: const Color(0xFFDF762D),
                          ),
                        ],
                      ),
                      if (item.totalQuantity > 1) ...[
                        const SizedBox(height: 8),
                        Text(
                          '${item.availableQuantity} of ${item.totalQuantity} units can be rented now',
                          style: TextStyle(
                            color: scheme.onSurfaceVariant,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              if (!isAvailable) ...[
                StaggeredSlideFade(
                  index: 1,
                  child: RentalNotice(
                    title: _availabilityLabel,
                    message:
                        'You can still browse this item, but a rental request is not available right now.',
                    icon: Icons.inventory_2_outlined,
                  ),
                ),
                const SizedBox(height: 16),
              ],
              if (item.description.trim().isNotEmpty)
                StaggeredSlideFade(
                  index: 2,
                  child: RentalSection(
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
                ),
              StaggeredSlideFade(
                index: 3,
                child: RentalSection(
                  title: 'Rental price and terms',
                  icon: Icons.receipt_long_outlined,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      RentalValueRow('Rental rate', rate),
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
                      if (item.isForSale && item.salePrice != null) ...[
                        const SizedBox(height: 10),
                        Text(
                          'For purchases, ask the operator.',
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
              ),
                ],
              ),
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
