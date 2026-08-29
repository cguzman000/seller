import 'package:intl/intl.dart';

String formatArgentineMoney(double value, {int decimalPlaces = 2}) {
  final safeDecimalPlaces = decimalPlaces.clamp(0, 6);
  final formattedNumber = NumberFormat.decimalPatternDigits(
    locale: 'es_AR',
    decimalDigits: safeDecimalPlaces,
  ).format(value);

  return '\$ $formattedNumber';
}

String formatArgentineNumber(double value, {int decimalPlaces = 2}) {
  final safeDecimalPlaces = decimalPlaces.clamp(0, 6);
  return NumberFormat.decimalPatternDigits(
    locale: 'es_AR',
    decimalDigits: safeDecimalPlaces,
  ).format(value);
}
