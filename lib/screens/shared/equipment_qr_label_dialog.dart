import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart' as pdf;
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../services/mx10_printer_service.dart';

class EquipmentQrLabelDialog extends StatefulWidget {
  const EquipmentQrLabelDialog({
    super.key,
    required this.qrCode,
    required this.itemName,
    this.qrData,
    this.qrMatrix,
    this.customerName,
    this.rentalId,
  });

  final String qrCode;
  final String itemName;
  final String? qrData;
  final Map<String, dynamic>? qrMatrix;
  final String? customerName;
  final String? rentalId;

  static Future<void> show(
    BuildContext context, {
    required String qrCode,
    required String itemName,
    String? qrData,
    Map<String, dynamic>? qrMatrix,
    String? customerName,
    String? rentalId,
  }) {
    return showDialog<void>(
      context: context,
      builder: (_) => EquipmentQrLabelDialog(
        qrCode: qrCode,
        itemName: itemName,
        qrData: qrData,
        qrMatrix: qrMatrix,
        customerName: customerName,
        rentalId: rentalId,
      ),
    );
  }

  @override
  State<EquipmentQrLabelDialog> createState() => _EquipmentQrLabelDialogState();
}

class _EquipmentQrLabelDialogState extends State<EquipmentQrLabelDialog> {
  bool _printing = false;
  bool _sharing = false;
  bool _connectingPrinter = false;
  bool _printingPrinter = false;
  bool _checkingPrinter = true;
  bool _printerConnected = false;
  bool _refreshingPrinterStatus = false;
  Timer? _printerStatusTimer;

  @override
  void initState() {
    super.initState();
    unawaited(_refreshPrinterStatus());
    _printerStatusTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (!_connectingPrinter && !_printingPrinter) {
        unawaited(_refreshPrinterStatus());
      }
    });
  }

  @override
  void dispose() {
    _printerStatusTimer?.cancel();
    super.dispose();
  }

  String get _payload => widget.qrData?.trim().isNotEmpty == true
      ? widget.qrData!.trim()
      : widget.qrCode.trim();

  Future<Uint8List> _makeLabelPdf() async {
    final document = pw.Document();
    const mm = pdf.PdfPageFormat.mm;
    final format = pdf.PdfPageFormat(50 * mm, 30 * mm, marginAll: 0);
    final name =
        widget.itemName.trim().isEmpty ? 'Equipment' : widget.itemName.trim();

    document.addPage(
      pw.Page(
        pageFormat: format,
        margin: pw.EdgeInsets.zero,
        build: (_) => pw.Padding(
          padding: pw.EdgeInsets.all(1.5 * mm),
          child: pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.center,
            children: [
              pw.BarcodeWidget(
                barcode: pw.Barcode.qrCode(),
                data: _payload,
                width: 25 * mm,
                height: 25 * mm,
                margin: pw.EdgeInsets.zero,
                drawText: false,
              ),
              pw.SizedBox(width: 2 * mm),
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  mainAxisAlignment: pw.MainAxisAlignment.center,
                  children: [
                    pw.Text(
                      widget.qrCode,
                      maxLines: 1,
                      style: pw.TextStyle(
                        fontSize: 8,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                    pw.SizedBox(height: 1.2 * mm),
                    pw.Text(
                      name,
                      maxLines: 2,
                      style: const pw.TextStyle(fontSize: 7.2),
                    ),
                    pw.SizedBox(height: 2 * mm),
                    pw.Text(
                      'RENT & PLAY',
                      style: pw.TextStyle(
                        fontSize: 6.5,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                    if (widget.customerName?.trim().isNotEmpty == true) ...[
                      pw.SizedBox(height: 1 * mm),
                      pw.Text(
                        'Renter: ${widget.customerName!.trim()}',
                        maxLines: 1,
                        style: const pw.TextStyle(fontSize: 5.5),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
    return document.save();
  }

  Future<void> _printLabel() async {
    if (_printing || _payload.isEmpty) return;
    setState(() => _printing = true);
    try {
      final bytes = await _makeLabelPdf();
      const mm = pdf.PdfPageFormat.mm;
      await Printing.layoutPdf(
        name: 'Rent and Play ${widget.qrCode}',
        format: pdf.PdfPageFormat(50 * mm, 30 * mm, marginAll: 0),
        dynamicLayout: false,
        onLayout: (_) async => bytes,
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not open the print dialog: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _printing = false);
    }
  }

  Future<void> _shareLabel() async {
    if (_sharing || _payload.isEmpty) return;
    setState(() => _sharing = true);
    try {
      final bytes = await _makeLabelPdf();
      await Printing.sharePdf(
        bytes: bytes,
        filename:
            '${widget.qrCode.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_')}.pdf',
        subject: 'Equipment QR label ${widget.qrCode}',
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not share the label PDF: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  Future<Map<String, String>?> _choosePrinter(
    List<Map<String, String>> printers,
  ) =>
      showModalBottomSheet<Map<String, String>>(
        context: context,
        showDragHandle: true,
        builder: (sheetContext) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Choose printer',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                ...printers.asMap().entries.map(
                      (entry) => ListTile(
                        leading: const Icon(Icons.print_rounded),
                        title: Text('Printer ${entry.key + 1}'),
                        subtitle: const Text('Available over Bluetooth'),
                        onTap: () => Navigator.pop(sheetContext, entry.value),
                      ),
                    ),
              ],
            ),
          ),
        ),
      );

  Future<void> _refreshPrinterStatus() async {
    if (_refreshingPrinterStatus) return;
    _refreshingPrinterStatus = true;
    try {
      final connected = await Mx10PrinterService.instance.isConnected();
      if (mounted) {
        setState(() {
          _printerConnected = connected;
          _checkingPrinter = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _printerConnected = false;
          _checkingPrinter = false;
        });
      }
    } finally {
      _refreshingPrinterStatus = false;
    }
  }

  Future<void> _connectPrinter() async {
    if (_connectingPrinter || _printingPrinter || _payload.isEmpty) return;
    setState(() => _connectingPrinter = true);
    try {
      final printerService = Mx10PrinterService.instance;
      final printers = await printerService.discoverPrinters();
      if (!mounted) return;
      if (printers.isEmpty) {
        throw Exception('No printer found. Turn it on and try again.');
      }
      final selected = printers.length == 1
          ? printers.first
          : await _choosePrinter(printers);
      if (!mounted || selected == null) return;
      await printerService.connect(selected['id'] ?? '');
      await _refreshPrinterStatus();
      if (mounted && !_printerConnected) {
        throw Exception('Could not connect to the printer. Try again.');
      }
    } on PlatformException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(error.message ?? 'Could not connect to printer.'),
          ),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(error.toString().replaceFirst('Exception: ', '')),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _connectingPrinter = false);
    }
  }

  Future<void> _printOnPrinter() async {
    if (_printingPrinter ||
        !_printerConnected ||
        _payload.isEmpty ||
        widget.qrMatrix == null) {
      return;
    }
    setState(() => _printingPrinter = true);
    try {
      final printerService = Mx10PrinterService.instance;
      if (!await printerService.isConnected()) {
        if (mounted) setState(() => _printerConnected = false);
        throw Exception(
          'Printer disconnected. Connect the printer before printing.',
        );
      }
      await printerService.printLabel(
        code: widget.qrCode,
        name: widget.itemName,
        qrMatrix: widget.qrMatrix!,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Label sent to printer.')),
        );
      }
    } on PlatformException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error.message ?? 'Printer print failed.')),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(error.toString().replaceFirst('Exception: ', ''))),
        );
      }
    } finally {
      await _refreshPrinterStatus();
      if (mounted) setState(() => _printingPrinter = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final code =
        widget.qrCode.trim().isEmpty ? 'EQUIPMENT' : widget.qrCode.trim();
    final displayName =
        widget.itemName.trim().isEmpty ? 'Equipment' : widget.itemName.trim();
    final colors = Theme.of(context).colorScheme;
    final printerStatusColor = _printerConnected
        ? const Color(0xFF238655)
        : _checkingPrinter || _connectingPrinter
            ? colors.secondary
            : colors.error;
    final printerStatusText = _checkingPrinter
        ? 'Checking connection…'
        : _connectingPrinter
            ? 'Connecting…'
            : _printerConnected
                ? 'Connected'
                : 'Disconnected';
    final printerStatusDescription = _checkingPrinter
        ? 'Checking the current printer connection.'
        : _connectingPrinter
            ? 'Keep the printer nearby while it connects.'
            : _printingPrinter
                ? 'Sending the label to the printer…'
                : _printerConnected
                    ? 'Ready to print.'
                    : 'Connect a printer before printing.';
    final printerButtonBusy =
        _checkingPrinter || _connectingPrinter || _printingPrinter;

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      contentPadding: const EdgeInsets.all(18),
      titlePadding: const EdgeInsets.fromLTRB(20, 18, 12, 4),
      title: Row(
        children: [
          const Icon(Icons.qr_code_2_rounded,
              color: Color(0xFFDF762D), size: 25),
          const SizedBox(width: 8),
          const Expanded(
            child: Text(
              'Equipment QR label',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            ),
          ),
          IconButton(
            tooltip: 'Close',
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.close_rounded),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '50 × 30 mm equipment label',
              style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 14),
            LayoutBuilder(
              builder: (context, constraints) {
                final qrSide =
                    (constraints.maxWidth * .48).clamp(92.0, 132.0).toDouble();
                return AspectRatio(
                  aspectRatio: 50 / 30,
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFDDE3EA)),
                    ),
                    child: Row(
                      children: [
                        SizedBox(
                          width: qrSide,
                          height: qrSide,
                          child: _payload.isEmpty
                              ? const Icon(Icons.qr_code_2, size: 100)
                              : QrImageView(
                                  data: _payload,
                                  version: QrVersions.auto,
                                  backgroundColor: Colors.white,
                                  errorCorrectionLevel: QrErrorCorrectLevel.M,
                                  padding: EdgeInsets.zero,
                                ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                code,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w900,
                                  color: Colors.black,
                                ),
                              ),
                              const SizedBox(height: 5),
                              Text(
                                displayName,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Colors.black87,
                                ),
                              ),
                              const SizedBox(height: 10),
                              const Text(
                                'RENT & PLAY',
                                style: TextStyle(
                                  fontWeight: FontWeight.w900,
                                  fontSize: 11,
                                  color: Color(0xFFC45E1B),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      await Clipboard.setData(ClipboardData(text: code));
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Copied $code')),
                        );
                      }
                    },
                    icon: const Icon(Icons.copy_rounded, size: 18),
                    label: const Text('Copy code'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _sharing ? null : _shareLabel,
                    icon: _sharing
                        ? const SizedBox.square(
                            dimension: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.ios_share_rounded, size: 18),
                    label: Text(_sharing ? 'Preparing…' : 'Share PDF'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: printerStatusColor.withOpacity(.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: printerStatusColor.withOpacity(.25),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    _checkingPrinter || _connectingPrinter
                        ? Icons.bluetooth_searching_rounded
                        : _printerConnected
                            ? Icons.bluetooth_connected_rounded
                            : Icons.bluetooth_disabled_rounded,
                    color: printerStatusColor,
                    size: 20,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          printerStatusText,
                          style: TextStyle(
                            color: printerStatusColor,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          printerStatusDescription,
                          style: TextStyle(
                            color: colors.onSurfaceVariant,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: printerButtonBusy || widget.qrMatrix == null
                    ? null
                    : _printerConnected
                        ? _printOnPrinter
                        : _connectPrinter,
                icon: printerButtonBusy
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.bluetooth_rounded),
                label: Text(_checkingPrinter
                    ? 'Checking connection…'
                    : _connectingPrinter
                        ? 'Connecting…'
                        : _printingPrinter
                            ? 'Printing…'
                            : _printerConnected
                                ? 'Print label'
                                : 'Connect printer'),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFFDF762D),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 13),
                ),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _printing ? null : _printLabel,
                icon: _printing
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.print_rounded),
                label: Text(
                    _printing ? 'Preparing label…' : 'Android print dialog'),
              ),
            ),
            const SizedBox(height: 7),
            Text(
              'Bluetooth connects directly to a nearby printer. The Android print dialog supports other compatible printers.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontSize: 11,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
