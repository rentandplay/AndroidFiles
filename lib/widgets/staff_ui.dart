import 'liquid_glass.dart';
import 'package:flutter/material.dart';

/// The counter has its own quiet, high-contrast visual system. Customer screens
/// keep their existing theme; routes opened by staff inherit this one.
class StaffTheme {
  static const navy = Color(0xFF13243A);
  static const orange = Color(0xFFB94D12);

  static ThemeData from(ThemeData base) {
    final fontFamily = base.textTheme.bodyMedium?.fontFamily;
    final dark = base.brightness == Brightness.dark;
    final scheme = ColorScheme.fromSeed(
      seedColor: orange,
      brightness: base.brightness,
      primary: dark ? const Color(0xFFFFB787) : orange,
      surface: dark ? const Color(0xFF162235) : Colors.white,
      onSurface: dark ? const Color(0xFFF1F5FA) : navy,
      onSurfaceVariant:
          dark ? const Color(0xFFADBACB) : const Color(0xFF59697B),
      outline: dark ? const Color(0xFF41516A) : const Color(0xFFCBD4DF),
      outlineVariant: dark ? const Color(0xFF2D3D53) : const Color(0xFFE2E8F0),
    );
    final shape =
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(18));
    final button = ButtonStyle(
      minimumSize: const WidgetStatePropertyAll(Size(48, 48)),
      padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(horizontal: 16, vertical: 13)),
      shape: WidgetStatePropertyAll(shape),
      textStyle: WidgetStatePropertyAll(TextStyle(
          fontFamily: fontFamily, fontSize: 14, fontWeight: FontWeight.w700)),
    );
    return base.copyWith(
      colorScheme: scheme,
      scaffoldBackgroundColor: Colors.transparent,
      cardColor: scheme.surface,
      dividerColor: scheme.outlineVariant,
      textTheme: base.textTheme
          .apply(bodyColor: scheme.onSurface, displayColor: scheme.onSurface)
          .copyWith(
            headlineSmall: TextStyle(
                fontSize: 26,
                height: 1.15,
                letterSpacing: -.8,
                fontWeight: FontWeight.w800,
                color: scheme.onSurface),
            titleLarge: TextStyle(
                fontSize: 20,
                letterSpacing: -.4,
                fontWeight: FontWeight.w800,
                color: scheme.onSurface),
            titleMedium: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: scheme.onSurface),
            bodyMedium:
                TextStyle(fontSize: 14, height: 1.4, color: scheme.onSurface),
            bodySmall: TextStyle(
                fontSize: 12, height: 1.4, color: scheme.onSurfaceVariant),
          )
          .apply(fontFamily: fontFamily),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: scheme.onSurface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        titleSpacing: 20,
        titleTextStyle: TextStyle(
            fontFamily: fontFamily,
            fontSize: 19,
            fontWeight: FontWeight.w800,
            color: scheme.onSurface),
      ),
      filledButtonTheme: FilledButtonThemeData(style: button),
      outlinedButtonTheme: OutlinedButtonThemeData(style: button),
      textButtonTheme: TextButtonThemeData(style: button),
      iconButtonTheme: const IconButtonThemeData(
          style:
              ButtonStyle(minimumSize: WidgetStatePropertyAll(Size(48, 48)))),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surface,
        hintStyle: TextStyle(color: scheme.onSurfaceVariant, fontSize: 14),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(18),
            borderSide: BorderSide(color: scheme.outlineVariant)),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(18),
            borderSide: BorderSide(color: scheme.outlineVariant)),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(18),
            borderSide: BorderSide(color: scheme.primary, width: 2)),
      ),
      chipTheme: base.chipTheme.copyWith(
        backgroundColor: scheme.surface,
        selectedColor: dark ? const Color(0xFF56301D) : const Color(0xFFFFE5CF),
        side: BorderSide(color: scheme.outlineVariant),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        indicatorColor:
            dark ? const Color(0xFF56301D) : const Color(0xFFFFE8D9),
        labelTextStyle: WidgetStateProperty.resolveWith((states) => TextStyle(
            fontFamily: fontFamily,
            fontSize: 11,
            fontWeight: states.contains(WidgetState.selected)
                ? FontWeight.w800
                : FontWeight.w500,
            color: states.contains(WidgetState.selected)
                ? scheme.primary
                : scheme.onSurfaceVariant)),
        iconTheme: WidgetStateProperty.resolveWith((states) => IconThemeData(
            size: 23,
            color: states.contains(WidgetState.selected)
                ? scheme.primary
                : scheme.onSurfaceVariant)),
      ),
      cardTheme: CardThemeData(
          color: scheme.surface,
          elevation: 0,
          margin: EdgeInsets.zero,
          shape:
              shape.copyWith(side: BorderSide(color: scheme.outlineVariant))),
      bottomSheetTheme: BottomSheetThemeData(
          backgroundColor: scheme.surface,
          surfaceTintColor: Colors.transparent,
          showDragHandle: true,
          shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.vertical(top: Radius.circular(28)))),
    );
  }
}

/// Preserve the staff theme on routes pushed onto the app's shared Navigator.
class StaffPageRoute<T> extends MaterialPageRoute<T> {
  StaffPageRoute({required WidgetBuilder builder})
      : super(
            builder: (context) => Theme(
                  data: StaffTheme.from(Theme.of(context)),
                  child: LiquidGlassScope(
                      child: LiquidAmbientBackdrop(
                          child: Builder(builder: builder))),
                ));
}

class StaffSurface extends StatelessWidget {
  const StaffSurface(
      {super.key,
      required this.child,
      this.padding = const EdgeInsets.all(16),
      this.color});
  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? color;

  @override
  Widget build(BuildContext context) => LiquidGlassContainer(
        filterBackdrop: false,
        borderRadius: 20,
        padding: padding,
        customGradient:
            color == null ? null : LinearGradient(colors: [color!, color!]),
        child: child,
      );
}

class StaffSectionHeading extends StatelessWidget {
  const StaffSectionHeading(this.title, {super.key, this.trailing});
  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 24, bottom: 12),
        child: Row(children: [
          Expanded(
              child:
                  Text(title, style: Theme.of(context).textTheme.titleMedium)),
          if (trailing != null) trailing!
        ]),
      );
}

class StaffActionTile extends StatelessWidget {
  const StaffActionTile(
      {super.key,
      required this.icon,
      required this.title,
      required this.subtitle,
      required this.onTap,
      this.count,
      this.urgent = false});
  final IconData icon;
  final String title, subtitle;
  final VoidCallback onTap;
  final int? count;
  final bool urgent;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final tone = urgent ? scheme.error : scheme.primary;
    return StaffSurface(
        padding: EdgeInsets.zero,
        child: Material(
          color: Colors.transparent,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
              side: BorderSide(color: scheme.outlineVariant)),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(children: [
                Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                        color: tone.withValues(alpha: .09),
                        borderRadius: BorderRadius.circular(13)),
                    child: Icon(icon, color: tone, size: 23)),
                const SizedBox(width: 12),
                Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      Text(title,
                          style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 3),
                      Text(subtitle,
                          style: Theme.of(context).textTheme.bodySmall),
                    ])),
                const SizedBox(width: 8),
                if (count != null)
                  Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: Text('$count',
                          style: TextStyle(
                              color: tone,
                              fontSize: 18,
                              fontWeight: FontWeight.w800))),
                Icon(Icons.chevron_right_rounded,
                    size: 20, color: scheme.onSurfaceVariant),
              ]),
            ),
          ),
        ));
  }
}

class StaffMetric extends StatelessWidget {
  const StaffMetric(
      {super.key,
      required this.label,
      required this.value,
      required this.icon,
      this.onTap,
      this.urgent = false});
  final String label, value;
  final IconData icon;
  final VoidCallback? onTap;
  final bool urgent;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final tone = urgent ? scheme.error : scheme.primary;
    return StaffSurface(
        padding: EdgeInsets.zero,
        child: Material(
          color: Colors.transparent,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
              side: BorderSide(color: scheme.outlineVariant)),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
              onTap: onTap,
              child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(icon, color: tone, size: 22),
                        const SizedBox(height: 12),
                        Text(value,
                            style: TextStyle(
                                fontSize: 28,
                                height: 1.1,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -1,
                                color: urgent ? tone : scheme.onSurface)),
                        const SizedBox(height: 6),
                        Text(label,
                            style: Theme.of(context).textTheme.bodySmall),
                      ]))),
        ));
  }
}

class StaffActionGuide extends StatelessWidget {
  const StaffActionGuide(this.number, this.title, this.description,
      {super.key});
  final String number, title, description;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 20),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
              width: 34,
              height: 34,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                  color: Theme.of(context)
                      .colorScheme
                      .primary
                      .withValues(alpha: .08),
                  borderRadius: BorderRadius.circular(10)),
              child: Text(number,
                  style: TextStyle(
                      color: Theme.of(context).colorScheme.primary,
                      fontSize: 12,
                      fontWeight: FontWeight.w800))),
          const SizedBox(width: 12),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text(title, style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 4),
                Text(description,
                    style: TextStyle(
                        fontSize: 13,
                        height: 1.5,
                        color: Theme.of(context).colorScheme.onSurfaceVariant)),
              ])),
        ]),
      );
}
