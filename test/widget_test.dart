import 'package:flutter_test/flutter_test.dart';

import 'package:seller/firestore_service.dart';
import 'package:seller/stock.dart';

void main() {
  test('sortAlphabetically orders product names case-insensitively', () {
    final sorted = sortAlphabetically(
      ['Zanahoria', 'manzana', 'Banano', 'apio'],
      (name) => name,
    );

    expect(sorted, ['apio', 'Banano', 'manzana', 'Zanahoria']);
  });

  test('ProductImageSize resolves the configured product image preset to pixel dimensions', () {
    expect(ProductImageSize.toPx('200'), 200);
    expect(ProductImageSize.toPx('500'), 500);
    expect(ProductImageSize.toPx('1000'), 1000);
    expect(ProductImageSize.toPx(null), 200);
    expect(ProductImageSize.toPx('unknown'), 200);
  });
}
