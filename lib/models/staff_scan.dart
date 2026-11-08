enum StaffScanMode {
  rental('BOOKING', 'Rental QR',
      'Scan the customer’s rental ticket to review or confirm handoff.'),
  equipment('INVENTORY', 'Equipment QR',
      'Scan the equipment sticker to prepare a unit or receive a return.');

  const StaffScanMode(this.apiKind, this.label, this.instruction);
  final String apiKind, label, instruction;

  static StaffScanMode fromKind(String kind) =>
      kind == 'INVENTORY' ? equipment : rental;
}

/// A manual lookup locates a record; it is never evidence of a physical QR scan.
class StaffScanResult {
  const StaffScanResult(
      {required this.code, required this.mode, this.manual = false});
  final String code;
  final StaffScanMode mode;
  final bool manual;
}

/// Remembers the last mode for this app session without saving customer data.
class StaffScanSession {
  static StaffScanMode lastMode = StaffScanMode.rental;
}
