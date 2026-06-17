import 'package:flutter/services.dart';

class CapitalizeOnInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    // Si el texto nuevo no está vacío y el texto antiguo estaba vacío,
    // o si la primera letra del texto nuevo es minúscula, capitalízala.
    if (newValue.text.isNotEmpty && (oldValue.text.isEmpty || newValue.text[0] != newValue.text[0].toUpperCase())) {
      // Capitaliza solo la primera letra del texto.
      final newText = newValue.text[0].toUpperCase() + (newValue.text.length > 1 ? newValue.text.substring(1) : '');
      return newValue.copyWith(
        text: newText,
        selection: TextSelection.collapsed(offset: newText.length),
      );
    }
    return newValue;
  }
}

class UpperCaseTextFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    return newValue.copyWith(text: newValue.text.toUpperCase());
  }
}

extension StringCapitalization on String {
  String toCapitalized() {
    if (isEmpty) return this;
    return this[0].toUpperCase() + substring(1).toLowerCase();
  }
}