import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:printing/printing.dart';
import '../../services/mx10_printer_service.dart';
import '../../services/rental_receipt.dart';
import '../../services/thermal_receipt.dart';
import '../../utils/record_codes.dart';

class RentalReceiptDialog extends StatefulWidget {
  const RentalReceiptDialog({super.key, required this.rental});
  final Map<String, dynamic> rental;
  @override
  State<RentalReceiptDialog> createState() => _RentalReceiptDialogState();
}

class _RentalReceiptDialogState extends State<RentalReceiptDialog> {
  final _printer = Mx10PrinterService.instance;
  late final List<Map<String, dynamic>> _lines;
  Map<String, dynamic> _status = {};
  Timer? _timer;
  bool _checking = true,
      _polling = false,
      _connecting = false,
      _printing = false,
      _pdf = false;
  String _message = '';
  bool _messageError = false, _connectionError = false;
  bool get _busy =>
      _connecting || _printing || _pdf || _status['printing'] == true;
  @override
  void initState() {
    super.initState();
    try {
      _lines = thermalReceiptLines(widget.rental);
    } catch (error) {
      _lines = [];
      _message = '$error';
      _messageError = true;
    }
    unawaited(_refresh());
    _timer = Timer.periodic(
        const Duration(seconds: 1), (_) => unawaited(_refresh()));
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    if (_polling) return;
    _polling = true;
    try {
      final status = await _printer.status();
      if (mounted) {
        setState(() {
          _status = status;
          _checking = false;
          _connectionError = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _status = {};
          _checking = false;
          _connectionError = true;
        });
      }
    } finally {
      _polling = false;
    }
  }

  String _error(Object error) => error is PlatformException
      ? error.message ?? 'Printer operation failed.'
      : '$error';
  Future<void> _connect() async {
    if (_busy || _checking) return;
    setState(() {
      _connecting = true;
      _message = '';
    });
    try {
      final printers = await _printer.discoverPrinters();
      if (!mounted) return;
      if (printers.isEmpty) {
        throw StateError(
            'No printer found. Turn on your printer and try again.');
      }
      final selected = printers.length == 1
          ? printers.first
          : await showModalBottomSheet<Map<String, String>>(
              context: context,
              showDragHandle: true,
              builder: (context) => SafeArea(
                      child: ListView(shrinkWrap: true, children: [
                    const ListTile(title: Text('Choose receipt printer')),
                    for (var i = 0; i < printers.length; i++)
                      ListTile(
                          leading: const Icon(Icons.print),
                          title: Text(printers[i]['name']?.isNotEmpty == true
                              ? printers[i]['name']!
                              : 'Printer ${i + 1}'),
                          subtitle: const Text('Available over Bluetooth'),
                          onTap: () => Navigator.pop(context, printers[i]))
                  ])));
      if (!mounted || selected == null) return;
      await _printer.connect(selected['id'] ?? '');
      await _refresh();
      if (mounted && _status['connected'] != true) {
        throw StateError('The printer did not connect. Try again.');
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _message = _error(error);
          _messageError = true;
        });
      }
    } finally {
      if (mounted) setState(() => _connecting = false);
    }
  }

  Future<void> _print() async {
    if (_busy ||
        _checking ||
        _connectionError ||
        _lines.isEmpty ||
        _status['connected'] != true) {
      return;
    }
    setState(() {
      _printing = true;
      _message = '';
    });
    try {
      if (!await _printer.isConnected()) {
        throw StateError('Printer disconnected. Connect it before printing.');
      }
      await _printer.printReceipt(_lines);
      if (mounted) {
        setState(() {
          _message =
              'Receipt sent to printer. Check the paper output before printing another copy.';
          _messageError = false;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _message =
              '${_error(error)} Check any partial paper output before retrying.';
          _messageError = true;
        });
      }
    } finally {
      await _refresh();
      if (mounted) setState(() => _printing = false);
    }
  }

  Future<void> _openPdf() async {
    if (_busy) return;
    setState(() => _pdf = true);
    try {
      await Printing.layoutPdf(
          name: 'Rental-${recordReference(widget.rental)}.pdf',
          onLayout: (_) => buildRentalReceipt(widget.rental));
    } catch (error) {
      if (mounted) {
        setState(() {
          _message = 'Could not open the PDF: $error';
          _messageError = true;
        });
      }
    } finally {
      if (mounted) setState(() => _pdf = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context), colors = theme.colorScheme;
    return PopScope(
      canPop: !_busy,
      child: Dialog(
        insetPadding: const EdgeInsets.all(16),
        clipBehavior: Clip.antiAlias,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 820,
            maxHeight: math.max(200, MediaQuery.sizeOf(context).height - 48),
          ),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 12, 16),
              child: Row(children: [
                Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      Text('Print rental receipt',
                          style: theme.textTheme.titleLarge?.copyWith(
                              fontSize: 20, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 6),
                      Text(
                          '${recordReference(widget.rental)} · ${widget.rental['item_name'] ?? 'Rental'}',
                          style: theme.textTheme.bodySmall),
                    ])),
                IconButton(
                    onPressed: _busy ? null : () => Navigator.pop(context),
                    tooltip: 'Close',
                    icon: const Icon(Icons.close, size: 21)),
              ]),
            ),
            const Divider(height: 1),
            Flexible(
                child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: LayoutBuilder(builder: (context, constraints) {
                final controls = Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _printerCard(),
                      const SizedBox(height: 14),
                      _paperSettings(),
                    ]);
                if (constraints.maxWidth >= 680) {
                  return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: _preview()),
                        const SizedBox(width: 20),
                        Expanded(child: controls),
                      ]);
                }
                return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      controls,
                      const SizedBox(height: 20),
                      _preview(),
                    ]);
              }),
            )),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    FilledButton.icon(
                      style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(48),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10))),
                      onPressed: _busy ||
                              _checking ||
                              _connectionError ||
                              _status['connected'] != true ||
                              _lines.isEmpty
                          ? null
                          : _print,
                      icon: const Icon(Icons.print_outlined, size: 20),
                      label: const Text('Print via Bluetooth'),
                    ),
                    const SizedBox(height: 6),
                    TextButton.icon(
                        onPressed: _busy ? null : _openPdf,
                        icon:
                            const Icon(Icons.picture_as_pdf_outlined, size: 18),
                        label: Text(_pdf ? 'Opening PDF…' : 'Print / save PDF'),
                        style: TextButton.styleFrom(
                            foregroundColor: colors.onSurfaceVariant)),
                  ]),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _card(Widget child) {
    final colors = Theme.of(context).colorScheme;
    return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
            border: Border.all(color: colors.outline),
            borderRadius: BorderRadius.circular(12)),
        child: child);
  }

  Widget _printerCard() {
    final theme = Theme.of(context), colors = theme.colorScheme;
    final connected = _status['connected'] == true;
    final printing = _printing || _status['printing'] == true;
    final warning = _status['warning']?.toString() ?? '';
    final status = _checking
        ? 'Checking printer connection…'
        : _connecting
            ? 'Connecting printer…'
            : printing
                ? 'Printing receipt… ${_status['progress'] ?? 0}%'
                : _connectionError
                    ? 'Connection check unavailable'
                    : connected
                        ? 'Printer connected'
                        : 'Printer not connected';
    return _card(
        Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        Container(
            padding: const EdgeInsets.all(9),
            decoration: BoxDecoration(
                color: colors.primary.withValues(alpha: .1),
                borderRadius: BorderRadius.circular(9)),
            child: Icon(Icons.print_outlined, color: colors.primary, size: 21)),
        const SizedBox(width: 12),
        Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Bluetooth printer',
              style: theme.textTheme.titleSmall?.copyWith(
                  color: colors.onSurface, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text('Connect your receipt printer.',
              style: theme.textTheme.bodySmall),
        ])),
      ]),
      const SizedBox(height: 18),
      Semantics(
          liveRegion: true,
          child: Row(children: [
            Icon(Icons.circle,
                size: 8,
                color: _busy || warning.isNotEmpty
                    ? colors.primary
                    : connected && !_connectionError
                        ? const Color(0xFF22A56F)
                        : colors.onSurfaceVariant),
            const SizedBox(width: 8),
            Expanded(
                child: Text(status,
                    key: const Key('receipt-printer-status'),
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(fontWeight: FontWeight.w600))),
          ])),
      const SizedBox(height: 7),
      Text(
          _connectionError
              ? 'Retry the connection check before printing.'
              : _status['paperOut'] == true
                  ? 'Load the paper roll, then try printing again.'
                  : _status['headHot'] == true
                      ? 'Let the print head cool, then try printing again.'
                      : printing
                          ? 'Keep the printer nearby while the receipt is being sent.'
                          : connected
                              ? 'Ready to print your receipt.'
                              : 'Turn on the printer, then connect it to this device.',
          style: theme.textTheme.bodySmall?.copyWith(height: 1.5)),
      const SizedBox(height: 14),
      OutlinedButton.icon(
          onPressed: _busy || _checking ? null : _connect,
          icon: const Icon(Icons.bluetooth, size: 19),
          label: Text(connected ? 'Change printer' : 'Connect printer'),
          style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(42),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(9)))),
      if (_connectionError)
        TextButton(
            onPressed: _busy ? null : _refresh,
            child: const Text('Retry connection check')),
      if (printing)
        const Padding(
            padding: EdgeInsets.only(top: 12),
            child: LinearProgressIndicator()),
      if (warning.isNotEmpty)
        Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(warning, style: theme.textTheme.bodySmall)),
      if (_message.isNotEmpty)
        Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                  color:
                      (_messageError ? colors.error : const Color(0xFF22A56F))
                          .withValues(alpha: .08),
                  borderRadius: BorderRadius.circular(8)),
              child: Semantics(
                  liveRegion: true,
                  child: Text(_message,
                      key: const Key('receipt-printer-message'),
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: colors.onSurface, height: 1.5))),
            )),
    ]));
  }

  Widget _paperSettings() {
    final theme = Theme.of(context);
    return _card(
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Continuous paper roll',
          style: theme.textTheme.titleSmall?.copyWith(
              color: theme.colorScheme.onSurface, fontWeight: FontWeight.w700)),
      const SizedBox(height: 8),
      Text(
          'Load the roll with the thermal side facing the print head. Leave enough paper at the tear edge before printing.',
          style: theme.textTheme.bodySmall?.copyWith(height: 1.5)),
    ]));
  }

  Widget _preview() {
    final theme = Theme.of(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text('Receipt preview',
          style: theme.textTheme.titleSmall?.copyWith(
              color: theme.colorScheme.onSurface, fontWeight: FontWeight.w700)),
      const SizedBox(height: 12),
      Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
            color: theme.colorScheme.onSurface.withValues(alpha: .04),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: theme.colorScheme.outline)),
        child: LayoutBuilder(builder: (context, constraints) {
          final width = math.min(330.0, constraints.maxWidth),
              scale = width * 48 / 55 / 384;
          return Center(
              child: Container(
            width: width,
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: const BoxDecoration(color: Colors.white, boxShadow: [
              BoxShadow(
                  color: Color(0x14071320),
                  blurRadius: 12,
                  offset: Offset(0, 3))
            ]),
            child: FractionallySizedBox(
                widthFactor: 48 / 55,
                child: Padding(
                  padding: EdgeInsets.all(12 * scale),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (final line in _lines)
                          if (line['separator'] == true)
                            Divider(
                                color: Colors.black,
                                thickness: 1,
                                height: 16 * scale)
                          else
                            Padding(
                                padding: EdgeInsets.only(bottom: 8 * scale),
                                child: Text(
                                  line['text'] as String,
                                  textAlign: line['center'] == true
                                      ? TextAlign.center
                                      : TextAlign.left,
                                  style: TextStyle(
                                      color: Colors.black,
                                      fontFamily: 'monospace',
                                      fontSize:
                                          (line['size'] as int? ?? 20) * scale,
                                      height: 1,
                                      fontWeight: line['bold'] == true
                                          ? FontWeight.bold
                                          : FontWeight.normal),
                                )),
                      ]),
                )),
          ));
        }),
      ),
    ]);
  }
}
