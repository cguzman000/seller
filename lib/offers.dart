import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:seller/widgets/barcode_scanner.dart';
import 'firestore_service.dart';
import 'app_localizations.dart';
import 'package:seller/pdf_generator.dart';
import 'package:seller/company_settings_provider.dart';
import 'package:seller/main.dart';

class OffersPage extends StatefulWidget {
  final User user;
  final String businessId;
  final String? role;
  final String? sellerId;
  const OffersPage({
    super.key,
    required this.user,
    required this.businessId,
    required this.role,
    this.sellerId,
  });

  @override
  State<OffersPage> createState() => _OffersPageState();
}

class _OffersPageState extends State<OffersPage> {
  final FirestoreService _firestoreService = FirestoreService();
  final TextEditingController _searchController = TextEditingController();
  String _searchTerm = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _printOffersCatalog(WidgetRef ref) async {
    final l10n = AppLocalizations.of(context);

    // Obtenemos la configuración de la empresa desde el provider
    final settings = ref.read(companySettingsProvider(widget.businessId));
    final settingsData = settings.asData?.value.data() as Map<String, dynamic>?;
    final vatRate = (settingsData?['vat_rate'] as num? ?? 21.0) / 100.0;
    final companyName = settingsData?['company_name'] as String?;
    final companyPhone = settingsData?['company_phone'] as String?;
    
    // 1. Obtener todas las ofertas
    final offersSnapshot = await _firestoreService.getAllOffersOnce(widget.businessId);
    if (offersSnapshot.docs.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.get('noOfferProductsToPrint'))),
        );
      }
      return;
    }

    // 2. Obtener IDs de productos únicos de las ofertas
    final productIdsWithOffers = offersSnapshot.docs
        .map((doc) => (doc.data() as Map<String, dynamic>)['productId'] as String?)
        .where((id) => id != null)
        .cast<String>()
        .toSet()
        .toList();

    if (productIdsWithOffers.isEmpty) return;

    // 3. Obtener los productos correspondientes
    final productsDocs = await _firestoreService.getProductsByIds(widget.businessId, productIdsWithOffers);
    
    // Filtrar solo productos activos
    final activeProducts = productsDocs.where((doc) {
       final data = doc.data() as Map<String, dynamic>;
       return data['state'] == null || data['state'] == true;
    }).toList();

    if (activeProducts.isEmpty) {
       if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.get('noOfferProductsToPrint'))),
        );
      }
      return;
    }

    // 4. Obtener datos auxiliares para el PDF
    final categoryDocsSnapshot = await _firestoreService.getCategoriesOnce(widget.businessId);
    final supplierDocsSnapshot = await _firestoreService.getSuppliersOnce(widget.businessId);
    
    final categoryMap = {for (var doc in categoryDocsSnapshot.docs) doc.id: doc['name'] as String};
    final supplierMap = {for (var doc in supplierDocsSnapshot.docs) doc.id: doc['name'] as String};

    // 5. Ordenar productos por categoría y nombre
    activeProducts.sort((a, b) {
       final dataA = a.data() as Map<String, dynamic>;
       final dataB = b.data() as Map<String, dynamic>;
       final catA = categoryMap[dataA['categoryId']] ?? '';
       final catB = categoryMap[dataB['categoryId']] ?? '';
       int catCompare = catA.compareTo(catB);
       if (catCompare != 0) return catCompare;
       return (dataA['name'] ?? '').toString().toLowerCase().compareTo((dataB['name'] ?? '').toString().toLowerCase());
    });
    
    String sellerName = widget.user.displayName ?? 'Vendedor';
    String sellerPhone = companyPhone ?? '';

    // 6. Generar PDF
    try {
      await PdfGenerator.generateCatalog(
        l10n: l10n,
        products: activeProducts,
        businessId: widget.businessId,
        categoryMap: categoryMap,
        supplierMap: supplierMap,
        catalogTitle: l10n.get('offers'),
        groupBy: 'category',
        vatRate: vatRate,
        companyName: companyName,
        sellerName: sellerName,
        sellerPhone: sellerPhone,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error al generar PDF: $e'), backgroundColor: Colors.red));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer(builder: (context, ref, child) {
      final l10n = AppLocalizations.of(context);
      // Observamos el proveedor de configuración. Riverpod maneja el estado de carga/error.
      final settingsAsyncValue = ref.watch(companySettingsProvider(widget.businessId));

      // Extraemos los datos cuando estén disponibles
      final settingsData = settingsAsyncValue.asData?.value.data() as Map<String, dynamic>?;
      final vatRate = (settingsData?['vat_rate'] as num? ?? 21.0) / 100.0;

      return Scaffold(
      appBar: AppBar(
        title: Text(l10n.get('offers')),
        actions: [
          IconButton(
            icon: const Icon(Icons.print_outlined),
            onPressed: () => _printOffersCatalog(ref),
            tooltip: l10n.get('printOffersCatalog'),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                labelText: 'Buscar por producto',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                suffixIcon: _searchTerm.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _searchTerm = '');
                        },
                      )
                    : null,
              ),
              onChanged: (val) => setState(() => _searchTerm = val),
            ),
          ),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: _firestoreService.getProducts(widget.businessId),
              builder: (context, productSnapshot) {
                if (!productSnapshot.hasData) return const Center(child: CircularProgressIndicator());
                
                final products = productSnapshot.data!.docs;
                final productDataMap = {for (var doc in products) doc.id: doc.data() as Map<String, dynamic>};

                return StreamBuilder<QuerySnapshot>(
                  stream: _firestoreService.getAllOffers(widget.businessId),
                  builder: (context, offerSnapshot) {
                    if (offerSnapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    if (!offerSnapshot.hasData || offerSnapshot.data!.docs.isEmpty) {
                      return const Center(child: Text('No hay ofertas registradas.'));
                    }

                    final offers = offerSnapshot.data!.docs;
                    final filteredOffers = offers.where((doc) {
                      if (_searchTerm.isEmpty) return true;
                      final data = doc.data() as Map<String, dynamic>;
                      final pId = data['productId'] as String?;
                      if (pId == null) return false;
                      final productData = productDataMap[pId];
                      final pName = (productData?['name'] as String? ?? '').toLowerCase();
                      final oName = data['name'] as String? ?? '';
                      final term = _searchTerm.toLowerCase();
                      return pName.toLowerCase().contains(term) || oName.toLowerCase().contains(term);
                    }).toList();

                    if (filteredOffers.isEmpty) {
                      return const Center(child: Text('No se encontraron ofertas.'));
                    }

                    return ListView.builder(
                      itemCount: filteredOffers.length,
                      itemBuilder: (context, index) {
                        final offerDoc = filteredOffers[index];
                        final offerData = offerDoc.data() as Map<String, dynamic>;
                        final productId = offerData['productId'] as String;
                        final productData = productDataMap[productId];
                        final productName = productData?['name'] ?? 'Producto no encontrado';
                        final unitsBox = (productData?['units_box'] as num?)?.toInt() ?? 0;
                        final productDisplayName = unitsBox > 1 
                            ? '$productName ${l10n.get('unitsPerBox').replaceFirst('{count}', unitsBox.toString())}' 
                            : productName;
                        final netPrice = (offerData['price'] as num).toDouble();
                        final grossPrice = netPrice * (1 + vatRate);

                        final offerCard = Card(
                          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          child: ListTile(
                              leading: const Icon(Icons.local_offer, color: Colors.orange),
                              title: Text(offerData['name'] ?? 'Oferta'),
                              subtitle: Text('$productDisplayName\nCant. Mínima: ${offerData['quantity']} unid. \nPrecio: \$${grossPrice.toStringAsFixed(2)} (Neto: \$${netPrice.toStringAsFixed(2)})'),
                              isThreeLine: true, // Asegura que el subtítulo tenga espacio para 3 líneas
                              onTap: () => _showOfferDialog(offerDoc, products),
                            ),
                          );
                        

                        if (widget.role == 'admin') {
                          return Dismissible(
                            key: Key(offerDoc.id),
                            direction: DismissDirection.endToStart,
                            background: Container(
                              color: Colors.red,
                              alignment: Alignment.centerRight,
                              padding: const EdgeInsets.symmetric(horizontal: 20),
                              child: const Icon(Icons.delete, color: Colors.white),
                            ),
                            confirmDismiss: (direction) async {
                              return await showDialog(
                                context: context,
                                builder: (context) => AlertDialog(
                                  title: const Text('Eliminar Oferta'),
                                  content: const Text('¿Estás seguro de eliminar esta oferta?'),
                                  actions: [
                                    TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
                                    TextButton(
                                      onPressed: () => Navigator.pop(context, true),
                                      child: const Text('Eliminar', style: TextStyle(color: Colors.red)),
                                    ),
                                  ],
                                ),
                              );
                            },
                            onDismissed: (direction) {
                              _firestoreService.deleteOffer(offerDoc.id);
                              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Oferta eliminada')));
                            },
                            child: offerCard,
                          );
                        }
                        return offerCard;
                      },
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showOfferDialog(null, null),
        tooltip: l10n.get('createOffer'),
        child: const Icon(Icons.add),
      ),
      bottomNavigationBar: SellerBottomNavigationBar(
        user: widget.user,
        businessId: widget.businessId,
        role: widget.role,
        sellerId: widget.sellerId,
        currentIndex: 5, // Índice para Ofertas
        allowSamePageNavigation: true,
      ),
    );
    });
  }

  void _showOfferDialog(DocumentSnapshot? offer, List<QueryDocumentSnapshot>? preloadedProducts) {
    // Usamos un Consumer para pasar el `ref` al diálogo y que este pueda acceder al provider
    showDialog(
      context: context,
      builder: (context) => Consumer(
        builder: (context, ref, child) {
          final settings = ref.watch(companySettingsProvider(widget.businessId));
          final vatRate = (settings.asData?.value.data() as Map<String, dynamic>?)?['vat_rate'] as num? ?? 21.0;

          return OfferDialog(
            user: widget.user,
            businessId: widget.businessId,
            firestoreService: _firestoreService,
            offer: offer,
            preloadedProducts: preloadedProducts,
            vatRate: vatRate / 100.0,
          );
        },
      ),
    );
  }
}

class OfferDialog extends StatefulWidget {
  final User user;
  final String businessId;
  final FirestoreService firestoreService;
  final DocumentSnapshot? offer;
  final List<QueryDocumentSnapshot>? preloadedProducts;
  final double vatRate;

  const OfferDialog({super.key, required this.user, required this.businessId, required this.firestoreService, this.offer, this.preloadedProducts, required this.vatRate});

  @override
  State<OfferDialog> createState() => _OfferDialogState();
}

class _OfferDialogState extends State<OfferDialog> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _quantityController = TextEditingController();
  final TextEditingController _priceController = TextEditingController();
  String? _selectedProductId;
  final TextEditingController _productSearchController = TextEditingController();
  final FocusNode _productSearchFocusNode = FocusNode();
  String? _selectedProductName;
  bool _offerPriceIncludesVat = false;

  @override
  void initState() {
    super.initState();
    if (widget.offer != null) {
      final data = widget.offer!.data() as Map<String, dynamic>;
      _nameController.text = data['name'] ?? '';
      _quantityController.text = data['quantity'].toString();
      // Formatear el precio a dos decimales desde el inicio.
      // El precio guardado es neto, y el checkbox de IVA incluido está desactivado por defecto,
      // por lo que mostramos el precio neto formateado.
      final netPrice = (data['price'] as num?)?.toDouble() ?? 0.0;
      _priceController.text = netPrice.toStringAsFixed(2);
      _selectedProductId = data['productId'];
      // Cargar el nombre del producto para mostrarlo en el campo de búsqueda
      _loadProductName(_selectedProductId!);
    }
  }

  Future<void> _loadProductName(String productId) async {
    final productDoc = await widget.firestoreService.getProductById(productId);
    if (productDoc.exists && mounted) {
      final data = productDoc.data() as Map<String, dynamic>;
      setState(() {
        _selectedProductName = data['name'] as String?;
        _productSearchController.text = _selectedProductName ?? '';
      });
    }
  }

  Future<void> _scanBarcodeAndSelectProduct() async {
    // 1. Abrir el escáner
    final barcode = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (context) => const BarcodeScannerSimple()),
    );

    if (barcode == null || !mounted) return;

    // 2. Buscar el producto por código de barras
    final productDoc = await widget.firestoreService.getProductByBarcode(widget.businessId, barcode);

    if (productDoc == null) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Producto no encontrado.')));
      return;
    }

    // 3. Si se encuentra, seleccionarlo
    final data = productDoc.data() as Map<String, dynamic>;
    setState(() => _productSearchController.text = (data['name'] as String? ?? ''));
  }

  @override
  void dispose() {
    _nameController.dispose();
    _quantityController.dispose();
    _priceController.dispose();
    _productSearchController.dispose();
    _productSearchFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.offer == null ? 'Añadir Oferta' : 'Editar Oferta'),
      content: SizedBox(
        width: MediaQuery.of(context).size.width * 0.8,
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          return RawAutocomplete<DocumentSnapshot>(
                            textEditingController: _productSearchController, // Usamos el controlador
                            focusNode: _productSearchFocusNode,
                            optionsBuilder: (TextEditingValue textEditingValue) {
                              return widget.firestoreService.searchProducts(widget.businessId, textEditingValue.text);
                            },
                            onSelected: (DocumentSnapshot selection) {
                              final data = selection.data() as Map<String, dynamic>;
                              setState(() {
                                _selectedProductId = selection.id;
                                _selectedProductName = data['name'] as String?;
                                _productSearchController.text = _selectedProductName ?? '';
                              });
                            },
                            displayStringForOption: (DocumentSnapshot option) {
                              final data = option.data() as Map<String, dynamic>;
                              return data['name'] as String? ?? '';
                            },
                            fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
                              return TextFormField(
                                controller: controller,
                                focusNode: focusNode,
                                decoration: InputDecoration(
                                  labelText: 'Buscar Producto',
                                  suffixIcon: controller.text.isNotEmpty
                                      ? IconButton(
                                          icon: const Icon(Icons.clear),
                                          onPressed: () {
                                            controller.clear();
                                            setState(() {
                                              _selectedProductId = null;
                                              _selectedProductName = null;
                                            });
                                          },
                                        )
                                      : null,
                                ),
                                validator: (value) {
                                  if (_selectedProductId == null) {
                                    return 'Debes seleccionar un producto';
                                  }
                                  return null;
                                },
                                onChanged: (text) {
                                  if (text != _selectedProductName) {
                                    setState(() {
                                      _selectedProductId = null;
                                    });
                                  }
                                },
                              );
                            },
                            optionsViewBuilder: (context, onSelected, options) {
                              return Align(
                                alignment: Alignment.topLeft,
                                child: Material(
                                  elevation: 4.0, // Sombra para el desplegable
                                  child: ConstrainedBox(
                                    constraints: BoxConstraints(maxHeight: 200, maxWidth: constraints.maxWidth),
                                    child: ListView.builder(
                                      padding: EdgeInsets.zero,
                                      shrinkWrap: true,
                                      itemCount: options.length,
                                      itemBuilder: (context, index) {
                                        final option = options.elementAt(index);
                                        final data = option.data() as Map<String, dynamic>;
                                        final name = data['name'] as String? ?? 'Sin Nombre';
                                        final price = (data['price'] as num?)?.toDouble() ?? 0.0;
                                        return ListTile(
                                          title: Text(name),
                                          trailing: Text('\$${price.toStringAsFixed(2)}'),
                                          onTap: () => onSelected(option),
                                        );
                                      },
                                    ),
                                  ),
                                ),
                              );
                            },
                          );
                        },
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.qr_code_scanner),
                      onPressed: _scanBarcodeAndSelectProduct,
                      tooltip: 'Escanear código de barras',
                    ),
                  ],
                ),
                TextFormField(controller: _nameController, decoration: const InputDecoration(labelText: 'Nombre Oferta (ej. Mayorista)')),
                TextFormField(controller: _quantityController, decoration: const InputDecoration(labelText: 'Cantidad Mínima'), keyboardType: TextInputType.number),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _priceController,
                        decoration: const InputDecoration(labelText: 'Precio Oferta', prefixText: '\$'),
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text('¿IVA Incl.?', style: TextStyle(fontSize: 12)),
                        Checkbox(
                          value: _offerPriceIncludesVat,
                          onChanged: (value) {
                            if (value == null) return;
                            setState(() {
                              _offerPriceIncludesVat = value;
                              final priceText = _priceController.text;
                              if (priceText.isNotEmpty) {
                                final priceInput = double.tryParse(priceText);
                                if (priceInput != null) {
                                  double newPrice;
                                  if (_offerPriceIncludesVat) {
                                    newPrice = priceInput * (1 + widget.vatRate);
                                  } else {
                                    newPrice = priceInput / (1 + widget.vatRate);
                                  }
                                  _priceController.text = newPrice.toStringAsFixed(2);
                                }
                              }
                            });
                          },
                          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        ElevatedButton(
          onPressed: () async {
            if (_formKey.currentState!.validate()) {
              final qty = double.tryParse(_quantityController.text) ?? 0;
              final priceInput = double.tryParse(_priceController.text) ?? 0;
              
              double finalPrice = priceInput;
              if (_offerPriceIncludesVat) {
                finalPrice = priceInput / (1 + widget.vatRate);
              }
              
              if (widget.offer == null) {
                await widget.firestoreService.addOffer(widget.businessId, _selectedProductId!, qty, finalPrice, _nameController.text);
              } else {
                await widget.firestoreService.updateOffer(widget.offer!.id, _selectedProductId!, qty, finalPrice, _nameController.text);
              }
              if (!context.mounted) return;
              Navigator.pop(context);
            }
          },
          child: const Text('Guardar'),
        ),
      ],
    );
  }
}