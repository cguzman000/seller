import 'package:flutter/material.dart';
import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'firestore_service.dart';
import 'main.dart'; // Importar para usar SellerBottomNavigationBar
import 'app_localizations.dart';
import 'package:seller/pdf_generator.dart';

class OffersPage extends StatefulWidget {
  final User user;
  final String businessId;
  const OffersPage({super.key, required this.user, required this.businessId});

  @override
  State<OffersPage> createState() => _OffersPageState();
}

class _OffersPageState extends State<OffersPage> {
  final FirestoreService _firestoreService = FirestoreService();
  final TextEditingController _searchController = TextEditingController();
  String _searchTerm = '';
  double _vatRate = 0.21;
  StreamSubscription? _settingsSubscription;
  String? _companyName;
  String? _companyPhone;

  @override
  void initState() {
    super.initState();
    _settingsSubscription = _firestoreService.getCompanySettings(widget.businessId).listen((snapshot) {
      if (mounted && snapshot.exists) {
        final settingsData = snapshot.data() as Map<String, dynamic>?;
        setState(() {
          _vatRate = (settingsData?['vat_rate'] as num? ?? 21.0) / 100.0;
          _companyName = settingsData?['company_name'] as String?;
          _companyPhone = settingsData?['company_phone'] as String?;
        });
      }
    });
  }

  @override
  void dispose() {
    _settingsSubscription?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _printOffersCatalog() async {
    final l10n = AppLocalizations.of(context);
    
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
    String sellerPhone = _companyPhone ?? '';

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
        vatRate: _vatRate,
        companyName: _companyName,
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
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.get('offers')),
        actions: [
          IconButton(
            icon: const Icon(Icons.print_outlined),
            onPressed: _printOffersCatalog,
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
                        final grossPrice = netPrice * (1 + _vatRate);

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
                          child: Card(
                            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            child: ListTile(
                              leading: const Icon(Icons.local_offer, color: Colors.orange),
                              title: Text(offerData['name'] ?? 'Oferta'),
                              subtitle: Text('$productDisplayName\nCant. Mínima: ${offerData['quantity']} unid. \nPrecio: \$${grossPrice.toStringAsFixed(2)} (Neto: \$${netPrice.toStringAsFixed(2)})'),
                              isThreeLine: true,
                              onTap: () => _showOfferDialog(offerDoc, products),
                            ),
                          ),
                        );
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
        tooltip: 'Añadir Oferta',
        child: const Icon(Icons.add),
      ),
      bottomNavigationBar: widget.user.uid != widget.businessId
          ? SellerBottomNavigationBar(
              user: widget.user,
              businessId: widget.businessId,
              sellerId: widget.user.uid,
              currentIndex: 3,
              allowSamePageNavigation: true,
            )
          : null,
    );
  }

  void _showOfferDialog(DocumentSnapshot? offer, List<QueryDocumentSnapshot>? preloadedProducts) {
    showDialog(
      context: context,
      builder: (context) => OfferDialog(
        user: widget.user,
        businessId: widget.businessId,
        firestoreService: _firestoreService,
        offer: offer,
        preloadedProducts: preloadedProducts,
        vatRate: _vatRate,
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
  late Stream<QuerySnapshot> _productsStream;
  bool _offerPriceIncludesVat = false;

  @override
  void initState() {
    super.initState();
    _productsStream = widget.firestoreService.getProducts(widget.businessId);
    if (widget.offer != null) {
      final data = widget.offer!.data() as Map<String, dynamic>;
      _nameController.text = data['name'] ?? '';
      _quantityController.text = data['quantity'].toString();
      _priceController.text = data['price'].toString();
      _selectedProductId = data['productId'];
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.offer == null ? 'Añadir Oferta' : 'Editar Oferta'),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              StreamBuilder<QuerySnapshot>(
                stream: _productsStream,
                builder: (context, snapshot) {
                  List<QueryDocumentSnapshot> products = [];
                  if (snapshot.hasData) {
                    products = snapshot.data!.docs;
                  } else if (widget.preloadedProducts != null) {
                    products = widget.preloadedProducts!;
                  }

                  if (products.isEmpty && snapshot.connectionState == ConnectionState.waiting) return const CircularProgressIndicator();

                  final l10n = AppLocalizations.of(context);
                  double? netPrice;
                  if (_selectedProductId != null) {
                    try {
                      final prod = products.firstWhere((p) => p.id == _selectedProductId);
                      netPrice = (prod['price'] as num?)?.toDouble();
                    } catch (_) {}
                  }

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      DropdownButtonFormField<String>(
                        initialValue: products.any((p) => p.id == _selectedProductId) ? _selectedProductId : null,
                        hint: const Text('Selecciona un Producto'),
                        isExpanded: true,
                        items: products.map((doc) {
                          final d = doc.data() as Map<String, dynamic>;
                          final uBox = (d['units_box'] as num?)?.toInt() ?? 0;
                          final dName = d['name'] ?? '';
                          final dispName = uBox > 1 
                              ? '$dName ${l10n.get('unitsPerBox').replaceFirst('{count}', uBox.toString())}' 
                              : dName;
                          return DropdownMenuItem(value: doc.id, child: Text(dispName));
                        }).toList(),
                        onChanged: (val) => setState(() => _selectedProductId = val),
                        validator: (val) => val == null ? 'Requerido' : null,
                      ),
                      if (netPrice != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 4.0, left: 4.0),
                          child: Text('Precio Normal: \$${(netPrice * (1 + widget.vatRate)).toStringAsFixed(2)} (Neto: \$${netPrice.toStringAsFixed(2)})', style: const TextStyle(color: Colors.grey, fontSize: 12)),
                        ),
                    ],
                  );
                },
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