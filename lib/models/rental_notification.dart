class RentalNotification {
  const RentalNotification(
      {required this.id,
      required this.type,
      required this.title,
      required this.message,
      required this.rentalId,
      required this.rentalCode,
      required this.createdAt,
      this.isRead = false});
  final String id, type, title, message, rentalId, rentalCode;
  final DateTime createdAt;
  final bool isRead;
  factory RentalNotification.fromMap(Map<String, dynamic> row) =>
      RentalNotification(
          id: row['id'].toString(),
          type: row['type']?.toString() ?? '',
          title: row['title']?.toString() ?? 'Rental update',
          message: row['message']?.toString() ?? '',
          rentalId: row['rental_id']?.toString() ?? '',
          rentalCode: row['rental_code']?.toString() ?? '',
          createdAt: DateTime.tryParse(row['created_at']?.toString() ?? '') ??
              DateTime.fromMillisecondsSinceEpoch(0),
          isRead: row['is_read'] == true);
  RentalNotification read() => RentalNotification(
      id: id,
      type: type,
      title: title,
      message: message,
      rentalId: rentalId,
      rentalCode: rentalCode,
      createdAt: createdAt,
      isRead: true);
}
