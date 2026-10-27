import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../screens/alerts/notifications_screen.dart';
import '../services/notification_service.dart';

/// A sleek, circular frosted glass action container for header icons (bell, settings, refresh, back).
class HeaderActionPod extends StatelessWidget {
  final Widget? child;
  final IconData? icon;
  final VoidCallback? onTap;
  final String? tooltip;
  final Color? iconColor;
  final double size;
  final EdgeInsetsGeometry? margin;

  const HeaderActionPod({
    super.key,
    this.child,
    this.icon,
    this.onTap,
    this.tooltip,
    this.iconColor,
    this.size = 38,
    this.margin,
  }) : assert(child != null || icon != null, 'Must provide child or icon');

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryText =
        isDark ? const Color(0xFFF8FAFC) : const Color(0xFF0F172A);
    final podBg = isDark
        ? const Color(0xFF1E2838).withValues(alpha: 0.65)
        : Colors.white.withValues(alpha: 0.68);
    final podBorder = isDark
        ? Colors.white.withValues(alpha: 0.22)
        : Colors.white.withValues(alpha: 0.95);

    Widget podContent = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: podBg,
        shape: BoxShape.circle,
        border: Border.all(color: podBorder, width: 1.2),
        boxShadow: [
          BoxShadow(
            color: isDark
                ? Colors.black.withValues(alpha: 0.35)
                : const Color(0xFF0F172A).withValues(alpha: 0.08),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
          BoxShadow(
            color: const Color(0xFFDF762D)
                .withValues(alpha: isDark ? 0.08 : 0.05),
            blurRadius: 6,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Center(
        child: child ??
            Icon(
              icon,
              size: 19,
              color: iconColor ?? primaryText,
            ),
      ),
    );

    if (onTap != null) {
      podContent = Material(
        color: Colors.transparent,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: podContent,
        ),
      );
    }

    if (tooltip != null) {
      podContent = Tooltip(
        message: tooltip!,
        child: podContent,
      );
    }

    return Padding(
      padding: margin ?? const EdgeInsets.symmetric(horizontal: 4),
      child: Center(child: podContent),
    );
  }
}

/// A notification bell enclosed in a frosted glass action pod with real-time unread badge.
class RentalNotificationBellPod extends StatelessWidget {
  const RentalNotificationBellPod({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryText =
        isDark ? const Color(0xFFF8FAFC) : const Color(0xFF0F172A);
    final count =
        context.watch<RentalNotificationService?>()?.unreadCount ?? 0;

    return HeaderActionPod(
      tooltip: count > 0 ? '$count unread notifications' : 'Notifications',
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const NotificationsScreen()),
      ),
      child: Badge(
        isLabelVisible: count > 0,
        label: Text(
          count > 99 ? '99+' : '$count',
          style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold),
        ),
        backgroundColor: const Color(0xFFDF762D),
        child: Icon(
          Icons.notifications_outlined,
          size: 20,
          color: primaryText,
        ),
      ),
    );
  }
}

/// A unified, genuine frosted-glass AppBar used across all screens.
/// Features optical background blur, translucent liquid glass gradient,
/// specular reflection highlights, correct status-bar contrast, and clean modern typography.
class GlassAppBar extends StatelessWidget implements PreferredSizeWidget {
  final Widget? title;
  final String? titleText;
  final List<Widget>? actions;
  final Widget? leading;
  final bool automaticallyImplyLeading;
  final bool centerTitle;
  final double height;
  final PreferredSizeWidget? bottom;
  final bool loading;
  final SystemUiOverlayStyle? systemOverlayStyle;

  const GlassAppBar({
    super.key,
    this.title,
    this.titleText,
    this.actions,
    this.leading,
    this.automaticallyImplyLeading = true,
    this.centerTitle = false,
    this.height = kToolbarHeight,
    this.bottom,
    this.loading = false,
    this.systemOverlayStyle,
  });

  @override
  Size get preferredSize => Size.fromHeight(
      height + (bottom?.preferredSize.height ?? (loading ? 3.5 : 1.5)));

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textPrimary =
        isDark ? const Color(0xFFF8FAFC) : const Color(0xFF0F172A);

    // Highly translucent liquid-glass gradient matching LiquidGlassBottomNavBar
    final frostedGlassFill = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: isDark
          ? [
              const Color(0xFF162030).withValues(alpha: 0.52),
              const Color(0xFF0D1420).withValues(alpha: 0.30),
            ]
          : [
              Colors.white.withValues(alpha: 0.42),
              const Color(0xFFFFFDFC).withValues(alpha: 0.22),
            ],
    );

    // Specular refraction top reflection sheen
    final topSpecularSheen = LinearGradient(
      colors: [
        Colors.white.withValues(alpha: isDark ? 0.22 : 0.90),
        (isDark ? const Color(0xFFDF762D) : const Color(0xFFFFB273))
            .withValues(alpha: isDark ? 0.25 : 0.38),
        Colors.white.withValues(alpha: isDark ? 0.10 : 0.65),
      ],
    );

    // Prismatic bottom refraction border with warm brand amber reflection
    final bottomRefractionBorder = LinearGradient(
      colors: [
        Colors.white.withValues(alpha: isDark ? 0.25 : 0.95),
        const Color(0xFFF3ECE4).withValues(alpha: isDark ? 0.15 : 0.60),
        const Color(0xFFDF762D).withValues(alpha: isDark ? 0.30 : 0.30),
        Colors.white.withValues(alpha: isDark ? 0.12 : 0.75),
      ],
    );

    // Explicit system status-bar brightness ensures dark icons in Light mode and white in Dark mode
    final effectiveOverlayStyle = systemOverlayStyle ??
        SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
          statusBarBrightness: isDark ? Brightness.dark : Brightness.light,
          systemNavigationBarColor: Colors.transparent,
          systemNavigationBarIconBrightness:
              isDark ? Brightness.light : Brightness.dark,
        );

    Widget? effectiveTitle = title;
    if (effectiveTitle == null && titleText != null) {
      effectiveTitle = Text(
        titleText!,
        style: TextStyle(
          color: textPrimary,
          fontSize: 20,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.5,
        ),
      );
    }

    final effectiveBottom = bottom ??
        PreferredSize(
          preferredSize: Size.fromHeight(loading ? 3.5 : 1.5),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (loading)
                const LinearProgressIndicator(
                  minHeight: 2.5,
                  backgroundColor: Colors.transparent,
                  valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFDF762D)),
                ),
              Container(
                height: 1.2,
                decoration: BoxDecoration(
                  gradient: bottomRefractionBorder,
                  boxShadow: [
                    BoxShadow(
                      color: isDark
                          ? Colors.black.withValues(alpha: 0.40)
                          : const Color(0xFF0F172A).withValues(alpha: 0.06),
                      blurRadius: 10,
                      offset: const Offset(0, 2),
                    ),
                    BoxShadow(
                      color: const Color(0xFFDF762D)
                          .withValues(alpha: isDark ? 0.10 : 0.05),
                      blurRadius: 6,
                      offset: const Offset(0, 1),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );

    return AppBar(
      systemOverlayStyle: effectiveOverlayStyle,
      titleSpacing: 16,
      automaticallyImplyLeading: automaticallyImplyLeading,
      leading: leading,
      centerTitle: centerTitle,
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      flexibleSpace: ClipRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 22.0, sigmaY: 22.0),
          child: Container(
            decoration: BoxDecoration(
              gradient: frostedGlassFill,
            ),
            child: Stack(
              fit: StackFit.expand,
              children: [
                // Top subtle specular reflection sheen
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  height: 1.5,
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: topSpecularSheen,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      title: effectiveTitle,
      actions: actions != null
          ? [
              ...actions!,
              const SizedBox(width: 8),
            ]
          : null,
      bottom: effectiveBottom,
    );
  }
}
