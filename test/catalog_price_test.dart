import 'package:flutter_test/flutter_test.dart';
import 'package:rent_and_play_app/models/item_model.dart';
import 'package:rent_and_play_app/utils/catalog_price.dart';

ItemModel priced(
        {String text = '', List<Map<String, dynamic>> options = const []}) =>
    ItemModel(
        id: 'gear',
        name: 'Gear',
        category: 'Sports',
        description: '',
        rateText: text,
        rateOptions: options,
        rateHourly: 0,
        imageUrl: '');

void main() {
  test(
      'starting price uses a configured timed package without changing the rate sheet',
      () {
    final item = priced(text: 'Complete rate sheet', options: [
      {'amount': 150, 'label': '5 hours', 'kind': 'TIMED'},
      {'amount': 50, 'label': 'hour', 'kind': 'TIMED'},
      {'amount': 10, 'label': 'Whole stay', 'kind': 'WHOLE_STAY'},
    ]);
    expect(catalogPriceLabel(item), 'From ₱50 / hour');
    expect(item.rateOptions.first['amount'], 150);
    expect(item.rateText, 'Complete rate sheet');
  });

  test(
      'single prices and legacy thousands separators stay accurate, missing rates stay unknown',
      () {
    expect(
        catalogPriceLabel(priced(options: [
          {'amount': 1250.5, 'label': 'day'}
        ])),
        '₱1,250.5 / day');
    expect(catalogPriceLabel(priced(text: '₱1,250 / day · ₱2,000 / 2 days')),
        'From ₱1,250 / day');
    expect(catalogPriceLabel(priced(text: '₱1,250/day, ₱2,000/2 days')),
        'From ₱1,250/day');
    expect(catalogPriceLabel(priced(text: 'Rent ₱150/5hrs')), '₱150/5hrs');
    expect(catalogPriceLabel(priced()), 'View rental rates');
  });
}
