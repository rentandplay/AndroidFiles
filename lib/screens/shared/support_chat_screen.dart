import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models/rental_model.dart';
import '../../services/chat_draft_store.dart';
import '../../services/mobile_api_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/glass_app_bar.dart';
import '../../widgets/liquid_glass.dart';
import '../../widgets/rental_ui.dart';

/// Customer and staff use the same authenticated API; the server owns roles,
/// membership, ordering, read cursors and retry deduplication.
class SupportInboxScreen extends StatefulWidget {
  const SupportInboxScreen({super.key, this.staff = false, this.api});
  final bool staff;
  final MobileApiService? api;

  @override
  State<SupportInboxScreen> createState() => _SupportInboxScreenState();
}

class _SupportInboxScreenState extends State<SupportInboxScreen>
    with WidgetsBindingObserver {
  MobileApiService get api => widget.api ?? MobileApiService.instance;
  List<Map<String, dynamic>> threads = [];
  Timer? timer;
  String? next;
  String error = '', filter = '';
  bool busy = false, starting = false, loaded = false, foreground = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    refresh();
    timer = Timer.periodic(const Duration(seconds: 7), (_) {
      if (foreground && (ModalRoute.of(context)?.isCurrent ?? false)) refresh();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    foreground = state == AppLifecycleState.resumed;
    if (foreground) refresh();
  }

  @override
  void dispose() {
    timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> refresh({bool older = false}) async {
    if (busy) return;
    busy = true;
    try {
      final params = <String, String>{
        if (filter.isNotEmpty) 'status': filter,
        if (older && next != null) 'before': next!
      };
      final result = await api
          .adminRequest('/chat/threads?${Uri(queryParameters: params).query}');
      if (!mounted) return;
      final rows = (result['threads'] as List)
          .map((r) => Map<String, dynamic>.from(r as Map))
          .toList();
      setState(() {
        threads = older
            ? {
                ...{for (final row in threads) row['id']: row},
                ...{for (final row in rows) row['id']: row}
              }.values.toList()
            : rows;
        next = result['next_cursor'] as String?;
        error = '';
        loaded = true;
      });
    } catch (problem) {
      if (mounted) {
        setState(() {
          error = '$problem';
          loaded = true;
        });
      }
    } finally {
      busy = false;
    }
  }

  Future<void> open(String id) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SupportChatScreen(
          threadId: id,
          staff: widget.staff,
          api: api,
        ),
      ),
    );
    if (mounted) refresh();
  }

  Future<void> start() async {
    if (starting) return;
    setState(() => starting = true);
    try {
      List<RentalModel> rentals = [];
      try {
        rentals = await api.listRentals();
      } catch (_) {}
      if (!mounted) return;

      final selectedRentalId = await showModalBottomSheet<String>(
        context: context,
        backgroundColor: Colors.transparent,
        isScrollControlled: true,
        builder: (ctx) => _TopicSelectorSheet(rentals: rentals),
      );

      if (selectedRentalId == null || !mounted) return;

      final result = await api.adminRequest(
        '/chat/threads',
        method: 'POST',
        body: {'rentalId': selectedRentalId},
      );
      if (mounted) await open(result['thread']['id'] as String);
    } catch (problem) {
      if (mounted) setState(() => error = '$problem');
    } finally {
      if (mounted) setState(() => starting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textPrimary =
        isDark ? const Color(0xFFF8FAFC) : const Color(0xFF0F172A);
    final textSecondary =
        isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: GlassAppBar(
        automaticallyImplyLeading: true,
        titleText: widget.staff ? 'Customer Inbox' : 'Rental Support',
        actions: [
          HeaderActionPod(
            icon: Icons.refresh_rounded,
            tooltip: 'Refresh conversations',
            onTap: refresh,
          ),
        ],
      ),
      body: LiquidAmbientBackdrop(
        child: SafeArea(
          bottom: false,
          child: Column(
            children: [
              // 1. Header Banner & Filter Pills
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: GlassCard(
                  padding: const EdgeInsets.all(14),
                  borderRadius: 18,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color:
                                  AppTheme.brandOrange.withValues(alpha: 0.14),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.support_agent_rounded,
                              color: AppTheme.brandOrange,
                              size: 20,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  widget.staff
                                      ? 'Staff Message Center'
                                      : 'How can we help?',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 14,
                                    color: textPrimary,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  widget.staff
                                      ? 'Manage inquiries and customer booking requests.'
                                      : 'Ask about equipment, rates, or an ongoing rental.',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: textSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          _filterPill('All', ''),
                          const SizedBox(width: 8),
                          _filterPill('Open', 'OPEN'),
                          const SizedBox(width: 8),
                          _filterPill('Resolved', 'RESOLVED'),
                        ],
                      ),
                    ],
                  ),
                ),
              ),

              if (error.isNotEmpty)
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  child: RentalNotice(
                    title: 'Notice',
                    message: error,
                    isError: true,
                  ),
                ),

              // 2. Thread List / States
              Expanded(
                child: !loaded
                    ? const Center(
                        child: CircularProgressIndicator(
                            color: AppTheme.brandOrange),
                      )
                    : RefreshIndicator(
                        onRefresh: refresh,
                        color: AppTheme.brandOrange,
                        child: threads.isEmpty
                            ? _buildEmptyState(textPrimary, textSecondary)
                            : ListView.builder(
                                padding: EdgeInsets.fromLTRB(
                                  16,
                                  4,
                                  16,
                                  widget.staff ? 32 : 100,
                                ),
                                itemCount:
                                    threads.length + (next != null ? 1 : 0),
                                itemBuilder: (context, index) {
                                  if (index == threads.length) {
                                    return Center(
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(
                                            vertical: 12),
                                        child: TextButton.icon(
                                          onPressed: () => refresh(older: true),
                                          icon:
                                              const Icon(Icons.history_rounded),
                                          label: const Text(
                                              'Load older conversations'),
                                        ),
                                      ),
                                    );
                                  }
                                  final row = threads[index];
                                  return _buildThreadCard(
                                      row, textPrimary, textSecondary);
                                },
                              ),
                      ),
              ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: widget.staff
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: FilledButton.icon(
                  key: const ValueKey('start-chat-btn'),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppTheme.brandOrange,
                    foregroundColor: Colors.white,
                    minimumSize: const Size.fromHeight(52),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    elevation: 3,
                  ),
                  onPressed: starting ? null : start,
                  icon: starting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.add_comment_rounded, size: 20),
                  label: Text(
                    starting ? 'Preparing chat…' : 'Ask a question',
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 15),
                  ),
                ),
              ),
            ),
    );
  }

  Widget _filterPill(String label, String value) {
    final isSelected = filter == value;
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: () {
        if (filter == value) return;
        setState(() => filter = value);
        refresh();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected
              ? AppTheme.brandOrange
              : Theme.of(context).cardColor.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected
                ? AppTheme.brandOrange
                : Theme.of(context).dividerColor.withValues(alpha: 0.4),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
            color: isSelected
                ? Colors.white
                : Theme.of(context).colorScheme.onSurface,
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState(Color textPrimary, Color textSecondary) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 48),
      children: [
        Center(
          child: Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: AppTheme.brandOrange.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.chat_bubble_outline_rounded,
              size: 34,
              color: AppTheme.brandOrange,
            ),
          ),
        ),
        const SizedBox(height: 18),
        Text(
          widget.staff ? 'No customer messages yet' : 'No conversations yet',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 17,
            color: textPrimary,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          widget.staff
              ? 'When customers send messages or questions about their rentals, they will show up here.'
              : 'Have questions about sports equipment, game bookings, or rental rules? Start a chat anytime!',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 13,
            color: textSecondary,
            height: 1.45,
          ),
        ),
      ],
    );
  }

  Widget _buildThreadCard(
    Map<String, dynamic> row,
    Color textPrimary,
    Color textSecondary,
  ) {
    final unread = (row['unread_count'] as num? ?? 0) > 0;
    final status = (row['status'] as String? ?? 'OPEN').toUpperCase();
    final subject = widget.staff
        ? '${row['customer_name'] ?? 'Customer'} · ${row['subject'] ?? 'Inquiry'}'
        : (row['subject'] as String? ?? 'Support inquiry');
    final rentalCode = row['rental_code'] as String?;
    final lastMessage = (row['last_message'] ?? '').toString();

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GlassCard(
        borderRadius: 16,
        padding: const EdgeInsets.all(14),
        onTap: () => open(row['id'] as String),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: unread
                    ? AppTheme.brandOrange.withValues(alpha: 0.16)
                    : Theme.of(context).dividerColor.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: Stack(
                children: [
                  Center(
                    child: Icon(
                      widget.staff ? Icons.person_rounded : Icons.forum_rounded,
                      color: unread ? AppTheme.brandOrange : textSecondary,
                      size: 20,
                    ),
                  ),
                  if (unread)
                    Positioned(
                      top: 2,
                      right: 2,
                      child: Container(
                        width: 9,
                        height: 9,
                        decoration: const BoxDecoration(
                          color: AppTheme.brandOrange,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          subject,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontWeight:
                                unread ? FontWeight.w800 : FontWeight.w700,
                            fontSize: 14,
                            color: textPrimary,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                          color: status == 'OPEN'
                              ? const Color(0xFFDF762D).withValues(alpha: 0.12)
                              : const Color(0xFF16A34A).withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          status,
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: status == 'OPEN'
                                ? const Color(0xFFDF762D)
                                : const Color(0xFF16A34A),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  if (rentalCode != null && rentalCode.isNotEmpty) ...[
                    Container(
                      margin: const EdgeInsets.only(bottom: 4),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 1.5),
                      decoration: BoxDecoration(
                        color: Theme.of(context)
                            .dividerColor
                            .withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        rentalCode,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: textSecondary,
                        ),
                      ),
                    ),
                  ],
                  Text(
                    lastMessage.isEmpty
                        ? 'Tap to view conversation'
                        : lastMessage,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      color: unread ? textPrimary : textSecondary,
                      fontWeight: unread ? FontWeight.w600 : FontWeight.w400,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              Icons.chevron_right_rounded,
              color: textSecondary.withValues(alpha: 0.5),
              size: 20,
            ),
          ],
        ),
      ),
    );
  }
}

class _TopicSelectorSheet extends StatelessWidget {
  const _TopicSelectorSheet({required this.rentals});
  final List<RentalModel> rentals;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textPrimary =
        isDark ? const Color(0xFFF8FAFC) : const Color(0xFF0F172A);
    final textSecondary =
        isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: textSecondary.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'What would you like to ask about?',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Select general inquiry or choose an ongoing rental to help staff assist you faster.',
            style: TextStyle(fontSize: 13, color: textSecondary),
          ),
          const SizedBox(height: 18),

          // General question tile
          ListTile(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: BorderSide(
                color: Theme.of(context).dividerColor.withValues(alpha: 0.5),
              ),
            ),
            leading: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppTheme.brandOrange.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.help_outline_rounded,
                color: AppTheme.brandOrange,
                size: 20,
              ),
            ),
            title: Text(
              'General question',
              style: TextStyle(fontWeight: FontWeight.w700, color: textPrimary),
            ),
            subtitle: Text(
              'Availability, rates, shop hours or game rules',
              style: TextStyle(fontSize: 12, color: textSecondary),
            ),
            trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 14),
            onTap: () => Navigator.pop(context, ''),
          ),

          if (rentals.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text(
              'OR ASK ABOUT A SPECIFIC RENTAL',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: textSecondary,
                letterSpacing: 0.8,
              ),
            ),
            const SizedBox(height: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 240),
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: rentals.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (context, i) {
                  final rental = rentals[i];
                  return ListTile(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                      side: BorderSide(
                        color: Theme.of(context)
                            .dividerColor
                            .withValues(alpha: 0.4),
                      ),
                    ),
                    leading: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0284C7).withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.sports_basketball_rounded,
                        color: Color(0xFF0284C7),
                        size: 20,
                      ),
                    ),
                    title: Text(
                      rental.itemName,
                      style: TextStyle(
                          fontWeight: FontWeight.w700, color: textPrimary),
                    ),
                    subtitle: Text(
                      'Ref: ${rental.displayReference} · ${rental.status}',
                      style: TextStyle(fontSize: 12, color: textSecondary),
                    ),
                    trailing:
                        const Icon(Icons.arrow_forward_ios_rounded, size: 14),
                    onTap: () => Navigator.pop(context, rental.rentalId),
                  );
                },
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class SupportChatScreen extends StatefulWidget {
  const SupportChatScreen({
    super.key,
    required this.threadId,
    this.staff = false,
    this.api,
  });

  final String threadId;
  final bool staff;
  final MobileApiService? api;

  @override
  State<SupportChatScreen> createState() => _SupportChatScreenState();
}

class TypingIndicatorBubble extends StatefulWidget {
  const TypingIndicatorBubble({
    super.key,
    required this.name,
    required this.isDark,
  });

  final String name;
  final bool isDark;

  @override
  State<TypingIndicatorBubble> createState() => _TypingIndicatorBubbleState();
}

class _TypingIndicatorBubbleState extends State<TypingIndicatorBubble>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Widget _buildDot(int index) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final delay = index * 0.2;
        final value = (_controller.value - delay) % 1.0;
        final offset = (value < 0.5)
            ? -5.0 * (1.0 - (value * 2 - 0.5).abs() * 2)
            : 0.0;
        return Transform.translate(
          offset: Offset(0, offset < 0 ? offset : 0),
          child: Container(
            width: 6,
            height: 6,
            margin: const EdgeInsets.symmetric(horizontal: 2),
            decoration: BoxDecoration(
              color: AppTheme.brandOrange.withValues(alpha: 0.9),
              shape: BoxShape.circle,
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: widget.isDark ? const Color(0xFF1E2635) : Colors.white,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(16),
            topRight: Radius.circular(16),
            bottomRight: Radius.circular(16),
            bottomLeft: Radius.circular(4),
          ),
          border: Border.all(
            color: widget.isDark
                ? const Color(0xFF2A374A)
                : const Color(0xFFE2E8F0),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 4,
              offset: const Offset(0, 1.5),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildDot(0),
            _buildDot(1),
            _buildDot(2),
            const SizedBox(width: 8),
            Text(
              '${widget.name} is typing…',
              style: TextStyle(
                fontSize: 12,
                color: widget.isDark
                    ? const Color(0xFF94A3B8)
                    : const Color(0xFF64748B),
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SupportChatScreenState extends State<SupportChatScreen>
    with WidgetsBindingObserver {
  MobileApiService get api => widget.api ?? MobileApiService.instance;
  final input = TextEditingController(), scroll = ScrollController();
  List<Map<String, dynamic>> messages = [];
  Map<String, dynamic>? thread, pending;
  Timer? timer, draftTimer;
  late final ChatDraftStore draftStore;
  bool restoring = true;
  String error = '';
  int last = 0, readThrough = 0;
  String? older;
  Map<String, dynamic>? typing;
  DateTime? lastTypingPing;
  bool busy = false, sending = false, loadingOlder = false, foreground = true;

  // Image Attachment state
  Uint8List? _attachedBytes;
  String? _attachedName;
  bool _uploadingImage = false;

  @override
  void initState() {
    super.initState();
    draftStore = ChatDraftStore('${api.signedInUserId}:${widget.threadId}');
    restoreDraft();
    input.addListener(() {
      if (restoring) return;
      draftTimer?.cancel();
      draftTimer = Timer(const Duration(milliseconds: 300), () {
        draftStore.save(input.text, pending).catchError((_) {});
      });
      if (input.text.trim().isNotEmpty) {
        final now = DateTime.now();
        if (lastTypingPing == null ||
            now.difference(lastTypingPing!).inMilliseconds > 2500) {
          lastTypingPing = now;
          api.adminRequest(
            '/chat/threads/${widget.threadId}/typing',
            method: 'POST',
            body: {'typing': true},
          ).catchError((_) => <String, dynamic>{});
        }
      }
    });
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) sync();
    });
    timer = Timer.periodic(const Duration(seconds: 4), (_) => sync());
  }

  Future<void> restoreDraft() async {
    try {
      final saved = await draftStore.load();
      if (!mounted) return;
      setState(() {
        input.text = saved['text'] as String? ?? '';
        pending = saved['pending'] == null
            ? null
            : Map<String, dynamic>.from(saved['pending'] as Map);
        if (pending != null) {
          error =
              'A message is waiting for confirmation. Tap Retry to check or send it safely.';
        }
      });
    } catch (_) {
    } finally {
      if (mounted) setState(() => restoring = false);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    foreground = state == AppLifecycleState.resumed;
    if (foreground) sync();
  }

  @override
  void dispose() {
    timer?.cancel();
    draftTimer?.cancel();
    if (!restoring) draftStore.save(input.text, pending).catchError((_) {});
    WidgetsBinding.instance.removeObserver(this);
    input.dispose();
    scroll.dispose();
    super.dispose();
  }

  void merge(List rows) {
    final byId = {for (final row in messages) row['id']: row};
    for (final row in rows) {
      final map = Map<String, dynamic>.from(row as Map);
      byId[map['id']] = map;
    }
    messages = byId.values.toList()
      ..sort((a, b) => (a['seq'] as int).compareTo(b['seq'] as int));
  }

  Future<void> sync() async {
    if (busy || !foreground || !(ModalRoute.of(context)?.isCurrent ?? true)) {
      return;
    }
    busy = true;
    try {
      final result = await api.adminRequest(
          '/chat/threads/${widget.threadId}/messages${last > 0 ? '?after=$last' : ''}');
      if (!mounted) return;
      final rows = result['messages'] as List;
      final atBottom = !scroll.hasClients ||
          scroll.position.maxScrollExtent - scroll.offset < 100;
      setState(() {
        thread = Map<String, dynamic>.from(result['thread'] as Map);
        typing = result['typing'] as Map<String, dynamic>?;
        if (last == 0) older = result['next_cursor'] as String?;
        if (rows.isNotEmpty) last = rows.last['seq'] as int;
        merge(rows);
        if (!sending && pending == null) error = '';
      });
      if (rows.isNotEmpty && atBottom) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && scroll.hasClients) {
            scroll.jumpTo(scroll.position.maxScrollExtent);
          }
        });
      }
      if (last > readThrough &&
          foreground &&
          atBottom &&
          (ModalRoute.of(context)?.isCurrent ?? false)) {
        await api.adminRequest('/chat/threads/${widget.threadId}/read',
            method: 'POST', body: {'through': last});
        readThrough = last;
      }
      if (result['has_more'] == true && rows.isNotEmpty) {
        Timer(Duration.zero, sync);
      }
    } catch (problem) {
      if (mounted) setState(() => error = '$problem');
    } finally {
      busy = false;
    }
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(
        source: source,
        maxWidth: 1600,
        maxHeight: 1600,
        imageQuality: 75,
      );
      if (picked == null) return;
      final bytes = await picked.readAsBytes();
      if (!mounted) return;
      setState(() {
        _attachedBytes = bytes;
        _attachedName = picked.name;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not open image: $e')),
        );
      }
    }
  }

  void _removeAttachment() {
    setState(() {
      _attachedBytes = null;
      _attachedName = null;
    });
  }

  void _showAttachmentOptions() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardColor = isDark ? const Color(0xFF1E2638) : Colors.white;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        decoration: BoxDecoration(
          color: cardColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: Colors.grey.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const Text(
              'Attach Photo or Document',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
            ),
            const SizedBox(height: 6),
            Text(
              'Send a clear photo of your School ID, Government ID, or item condition.',
              style: TextStyle(
                fontSize: 12,
                color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
              ),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: () {
                      Navigator.pop(ctx);
                      _pickImage(ImageSource.camera);
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      decoration: BoxDecoration(
                        color: AppTheme.brandOrange.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: AppTheme.brandOrange.withValues(alpha: 0.25),
                        ),
                      ),
                      child: const Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.camera_alt_rounded,
                              color: AppTheme.brandOrange, size: 28),
                          SizedBox(height: 8),
                          Text(
                            'Camera',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                              color: AppTheme.brandOrange,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: () {
                      Navigator.pop(ctx);
                      _pickImage(ImageSource.gallery);
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      decoration: BoxDecoration(
                        color: Colors.blue.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: Colors.blue.withValues(alpha: 0.25),
                        ),
                      ),
                      child: const Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.photo_library_rounded,
                              color: Colors.blue, size: 28),
                          SizedBox(height: 8),
                          Text(
                            'Gallery',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                              color: Colors.blue,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> send() async {
    if (restoring ||
        sending ||
        (pending == null && input.text.trim().isEmpty && _attachedBytes == null)) {
      return;
    }

    setState(() {
      sending = true;
      error = '';
    });

    try {
      String textToSend = input.text.trim();

      // If an image is attached, upload it first
      if (_attachedBytes != null) {
        setState(() => _uploadingImage = true);
        try {
          final isPng = (_attachedName ?? '').toLowerCase().endsWith('.png');
          final photoUrl = await api.uploadChatAttachment(
            threadId: widget.threadId,
            bytes: _attachedBytes!,
            contentType: isPng ? 'image/png' : 'image/jpeg',
          );
          textToSend = '[Photo: $photoUrl]${textToSend.isNotEmpty ? '\n$textToSend' : ''}';
          _attachedBytes = null;
          _attachedName = null;
        } catch (uploadError) {
          if (mounted) {
            setState(() {
              error = 'Could not upload photo: $uploadError';
              sending = false;
              _uploadingImage = false;
            });
            return;
          }
        } finally {
          if (mounted) setState(() => _uploadingImage = false);
        }
      }

      if (textToSend.isEmpty) {
        setState(() => sending = false);
        return;
      }

      pending ??= {
        'text': textToSend,
        'requestKey': MobileApiService.operationKey(),
      };

      draftTimer?.cancel();
      await draftStore.save(input.text, pending);
      final result = await api.adminRequest(
        '/chat/threads/${widget.threadId}/messages',
        method: 'POST',
        body: pending,
      );
      if (!mounted) return;
      setState(() {
        merge([result['message']]);
        thread = Map<String, dynamic>.from(result['thread'] as Map);
        pending = null;
        input.clear();
        draftStore.clear().catchError((_) {});
      });
      api.adminRequest(
        '/chat/threads/${widget.threadId}/typing',
        method: 'POST',
        body: {'typing': false},
      ).catchError((_) => <String, dynamic>{});
      sync();
    } catch (problem) {
      if (mounted) {
        setState(() {
          if (problem is MobileApiException &&
              (problem.statusCode ?? 0) >= 400 &&
              (problem.statusCode ?? 0) < 500) {
            pending = null;
          }
          error = '$problem\nYour message is kept. Try sending again.';
        });
      }
    } finally {
      if (mounted) setState(() => sending = false);
    }
  }

  Future<void> loadOlder() async {
    if (loadingOlder || older == null) return;
    setState(() => loadingOlder = true);
    try {
      final result = await api.adminRequest(
          '/chat/threads/${widget.threadId}/messages?before=$older');
      if (!mounted) return;
      setState(() {
        merge(result['messages'] as List);
        older = result['next_cursor'] as String?;
      });
    } catch (problem) {
      if (mounted) setState(() => error = '$problem');
    } finally {
      if (mounted) setState(() => loadingOlder = false);
    }
  }

  Future<void> changeStatus() async {
    try {
      final result = await api.adminRequest(
        '/chat/threads/${widget.threadId}/status',
        method: 'PATCH',
        body: {'status': thread?['status'] == 'OPEN' ? 'RESOLVED' : 'OPEN'},
      );
      if (mounted) {
        setState(
            () => thread = Map<String, dynamic>.from(result['thread'] as Map));
      }
    } catch (problem) {
      if (mounted) setState(() => error = '$problem');
    }
  }

  String? _extractPhotoUrl(String text) {
    final photoTag = RegExp(r'\[Photo:\s*(\S+)\]').firstMatch(text);
    if (photoTag != null) return photoTag.group(1);
    final directUrl = RegExp(r'(https?:\/\/\S+\.(?:png|jpg|jpeg|webp)(?:\?\S*)?)', caseSensitive: false).firstMatch(text);
    if (directUrl != null) return directUrl.group(1);
    final supabaseUrl = RegExp(r'(https?:\/\/\S+\/storage\/v1\/object\/public\/\S+)').firstMatch(text);
    if (supabaseUrl != null) return supabaseUrl.group(1);
    return null;
  }

  String _cleanDisplayMessage(String text) {
    return text.replaceAll(RegExp(r'\[Photo:\s*\S+\]'), '').trim();
  }

  void _openImageDialog(String imageUrl) {
    showDialog(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.85),
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(12),
        child: Stack(
          alignment: Alignment.center,
          children: [
            InteractiveViewer(
              maxScale: 4.0,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Image.network(
                  imageUrl,
                  fit: BoxFit.contain,
                  loadingBuilder: (c, child, progress) {
                    if (progress == null) return child;
                    return const SizedBox(
                      width: 120,
                      height: 120,
                      child: Center(
                        child: CircularProgressIndicator(
                          color: AppTheme.brandOrange,
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
            Positioned(
              top: 8,
              right: 8,
              child: IconButton(
                style: IconButton.styleFrom(
                  backgroundColor: Colors.black.withValues(alpha: 0.6),
                ),
                icon: const Icon(Icons.close_rounded, color: Colors.white),
                onPressed: () => Navigator.pop(ctx),
              ),
            ),
          ],
        ),
      ),
    );
  }

  bool _isDifferentDay(DateTime a, DateTime b) {
    return a.year != b.year || a.month != b.month || a.day != b.day;
  }

  String _formatDateDivider(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final check = DateTime(date.year, date.month, date.day);

    if (check == today) return 'Today';
    if (check == yesterday) return 'Yesterday';
    if (date.year == now.year) {
      return DateFormat('EEEE, MMM d').format(date);
    }
    return DateFormat('MMM d, yyyy').format(date);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textPrimary =
        isDark ? const Color(0xFFF8FAFC) : const Color(0xFF0F172A);
    final textSecondary =
        isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);
    final resolved = thread?['status'] == 'RESOLVED';

    final title = widget.staff
        ? (thread?['customer_name']?.toString() ?? 'Customer')
        : (thread?['subject']?.toString() ?? 'Rental Support');
    final subtitle = resolved
        ? 'Thread resolved · Send reply to reopen'
        : (widget.staff ? 'Customer inquiry' : '🟢 Online support · Replies typically within minutes');

    return PopScope(
      canPop: !sending,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text('Retry your pending message before leaving.')),
          );
        }
      },
      child: Scaffold(
        extendBodyBehindAppBar: true,
        appBar: GlassAppBar(
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: textPrimary,
                ),
              ),
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: resolved ? Colors.orange : (isDark ? const Color(0xFF6EE7B7) : const Color(0xFF059669)),
                ),
              ),
            ],
          ),
          actions: [
            HeaderActionPod(
              icon: Icons.refresh_rounded,
              tooltip: 'Refresh messages',
              onTap: sync,
            ),
            if (widget.staff && thread != null) ...[
              const SizedBox(width: 6),
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: FilledButton.tonal(
                  style: FilledButton.styleFrom(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
                    minimumSize: const Size(0, 34),
                  ),
                  onPressed: sending ? null : changeStatus,
                  child: Text(resolved ? 'Reopen' : 'Resolve',
                      style: const TextStyle(fontSize: 12)),
                ),
              ),
            ],
          ],
        ),
        body: LiquidAmbientBackdrop(
          child: SafeArea(
            bottom: false,
            child: Column(
              children: [
                if (error.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: RentalNotice(
                      title: 'Notice',
                      message: error,
                      isError: true,
                      action: pending != null
                          ? TextButton(
                              onPressed: sending ? null : send,
                              child: const Text('Retry'),
                            )
                          : null,
                    ),
                  ),

                Expanded(
                  child: thread == null && error.isEmpty
                      ? const Center(
                          child: CircularProgressIndicator(
                              color: AppTheme.brandOrange),
                        )
                      : ListView(
                          controller: scroll,
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                          children: [
                            if (older != null)
                              Center(
                                child: TextButton.icon(
                                  onPressed: loadingOlder ? null : loadOlder,
                                  icon: const Icon(Icons.arrow_upward_rounded,
                                      size: 14),
                                  label: Text(
                                    loadingOlder
                                        ? 'Loading…'
                                        : 'Load earlier messages',
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                ),
                              ),

                            // Top notice banner
                            Container(
                              margin: const EdgeInsets.only(bottom: 16),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 14, vertical: 10),
                              decoration: BoxDecoration(
                                color: isDark
                                    ? const Color(0xFF1E2638).withValues(alpha: 0.8)
                                    : Colors.white.withValues(alpha: 0.85),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: isDark
                                      ? const Color(0xFF2E3D52)
                                      : const Color(0xFFE2E8F0),
                                ),
                              ),
                              child: Row(
                                children: [
                                  const Icon(
                                    Icons.lock_outline_rounded,
                                    size: 16,
                                    color: AppTheme.brandOrange,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      'Chat history is preserved securely. Please do not share passwords or payment credentials.',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: textSecondary,
                                        height: 1.35,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),

                            if (messages.isEmpty)
                              Padding(
                                padding: const EdgeInsets.all(32),
                                child: Column(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(14),
                                      decoration: BoxDecoration(
                                        color: AppTheme.brandOrange
                                            .withValues(alpha: 0.12),
                                        shape: BoxShape.circle,
                                      ),
                                      child: const Icon(
                                        Icons.chat_bubble_outline_rounded,
                                        size: 28,
                                        color: AppTheme.brandOrange,
                                      ),
                                    ),
                                    const SizedBox(height: 12),
                                    Text(
                                      'Send your question here.\nOur support team will respond as soon as possible.',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                          color: textSecondary, fontSize: 13),
                                    ),
                                  ],
                                ),
                              ),

                            // Render messages with date dividers
                            ..._buildMessageListWithDividers(isDark, textSecondary),

                            if (typing != null && typing!['is_typing'] == true)
                              TypingIndicatorBubble(
                                name: typing!['name'] as String? ??
                                    (widget.staff ? 'Customer' : 'Staff'),
                                isDark: isDark,
                              ),
                          ],
                        ),
                ),

                // Enhanced Composer Bar with Quick Replies & Camera
                _buildComposer(resolved, isDark, textPrimary, textSecondary),
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _buildMessageListWithDividers(bool isDark, Color textSecondary) {
    final widgets = <Widget>[];
    DateTime? lastDate;

    for (int i = 0; i < messages.length; i++) {
      final row = messages[i];
      final createdAt = row['created_at'];
      final date = createdAt is String
          ? DateTime.tryParse(createdAt)?.toLocal()
          : null;

      if (date != null) {
        if (lastDate == null || _isDifferentDay(lastDate, date)) {
          lastDate = date;
          widgets.add(
            Center(
              child: Container(
                margin: const EdgeInsets.symmetric(vertical: 12),
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: isDark
                      ? const Color(0xFF2A374A)
                      : const Color(0xFFE2E8F0),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  _formatDateDivider(date),
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: textSecondary,
                  ),
                ),
              ),
            ),
          );
        }
      }

      widgets.add(_buildMessageBubble(row, isDark));
    }

    return widgets;
  }

  Widget _buildMessageBubble(Map<String, dynamic> row, bool isDark) {
    final own = (row['sender_role'] == 'STAFF') == widget.staff;
    final read = (thread?[widget.staff ? 'customer_read_seq' : 'staff_read_seq']
                as num? ??
            0) >=
        (row['seq'] as num);
    final createdAt = row['created_at'];
    final date =
        createdAt is String ? DateTime.tryParse(createdAt)?.toLocal() : null;
    final timeStr = date != null ? DateFormat('h:mm a').format(date) : '';

    final rawText = row['text'] as String? ?? '';
    final photoUrl = _extractPhotoUrl(rawText);
    final displayText = _cleanDisplayMessage(rawText);

    return Align(
      alignment: own ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.80,
        ),
        decoration: BoxDecoration(
          color: own
              ? AppTheme.brandOrange
              : (isDark ? const Color(0xFF1E2638) : Colors.white),
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(18),
            topRight: const Radius.circular(18),
            bottomLeft: Radius.circular(own ? 18 : 4),
            bottomRight: Radius.circular(own ? 4 : 18),
          ),
          border: own
              ? null
              : Border.all(
                  color: isDark
                      ? const Color(0xFF2E3D52)
                      : const Color(0xFFE2E8F0),
                ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 4,
              offset: const Offset(0, 1.5),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment:
              own ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            if (!own) ...[
              Builder(builder: (context) {
                final isSenderStaff = row['sender_role'] == 'STAFF';
                String displayName = row['sender_name'] as String? ??
                    (isSenderStaff ? 'Support' : 'Customer');
                if (isSenderStaff && !widget.staff) {
                  final clean = displayName
                      .replaceAll('(Staff)', '')
                      .replaceAll('(you)', '')
                      .trim();
                  final first = clean.split(RegExp(r'\s+')).first;
                  displayName = first.isNotEmpty ? first : 'Support';
                }
                return Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        displayName,
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                          color: isSenderStaff
                              ? AppTheme.brandOrange
                              : (isDark
                                  ? const Color(0xFF93C5FD)
                                  : const Color(0xFF2563EB)),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 1.5),
                        decoration: BoxDecoration(
                          color: (isSenderStaff
                                  ? AppTheme.brandOrange
                                  : Colors.blue)
                              .withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              isSenderStaff
                                  ? Icons.verified_user_rounded
                                  : Icons.person_rounded,
                              size: 10,
                              color: isSenderStaff
                                  ? AppTheme.brandOrange
                                  : const Color(0xFF2563EB),
                            ),
                            const SizedBox(width: 3),
                            Text(
                              isSenderStaff ? 'STAFF' : 'CUSTOMER',
                              style: TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.w800,
                                color: isSenderStaff
                                    ? AppTheme.brandOrange
                                    : const Color(0xFF2563EB),
                                letterSpacing: 0.4,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              }),
            ],

            // If an image was attached in this message
            if (photoUrl != null) ...[
              GestureDetector(
                onTap: () => _openImageDialog(photoUrl),
                child: Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Stack(
                      children: [
                        ConstrainedBox(
                          constraints: const BoxConstraints(
                            maxHeight: 220,
                            maxWidth: 280,
                          ),
                          child: Image.network(
                            photoUrl,
                            fit: BoxFit.cover,
                            loadingBuilder: (c, child, progress) {
                              if (progress == null) return child;
                              return Container(
                                height: 160,
                                width: 220,
                                color: Colors.black.withValues(alpha: 0.08),
                                child: const Center(
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: AppTheme.brandOrange,
                                  ),
                                ),
                              );
                            },
                            errorBuilder: (_, __, ___) => Container(
                              padding: const EdgeInsets.all(12),
                              color: Colors.black.withValues(alpha: 0.08),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.broken_image_rounded, size: 18),
                                  SizedBox(width: 6),
                                  Text('Image preview',
                                      style: TextStyle(fontSize: 11)),
                                ],
                              ),
                            ),
                          ),
                        ),
                        Positioned(
                          bottom: 6,
                          right: 6,
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.6),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.fullscreen_rounded,
                              size: 16,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],

            if (displayText.isNotEmpty) ...[
              SelectableText(
                displayText,
                style: TextStyle(
                  fontSize: 14,
                  color: own
                      ? Colors.white
                      : (isDark
                          ? const Color(0xFFF8FAFC)
                          : const Color(0xFF0F172A)),
                  height: 1.35,
                ),
              ),
            ],

            const SizedBox(height: 4),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  timeStr,
                  style: TextStyle(
                    fontSize: 10,
                    color: own
                        ? Colors.white.withValues(alpha: 0.8)
                        : (isDark
                            ? const Color(0xFF94A3B8)
                            : const Color(0xFF64748B)),
                  ),
                ),
                if (own) ...[
                  const SizedBox(width: 4),
                  Icon(
                    read ? Icons.done_all_rounded : Icons.done_rounded,
                    size: 13,
                    color: Colors.white.withValues(alpha: 0.9),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickReplyChip(String label, String text, bool isDark) {
    return ActionChip(
      label: Text(label, style: const TextStyle(fontSize: 11)),
      padding: const EdgeInsets.symmetric(horizontal: 6),
      visualDensity: VisualDensity.compact,
      backgroundColor:
          isDark ? const Color(0xFF1E2638) : const Color(0xFFF1F5F9),
      side: BorderSide(
        color: isDark ? const Color(0xFF2E3D52) : const Color(0xFFE2E8F0),
      ),
      onPressed: () {
        HapticFeedback.selectionClick();
        setState(() {
          input.text = text;
          input.selection =
              TextSelection.fromPosition(TextPosition(offset: text.length));
        });
      },
    );
  }

  Widget _buildComposer(
    bool resolved,
    bool isDark,
    Color textPrimary,
    Color textSecondary,
  ) {
    final disabled = restoring || (widget.staff && resolved);
    final canSend = !sending &&
        !disabled &&
        thread != null &&
        (input.text.trim().isNotEmpty || _attachedBytes != null || pending != null);

    final viewInsets = MediaQuery.viewInsetsOf(context);
    final viewPadding = MediaQuery.viewPaddingOf(context);
    final safeBottom = viewPadding.bottom > 0
        ? viewPadding.bottom
        : MediaQuery.paddingOf(context).bottom;
    final effectiveBottom =
        viewInsets.bottom > 0 ? 8.0 : math.max(safeBottom + 8.0, 16.0);

    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF141B26) : Colors.white,
        border: Border(
          top: BorderSide(
            color: isDark ? const Color(0xFF242E40) : const Color(0xFFE2E8F0),
            width: 1,
          ),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.25 : 0.05),
            blurRadius: 10,
            offset: const Offset(0, -3),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 1. Quick Replies for both Customer and Staff
          if (!disabled)
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
              child: Row(
                children: [
                  if (widget.staff) ...[
                    _buildQuickReplyChip(
                        "🪪 Accepted IDs",
                        "Tumatanggap po kami ng National ID, Driver's License, Passport, UMID, Postal ID, o Valid School ID with enrollment proof.",
                        isDark),
                    const SizedBox(width: 6),
                    _buildQuickReplyChip(
                        "📋 Requirements",
                        "Kailangan lamang po ng 1 Valid ID (Government o School ID), pirma sa agreement, at active contact info.",
                        isDark),
                    const SizedBox(width: 6),
                    _buildQuickReplyChip(
                        "⏰ Store Hours",
                        "Bukas po kami araw-araw mula 8:00 AM hanggang 8:00 PM para sa pickup/return.",
                        isDark),
                    const SizedBox(width: 6),
                    _buildQuickReplyChip(
                        "📍 Pickup & Return",
                        "Maaari ninyong i-pickup at i-return ang unit sa aming rental shop desk habang operating hours.",
                        isDark),
                    const SizedBox(width: 6),
                    _buildQuickReplyChip(
                        "✅ ID Approved",
                        "Approved na po ang inyong ID at requirements! Pwede na po kayong mag-proceed sa rental booking.",
                        isDark),
                  ] else ...[
                    _buildQuickReplyChip(
                        "🪪 School ID accepted?",
                        "Tumatanggap po ba kayo ng School ID o Student ID as valid ID?",
                        isDark),
                    const SizedBox(width: 6),
                    _buildQuickReplyChip(
                        "📋 Requirements",
                        "Ano po ang mga kailangan at requirements para makapag-rent?",
                        isDark),
                    const SizedBox(width: 6),
                    _buildQuickReplyChip(
                        "💰 Rates & Deposit",
                        "Magkano po ang rental rates at required security deposit?",
                        isDark),
                    const SizedBox(width: 6),
                    _buildQuickReplyChip(
                        "⏰ Store Hours",
                        "Ano po ang operating hours at address ng pickup location?",
                        isDark),
                    const SizedBox(width: 6),
                    _buildQuickReplyChip(
                        "🎮 Available Units",
                        "Available po ba ang gaming consoles at sports equipment ngayon?",
                        isDark),
                    const SizedBox(width: 6),
                    _buildQuickReplyChip(
                        "⏱️ Extend Rental",
                        "Pwede po bang magpa-extend ng aking rental duration?",
                        isDark),
                  ],
                ],
              ),
            ),

          // 2. Attachment Preview Bar (if photo is selected)
          if (_attachedBytes != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 6, 14, 2),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF1E2638) : const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: AppTheme.brandOrange.withValues(alpha: 0.3),
                  ),
                ),
                child: Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.memory(
                        _attachedBytes!,
                        width: 44,
                        height: 44,
                        fit: BoxFit.cover,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Photo attached',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 12,
                            ),
                          ),
                          Text(
                            _attachedName ?? 'Tap send to attach with message',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 11, color: textSecondary),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded, size: 18),
                      tooltip: 'Remove photo',
                      onPressed: sending ? null : _removeAttachment,
                    ),
                  ],
                ),
              ),
            ),

          // 3. Main Input Bar Row
          Padding(
            padding: EdgeInsets.fromLTRB(12, 6, 12, effectiveBottom),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                // (+) Attachment button
                Container(
                  margin: const EdgeInsets.only(right: 8, bottom: 2),
                  decoration: BoxDecoration(
                    color: isDark
                        ? const Color(0xFF1E2638)
                        : const Color(0xFFF1F5F9),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: isDark
                          ? const Color(0xFF2E3D52)
                          : const Color(0xFFE2E8F0),
                    ),
                  ),
                  child: IconButton(
                    icon: const Icon(Icons.add_photo_alternate_rounded),
                    color: AppTheme.brandOrange,
                    iconSize: 20,
                    tooltip: 'Attach Photo',
                    onPressed: disabled || sending ? null : _showAttachmentOptions,
                  ),
                ),

                // Text Field Input
                Expanded(
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
                    decoration: BoxDecoration(
                      color: isDark
                          ? const Color(0xFF1E2638)
                          : const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(
                        color: isDark
                            ? const Color(0xFF2E3D52)
                            : const Color(0xFFE2E8F0),
                      ),
                    ),
                    child: TextField(
                      controller: input,
                      enabled: !disabled && pending == null,
                      minLines: 1,
                      maxLines: 4,
                      maxLength: 2000,
                      textCapitalization: TextCapitalization.sentences,
                      onChanged: (_) => setState(() {}),
                      decoration: InputDecoration(
                        counterText: '',
                        hintText: disabled
                            ? 'Chat is marked resolved'
                            : 'Type a message…',
                        hintStyle: TextStyle(
                          fontSize: 14,
                          color: isDark
                              ? const Color(0xFF94A3B8)
                              : const Color(0xFF64748B),
                        ),
                        border: InputBorder.none,
                        contentPadding:
                            const EdgeInsets.symmetric(vertical: 8),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),

                // Send Button
                Material(
                  color: canSend
                      ? AppTheme.brandOrange
                      : (isDark
                          ? const Color(0xFF2E3D52)
                          : const Color(0xFFCBD5E1)),
                  shape: const CircleBorder(),
                  elevation: canSend ? 2 : 0,
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: sending || thread == null || (widget.staff && resolved) ? null : send,
                    child: Padding(
                      padding: const EdgeInsets.all(10),
                      child: sending || _uploadingImage
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : Icon(
                              pending != null
                                  ? Icons.refresh_rounded
                                  : Icons.send_rounded,
                              color: Colors.white,
                              size: 20,
                            ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
