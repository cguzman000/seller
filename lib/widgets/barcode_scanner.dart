import 'dart:async';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

class BarcodeScannerSimple extends StatefulWidget {
  const BarcodeScannerSimple({super.key});

  @override
  State<BarcodeScannerSimple> createState() => _BarcodeScannerSimpleState();
}

class _BarcodeScannerSimpleState extends State<BarcodeScannerSimple> {
  bool _isPopping = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Escanear Código')),
      body: MobileScanner(
        onDetect: (capture) async {
          // Si ya estamos en proceso de cerrar la pantalla, ignoramos detecciones adicionales.
          if (_isPopping) return;

          final barcode = capture.barcodes.firstOrNull?.rawValue;
          if (barcode != null && mounted) {
            // Marcamos que estamos por cerrar la pantalla.
            _isPopping = true;
            // Usamos un microtask para asegurar que la navegación ocurra de forma segura.
            scheduleMicrotask(() => Navigator.of(context).pop(barcode));
          }
        },
      ),
    );
  }
}