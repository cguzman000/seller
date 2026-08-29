import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:seller/customers.dart';
import 'package:seller/firestore_service.dart';
import 'package:seller/money_format.dart';
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

  test('buildDebtAmountText renders the debt label and amount using configured decimals', () {
    final widget = buildDebtAmountText(
      1234.56,
      onTap: () {},
      debtLabel: 'Deuda',
      decimalPlaces: 2,
    );

    expect(widget, isA<InkWell>());
    final button = widget as InkWell;
    expect(button.onTap, isNotNull);
  });

  test('formatArgentineMoney uses the Argentine pattern with thousands separator and configured decimals', () {
    expect(formatArgentineMoney(1234.56, decimalPlaces: 2), '\$ 1.234,56');
    expect(formatArgentineMoney(1234, decimalPlaces: 0), '\$ 1.234');
  });
}
