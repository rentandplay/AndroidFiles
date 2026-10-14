import 'package:flutter/material.dart';

class ItemModel {
  final String id;
  final String name;
  final String category;
  final String description;
  final String rateText;
  final List<Map<String, dynamic>> rateOptions;
  final double rateHourly;
  final String? specialRate;
  final double? salePrice;
  final double latePenalty;
  final bool isForSale;
  final String imageUrl;
  final String status;
  final String? qrCode;
  final String? stockGroupId;
  final int availableQuantity;
  final int totalQuantity;

  ItemModel({
    required this.id,
    required this.name,
    required this.category,
    required this.description,
    required this.rateText,
    this.rateOptions = const [],
    required this.rateHourly,
    this.specialRate,
    this.salePrice,
    this.latePenalty = 50.0,
    this.isForSale = false,
    required this.imageUrl,
    this.status = 'available',
    this.qrCode,
    this.stockGroupId,
    this.availableQuantity = 1,
    this.totalQuantity = 1,
  });

  String get cleanImageUrl {
    String url = imageUrl.trim();
    if (url.startsWith('assets/assets/')) {
      return url.replaceFirst('assets/assets/', 'assets/');
    }
    if (url.isEmpty) {
      return 'assets/images/logo_rent_and_play.png';
    }
    if (!url.startsWith('assets/') && !url.startsWith('http')) {
      return 'assets/$url';
    }
    return url;
  }

  Widget buildImage(
      {BoxFit fit = BoxFit.cover, double? width, double? height}) {
    final url = cleanImageUrl;
    if (url.startsWith('http://') || url.startsWith('https://')) {
      return Image.network(
        url,
        width: width,
        height: height,
        fit: fit,
        loadingBuilder: (context, child, loadingProgress) {
          if (loadingProgress == null) return child;
          return Container(
            width: width,
            height: height,
            color: Colors.grey.shade100,
            child: const Center(
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          );
        },
        errorBuilder: (context, error, stackTrace) => Container(
          width: width,
          height: height,
          color: Colors.grey.shade200,
          child: const Center(
            child: Icon(Icons.image_not_supported_outlined,
                color: Colors.grey, size: 36),
          ),
        ),
      );
    }
    return Image.asset(
      url,
      width: width,
      height: height,
      fit: fit,
      errorBuilder: (context, error, stackTrace) => Container(
        width: width,
        height: height,
        color: Colors.grey.shade200,
        child: const Center(
          child: Icon(Icons.inventory_2_outlined, color: Colors.grey, size: 36),
        ),
      ),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'category': category,
      'description': description,
      'rateText': rateText,
      'rateOptions': rateOptions,
      'rateHourly': rateHourly,
      'specialRate': specialRate,
      'salePrice': salePrice,
      'latePenalty': latePenalty,
      'isForSale': isForSale,
      'imageUrl': cleanImageUrl,
      'status': status,
      'qrCode': qrCode,
    };
  }

  static String _catalogCategory(String value) {
    final lower = value.toLowerCase();
    if (lower.contains('sport')) return 'Sports';
    if (lower.contains('board')) return 'Board Games';
    if (lower.contains('tech') || lower.contains('gaming')) {
      return 'Tech Rentals';
    }
    if (lower.contains('card')) return 'Cards';
    return value;
  }

  factory ItemModel.fromMap(Map<String, dynamic> map, {String? id}) {
    String rawImageUrl = map['image_url'] ??
        map['imageUrl'] ??
        findByCode(map['name']?.toString() ?? '')?.imageUrl ??
        'assets/images/logo_rent_and_play.png';
    if (rawImageUrl.startsWith('assets/assets/')) {
      rawImageUrl = rawImageUrl.replaceFirst('assets/assets/', 'assets/');
    }

    return ItemModel(
      id: id ?? map['id'] ?? '',
      name: map['name'] ?? '',
      category: _catalogCategory(map['category']?.toString() ?? 'Sports'),
      description:
          map['description'] ?? 'Equipment rental for indoor or outdoor play.',
      rateText: map['rate_text'] ?? map['rateText'] ?? '',
      rateOptions:
          ((map['rate_options'] ?? map['rateOptions']) as List? ?? const [])
              .whereType<Map>()
              .map((option) => Map<String, dynamic>.from(option))
              .toList(growable: false),
      rateHourly: (map['rental_rate'] ?? map['rateHourly'] ?? 0.0).toDouble(),
      specialRate: map['specialRate'],
      salePrice: (map['sale_price'] ?? map['salePrice']) is num
          ? (map['sale_price'] ?? map['salePrice']).toDouble()
          : null,
      latePenalty:
          (map['late_penalty_rate'] ?? map['latePenalty'] ?? 50.0).toDouble(),
      isForSale: map['is_for_sale'] ?? map['isForSale'] ?? false,
      imageUrl: rawImageUrl,
      status: map['can_rent'] == false && map['status'] == 'AVAILABLE'
          ? 'unavailable'
          : map['status'] ?? 'available',
      qrCode: map['item_code'] ?? map['qrCode'] ?? map['qr_code'],
      stockGroupId: map['stock_group_id']?.toString(),
      availableQuantity: (map['available_quantity'] as num?)?.toInt() ?? 1,
      totalQuantity: (map['total_quantity'] as num?)?.toInt() ?? 1,
    );
  }

  ItemModel copyWith({
    String? id,
    String? name,
    String? category,
    String? description,
    String? rateText,
    List<Map<String, dynamic>>? rateOptions,
    double? rateHourly,
    String? specialRate,
    double? salePrice,
    double? latePenalty,
    bool? isForSale,
    String? imageUrl,
    String? status,
    String? qrCode,
    String? stockGroupId,
    int? availableQuantity,
    int? totalQuantity,
  }) {
    return ItemModel(
      id: id ?? this.id,
      name: name ?? this.name,
      category: category ?? this.category,
      description: description ?? this.description,
      rateText: rateText ?? this.rateText,
      rateOptions: rateOptions ?? this.rateOptions,
      rateHourly: rateHourly ?? this.rateHourly,
      specialRate: specialRate ?? this.specialRate,
      salePrice: salePrice ?? this.salePrice,
      latePenalty: latePenalty ?? this.latePenalty,
      isForSale: isForSale ?? this.isForSale,
      imageUrl: imageUrl ?? this.imageUrl,
      status: status ?? this.status,
      qrCode: qrCode ?? this.qrCode,
      stockGroupId: stockGroupId ?? this.stockGroupId,
      availableQuantity: availableQuantity ?? this.availableQuantity,
      totalQuantity: totalQuantity ?? this.totalQuantity,
    );
  }

  /// Looks up equipment by scanned QR code, label code, or ID/name
  static ItemModel? findByCode(String code, {List<ItemModel>? catalog}) {
    final cleanCode = code.trim().toLowerCase();
    if (cleanCode.isEmpty) return null;

    final items = catalog ?? getInitialCatalog();

    // Direct match on ID or qrCode
    for (var item in items) {
      if (item.id.toLowerCase() == cleanCode) return item;
      if (item.qrCode != null && item.qrCode!.toLowerCase() == cleanCode) {
        return item;
      }
    }

    // Exact label aliases mapping from rent-play-qr-labels
    final labelAliases = <String, String>{
      'sport-badminton-001': 'item_badminton',
      'sport-basketball-001': 'item_basketball',
      'sport-bike-001': 'item_bike',
      'sport-bike-002': 'item_bike',
      'card-bingo-001': 'item_bingo',
      'board-chess-001': 'item_chess',
      'card-deck-001': 'item_cards_deck',
      'board-jenga-001': 'item_jenga',
      'sport-pickleball-001': 'item_pickleball',
      'sport-pickleball-002': 'item_pickleball',
      'conso-0001': 'item_ps4',
      'conso-ps4-001': 'item_ps4',
      'board-scrabble-001': 'item_scrabble',
      'card-uno-001': 'item_uno',
      'sport-volleyball-001': 'item_volleyball',
      'conso-switch-001': 'item_switch',
      'conso-ps5-001': 'item_ps5',
      // Raw QR payload codes from HTML labels
      'rentplay:03479080-9': 'item_basketball',
      'rentplay:4155': 'item_jenga',
      'rentplay:068391': 'item_pickleball',
      'rentplay:80544': 'item_uno',
      'rentplay:82655': 'item_volleyball',
    };

    if (labelAliases.containsKey(cleanCode)) {
      final targetId = labelAliases[cleanCode]!;
      return items.firstWhere((item) => item.id == targetId,
          orElse: () => items.first);
    }

    // Keyword matching
    for (var item in items) {
      if (item.name.toLowerCase().contains(cleanCode) ||
          cleanCode.contains(item.name.toLowerCase())) {
        return item;
      }
    }

    return null;
  }

  static List<ItemModel> getInitialCatalog() {
    return [
      ItemModel(
        id: 'item_bike',
        qrCode: 'EQUIP-002',
        name: 'Bicycle',
        category: 'Sports',
        description:
            'Durable 21-speed mountain bike with adjustable seat, helmet, and safety reflectors suitable for all terrains.',
        rateText: '₱150/30m, ₱200/hr, ₱500/3-hrs',
        rateOptions: const [
          {
            'id': 'half-hour',
            'label': '30 minutes',
            'kind': 'SHORT',
            'duration_minutes': 30,
            'amount': 150,
          },
          {
            'id': 'hour',
            'label': 'Per hour',
            'kind': 'HOURLY',
            'duration_minutes': 60,
            'amount': 200,
          },
          {
            'id': 'three-hour-special',
            'label': '3-hour special',
            'kind': 'PACKAGE',
            'duration_minutes': 180,
            'amount': 500,
          },
        ],
        rateHourly: 200.0,
        specialRate: '₱150 / 30 mins | ₱500 / 3 hours',
        isForSale: false,
        imageUrl: 'assets/images/Bike.png',
        status: 'available',
      ),
      ItemModel(
        id: 'item_pickleball',
        qrCode: 'EQUIP-009',
        name: 'Pickleball Set',
        category: 'Sports',
        description:
            'Complete set including 4 lightweight graphite paddles, 6 outdoor pickleballs, and a portable net system.',
        rateText: '₱120/hr',
        rateHourly: 120.0,
        isForSale: false,
        imageUrl: 'assets/images/Pickleball_Set.png',
        status: 'available',
      ),
      ItemModel(
        id: 'item_badminton',
        qrCode: 'EQUIP-001',
        name: 'Badminton Set',
        category: 'Sports',
        description:
            'Includes 4 steel rackets, 6 durable shuttlecocks, and a quick-setup net for outdoor or indoor court play.',
        rateText: '₱100/hr',
        rateHourly: 100.0,
        isForSale: false,
        imageUrl: 'assets/images/Badminton_Set.png',
        status: 'available',
      ),
      ItemModel(
        id: 'item_basketball',
        qrCode: 'EQUIP-003',
        name: 'Basketball',
        category: 'Sports',
        description:
            'Official size 7 indoor/outdoor composite leather basketball with deep channels for superior grip and bounce.',
        rateText: '₱50/hr, ₱200/5-hrs',
        rateHourly: 50.0,
        specialRate: '₱200 / 5 hours',
        isForSale: false,
        imageUrl: 'assets/images/Basketball.png',
        status: 'available',
      ),
      ItemModel(
        id: 'item_volleyball',
        qrCode: 'EQUIP-014',
        name: 'Volleyball',
        category: 'Sports',
        description:
            'Official regulation size 5 soft-touch leather volleyball ideal for beach or indoor court recreational play.',
        rateText: '₱50/hr, ₱200/5-hrs',
        rateHourly: 50.0,
        specialRate: '₱200 / 5 hours',
        isForSale: false,
        imageUrl: 'assets/images/Volleyball.png',
        status: 'available',
      ),

      // Cards
      ItemModel(
        id: 'item_cards_deck',
        qrCode: 'EQUIP-006',
        name: 'Deck of Cards',
        category: 'Cards',
        description:
            'Standard 52-card poker deck made of plastic-coated cardstock for smooth shuffling and long-lasting durability.',
        rateText: 'Rent ₱50/5hrs | Sale ₱150',
        rateHourly: 10.0,
        specialRate: '₱50 / 5 hours',
        salePrice: 150.0,
        isForSale: true,
        imageUrl: 'assets/images/Playing_Cards.png',
        status: 'available',
      ),
      ItemModel(
        id: 'item_uno',
        qrCode: 'EQUIP-013',
        name: 'Uno Cards',
        category: 'Cards',
        description:
            'Classic Uno card game featuring 112 cards including Wild, Draw Four, and custom rule action cards.',
        rateText: 'Rent ₱100/5hrs | Sale ₱300',
        rateHourly: 20.0,
        specialRate: '₱100 / 5 hours',
        salePrice: 300.0,
        isForSale: true,
        imageUrl: 'assets/images/UNO_Cards.png',
        status: 'available',
      ),
      ItemModel(
        id: 'item_bingo',
        qrCode: 'EQUIP-004',
        name: 'Bingo Set',
        category: 'Cards',
        description:
            'Bingo Set: Includes master board, cage, numbered balls, and reusable bingo cards for group entertainment.',
        rateText: 'Rent ₱150/5hrs | Sale ₱450',
        rateHourly: 30.0,
        specialRate: '₱150 / 5 hours',
        salePrice: 450.0,
        isForSale: true,
        imageUrl: 'assets/images/Bingo.png',
        status: 'available',
      ),

      // Board Games
      ItemModel(
        id: 'item_jenga',
        qrCode: 'EQUIP-007',
        name: 'Jenga',
        category: 'Board Games',
        description:
            'Includes 54 precision-crafted hardwood blocks for building tower balance games suitable for all ages.',
        rateText: 'Rent ₱150/5hrs, ₱250 Whole Stay',
        rateHourly: 30.0,
        specialRate:
            '₱150 / 5 hrs | ₱250 Whole Stay (Lost piece penalty: ₱50/piece)',
        isForSale: false,
        imageUrl: 'assets/images/Jenga.png',
        status: 'available',
      ),
      ItemModel(
        id: 'item_scrabble',
        qrCode: 'EQUIP-012',
        name: 'Scrabble',
        category: 'Board Games',
        description:
            'Classic Scrabble crossword game with full letter tile set, 4 tile racks, and folding game board.',
        rateText: 'Rent ₱150/5hrs, ₱250 Whole Stay',
        rateHourly: 30.0,
        specialRate:
            '₱150 / 5 hrs | ₱250 Whole Stay (Lost piece penalty: ₱50/piece)',
        isForSale: false,
        imageUrl: 'assets/images/Scrabble.png',
        status: 'available',
      ),
      ItemModel(
        id: 'item_chess',
        qrCode: 'EQUIP-005',
        name: 'Chess Set',
        category: 'Board Games',
        description:
            'Tournament-grade weighted wooden chess set with 32 hand-carved pieces and folding wooden board.',
        rateText: 'Rent ₱150/5hrs, ₱250 Whole Stay',
        rateHourly: 30.0,
        specialRate:
            '₱150 / 5 hrs | ₱250 Whole Stay (Lost piece penalty: ₱50/piece)',
        isForSale: false,
        imageUrl: 'assets/images/Chess.png',
        status: 'available',
      ),

      // Tech Rentals
      ItemModel(
        id: 'item_ps4',
        qrCode: 'EQUIP-010',
        name: 'PlayStation 4 Console',
        category: 'Tech Rentals',
        description:
            'PS4 Slim 1TB console bundled with 2 DualShock 4 wireless controllers, HDMI cable, and pre-installed top titles.',
        rateText: '₱250/hr',
        rateHourly: 250.0,
        isForSale: false,
        imageUrl: 'assets/images/PS4.png',
        status: 'available',
      ),
      ItemModel(
        id: 'item_switch',
        qrCode: 'EQUIP-008',
        name: 'Nintendo Switch',
        category: 'Tech Rentals',
        description:
            'Nintendo Switch OLED console with Joy-Con controllers, dock, AC adapter, and protective carrying case.',
        rateText: '₱200/hr',
        rateHourly: 200.0,
        isForSale: false,
        imageUrl: 'assets/images/Nintendo_Switch.png',
        status: 'available',
      ),
      ItemModel(
        id: 'item_ps5',
        qrCode: 'EQUIP-011',
        name: 'PlayStation 5 Console',
        category: 'Tech Rentals',
        description:
            'PS5 Disc Edition console with DualSense wireless controller, ultra-high speed SSD, and 4K graphics support.',
        rateText: '₱120/day',
        rateHourly: 120.0,
        specialRate: '₱120 / day',
        isForSale: false,
        imageUrl: 'assets/images/PS4.png',
        status: 'available',
      ),
    ];
  }
}
