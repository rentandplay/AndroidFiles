import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class RentPlayWordmark extends StatelessWidget {
  const RentPlayWordmark({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Semantics(
      label: 'Rent & Play',
      excludeSemantics: true,
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: 'rent',
              style:
                  TextStyle(color: isDark ? Colors.white : AppTheme.brandNavy),
            ),
            const TextSpan(
              text: '&',
              style: TextStyle(color: AppTheme.brandOrangeLight),
            ),
            TextSpan(
              text: 'play',
              style:
                  TextStyle(color: isDark ? Colors.white : AppTheme.brandNavy),
            ),
          ],
        ),
        style: const TextStyle(
          fontSize: 24,
          fontWeight: FontWeight.w900,
          letterSpacing: -1.2,
          height: 1,
        ),
      ),
    );
  }
}
