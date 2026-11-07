import 'package:flutter/material.dart';
import '../services/business_settings.dart';
import '../services/mobile_api_service.dart';
import 'liquid_glass.dart';

class LiveBusinessSettings extends StatefulWidget {
  const LiveBusinessSettings({super.key, this.api, required this.builder});
  final MobileApiService? api;
  final Widget Function(BuildContext, BusinessSettings) builder;
  @override
  State<LiveBusinessSettings> createState() => _LiveBusinessSettingsState();
}

class _LiveBusinessSettingsState extends State<LiveBusinessSettings> {
  late final BusinessSettings settings;
  @override
  void initState() {
    super.initState();
    settings = BusinessSettings(widget.api ?? MobileApiService.instance);
  }

  @override
  void dispose() {
    settings.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
      listenable: settings,
      builder: (context, _) => widget.builder(context, settings));
}

class LiveAnnouncementBanner extends StatelessWidget {
  const LiveAnnouncementBanner({super.key, required this.settings});
  final Map<String, dynamic> settings;
  @override
  Widget build(BuildContext context) {
    final text = (settings['announcement_text'] ?? '').toString().trim();
    if (settings['announcement_enabled'] != true || text.isEmpty) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Semantics(
          liveRegion: true,
          child: GlassCard(
            padding: const EdgeInsets.all(14),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Icon(Icons.campaign_rounded, color: Color(0xFFCA8A04)),
              const SizedBox(width: 10),
              Expanded(
                  child: Text(text,
                      style: Theme.of(context).textTheme.bodyMedium)),
            ]),
          )),
    );
  }
}
