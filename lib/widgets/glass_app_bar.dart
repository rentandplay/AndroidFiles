import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../screens/alerts/notifications_screen.dart';
import '../services/notification_service.dart';
import 'liquid_glass_optics.dart';

/// A sleek, circular frosted glass action container for header icons (bell, settings, refresh, back).
class HeaderActionPod extends StatelessWidget {
  final Widget? child;
  final IconData? icon;
  final VoidCallback? onTap;
  final String? tooltip;
  final Color? iconColor;
  final double size;
  final EdgeInsetsGeometry? margin;
  final Color? podBg;
  final Color? podBorder;

  const HeaderActionPod({
    super.key,
    this.child,
    this.icon,
    this.onTap,
    this.tooltip,
    this.iconColor,
    this.size = 38,
    this.margin,
    this.podBg,
    this.podBorder,
  }) : assert(child != null || icon != null, 'Must provide child or icon');

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryText = iconColor ??
        (isDark ? const Color(0xFFF8FAFC) : const Color(0xFF0F172A));
    final effectivePodBg = podBg ??
        (isDark
            ? const Color(0xFF1E293B).withValues(alpha: 0.60)
            : Colors.white.withValues(alpha: 0.92));
    final effectivePodBorder = podBorder ??
        (isDark
            ? Colors.white.withValues(alpha: 0.18)
            : const Color(0xFFE6DFD5).withValues(alpha: 0.60));

    Widget podContent = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: effectivePodBg,
        shape: BoxShape.circle,
        border: Border.all(color: effectivePodBorder, width: 1.1),
        boxShadow: [
          BoxShadow(
            color: isDark
                ? Colors.black.withValues(alpha: 0.30)
                : const Color(0xFF0F172A).withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
            blurStyle: BlurStyle.outer,
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

    if (LiquidGlassScope.of(context)) {
      podContent = LiquidGlassOptics(
        borderRadius: size / 2,
        blurSigma: 2,
        child: podContent,
      );
    }

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
  final Color? podBg;
  final Color? podBorder;
  final Color? iconColor;

  const RentalNotificationBellPod({
    super.key,
    this.podBg,
    this.podBorder,
    this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryText = iconColor ??
        (isDark ? const Color(0xFFF8FAFC) : const Color(0xFF0F172A));
    final count = context.watch<RentalNotificationService?>()?.unreadCount ?? 0;

    return HeaderActionPod(
      podBg: podBg,
      podBorder: podBorder,
      iconColor: primaryText,
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
      height + (bottom?.preferredSize.height ?? (loading ? 3.5 : 1.0)));

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textPrimary =
        isDark ? const Color(0xFFF8FAFC) : const Color(0xFF0F172A);

    final frostedGlassFill = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: isDark
          ? [
              const Color(0xFF151E2E).withValues(alpha: 0.58),
              const Color(0xFF0F1623).withValues(alpha: 0.44),
            ]
          : [
              Colors.white.withValues(alpha: 0.60),
              const Color(0xFFFAF6F0).withValues(alpha: 0.44),
            ],
    );

    final bottomRefractionBorder = LinearGradient(
      colors: [
        isDark
            ? Colors.white.withValues(alpha: 0.14)
            : const Color(0xFFE8E0D5).withValues(alpha: 0.85),
        const Color(0xFFDF762D).withValues(alpha: isDark ? 0.22 : 0.18),
        isDark
            ? Colors.white.withValues(alpha: 0.10)
            : const Color(0xFFE8E0D5).withValues(alpha: 0.85),
      ],
    );

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
          preferredSize: Size.fromHeight(loading ? 3.5 : 1.0),
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
                height: 1.0,
                decoration: BoxDecoration(
                  gradient: bottomRefractionBorder,
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
          filter: ImageFilter.blur(
            sigmaX: 5.0,
            sigmaY: 5.0,
            tileMode: TileMode.mirror,
          ),
          child: Container(
            decoration: BoxDecoration(
              gradient: frostedGlassFill,
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
