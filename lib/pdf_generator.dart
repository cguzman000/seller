import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:seller/app_localizations.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'firestore_service.dart';

class PdfGenerator {
  static Future<void> generateCatalog({
    required AppLocalizations l10n,
    required String businessId,
    required List<DocumentSnapshot> products,
    required Map<String, String> categoryMap,
    required double vatRate,
    String? companyName,
    String? companyLogoUrl,
    String? sellerName,
    String? sellerPhone,
    required Map<String, String> supplierMap,
    String? groupBy,
    String? catalogTitle,
    String? categoryFilterName,
    String? supplierFilterName,
  }) async {
    final pdf = pw.Document();
    final now = DateTime.now();
    final formattedDate = DateFormat('dd/MM/yyyy HH:mm').format(now);
    final baseColor = PdfColors.blue900;
    final firestoreService = FirestoreService();

    // OPTIMIZACIÓN: Obtener todas las ofertas para los productos de la lista en lotes.
    // Esto evita hacer una consulta a la base de datos por cada producto.
    final productIds = products.map((doc) => doc.id).toList();
    final Map<String, List<QueryDocumentSnapshot>> offersByProduct = {};

    if (productIds.isNotEmpty) {
      final firestore = FirebaseFirestore.instance;
      const batchSize = 30; // Límite de Firestore para consultas 'in'

      for (int i = 0; i < productIds.length; i += batchSize) {
        final sublist = productIds.sublist(i, i + batchSize > productIds.length ? productIds.length : i + batchSize);
        
        // Usamos una consulta de grupo de colección para buscar en todas las subcolecciones 'offers'.
        // Esto requiere que los documentos de oferta tengan un campo 'businessId' y 'productId'.
        // También necesitará un índice compuesto en Firestore.
        final offersSnapshot = await firestore
            .collection('offers')
            .where('userId', isEqualTo: businessId)
            .where('productId', whereIn: sublist)
            .get();

        for (final offerDoc in offersSnapshot.docs) {
          final offerData = offerDoc.data();
          final productId = offerData['productId'] as String?;
          if (productId != null) {
            (offersByProduct[productId] ??= []).add(offerDoc);
          }
        }
      }
    }

    String? finalLogoUrl = companyLogoUrl;
    if (finalLogoUrl == null && products.isNotEmpty) {
      try {
        final settingsDoc = await firestoreService.getCompanySettings(businessId).first;
        if (settingsDoc.exists) {
          final settingsData = settingsDoc.data() as Map<String, dynamic>;
          finalLogoUrl = settingsData['company_logo_url'];
        }
      } catch (_) {}
    }

    pw.ImageProvider? logoImage;
    if (finalLogoUrl != null && finalLogoUrl.isNotEmpty) {
      try {
        logoImage = await networkImage(finalLogoUrl);
      } catch (_) {}
    }

    // Función auxiliar para generar la fila de un producto
    Future<List<dynamic>> generateProductRow(DocumentSnapshot doc) async {
      final data = doc.data() as Map<String, dynamic>;
      final categoryName = categoryMap[data['categoryId']] ?? '${l10n.get('no')} ${l10n.get('category')}';
      final description = data['description'] as String?;
      final netPrice = (data['price'] as num?)?.toDouble() ?? 0.0;
      final priceWithVat = netPrice * (1 + vatRate);

      final productOffers = offersByProduct[doc.id] ?? [];

      // Ordenar las ofertas por cantidad de menor a mayor
      productOffers.sort((a, b) {
        final dataA = a.data() as Map<String, dynamic>;
        final dataB = b.data() as Map<String, dynamic>;
        final qtyA = (dataA['quantity'] as num?)?.toDouble() ?? 0.0;
        final qtyB = (dataB['quantity'] as num?)?.toDouble() ?? 0.0;
        return qtyA.compareTo(qtyB);
      });

      final List<pw.Widget> priceWidgets = [
        pw.Text('\$${priceWithVat.toStringAsFixed(0)}'),
        pw.Text('(Neto: \$${netPrice.toStringAsFixed(2)})',
            style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600)),
      ];

      if (productOffers.isNotEmpty) {
        priceWidgets.add(pw.SizedBox(height: 2));
        priceWidgets.add(pw.Text(l10n.get('offers'),
            style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, color: PdfColors.red800)));
        for (var offerDoc in productOffers) {
          final offerData = offerDoc.data() as Map<String, dynamic>;
          final qty = (offerData['quantity'] as num?)?.toDouble() ?? 0.0;
          final offerNetPrice = (offerData['price'] as num?)?.toDouble() ?? 0.0;
          final offerPriceWithVat = offerNetPrice * (1 + vatRate);
          priceWidgets.add(
            pw.Container(
              margin: const pw.EdgeInsets.only(top: 2),
              padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: pw.BoxDecoration(
                color: PdfColors.red50,
                borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
                border: pw.Border.all(color: PdfColors.red200),
              ),
              child: pw.Text(
                'x${qty.toStringAsFixed(0)}: \$${offerPriceWithVat.toStringAsFixed(0)} \n(Neto: \$${offerNetPrice.toStringAsFixed(2)})',
                style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, color: PdfColors.red800),
              ),
            ),
          );
        }
      }

      // Placeholder para la imagen en caso de que un producto no la tenga
      pw.Widget imageWidget = pw.Container(
        width: 75,
        height: 75,
        decoration: pw.BoxDecoration(
          color: PdfColors.grey200,
          borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
        ),
      );

      if (data['imageUrl'] != null && (data['imageUrl'] as String).isNotEmpty) {
        try {
          final provider = await networkImage(data['imageUrl']);
          imageWidget = pw.SizedBox(
            width: 75,
            height: 75,
            child: pw.ClipRRect(
              horizontalRadius: 8, // Radio para redondear las esquinas
              verticalRadius: 8,  // Radio para redondear las esquinas
              child: pw.Image(provider, fit: pw.BoxFit.cover),
            ),
          );
        } catch (e) {
          // Si falla la carga de la imagen, se usará el placeholder gris de arriba
        }
      }

      final unitsBox = (data['units_box'] as num?)?.toInt() ?? 0;
      final productName = data['name'] ?? 'Sin nombre';
      final productDisplayName = unitsBox > 1
          ? '$productName ${l10n.get('unitsPerBox').replaceFirst('{count}', unitsBox.toString())}'
          : productName;

      return [
        imageWidget,
        pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(productDisplayName),
            pw.Text(categoryName, style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700)),
            if (description != null && description.trim().isNotEmpty)
              pw.Text('${l10n.get('description')}: $description',
                  textAlign: pw.TextAlign.justify,
                  style: pw.TextStyle(fontSize: 8, fontStyle: pw.FontStyle.italic)),
          ],
        ),
        pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          mainAxisSize: pw.MainAxisSize.min,
          children: priceWidgets,
        ),
      ];
    }

    final List<pw.Widget> content = [];

    // Cabecera del Documento
    content.add(
      pw.Header(
        level: 0,
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.center,
              children: [
                if (logoImage != null) ...[
                  pw.Image(logoImage, width: 50, height: 50),
                  pw.SizedBox(width: 15),
                ],
                
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(companyName ?? 'Catálogo de Productos',
                        style: pw.TextStyle(
                            fontSize: 24,
                            fontWeight: pw.FontWeight.bold,
                            color: baseColor)),
                    if (companyName != null)
                      pw.Text('Lista de Precios',
                          style: pw.TextStyle(fontSize: 18, color: PdfColors.grey700)),
                    if (catalogTitle != null) ...[
                      pw.SizedBox(height: 8),
                      pw.Text(catalogTitle,
                          style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold, color: baseColor)),
                    ],
                    if (categoryFilterName != null) ...[
                      pw.SizedBox(height: 8),
                      pw.Text(categoryFilterName,
                          style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold, color: baseColor)),
                    ],
                    if (supplierFilterName != null) ...[
                      pw.SizedBox(height: 8),
                      pw.Text('Proveedor: $supplierFilterName',
                          style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold, color: baseColor)),
                    ],
                  ],
                ),
              ],
            ),
            pw.SizedBox(height: 5),
            pw.Divider(color: baseColor, thickness: 2),
          ],
        ),
      ),
    );

    // Lógica de Agrupación y Generación de Tablas
    if (groupBy != null) {
      final Map<String, List<DocumentSnapshot>> groupedProducts = {};
      for (var doc in products) {
        final data = doc.data() as Map<String, dynamic>;
        String key;
        if (groupBy == 'category') {
          key = data['categoryId'] ?? 'null';
        } else {
          key = data['supplierId'] ?? 'null';
        }
        if (!groupedProducts.containsKey(key)) groupedProducts[key] = [];
        groupedProducts[key]!.add(doc);
      }

      final sortedKeys = groupedProducts.keys.toList()..sort((a, b) {
        if (a == 'null') return 1;
        if (b == 'null') return -1;
        String nameA = (groupBy == 'category' ? categoryMap[a] : supplierMap[a]) ?? '';
        String nameB = (groupBy == 'category' ? categoryMap[b] : supplierMap[b]) ?? '';
        return nameA.toLowerCase().compareTo(nameB.toLowerCase());
      });

      bool isFirstGroup = true;
      for (var key in sortedKeys) {
        final groupName = key == 'null' ? 
            '${l10n.get('no')} ${l10n.get(groupBy == 'category' ? 'category' : 'supplier')}' : 
            (groupBy == 'category' ? categoryMap[key] : supplierMap[key]) ?? 'Desconocido';

        if (!isFirstGroup) {
          content.add(pw.SizedBox(height: 1));
          content.add(pw.NewPage());//NUEVO PÁGINA ENTRE GRUPOS
        }
        isFirstGroup = false;

        content.add(pw.SizedBox(height: 10));
        content.add(pw.Header(
          level: 1,
          child: pw.Text(groupName, style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold, color: baseColor)),
        ));
        content.add(pw.SizedBox(height: 5));

        final groupDocs = groupedProducts[key]!;
        // Aseguramos orden alfabético dentro del grupo
        groupDocs.sort((a, b) {
           final dA = a.data() as Map<String, dynamic>;
           final dB = b.data() as Map<String, dynamic>;
           return (dA['name'] ?? '').toString().toLowerCase().compareTo((dB['name'] ?? '').toString().toLowerCase());
        });

        final tableData = await Future.wait(groupDocs.map((doc) => generateProductRow(doc)));

        content.add(pw.TableHelper.fromTextArray(
          border: null,
          headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10, color: baseColor),
          cellStyle: const pw.TextStyle(fontSize: 10),
          headerDecoration: const pw.BoxDecoration(color: PdfColors.white),
          cellAlignment: pw.Alignment.centerLeft,
          cellAlignments: {2: pw.Alignment.centerRight},
          headerAlignments: {2: pw.Alignment.centerRight},
          cellPadding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 8),
          oddRowDecoration: const pw.BoxDecoration(color: PdfColors.grey100),
          headers: ['', l10n.get('productHeader'), l10n.get('total')],
          data: tableData,
          columnWidths: {
            0: const pw.FixedColumnWidth(85),
            1: const pw.FlexColumnWidth(),
            2: const pw.IntrinsicColumnWidth(),
          },
        ));
      }
    } else {
      // Sin agrupar
      final tableData = await Future.wait(products.map((doc) => generateProductRow(doc)));
      content.add(pw.TableHelper.fromTextArray(
        border: null,
        headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10, color: baseColor),
        cellStyle: const pw.TextStyle(fontSize: 10),
        headerDecoration: const pw.BoxDecoration(color: PdfColors.white),
        cellAlignment: pw.Alignment.centerLeft,
        cellAlignments: {2: pw.Alignment.centerRight},
        headerAlignments: {2: pw.Alignment.centerRight},
        cellPadding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 8),
        oddRowDecoration: const pw.BoxDecoration(color: PdfColors.grey100),
        headers: ['', l10n.get('productHeader'), l10n.get('total')],
        data: tableData,
        columnWidths: {
          0: const pw.FixedColumnWidth(85),
          1: const pw.FlexColumnWidth(),
          2: const pw.IntrinsicColumnWidth(),
        },
      ));
    }

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        orientation: pw.PageOrientation.portrait,
        header: (pw.Context context) {
          if (context.pageNumber == 1) return pw.SizedBox();
          return pw.Container(
            alignment: pw.Alignment.centerRight,
            margin: const pw.EdgeInsets.only(bottom: 3.0 * PdfPageFormat.mm),
            child: pw.Text(
                'Catálogo - ${companyName ?? 'Seller App'} | Pág. ${context.pageNumber}',
                style: pw.Theme.of(context)
                    .defaultTextStyle
                    .copyWith(color: PdfColors.grey)),
          );
        },
        footer: (pw.Context context) {
          return pw.Container(
            alignment: pw.Alignment.centerRight,
            margin: const pw.EdgeInsets.only(top: 1.0 * PdfPageFormat.cm),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              mainAxisSize: pw.MainAxisSize.min,
              children: [
                if (sellerName != null || (sellerPhone != null && sellerPhone.isNotEmpty))
                  pw.Text(
                    'Atendido por: ${sellerName ?? ''} ${sellerPhone != null && sellerPhone.isNotEmpty ? ' - Tel: $sellerPhone' : ''}',
                    style: pw.Theme.of(context).defaultTextStyle.copyWith(color: PdfColors.grey800, fontSize: 10, fontWeight: pw.FontWeight.bold),
                  ),
                pw.SizedBox(height: 4),
                pw.Text(
                    'Generado el $formattedDate - Página ${context.pageNumber} de ${context.pagesCount}',
                    style: pw.Theme.of(context).defaultTextStyle.copyWith(color: PdfColors.grey, fontSize: 10)),
              ],
            ),
          );
        },
        build: (pw.Context context) => content,
      ),
    );

    // 4. Mostrar la vista previa de impresión
    await Printing.layoutPdf(
        onLayout: (PdfPageFormat format) async => pdf.save());
  }

  static Future<void> generateInventoryReport({
    required AppLocalizations l10n,
    required String businessId,
    required List<DocumentSnapshot> products,
  }) async {
    final pdf = pw.Document();
    final now = DateTime.now();
    final formattedDate = DateFormat('dd/MM/yyyy HH:mm').format(now);
    final baseColor = PdfColors.blue900;
    final firestoreService = FirestoreService();

    // Obtener configuración de la empresa (nombre y logo)
    String? companyName;
    String? companyLogoUrl;
    try {
      final settingsDoc = await firestoreService.getCompanySettings(businessId).first;
      if (settingsDoc.exists) {
        final settingsData = settingsDoc.data() as Map<String, dynamic>;
        companyName = settingsData['company_name'];
        companyLogoUrl = settingsData['company_logo_url'];
      }
    } catch (_) {}

    pw.ImageProvider? logoImage;
    if (companyLogoUrl != null && companyLogoUrl.isNotEmpty) {
      try {
        logoImage = await networkImage(companyLogoUrl);
      } catch (_) {}
    }

    // Preparar datos
    double totalInventoryValue = 0.0;
    int totalItems = 0;

    final dataList = products.map((doc) {
      final data = doc.data() as Map<String, dynamic>;
      final unitsBox = (data['units_box'] as num?)?.toInt() ?? 0;
      final productName = data['name'] ?? 'Sin nombre';
      final productDisplayName = unitsBox > 1
          ? '$productName ${l10n.get('unitsPerBox').replaceFirst('{count}', unitsBox.toString())}'
          : productName;
      final stock = (data['stock'] as num?)?.toInt() ?? 0;
      final cost = (data['purch_price'] as num?)?.toDouble() ?? 0.0;
      final total = stock * cost;

      if (stock > 0) {
        totalInventoryValue += total;
        totalItems += stock;
      }

      return [
        productDisplayName,
        stock.toString(),
        '\$${NumberFormat.currency(locale: 'es_CL', symbol: '', decimalDigits: 0).format(cost)}',
        '\$${NumberFormat.currency(locale: 'es_CL', symbol: '', decimalDigits: 0).format(total)}',
      ];
    }).toList();

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        header: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Row(
              children: [
                if (logoImage != null) ...[
                  pw.Image(logoImage, width: 40, height: 40),
                  pw.SizedBox(width: 10),
                ],
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(companyName ?? 'Reporte de Inventario', style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold, color: baseColor)),
                    pw.Text('Generado: $formattedDate', style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700)),
                  ],
                ),
              ],
            ),
            pw.SizedBox(height: 10),
            pw.Divider(color: baseColor),
            pw.SizedBox(height: 10),
          ],
        ),
        build: (context) => [
          pw.TableHelper.fromTextArray(
            headers: [l10n.get('productHeader'), l10n.get('stock'), l10n.get('costValue'), l10n.get('total')],
            data: dataList,
            headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.white),
            headerDecoration: pw.BoxDecoration(color: baseColor),
            cellAlignment: pw.Alignment.centerLeft,
            cellAlignments: {
              1: pw.Alignment.centerRight,
              2: pw.Alignment.centerRight,
              3: pw.Alignment.centerRight,
            },
            oddRowDecoration: const pw.BoxDecoration(color: PdfColors.grey100),
          ),
          pw.SizedBox(height: 20),
          pw.Container(
            alignment: pw.Alignment.centerRight,
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: [
                pw.Text('Total Unidades: $totalItems', style: const pw.TextStyle(fontSize: 12)),
                pw.Text('Valor Total Inventario: \$${NumberFormat.currency(locale: 'es_CL', symbol: '', decimalDigits: 0).format(totalInventoryValue)}', style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold, color: baseColor)),
              ],
            ),
          ),
        ],
        footer: (context) => pw.Container(
          alignment: pw.Alignment.centerRight,
          margin: const pw.EdgeInsets.only(top: 10),
          child: pw.Text('Página ${context.pageNumber} de ${context.pagesCount}', style: const pw.TextStyle(color: PdfColors.grey)),
        ),
      ),
    );

    await Printing.layoutPdf(onLayout: (format) => pdf.save());
  }

  static Future<void> generateSalesReport({
    required String businessId,
    required List<DocumentSnapshot> sales,
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    final pdf = pw.Document();
    final now = DateTime.now();
    final formattedDate = DateFormat('dd/MM/yyyy HH:mm').format(now);
    final baseColor = PdfColors.blue900;
    final firestoreService = FirestoreService();

    // Obtener configuración de la empresa
    String? companyName;
    String? companyLogoUrl;
    try {
      final settingsDoc = await firestoreService.getCompanySettings(businessId).first;
      if (settingsDoc.exists) {
        final settingsData = settingsDoc.data() as Map<String, dynamic>;
        companyName = settingsData['company_name'];
        companyLogoUrl = settingsData['company_logo_url'];
      }
    } catch (_) {}

    pw.ImageProvider? logoImage;
    if (companyLogoUrl != null && companyLogoUrl.isNotEmpty) {
      try {
        logoImage = await networkImage(companyLogoUrl);
      } catch (_) {}
    }

    double totalSales = 0.0;
    final dataList = sales.map((doc) {
      final data = doc.data() as Map<String, dynamic>;
      final date = (data['saleDate'] as Timestamp).toDate();
      final customer = data['customerName'] ?? 'Cliente';
      final total = (data['totalAmount'] as num).toDouble();
      totalSales += total;

      return [
        DateFormat('dd/MM/yyyy HH:mm').format(date),
        customer,
        '\$${NumberFormat.currency(locale: 'es_CL', symbol: '', decimalDigits: 0).format(total)}',
      ];
    }).toList();

    String periodText = 'Histórico completo';
    if (startDate != null && endDate != null) {
      periodText = '${DateFormat('dd/MM/yyyy').format(startDate)} - ${DateFormat('dd/MM/yyyy').format(endDate)}';
    }

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        header: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Row(
              children: [
                if (logoImage != null) ...[
                  pw.Image(logoImage, width: 40, height: 40),
                  pw.SizedBox(width: 10),
                ],
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(companyName ?? 'Reporte de Ventas', style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold, color: baseColor)),
                    pw.Text('Período: $periodText', style: const pw.TextStyle(fontSize: 12)),
                    pw.Text('Generado: $formattedDate', style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700)),
                  ],
                ),
              ],
            ),
            pw.SizedBox(height: 10),
            pw.Divider(color: baseColor),
            pw.SizedBox(height: 10),
          ],
        ),
        build: (context) => [
          pw.TableHelper.fromTextArray(
            headers: ['Fecha', 'Cliente', 'Total'],
            data: dataList,
            headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.white),
            headerDecoration: pw.BoxDecoration(color: baseColor),
            cellAlignment: pw.Alignment.centerLeft,
            cellAlignments: {
              2: pw.Alignment.centerRight,
            },
            oddRowDecoration: const pw.BoxDecoration(color: PdfColors.grey100),
          ),
          pw.SizedBox(height: 20),
          pw.Container(
            alignment: pw.Alignment.centerRight,
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: [
                pw.Text('Transacciones: ${sales.length}', style: const pw.TextStyle(fontSize: 12)),
                pw.Text('Total Ventas: \$${NumberFormat.currency(locale: 'es_CL', symbol: '', decimalDigits: 0).format(totalSales)}', style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold, color: baseColor)),
              ],
            ),
          ),
        ],
        footer: (context) => pw.Container(
          alignment: pw.Alignment.centerRight,
          margin: const pw.EdgeInsets.only(top: 10),
          child: pw.Text('Página ${context.pageNumber} de ${context.pagesCount}', style: const pw.TextStyle(color: PdfColors.grey)),
        ),
      ),
    );

    await Printing.layoutPdf(onLayout: (format) => pdf.save());
  }

  static Future<void> generateDebtorsReport({
    required String businessId,
    required List<Map<String, dynamic>> debtors,
  }) async {
    final pdf = pw.Document();
    final now = DateTime.now();
    final formattedDate = DateFormat('dd/MM/yyyy HH:mm').format(now);
    final baseColor = PdfColors.blue900;
    final firestoreService = FirestoreService();

    // Obtener configuración de la empresa
    String? companyName;
    String? companyLogoUrl;
    try {
      final settingsDoc = await firestoreService.getCompanySettings(businessId).first;
      if (settingsDoc.exists) {
        final settingsData = settingsDoc.data() as Map<String, dynamic>;
        companyName = settingsData['company_name'];
        companyLogoUrl = settingsData['company_logo_url'];
      }
    } catch (_) {}

    pw.ImageProvider? logoImage;
    if (companyLogoUrl != null && companyLogoUrl.isNotEmpty) {
      try {
        logoImage = await networkImage(companyLogoUrl);
      } catch (_) {}
    }

    double totalDebt = 0.0;
    final dataList = debtors.map((d) {
      final debt = (d['debt'] as num).toDouble();
      totalDebt += debt;
      return [
        d['name'],
        '\$${NumberFormat.currency(locale: 'es_CL', symbol: '', decimalDigits: 0).format(debt)}',
      ];
    }).toList();

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        header: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Row(
              children: [
                if (logoImage != null) ...[
                  pw.Image(logoImage, width: 40, height: 40),
                  pw.SizedBox(width: 10),
                ],
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(companyName ?? 'Reporte de Cuentas por Cobrar', style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold, color: baseColor)),
                    pw.Text('Generado: $formattedDate', style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700)),
                  ],
                ),
              ],
            ),
            pw.SizedBox(height: 10),
            pw.Divider(color: baseColor),
            pw.SizedBox(height: 10),
          ],
        ),
        build: (context) => [
          pw.TableHelper.fromTextArray(
            headers: ['Cliente', 'Deuda Pendiente'],
            data: dataList,
            headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.white),
            headerDecoration: pw.BoxDecoration(color: baseColor),
            cellAlignment: pw.Alignment.centerLeft,
            cellAlignments: {
              1: pw.Alignment.centerRight,
            },
            oddRowDecoration: const pw.BoxDecoration(color: PdfColors.grey100),
          ),
          pw.SizedBox(height: 20),
          pw.Container(
            alignment: pw.Alignment.centerRight,
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: [
                pw.Text('Clientes con deuda: ${debtors.length}', style: const pw.TextStyle(fontSize: 12)),
                pw.Text('Total por Cobrar: \$${NumberFormat.currency(locale: 'es_CL', symbol: '', decimalDigits: 0).format(totalDebt)}', style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold, color: PdfColors.red)),
              ],
            ),
          ),
        ],
        footer: (context) => pw.Container(
          alignment: pw.Alignment.centerRight,
          margin: const pw.EdgeInsets.only(top: 10),
          child: pw.Text('Página ${context.pageNumber} de ${context.pagesCount}', style: const pw.TextStyle(color: PdfColors.grey)),
        ),
      ),
    );

    await Printing.layoutPdf(onLayout: (format) => pdf.save());
  }

  static Future<void> generateFinancialSummaryReport({
    required AppLocalizations l10n,
    required String businessId,
    required List<DocumentSnapshot> sales,
    required List<DocumentSnapshot> payments,
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    final pdf = pw.Document();
    final now = DateTime.now();
    final formattedDate = DateFormat('dd/MM/yyyy HH:mm').format(now);
    final baseColor = PdfColors.blue900;
    final firestoreService = FirestoreService();

    // Obtener configuración de la empresa
    String? companyName;
    String? companyLogoUrl;
    try {
      final settingsDoc = await firestoreService.getCompanySettings(businessId).first;
      if (settingsDoc.exists) {
        final settingsData = settingsDoc.data() as Map<String, dynamic>;
        companyName = settingsData['company_name'];
        companyLogoUrl = settingsData['company_logo_url'];
      }
    } catch (_) {}

    pw.ImageProvider? logoImage;
    if (companyLogoUrl != null && companyLogoUrl.isNotEmpty) {
      try {
        logoImage = await networkImage(companyLogoUrl);
      } catch (_) {}
    }

    // Cálculos
    final List<Map<String, dynamic>> combinedList = [];
    final Map<String, String> saleNumMap = {
      for (var doc in sales) doc.id: (doc.data() as Map<String, dynamic>)['sale_number']?.toString() ?? ''
    };

    double totalSales = 0.0;
    for (var doc in sales) {
      final data = doc.data() as Map<String, dynamic>;
      final amount = (data['totalAmount'] as num).toDouble();
      totalSales += amount;
      combinedList.add({
        'date': (data['saleDate'] as Timestamp).toDate(),
        'customer': (data['customerName'] as String? ?? 'N/A').toUpperCase(),
        'saleNumber': data['sale_number']?.toString() ?? '',
        'saleAmount': amount,
        'paymentAmount': 0.0,
      });
    }

    double totalCash = 0.0;
    double totalBank = 0.0;
    for (var doc in payments) {
      final data = doc.data() as Map<String, dynamic>;
      final amount = (data['amount'] as num).toDouble();
      if (data['payment_type'] == 'Efectivo') {
        totalCash += amount;
      } else {
        totalBank += amount;
      }
      combinedList.add({
        'date': (data['date'] as Timestamp).toDate(),
        'customer': (data['customerName'] as String? ?? 'N/A').toUpperCase(),
        'saleNumber': saleNumMap[data['saleId']] ?? data['sale_number']?.toString() ?? '',
        'saleAmount': 0.0,
        'paymentAmount': amount,
      });
    }
    double totalPayments = totalCash + totalBank;

    combinedList.sort((a, b) => b['date'].compareTo(a['date']));

    String periodText = 'Histórico completo';
    if (startDate != null && endDate != null) {
      periodText = '${DateFormat('dd/MM/yyyy').format(startDate)} - ${DateFormat('dd/MM/yyyy').format(endDate)}';
    }

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        header: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Row(
              children: [
                if (logoImage != null) ...[
                  pw.Image(logoImage, width: 40, height: 40),
                  pw.SizedBox(width: 10),
                ],
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(companyName ?? l10n.get('salesAndPaymentsReport'), style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold, color: baseColor)),
                    pw.Text('Período: $periodText', style: const pw.TextStyle(fontSize: 12)),
                  ],
                ),
              ],
            ),
            pw.SizedBox(height: 10),
            pw.Divider(color: baseColor),
            pw.SizedBox(height: 10),
          ],
        ),
        build: (context) => [
          // Resumen
          pw.Header(level: 1, text: l10n.get('financialSummary')),
          pw.Container(
            padding: const pw.EdgeInsets.all(10),
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: PdfColors.grey300),
              borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
            ),
            child: pw.Column(
              children: [
                _summaryRow(l10n.get('totalSales'), totalSales, isBold: true),
                pw.Divider(),
                _summaryRow('${l10n.get('totalPayments')} (${l10n.get('cash')})', totalCash),
                _summaryRow('${l10n.get('totalPayments')} (${l10n.get('bank')})', totalBank),
                _summaryRow(l10n.get('totalPayments'), totalPayments, color: PdfColors.green800, isBold: true),
              ],
            ),
          ),
          pw.SizedBox(height: 20),

          // Lista de Ventas
          pw.Header(level: 1, text: l10n.get('salesAndPaymentsReport')),
          pw.TableHelper.fromTextArray(
            headers: [l10n.get('date'), 'ID', l10n.get('customerLabel'), l10n.get('sales'), l10n.get('payments')],
            data: combinedList.map((item) {
              return [
                DateFormat('dd/MM/yy').format(item['date']),
                item['saleNumber'],
                item['customer'],
                item['saleAmount'] > 0 ? '\$${NumberFormat.currency(locale: 'es_CL', symbol: '', decimalDigits: 0).format(item['saleAmount']).trim()}' : '',
                item['paymentAmount'] > 0 ? '\$${NumberFormat.currency(locale: 'es_CL', symbol: '', decimalDigits: 0).format(item['paymentAmount']).trim()}' : '',
              ];
            }).toList(),
            headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.white),
            headerDecoration: pw.BoxDecoration(color: baseColor),
            cellAlignments: {
              3: pw.Alignment.centerRight,
              4: pw.Alignment.centerRight,
            },
          ),
        ],
        footer: (context) => pw.Container(
          alignment: pw.Alignment.centerRight,
          margin: const pw.EdgeInsets.only(top: 10),
          child: pw.Text('Generado: $formattedDate - Página ${context.pageNumber}', style: const pw.TextStyle(color: PdfColors.grey, fontSize: 8)),
        ),
      ),
    );

    await Printing.layoutPdf(onLayout: (format) => pdf.save());
  }

  static pw.Widget _summaryRow(String label, double value, {bool isBold = false, PdfColor? color}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 2),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(label, style: pw.TextStyle(fontWeight: isBold ? pw.FontWeight.bold : pw.FontWeight.normal)),
          pw.Text(
            '\$${NumberFormat.currency(locale: 'es_CL', symbol: '', decimalDigits: 0).format(value).trim()}',
            style: pw.TextStyle(
              fontWeight: isBold ? pw.FontWeight.bold : pw.FontWeight.normal,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  static Future<void> generateSalesByProductReport({
    required AppLocalizations l10n,
    required String businessId,
    required List<Map<String, dynamic>> productSales,
    required double totalSales,
    required Uint8List chartImage,
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    final pdf = pw.Document();
    final now = DateTime.now();
    final formattedDate = DateFormat('dd/MM/yyyy HH:mm').format(now);
    final baseColor = PdfColors.blue900;
    final firestoreService = FirestoreService();

    // Obtener configuración de la empresa
    String? companyName;
    String? companyLogoUrl;
    try {
      final settingsDoc = await firestoreService.getCompanySettings(businessId).first;
      if (settingsDoc.exists) {
        final settingsData = settingsDoc.data() as Map<String, dynamic>;
        companyName = settingsData['company_name'];
        companyLogoUrl = settingsData['company_logo_url'];
      }
    } catch (_) {}

    pw.ImageProvider? logoImage;
    if (companyLogoUrl != null && companyLogoUrl.isNotEmpty) {
      try {
        logoImage = await networkImage(companyLogoUrl);
      } catch (_) {}
    }

    String periodText = l10n.get('all');
    if (startDate != null && endDate != null) {
      periodText = '${DateFormat('dd/MM/yyyy').format(startDate)} - ${DateFormat('dd/MM/yyyy').format(endDate)}';
    }

    final chartProvider = pw.MemoryImage(chartImage);

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        header: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Row(
              children: [
                if (logoImage != null) ...[
                  pw.Image(logoImage, width: 40, height: 40),
                  pw.SizedBox(width: 10),
                ],
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(companyName ?? l10n.get('salesByProduct'), style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold, color: baseColor)),
                    pw.Text('${l10n.get('filter')}: $periodText', style: const pw.TextStyle(fontSize: 12)),
                  ],
                ),
              ],
            ),
            pw.SizedBox(height: 10),
            pw.Divider(color: baseColor),
            pw.SizedBox(height: 10),
          ],
        ),
        build: (context) => [
          pw.Header(level: 1, text: l10n.get('salesByProduct')),
          pw.SizedBox(height: 10),
          pw.Center(
            child: pw.SizedBox(
              width: 300,
              height: 300,
              child: pw.Image(chartProvider),
            ),
          ),
          pw.SizedBox(height: 20),
          pw.TableHelper.fromTextArray(
            headers: ['', l10n.get('productHeader'), l10n.get('quantityHeader'), l10n.get('total')],
            data: productSales.asMap().entries.map((entry) {
              final index = entry.key;
              final p = entry.value;
              final List<PdfColor> pdfPieColors = [
                PdfColors.blue400,
                PdfColors.green400,
                PdfColors.orange400,
                PdfColors.red400,
                PdfColors.purple400,
                PdfColors.grey400,
              ];
              final color = pdfPieColors[index % pdfPieColors.length];

              return [
                pw.Container(
                  width: 12,
                  height: 12,
                  decoration: pw.BoxDecoration(color: color, shape: pw.BoxShape.circle),
                ),
                pw.Text(p['name'].toString().toUpperCase(), textAlign: pw.TextAlign.left),
                pw.Text(p['quantity'].toStringAsFixed(0), textAlign: pw.TextAlign.right),
                pw.Text('\$${NumberFormat.currency(locale: 'es_CL', symbol: '', decimalDigits: 0).format(p['total'])}', textAlign: pw.TextAlign.right),
              ];
            }).toList(),
            headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.white),
            headerDecoration: pw.BoxDecoration(color: baseColor),
            cellAlignment: pw.Alignment.centerLeft,
            cellAlignments: {
              1: pw.Alignment.centerRight,
              2: pw.Alignment.centerLeft,
              3: pw.Alignment.centerRight,
            },
            columnWidths: {
              0: const pw.FixedColumnWidth(20),
              1: const pw.FlexColumnWidth(3),
            },
            oddRowDecoration: const pw.BoxDecoration(color: PdfColors.grey100),
          ),
          pw.SizedBox(height: 20),
          pw.Container(
            alignment: pw.Alignment.centerRight,
            child: pw.Text(
              '${l10n.get('totalSales')}: \$${NumberFormat.currency(locale: 'es_CL', symbol: '', decimalDigits: 0).format(totalSales)}',
              style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold, color: baseColor),
            ),
          ),
        ],
        footer: (context) => pw.Container(
          alignment: pw.Alignment.centerRight,
          margin: const pw.EdgeInsets.only(top: 10),
          child: pw.Text('Generado: $formattedDate - Página ${context.pageNumber}', style: const pw.TextStyle(color: PdfColors.grey, fontSize: 8)),
        ),
      ),
    );

    await Printing.layoutPdf(onLayout: (format) => pdf.save());
  }
}