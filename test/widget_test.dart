import 'package:flutter_test/flutter_test.dart';

import 'package:seller/stock.dart';

void main() {
  test('sortAlphabetically orders product names case-insensitively', () {
    final sorted = sortAlphabetically(
      ['Zanahoria', 'manzana', 'Banano', 'apio'],
      (name) => name,
    );

    expect(sorted, ['apio', 'Banano', 'manzana', 'Zanahoria']);
  });
}
