import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

class BarcodeScannerSimple extends StatefulWidget {
  final Function(String)? onBarcodeDetected;
  const BarcodeScannerSimple({super.key, this.onBarcodeDetected});

  @override
  State<BarcodeScannerSimple> createState() => _BarcodeScannerSimpleState();
}

class _BarcodeScannerSimpleState extends State<BarcodeScannerSimple> {
  final MobileScannerController _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.normal,
    facing: CameraFacing.back,
  );
  bool _isProcessing = false;

  @override
  Widget build(BuildContext context) {
    // Si no hay callback, envolvemos el escáner en un Scaffold con AppBar.
    if (widget.onBarcodeDetected == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Escanear Código')),
        body: _buildScanner(),
      );
    }
    // Si hay callback, devolvemos solo el escáner para que se pueda incrustar.
    return _buildScanner();
  }

  Widget _buildScanner() {
    return MobileScanner(
      controller: _controller,
      onDetect: (capture) {
        if (_isProcessing) return;

        final barcode = capture.barcodes.firstOrNull?.rawValue;
        if (barcode != null) {
          _isProcessing = true;
          HapticFeedback.lightImpact();

          if (widget.onBarcodeDetected != null) {
            widget.onBarcodeDetected!(barcode);
            // Damos un pequeño respiro para que la UI se actualice antes de permitir otra detección.
            Future.delayed(const Duration(seconds: 1), () {
              if (mounted) setState(() => _isProcessing = false);
            });
          } else if (Navigator.canPop(context)) {
            // Comportamiento original: cerrar y devolver el valor.
            scheduleMicrotask(() => Navigator.of(context).pop(barcode));
          }
        }
      },
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}