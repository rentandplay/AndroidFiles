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
  bool _printingMx10 = false;
  String? _mx10PrinterName;

  @override
  void initState() {
    super.initState();
    _mx10PrinterName = Mx10PrinterService.instance.connectedDeviceName;
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

  Future<Map<String, String>?> _chooseMx10Printer(
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
                  'Choose MX10 printer',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                ...printers.map(
                  (printer) => ListTile(
                    leading: const Icon(Icons.print_rounded),
                    title: Text(printer['name'] ?? 'MX10 label printer'),
                    subtitle: Text(printer['id'] ?? ''),
                    onTap: () => Navigator.pop(sheetContext, printer),
                  ),
                ),
              ],
            ),
          ),
        ),
      );

  Future<void> _printOnMx10() async {
    if (_printingMx10 || _payload.isEmpty || widget.qrMatrix == null) return;
    setState(() => _printingMx10 = true);
    try {
      final printerService = Mx10PrinterService.instance;
      if (_mx10PrinterName == null) {
        final printers = await printerService.discoverPrinters();
        if (!mounted) return;
        if (printers.isEmpty) {
          throw Exception('No MX10 printer found. Turn it on and try again.');
        }
        final selected = printers.length == 1
            ? printers.first
            : await _chooseMx10Printer(printers);
        if (!mounted || selected == null) return;
        _mx10PrinterName = await printerService.connect(selected['id'] ?? '');
      }
      await printerService.printLabel(
        code: widget.qrCode,
        name: widget.itemName,
        qrMatrix: widget.qrMatrix!,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Label sent to ${_mx10PrinterName ?? 'MX10'}.')),
        );
      }
    } on PlatformException catch (error) {
      if (mounted) {
        if (error.code == 'printer_disconnected' ||
            error.code == 'print_failed') {
          _mx10PrinterName = null;
          Mx10PrinterService.instance.clearConnection();
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error.message ?? 'MX10 print failed.')),
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
      if (mounted) setState(() => _printingMx10 = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final code =
        widget.qrCode.trim().isEmpty ? 'EQUIPMENT' : widget.qrCode.trim();
    final displayName =
        widget.itemName.trim().isEmpty ? 'Equipment' : widget.itemName.trim();

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
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _printingMx10 || widget.qrMatrix == null
                    ? null
                    : _printOnMx10,
                icon: _printingMx10
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.bluetooth_rounded),
                label: Text(_printingMx10
                    ? (_mx10PrinterName == null ? 'Finding MX10…' : 'Printing…')
                    : _mx10PrinterName == null
                        ? 'Connect & print with MX10'
                        : 'Print with $_mx10PrinterName'),
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
              'MX10 uses Bluetooth. The Android print dialog is available for other compatible printers.',
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
