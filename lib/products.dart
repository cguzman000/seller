import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/services.dart';
import 'dart:io';
import 'package:image_picker/image_picker.dart';
import 'firestore_service.dart';
import 'app_localizations.dart';
import 'util/text_formatter.dart';
import 'package:seller/pdf_generator.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'main.dart'; // Importar para usar SellerBottomNavigationBar

class ProductsPage extends StatefulWidget {
  final User user;
  final String businessId;
  final String role;
  final String? sellerId;
  const ProductsPage({super.key, required this.user, required this.businessId, required this.role, this.sellerId});

  @override
  State<ProductsPage> createState() => _ProductsPageState();
}

class _ProductsPageState extends State<ProductsPage> {
  final FirestoreService _firestoreService = FirestoreService();
  double _vatRate = 0.21;
  final TextEditingController _searchController = TextEditingController();
  String _searchTerm = '';
  String? _selectedCategoryIdFilter;
  String? _selectedSupplierIdFilter;
  String? _selectedCategoryNameFilter;
  String? _selectedSupplierNameFilter;
  SortOption _sortOption = SortOption.none;
  String? _companyName;
  String? _companyPhone;

  @override
  void initState() {
    super.initState();
    _loadCompanySettings();
    _searchController.addListener(() {
      setState(() {
        _searchTerm = _searchController.text;
      });
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadCompanySettings() async {
    final settingsDoc = await _firestoreService.getCompanySettingsOnce(widget.businessId);
    if (mounted && settingsDoc.exists) {
      final settingsData = settingsDoc.data() as Map<String, dynamic>?;
      setState(() {
        _vatRate = (settingsData?['vat_rate'] as num? ?? 21.0) / 100.0;
        _companyName = settingsData?['company_name'] as String?;
        _companyPhone = settingsData?['company_phone'] as String?;
      });
    }
  }

  Future<void> _scanBarcode() async {
    final result = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (context) => const BarcodeScannerSimple()),
    );

    if (result != null && mounted) {
      _searchController.text = result;

      final snapshot = await FirebaseFirestore.instance
          .collection('products')
          .where('userId', isEqualTo: widget.businessId)
          .where('bar_code', isEqualTo: result.trim())
          .limit(1)
          .get();

      if (snapshot.docs.isNotEmpty && mounted) {
        _showProductDialog(product: snapshot.docs.first);
      }
    }
  }

  void _showProductDialog({DocumentSnapshot? product}) {
    showDialog(
      context: context,
      builder: (context) {
        return ProductDialog(
          user: widget.user,
          businessId: widget.businessId,
          firestoreService: _firestoreService,
          product: product,
        );
      },
    );
  }

  Future<void> _printProducts() async {
    final l10n = AppLocalizations.of(context);
    // 1. Obtener los datos más recientes de Firestore
    final productDocsSnapshot = await _firestoreService.getProductsOnce(widget.businessId, categoryId: _selectedCategoryIdFilter, supplierId: _selectedSupplierIdFilter);
    final categoryDocsSnapshot = await _firestoreService.getCategoriesOnce(widget.businessId);
    final supplierDocsSnapshot = await _firestoreService.getSuppliersOnce(widget.businessId);

    final categoryMap = {for (var doc in categoryDocsSnapshot.docs) doc.id: (doc['name'] as String)};
    final supplierMap = {for (var doc in supplierDocsSnapshot.docs) doc.id: (doc['name'] as String)};

    // 2. Filtrar los productos según el término de búsqueda actual
    final filteredDocs = productDocsSnapshot.docs.where((doc) {
      final data = doc.data() as Map<String, dynamic>;

      // Solo mostrar productos activos en el PDF
      final isActive = data['state'] ?? true;
      if (!isActive) return false;

      if (_searchTerm.isEmpty) return true;
      final name = data['name_lowercase'] as String? ?? '';
      return name.contains(_searchTerm.toLowerCase());
    }).toList();

    // 3. Ordenar según la opción seleccionada
    if (_sortOption == SortOption.byCategory) {
      filteredDocs.sort((a, b) {
        final dataA = a.data() as Map<String, dynamic>;
        final dataB = b.data() as Map<String, dynamic>;

        // Mover productos sin categoría al final
        if (dataA['categoryId'] == null && dataB['categoryId'] != null) return 1;
        if (dataA['categoryId'] != null && dataB['categoryId'] == null) return -1;

        final catA = categoryMap[dataA['categoryId']] ?? 'Sin categoría';
        final catB = categoryMap[dataB['categoryId']] ?? 'Sin categoría';
        int cmp = catA.toLowerCase().compareTo(catB.toLowerCase());
        if (cmp != 0) return cmp;
        return (dataA['name'] ?? '').toString().toLowerCase().compareTo((dataB['name'] ?? '').toString().toLowerCase());
      });
    } else if (_sortOption == SortOption.bySupplier) {
      filteredDocs.sort((a, b) {
        final dataA = a.data() as Map<String, dynamic>;
        final dataB = b.data() as Map<String, dynamic>;

        // Mover productos sin proveedor al final
        if (dataA['supplierId'] == null && dataB['supplierId'] != null) return 1;
        if (dataA['supplierId'] != null && dataB['supplierId'] == null) return -1;

        final supA = supplierMap[dataA['supplierId']] ?? 'Sin proveedor';
        final supB = supplierMap[dataB['supplierId']] ?? 'Sin proveedor';
        int cmp = supA.toLowerCase().compareTo(supB.toLowerCase());
        if (cmp != 0) return cmp;
        return (dataA['name'] ?? '').toString().toLowerCase().compareTo((dataB['name'] ?? '').toString().toLowerCase());
      });
    } else {
      filteredDocs.sort((a, b) {
        final dataA = a.data() as Map<String, dynamic>;
        final dataB = b.data() as Map<String, dynamic>;
        return (dataA['name'] ?? '').toString().toLowerCase().compareTo((dataB['name'] ?? '').toString().toLowerCase());
      });
    }

    if (filteredDocs.isEmpty) {
      if (mounted) {
        final l10n = AppLocalizations.of(context);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l10n.get('noProductsToPrint'))));
      }
      return;
    }

    // 4. Obtener datos del vendedor para el pie de página
    String sellerName = widget.user.displayName ?? 'Vendedor';
    String sellerPhone = '';

    try {
      final userDoc = await _firestoreService.getUserById(widget.user.uid);
      if (userDoc.exists) {
        final userData = userDoc.data() as Map<String, dynamic>;
        if (userData['name'] != null && (userData['name'] as String).isNotEmpty) {
          sellerName = userData['name'];
        }
        if (widget.user.uid != widget.businessId) {
          sellerPhone = userData['phone'] ?? '';
        }
      }
    } catch (_) {}

    if (widget.user.uid == widget.businessId) {
      // Si es el administrador, usamos el teléfono de la empresa
      sellerPhone = _companyPhone ?? '';
    }

    // 5. Generar el documento PDF usando la nueva clase
    try {
      await PdfGenerator.generateCatalog(
        l10n: l10n,
        products: filteredDocs,
        businessId: widget.businessId,
        categoryMap: categoryMap,
        supplierMap: supplierMap,
        groupBy: _sortOption == SortOption.byCategory ? 'category' : (_sortOption == SortOption.bySupplier ? 'supplier' : null),
        vatRate: _vatRate,
        categoryFilterName: _selectedCategoryNameFilter,
        supplierFilterName: _selectedSupplierNameFilter,
        companyName: _companyName,
        sellerName: sellerName,
        sellerPhone: sellerPhone,
      );
    } catch (e) {
      if (mounted) {
        final error = e.toString();
        // Intentamos extraer el enlace específico del error
        final RegExp regExp = RegExp(r'https://console\.firebase\.google\.com[^\s]+');
        final match = regExp.firstMatch(error);
        final url = match?.group(0);

        if (error.contains('failed-precondition') || error.contains('index')) {
          showDialog(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Falta Índice de Firestore'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Para optimizar la velocidad, se requiere un índice nuevo.'),
                    if (url != null) ...[
                      const SizedBox(height: 16),
                      const Text('Copia este enlace completo y ábrelo en tu navegador:', style: TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      SelectableText(url, style: const TextStyle(color: Colors.blue, decoration: TextDecoration.underline)),
                    ],
                    const SizedBox(height: 16),
                    const Text('Detalle técnico:', style: TextStyle(fontSize: 12, color: Colors.grey)),
                    const SizedBox(height: 4),
                    SelectableText(error, style: const TextStyle(fontSize: 10, color: Colors.red)),
                  ],
                ),
              ),
              actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cerrar'))],
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error al generar PDF: $e'), backgroundColor: Colors.red),
          );
        }
      }
    }
  }

  void _showFilterSelectionDialog({required String title, required Stream<QuerySnapshot> stream, required Function(String?, String?) onSelected}) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(title),
          content: SizedBox(
            width: double.maxFinite,
            child: StreamBuilder<QuerySnapshot>(
              stream: stream,
              builder: (context, snapshot) {
                if (snapshot.hasError) return Text('Error: ${snapshot.error}');
                if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
                final docs = snapshot.data!.docs;
                if (docs.isEmpty) return const Text('No hay opciones disponibles.');

                return ListView.separated(
                  shrinkWrap: true,
                  itemCount: docs.length,
                  separatorBuilder: (context, index) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final doc = docs[index];
                    final name = doc['name'] as String;
                    return ListTile(
                      title: Text(name),
                      onTap: () {
                        onSelected(doc.id, name);
                        Navigator.pop(context);
                      },
                    );
                  },
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.get('products')),
        actions: [
          IconButton(
            icon: const Icon(Icons.print_outlined),
            onPressed: _printProducts,
            tooltip: l10n.get('printList'),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      labelText: l10n.get('searchProductHint'),
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (_searchTerm.isNotEmpty)
                            IconButton(
                              icon: const Icon(Icons.clear),
                              onPressed: () {
                                _searchController.clear();
                              },
                            ),
                          IconButton(
                            icon: const Icon(Icons.qr_code_scanner),
                            onPressed: _scanBarcode,
                            tooltip: l10n.get('scanBarcode'),
                          ),
                        ],
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12.0),
                      ),
                    ),
                  ),
                ),
                PopupMenuButton<SortOption>(
                  icon: const Icon(Icons.sort, color: Colors.black),
                  onSelected: (SortOption result) {
                    setState(() {
                      _sortOption = result;
                    });
                  },
                  itemBuilder: (BuildContext context) => <PopupMenuEntry<SortOption>>[
                    PopupMenuItem<SortOption>(
                      value: SortOption.none,
                      child: Text(l10n.get('ungrouped')),
                    ),
                    PopupMenuItem<SortOption>(
                      value: SortOption.byCategory,
                      child: Text(l10n.get('groupByCategory')),
                    ),
                    PopupMenuItem<SortOption>(
                      value: SortOption.bySupplier,
                      child: Text(l10n.get('groupBySupplier')),
                    ),
                  ],
                ),
                PopupMenuButton<String>(
                  icon: Icon(
                    Icons.filter_list,
                    color: (_selectedCategoryIdFilter != null || _selectedSupplierIdFilter != null)
                        ? Theme.of(context).colorScheme.primary
                        : Colors.black,
                  ),
                  tooltip: l10n.get('filter'),
                  onSelected: (value) {
                    if (value == 'category') {
                      _showFilterSelectionDialog(
                        title: l10n.get('selectCategory'),
                        stream: _firestoreService.getCategories(widget.businessId),
                        onSelected: (id, name) => setState(() {
                          _selectedCategoryIdFilter = id;
                          _selectedCategoryNameFilter = name;
                          _selectedSupplierIdFilter = null; // Limpiamos el otro filtro
                          _selectedSupplierNameFilter = null;
                        }),
                      );
                    } else if (value == 'supplier') {
                      _showFilterSelectionDialog(
                        title: l10n.get('selectSupplier'),
                        stream: _firestoreService.getSuppliers(widget.businessId),
                        onSelected: (id, name) => setState(() {
                          _selectedSupplierIdFilter = id;
                          _selectedSupplierNameFilter = name;
                          _selectedCategoryIdFilter = null; // Limpiamos el otro filtro
                          _selectedCategoryNameFilter = null;
                        }),
                      );
                    } else if (value == 'clear') {
                      setState(() {
                        _selectedCategoryNameFilter = null;
                        _selectedSupplierNameFilter = null;
                        _selectedCategoryIdFilter = null;
                        _selectedSupplierIdFilter = null;
                      });
                    }
                  },
                  itemBuilder: (context) => [
                    PopupMenuItem(value: 'category', child: Text(l10n.get('filterByCategory'))),
                    PopupMenuItem(value: 'supplier', child: Text(l10n.get('filterBySupplier'))),
                    const PopupMenuDivider(),
                    PopupMenuItem(value: 'clear', child: Text(l10n.get('viewAll'))),
                  ],
                ),
              ],
            ),
          ),
          if (_selectedCategoryNameFilter != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(
                '${l10n.get('category')}: $_selectedCategoryNameFilter',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.blueGrey),
              ),
            ),
          if (_selectedSupplierNameFilter != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(
                '${l10n.get('supplier')}: $_selectedSupplierNameFilter',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.blueGrey),
              ),
            ),
          Expanded(
            child: ProductList(
              user: widget.user,
              businessId: widget.businessId,
              firestoreService: _firestoreService,
              searchTerm: _searchTerm,
              categoryIdFilter: _selectedCategoryIdFilter,
              supplierIdFilter: _selectedSupplierIdFilter,
              vatRate: _vatRate,
              sortOption: _sortOption,
              onProductTap: (product) => _showProductDialog(product: product),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showProductDialog(),
        tooltip: l10n.get('addProduct'),
        child: const Icon(Icons.add),
      ),
      bottomNavigationBar: SellerBottomNavigationBar(
        user: widget.user,
        businessId: widget.businessId,
        role: widget.role,
        sellerId: widget.sellerId,
        currentIndex: 4, // Índice para Productos
      ),
    );
  }
}

enum SortOption { none, byCategory, bySupplier }

class ProductList extends StatelessWidget {
  final User user;
  final String businessId;
  final FirestoreService firestoreService;
  final String searchTerm;
  final String? categoryIdFilter;
  final String? supplierIdFilter;
  final double vatRate;
  final SortOption sortOption;
  final Function(DocumentSnapshot) onProductTap;

  const ProductList({
    super.key,
    required this.user,
    required this.businessId,
    required this.firestoreService,
    required this.searchTerm,
    this.categoryIdFilter,
    this.supplierIdFilter,
    required this.vatRate,
    required this.sortOption,
    required this.onProductTap,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return FutureBuilder<List<QuerySnapshot>>(
      future: Future.wait([
        firestoreService.getCategoriesOnce(businessId),
        firestoreService.getSuppliersOnce(businessId),
      ]),
      builder: (context, futureSnapshot) {
        if (futureSnapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (futureSnapshot.hasError) {
          return Center(child: Text('Error al cargar datos: ${futureSnapshot.error}'));
        }
        if (!futureSnapshot.hasData || futureSnapshot.data!.length < 2) {
          return const Center(child: Text('No se pudieron cargar los datos.'));
        }

        final categoryDocs = futureSnapshot.data![0].docs;
        final supplierDocs = futureSnapshot.data![1].docs;
        final categoryMap = {for (var doc in categoryDocs) doc.id: (doc['name'] as String)};
        final supplierMap = {for (var doc in supplierDocs) doc.id: (doc['name'] as String)};

        return StreamBuilder<QuerySnapshot>(
          stream: firestoreService.getProducts(businessId, categoryId: categoryIdFilter, supplierId: supplierIdFilter),
          builder: (context, productSnapshot) {
            if (productSnapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (productSnapshot.hasError) {
              final error = productSnapshot.error.toString();
              if (error.contains('failed-precondition') || error.contains('index')) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 48),
                        const SizedBox(height: 16),
                        const Text('Falta un índice en Firebase', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 8),
                        const Text('Selecciona y copia el siguiente enlace para crearlo:', textAlign: TextAlign.center),
                        const SizedBox(height: 16),
                        Container(
                          height: 200, // Altura fija para el cuadro de texto
                          padding: const EdgeInsets.all(8.0),
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.grey.shade300),
                            borderRadius: BorderRadius.circular(8),
                            color: Colors.grey.shade50,
                          ),
                          child: SingleChildScrollView( // Permite el scroll
                            child: SelectableText(error, style: const TextStyle(color: Colors.blue, fontSize: 12)),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }
              return Center(child: Text('Error: ${productSnapshot.error}'));
            }
            if (!productSnapshot.hasData) {
              return const Center(child: Text('No hay productos.'));
            }

            final productDocs = productSnapshot.data!.docs;
            final filteredDocs = productDocs.where((doc) {
              if (searchTerm.isEmpty) return true;
              final data = doc.data() as Map<String, dynamic>;
              final name = (data['name'] as String? ?? '').toLowerCase();
              return name.contains(searchTerm.toLowerCase());
            }).toList();

            if (filteredDocs.isEmpty) {
              return Center(child: Text(searchTerm.isEmpty ? l10n.get('noProducts') : l10n.get('noProductsFound')));
            }

            if (sortOption == SortOption.none) {
              filteredDocs.sort((a, b) {
                final dataA = a.data() as Map<String, dynamic>;
                final dataB = b.data() as Map<String, dynamic>;
                return (dataA['name'] ?? '').toString().toLowerCase().compareTo((dataB['name'] ?? '').toString().toLowerCase());
              });
            }

            if (sortOption != SortOption.none) {
              return _buildGroupedListView(context, filteredDocs, categoryMap, supplierMap);
            }
            return _buildProductListView(context, filteredDocs, categoryMap);
          },
        );
      },
    );
  }

  Widget _buildGroupedListView(BuildContext context, List<DocumentSnapshot> products, Map<String, String> categoryMap, Map<String, String> supplierMap) {
    final l10n = AppLocalizations.of(context);
    final Map<String, List<DocumentSnapshot>> groupedProducts = {};

    for (var doc in products) {
      final data = doc.data() as Map<String, dynamic>;
      String? key;
      if (sortOption == SortOption.byCategory) {
        key = data['categoryId']?.toString();
      } else if (sortOption == SortOption.bySupplier) {
        key = data['supplierId']?.toString();
      }
      key ??= 'sin-grupo';

      if (!groupedProducts.containsKey(key)) {
        groupedProducts[key] = [];
      }
      groupedProducts[key]!.add(doc);
    }

    final sortedGroupKeys = groupedProducts.keys.toList()
      ..sort((a, b) {
        if (a == 'sin-grupo') return 1;
        if (b == 'sin-grupo') return -1;
        String nameA = (sortOption == SortOption.byCategory ? categoryMap[a] : supplierMap[a]) ?? '';
        String nameB = (sortOption == SortOption.byCategory ? categoryMap[b] : supplierMap[b]) ?? '';
        return nameA.compareTo(nameB);
      });

    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 100),
      itemCount: sortedGroupKeys.length,
      itemBuilder: (context, index) {
        final key = sortedGroupKeys[index];
        final groupProducts = groupedProducts[key]!;
        String title;
        if (key == 'sin-grupo') {
          title = sortOption == SortOption.byCategory ? '${l10n.get('no')} ${l10n.get('category')}' : '${l10n.get('no')} ${l10n.get('supplier')}';
        } else {
          title = (sortOption == SortOption.byCategory ? categoryMap[key] : supplierMap[key]) ?? 'Desconocido';
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
              child: Text(title.toUpperCase(), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey, letterSpacing: 1.2)),
            ),
            ...groupProducts.map((doc) => Column(children: [_buildProductItem(context, doc, categoryMap, products), const Divider(height: 1, indent: 16, endIndent: 16)])),
            const Divider(),
          ],
        );
      },
    );
  }

  ListView _buildProductListView(BuildContext context, List<DocumentSnapshot> products, Map<String, String> categoryMap) {
    return ListView.separated(
      padding: const EdgeInsets.only(bottom: 100),
      itemCount: products.length,
      separatorBuilder: (context, index) => const Divider(height: 1, indent: 16, endIndent: 16),
      itemBuilder: (context, index) => _buildProductItem(context, products[index], categoryMap, products),
    );
  }

  Widget _buildProductItem(BuildContext context, DocumentSnapshot doc, Map<String, String> categoryMap, List<DocumentSnapshot> allProducts) {
    final data = doc.data() as Map<String, dynamic>;
    final netPrice = (data['price'] is num)
        ? (data['price'] as num).toDouble()
        : double.tryParse(data['price']?.toString() ?? '0') ?? 0.0;
    final priceWithVat = netPrice * (1 + vatRate);
    final categoryId = data['categoryId']?.toString();
    final l10n = AppLocalizations.of(context);
    final categoryName = categoryId != null ? categoryMap[categoryId] : '${l10n.get('no')} ${l10n.get('category')}';
    final bool isActive = (data['state'] is bool) ? data['state'] : true;
    final unitsBox = (data['units_box'] as num?)?.toInt() ?? 0;
    final imageUrl = data['imageUrl']?.toString();
    
    return Dismissible(
      key: Key(doc.id),
      direction: DismissDirection.endToStart,
      background: Container(
        color: Colors.red,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.symmetric(horizontal: 20.0),
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      confirmDismiss: (direction) => _confirmDismissProduct(context, doc.id),
      onDismissed: (direction) => _onProductDismissed(context, doc.id),
      child: InkWell(
        onTap: () => onProductTap(doc),
        child: Container(
          color: isActive ? Colors.transparent : Colors.grey.shade50,
          child: Opacity(
            opacity: isActive ? 1.0 : 0.5,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
            child: Row(
              children: [
                GestureDetector(
                  onTap: () => _showLargeImageDialog(context, allProducts, allProducts.indexOf(doc)),
                  child: imageUrl != null
                      ? ClipRRect(
                          borderRadius: BorderRadius.circular(4.0),
                          child: Image.network(imageUrl, width: 75, height: 75, fit: BoxFit.cover))
                      : const Icon(Icons.image, size: 50),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text.rich(
                              TextSpan(
                                children: [
                                  TextSpan(
                                    text: (data['name'] as String? ?? ''),
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      decoration: isActive ? TextDecoration.none : TextDecoration.lineThrough,
                                    ),
                                  ),
                                  if (unitsBox > 1)
                                    TextSpan(
                                      text: ' ${l10n.get('unitsPerBox').replaceFirst('{count}', unitsBox.toString())}',
                                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.normal, color: Colors.grey[600]),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                      Text(categoryName ?? '', style: Theme.of(context).textTheme.bodySmall),
                      Text('Stock: ${data['stock'] ?? 0}'),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text('\$${priceWithVat.toStringAsFixed(0)}', style: const TextStyle(fontSize: 16)),
                    Text('(neto \$${netPrice.toStringAsFixed(2)})', style: const TextStyle(fontSize: 12)),
                    StreamBuilder<QuerySnapshot>(
                      stream: firestoreService.getOffers(doc.id),
                      builder: (context, snapshot) {
                        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) return const SizedBox.shrink();
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(l10n.get('offers'), style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.red.shade800)),
                            ...snapshot.data!.docs.map((offer) {
                            final oData = offer.data() as Map<String, dynamic>;
                            final oQty = (oData['quantity'] is num)
                                ? (oData['quantity'] as num).toDouble()
                                : double.tryParse(oData['quantity']?.toString() ?? '0') ?? 0.0;
                            final oNet = (oData['price'] is num)
                                ? (oData['price'] as num).toDouble()
                                : double.tryParse(oData['price']?.toString() ?? '0') ?? 0.0;
                            final oGross = oNet * (1 + vatRate);
                            return Container(
                              margin: const EdgeInsets.only(top: 2),
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.red.shade50,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: Colors.red.shade200),
                              ),
                              child: Text(
                                'x${oQty.toStringAsFixed(0)}: \$${oGross.toStringAsFixed(0)} \n(Neto: \$${oNet.toStringAsFixed(2)})',
                                style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.red.shade800),
                              ),
                            );
                          }),
                          ],
                        );
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
      ),
    );
  }

  void _showLargeImageDialog(BuildContext context, List<DocumentSnapshot> products, int initialIndex) {
    final l10n = AppLocalizations.of(context);
    showDialog(
      context: context,
      builder: (context) => Dialog(
        insetPadding: const EdgeInsets.all(10),
        child: SizedBox(
          width: double.maxFinite,
          height: MediaQuery.of(context).size.height * 0.85,
          child: Stack(
            children: [
              PageView.builder(
                controller: PageController(initialPage: initialIndex),
                itemCount: products.length,
                itemBuilder: (context, index) {
                  final doc = products[index];
                  final data = doc.data() as Map<String, dynamic>;
                  final unitsBox = (data['units_box'] as num?)?.toInt() ?? 0;
                  final productId = doc.id;

                  final netPrice = (data['price'] is num)
                      ? (data['price'] as num).toDouble()
                      : double.tryParse(data['price']?.toString() ?? '0') ?? 0.0;

                  return SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Center(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(20.0),
                            child: data['imageUrl'] != null
                                ? Image.network(data['imageUrl'], fit: BoxFit.contain, height: 300)
                                : const SizedBox(
                                    height: 200,
                                    child: Icon(Icons.image, size: 100, color: Colors.grey)),
                          ),
                        ),
                        
                        Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text.rich(
                                TextSpan(
                                  children: [
                                    TextSpan(
                                      text: (data['name'] as String? ?? ''),
                                      style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                                    ),
                                    if (unitsBox > 1)
                                      TextSpan(
                                        text: ' ${l10n.get('unitsPerBox').replaceFirst('{count}', unitsBox.toString())}',
                                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.normal, color: Colors.grey),
                                      ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 8),
                              if (data['description'] != null && data['description'].toString().isNotEmpty) ...[
                                Text(
                                  data['description'],
                                  style: const TextStyle(fontSize: 16),
                                  textAlign: TextAlign.justify,
                                ),
                                const SizedBox(height: 16),
                              ],
                              
                              Text.rich(
                                TextSpan(
                                  text: 'Precio: \$${(netPrice * (1 + vatRate)).toStringAsFixed(0)} ',
                                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.blue),
                                  children: [
                                    TextSpan(
                                      text: '(Neto: \$${netPrice.toStringAsFixed(2)})',
                                      style: const TextStyle(fontSize: 20, color: Colors.grey, fontWeight: FontWeight.normal),
                                    ),
                                  ],
                                ),
                              ),

                              const SizedBox(height: 16),
                              
                              StreamBuilder<QuerySnapshot>(
                                stream: firestoreService.getOffers(productId),
                                builder: (context, snapshot) {
                                  if (!snapshot.hasData || snapshot.data!.docs.isEmpty) return const SizedBox.shrink();
                                  
                                  return Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Divider(),
                                      const Text('Ofertas:', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                                      const SizedBox(height: 8),
                                      ...snapshot.data!.docs.map((offer) {
                                        final oData = offer.data() as Map<String, dynamic>;
                                        final oQty = (oData['quantity'] is num) ? (oData['quantity'] as num).toDouble() : 0.0;
                                        final oNet = (oData['price'] is num) ? (oData['price'] as num).toDouble() : 0.0;
                                        final oGross = oNet * (1 + vatRate);
                                        
                                        return Padding(
                                          padding: const EdgeInsets.only(bottom: 4.0),
                                          child: Text.rich(
                                            TextSpan(
                                              text: '• x${oQty.toStringAsFixed(0)}: \$${oGross.toStringAsFixed(0)} ',
                                              style: const TextStyle(fontSize: 18, color: Colors.red, fontWeight: FontWeight.bold),
                                              children: [
                                                TextSpan(
                                                  text: '(Neto: \$${oNet.toStringAsFixed(2)})',
                                                  style: const TextStyle(fontSize: 18, color: Colors.grey),
                                                ),
                                              ],
                                            ),
                                          ),
                                        );
                                      }),
                                    ],
                                  );
                                },
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
              Positioned(
                top: 0,
                right: 0,
                child: IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<bool> _confirmDismissProduct(BuildContext context, String productId) async {
    final isAssociated = await firestoreService.isProductInAnySale(productId);

    if (!context.mounted) return false;

    if (isAssociated) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Este producto no se puede eliminar porque está en una o más ventas.'),
          backgroundColor: Colors.red,
        ),
      );
      return false;
    }

    return await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirmar Eliminación'),
        content: const Text('¿Seguro que quieres eliminar este producto?'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancelar')),
          TextButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Eliminar', style: TextStyle(color: Colors.red))),
        ],
      ),
    ) ?? false;
  }

  void _onProductDismissed(BuildContext context, String productId) async {
    try {
      await firestoreService.deleteProduct(productId);
      await firestoreService.deleteProductOffers(productId); // Clean up offers
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Producto eliminado')));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error al eliminar: $e')));
      }
    }
  }
}

class ProductDialog extends StatefulWidget {
  final User user;
  final String businessId;
  final FirestoreService firestoreService;
  final DocumentSnapshot? product;

  const ProductDialog({
    super.key, 
    required this.user,
    required this.businessId,
    required this.firestoreService,
    this.product,
  });

  @override
  State<ProductDialog> createState() => _ProductDialogState();
}

class _ProductDialogState extends State<ProductDialog> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameController;
  late TextEditingController _descriptionController;
  late TextEditingController _barCodeController;
  late TextEditingController _purchPriceController;
  late TextEditingController _priceController;
  late TextEditingController _stockController;
  late TextEditingController _safetyStockController;
  late TextEditingController _marginController;
  late TextEditingController _unitsBoxController;

  String? _selectedCategoryId;
  String? _selectedSupplierId;
  File? _imageFile;
  String? _existingImageUrl;
  final ValueNotifier<String?> _suggestedPriceTextNotifier = ValueNotifier(null);
  double _vatRateFromSettings = 0.21;
  double _defaultMarginFromSettings = 30.0;
  bool _salePriceIncludesVat = false;
  bool _purchasePriceIncludesVat = false;
  bool _isActive = true;
  bool _isLoading = true;
  Stream<QuerySnapshot>? _offersStream;
  late Stream<QuerySnapshot> _categoriesStream;
  late Stream<QuerySnapshot> _suppliersStream;

  bool get isEditing => widget.product != null;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController();
    _descriptionController = TextEditingController();
    _barCodeController = TextEditingController();
    _purchPriceController = TextEditingController();
    _priceController = TextEditingController();
    _stockController = TextEditingController();
    _safetyStockController = TextEditingController();
    _unitsBoxController = TextEditingController();
    _marginController = TextEditingController();

    _purchPriceController.addListener(_updateSuggestion);
    _marginController.addListener(_updateSuggestion);
    _priceController.addListener(_updateSuggestion);

    _categoriesStream = widget.firestoreService.getCategories(widget.businessId);
    _suppliersStream = widget.firestoreService.getSuppliers(widget.businessId);

    if (isEditing) {
      _offersStream = widget.firestoreService.getOffers(widget.product!.id);
    }

    _initializeForm();
  }

  Future<void> _initializeForm() async {
    await _loadCompanySettings();

    final data = widget.product?.data() as Map<String, dynamic>?;

    _nameController.text = data?['name']?.toString() ?? '';
    _descriptionController.text = data?['description']?.toString() ?? '';
    _barCodeController.text = data?['bar_code']?.toString() ?? '';
    
    // Safe parsing for numeric fields
    var stockVal = data?['stock'];
    _stockController.text = (stockVal is num ? stockVal.toInt() : (int.tryParse(stockVal?.toString() ?? '0') ?? 0)).toString();

    var safetyStockVal = data?['safety_stock'];
    _safetyStockController.text = (safetyStockVal is num ? safetyStockVal.toInt() : (int.tryParse(safetyStockVal?.toString() ?? '5') ?? 5)).toString();

    var unitsBoxVal = data?['units_box'];
    if (unitsBoxVal is num) {
      _unitsBoxController.text = unitsBoxVal.toInt().toString();
    } else {
      _unitsBoxController.text = unitsBoxVal?.toString() ?? '';
    }

    // Safe parsing for booleans
    var purchVatVal = data?['purchase_price_includes_vat'];
    _purchasePriceIncludesVat = purchVatVal is bool ? purchVatVal : false;

    _selectedCategoryId = data?['categoryId']?.toString();
    _selectedSupplierId = data?['supplierId']?.toString();
    _existingImageUrl = data?['imageUrl']?.toString();
    
    var stateVal = data?['state'];
    _isActive = stateVal is bool ? stateVal : true;

    _updateFieldsOnLoad(data);
    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _loadCompanySettings() async {
    final settingsDoc = await widget.firestoreService.getCompanySettingsOnce(widget.businessId);
    if (settingsDoc.exists) {
      final settingsData = settingsDoc.data() as Map<String, dynamic>?;
      _vatRateFromSettings = (settingsData?['vat_rate'] as num? ?? 21.0) / 100.0;
      _defaultMarginFromSettings = (settingsData?['default_margin'] as num? ?? 30.0).toDouble();
    }
  }

  void _updateFieldsOnLoad(Map<String, dynamic>? data) {
    if (isEditing && data != null) {
      // Helper to safely get double
      double getSafeDouble(dynamic val) {
        if (val is num) return val.toDouble();
        if (val is String) return double.tryParse(val) ?? 0.0;
        return 0.0;
      }

      final netPurchasePrice = getSafeDouble(data['purch_price']);
      final purchasePriceToShow = _purchasePriceIncludesVat
          ? netPurchasePrice * (1 + _vatRateFromSettings)
          : netPurchasePrice;
      _purchPriceController.text = purchasePriceToShow.toStringAsFixed(2);

      final netSalePrice = getSafeDouble(data['price']);
      final priceToShow = _salePriceIncludesVat
          ? netSalePrice * (1 + _vatRateFromSettings)
          : netSalePrice;
      _priceController.text = priceToShow.toStringAsFixed(2);

      final purchasePrice = getSafeDouble(data['purch_price']);

      if (netSalePrice > 0 && purchasePrice > 0) {
        final netCost = purchasePrice;
        final margin = (1 - (netCost / netSalePrice)) * 100;
        _marginController.text = margin.toStringAsFixed(2);
      } else {
        _marginController.text = _defaultMarginFromSettings.toString();
      }
    } else {
      _marginController.text = _defaultMarginFromSettings.toString();
      _priceController.text = '0.0';
    }
  }

  @override
  void dispose
  () {
    _nameController.dispose();
    _descriptionController.dispose();
    _barCodeController.dispose();
    _purchPriceController.dispose();
    _priceController.dispose();
    _stockController.dispose();
    _safetyStockController.dispose();
    _marginController.dispose();
    _unitsBoxController.dispose();
    _suggestedPriceTextNotifier.dispose();
    super.dispose();
  }

  Future<void> _scanBarcode() async {
    final result = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (context) => const BarcodeScannerSimple()),
    );

    if (result != null && mounted) {
      setState(() {
        _barCodeController.text = result;
      });
    }
  }

  void _updateSuggestion() {
    if (!mounted) return;
    _suggestSalePrice(vatRate: _vatRateFromSettings, margin: double.tryParse(_marginController.text));
  }

  void _suggestSalePrice({required double vatRate, double? margin}) {
    if (!mounted) return;
    final costText = _purchPriceController.text;
    final marginText = _marginController.text;

    final currentVatRate = vatRate;
    final currentMarginPercent = margin ?? double.tryParse(marginText);

    if (costText.isNotEmpty && currentMarginPercent != null) {
      final costInput = double.tryParse(costText);

      if (costInput != null && currentMarginPercent < 100 && currentMarginPercent > 0) {
        final netCost = _purchasePriceIncludesVat ? costInput / (1 + currentVatRate) : costInput;
        final suggestedPrice = netCost / (1 - (currentMarginPercent / 100));
        if (suggestedPrice.isFinite) {
          final suggestedPriceWithVat = suggestedPrice * (1 + currentVatRate);
          _suggestedPriceTextNotifier.value = 'Sugerido: \$${suggestedPriceWithVat.toStringAsFixed(2)} (neto: \$${suggestedPrice.toStringAsFixed(2)})';
        } else {
          _suggestedPriceTextNotifier.value = null;
        }
      } else {
        _suggestedPriceTextNotifier.value = null;
      }
    }
  }

  void _recalculatePurchasePriceOnVatToggle(bool isNowIncludingVat, {double? vatRate}) {
    final costText = _purchPriceController.text;
    if (costText.isEmpty) return;

    final costInput = double.tryParse(costText);
    if (costInput == null) return;

    final currentVatRate = vatRate ?? _vatRateFromSettings;
    double newCost;

    if (isNowIncludingVat) {
      newCost = costInput * (1 + currentVatRate);
    } else {
      newCost = costInput / (1 + currentVatRate);
    }

    _purchPriceController.text = newCost.toStringAsFixed(2);
    _suggestSalePrice(vatRate: currentVatRate);
  }

  void _recalculateSalePriceOnVatToggle(bool isNowIncludingVat) {
    final priceText = _priceController.text;
    if (priceText.isEmpty) return;

    final priceInput = double.tryParse(priceText);
    if (priceInput == null) return;

    final currentVatRate = _vatRateFromSettings;
    double newPrice;

    if (isNowIncludingVat) {
      newPrice = priceInput * (1 + currentVatRate);
    } else {
      newPrice = priceInput / (1 + currentVatRate);
    }

    _priceController.text = newPrice.toStringAsFixed(2);
  }

  Future<void> _pickImage() async {
    final pickedFile = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (pickedFile != null) {
      setState(() {
        _imageFile = File(pickedFile.path);
      });
    }
  }

  Future<void> _saveProduct() async {
    if (_formKey.currentState!.validate()) {
      final name = _nameController.text;
      final description = _descriptionController.text;
      final barCode = _barCodeController.text;

      final isUnique = await widget.firestoreService.isProductNameUnique(
        widget.businessId,
        name,
        currentProductId: widget.product?.id,
      );

      if (!isUnique && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Ya existe un producto con este nombre.'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      if (barCode.isNotEmpty) {
        final isBarcodeUnique = await widget.firestoreService.isBarcodeUnique(
          widget.businessId,
          barCode,
          currentProductId: widget.product?.id,
        );

        if (!isBarcodeUnique && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Ya existe un producto con este código de barras.'), backgroundColor: Colors.red),
          );
          return;
        }
      }

      final purchPriceInput = double.tryParse(_purchPriceController.text) ?? 0.0;
      final priceInput = double.tryParse(_priceController.text) ?? 0.0;
      final stock = int.tryParse(_stockController.text) ?? 0;
      final safetyStock = int.tryParse(_safetyStockController.text) ?? 5;
      final unitsBox = int.tryParse(_unitsBoxController.text);

      final double salePriceToSave;
      if (_salePriceIncludesVat) {
        salePriceToSave = priceInput / (1 + _vatRateFromSettings);
      } else {
        salePriceToSave = priceInput;
      }

      final double purchasePriceToSave;
      if (_purchasePriceIncludesVat) {
        purchasePriceToSave = purchPriceInput / (1 + _vatRateFromSettings);
      } else {
        purchasePriceToSave = purchPriceInput;
      }

      String? imageUrl = _existingImageUrl;

      try {
        if (isEditing) {
          if (_imageFile != null) {
            imageUrl = await widget.firestoreService.uploadImage(_imageFile!, widget.product!.id);
          }
          await widget.firestoreService.updateProduct(widget.product!.id, name, description, barCode, purchasePriceToSave, _purchasePriceIncludesVat, salePriceToSave, stock, safetyStock, unitsBox, imageUrl, _selectedCategoryId, _selectedSupplierId, _isActive);
        } else {
          final docRef = await widget.firestoreService.addProduct(widget.businessId, name, description, barCode, purchasePriceToSave, _purchasePriceIncludesVat, salePriceToSave, stock, safetyStock, unitsBox, null, _selectedCategoryId, _selectedSupplierId, _isActive);
          if (_imageFile != null) {
            imageUrl = await widget.firestoreService.uploadImage(_imageFile!, docRef.id);
            await docRef.update({'imageUrl': imageUrl});
          }
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error al guardar: $e'), backgroundColor: Colors.red),
          );
        }
        return;
      }

      if (!mounted) return;
      Navigator.of(context).pop();
    }
  }

  Future<void> _showAddCategoryDialog() async {
    final categoryNameController = TextEditingController();
    final newCategory = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Añadir Nueva Categoría'),
        content: SizedBox(
          width: double.maxFinite,
          child: TextField(
            controller: categoryNameController,
            autofocus: true,
            textCapitalization: TextCapitalization.characters,
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z\s]')), CapitalizeOnInputFormatter()],
            decoration: const InputDecoration(labelText: 'Nombre de la categoría'),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancelar')),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(categoryNameController.text),
            child: const Text('Guardar'),
          ),
        ],
      ),
    );

    if (newCategory != null && newCategory.isNotEmpty) {
      final docRef = await widget.firestoreService.addCategory(widget.businessId, newCategory);
      setState(() {
        _selectedCategoryId = docRef.id;
      });
    }
  }

  Future<void> _showAddSupplierDialog() async {
    final formKey = GlobalKey<FormState>();
    final nameController = TextEditingController();
    final contactController = TextEditingController();
    final phoneController = TextEditingController();
    final emailController = TextEditingController();

    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Añadir Nuevo Proveedor'),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: nameController,
                    decoration: const InputDecoration(labelText: 'Nombre del Proveedor'),
                    validator: (value) => (value?.isEmpty ?? true) ? 'Este campo es requerido' : null,
                    textCapitalization: TextCapitalization.characters,
                    inputFormatters: [CapitalizeOnInputFormatter()],
                  ),
                  TextFormField(
                    controller: contactController,
                    decoration: const InputDecoration(labelText: 'Persona de Contacto'),
                    textCapitalization: TextCapitalization.characters,
                    inputFormatters: [CapitalizeOnInputFormatter()],
                  ),
                  TextFormField(
                    controller: phoneController,
                    decoration: const InputDecoration(labelText: 'Teléfono'),
                    keyboardType: TextInputType.phone,
                  ),
                  TextFormField(
                    controller: emailController,
                    decoration: const InputDecoration(labelText: 'Email'),
                    keyboardType: TextInputType.emailAddress,
                  ),
                ],
              ),
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancelar')),
          ElevatedButton(
            onPressed: () {
              if (formKey.currentState!.validate()) {
                Navigator.of(context).pop({
                  'name': nameController.text,
                  'contact': contactController.text,
                  'phone': phoneController.text,
                  'email': emailController.text,
                });
              }
            },
            child: const Text('Guardar'),
          ),
        ],
      ),
    );

    if (result != null) {
      final docRef = await widget.firestoreService.addSupplier(
        widget.businessId,
        result['name']!,
        result['contact']!,
        result['phone']!,
        result['email']!,
      );
      setState(() => _selectedSupplierId = docRef.id);
    }
  }

  Future<void> _showAddOfferDialog() async {
    final quantityController = TextEditingController();
    final priceController = TextEditingController();
    final nameController = TextEditingController();
    bool offerPriceIncludesVat = false;

    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setStateDialog) {
          return AlertDialog(
            title: const Text('Añadir Oferta'),
            content: SizedBox(
              width: double.maxFinite,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: nameController,
                      decoration: const InputDecoration(labelText: 'Nombre (ej. Mayorista)'),
                      textCapitalization: TextCapitalization.sentences,
                    ),
                    TextField(
                      controller: quantityController,
                      decoration: const InputDecoration(labelText: 'Cantidad Mínima'),
                      keyboardType: TextInputType.number,
                    ),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(
                          child: TextField(
                            controller: priceController,
                            decoration: const InputDecoration(labelText: 'Precio Unitario', prefixText: '\$'),
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text('¿IVA Incl.?', style: TextStyle(fontSize: 12)),
                            Checkbox(
                              value: offerPriceIncludesVat,
                              onChanged: (value) {
                                if (value == null) return;
                                setStateDialog(() {
                                  offerPriceIncludesVat = value;
                                  final priceText = priceController.text;
                                  if (priceText.isNotEmpty) {
                                    final priceInput = double.tryParse(priceText);
                                    if (priceInput != null) {
                                      double newPrice;
                                      if (offerPriceIncludesVat) {
                                        newPrice = priceInput * (1 + _vatRateFromSettings);
                                      } else {
                                        newPrice = priceInput / (1 + _vatRateFromSettings);
                                      }
                                      priceController.text = newPrice.toStringAsFixed(2);
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
              TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancelar')),
              ElevatedButton(
                onPressed: () async {
                  final qty = double.tryParse(quantityController.text);
                  final priceInput = double.tryParse(priceController.text);
                  final name = nameController.text;

                  if (qty != null && priceInput != null && name.isNotEmpty) {
                    double finalPrice = priceInput;
                    if (offerPriceIncludesVat) {
                      finalPrice = priceInput / (1 + _vatRateFromSettings);
                    }

                    await widget.firestoreService.addOffer(
                      widget.businessId,
                      widget.product!.id,
                      qty,
                      finalPrice,
                      name
                    );
                    if (context.mounted) {
                      Navigator.of(context).pop();
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Oferta creada con éxito')));
                    }
                  }
                },
                child: const Text('Guardar'),
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(isEditing ? l10n.get('editProduct') : l10n.get('addProduct')),      
      content: _isLoading
          ? const SizedBox(height: 200, child: Center(child: CircularProgressIndicator()))
          : SizedBox(
              width: double.maxFinite,
              child: SingleChildScrollView(
                child: Form(
                  key: _formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Center(
                        child: Stack(
                          children: [
                        GestureDetector(
                          onTap: _pickImage,
                          child: Container(
                            height: 120,
                            width: 120,
                            decoration: BoxDecoration(
                              color: Colors.grey[200],
                              borderRadius: BorderRadius.circular(12),
                              image: _imageFile != null
                                  ? DecorationImage(image: FileImage(_imageFile!), fit: BoxFit.cover)
                                  : (_existingImageUrl != null
                                      ? DecorationImage(image: NetworkImage(_existingImageUrl!), fit: BoxFit.cover)
                                      : null),
                            ),
                            child: (_imageFile == null && _existingImageUrl == null)
                                ? Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      const Icon(Icons.camera_alt, size: 30, color: Colors.grey),
                                      Text(l10n.get('uploadLogo'), style: const TextStyle(fontSize: 12, color: Colors.grey)),
                                    ],
                                  )
                                : null,
                          ),
                        ),
                        if (_imageFile != null || _existingImageUrl != null)
                          Positioned(
                            bottom: 0,
                            right: 0,
                            child: CircleAvatar(
                              radius: 20,
                              backgroundColor: Colors.white,
                              child: IconButton(
                                icon: const Icon(Icons.delete, color: Colors.red, size: 20),
                                onPressed: () => setState(() {
                                  _imageFile = null;
                                  _existingImageUrl = null;
                                }),
                                tooltip: l10n.get('deleteLogo'),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(l10n.get('productState'), style: const TextStyle(fontSize: 16)),
                      Switch(
                        value: _isActive,
                        onChanged: (value) {
                          setState(() => _isActive = value);
                        },
                        activeTrackColor: Colors.lightGreenAccent,
                      ),
                    ],
                  ),
                  TextFormField(
                    controller: _nameController,
                    decoration: InputDecoration(labelText: l10n.get('name')),
                    textCapitalization: TextCapitalization.characters,
                    inputFormatters: [CapitalizeOnInputFormatter()],
                    validator: (value) => value!.isEmpty ? l10n.get('required') : null,
                  ),
                  TextFormField(
                    controller: _descriptionController,
                    decoration: InputDecoration(labelText: l10n.get('description')),
                    textCapitalization: TextCapitalization.characters,
                    maxLines: 3,
                    minLines: 1,
                  ),
                  TextFormField(
                    controller: _barCodeController,
                    decoration: InputDecoration(
                      labelText: l10n.get('barCode'),
                      prefixIcon: const Icon(Icons.qr_code),
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.camera_alt),
                        onPressed: _scanBarcode,
                      ),
                    ),
                    keyboardType: TextInputType.text,
                  ),
                  TextFormField(
                    controller: _unitsBoxController,
                    decoration: InputDecoration(labelText: l10n.get('unitsBox')),
                    keyboardType: TextInputType.number,
                  ),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        child: StreamBuilder<QuerySnapshot>(
                          stream: _categoriesStream,
                          builder: (context, snapshot) {
                            if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
                            final categories = snapshot.data!.docs;
                            // Validar que la categoría seleccionada exista en la lista cargada para evitar errores
                            final val = _selectedCategoryId != null && categories.any((d) => d.id == _selectedCategoryId) ? _selectedCategoryId : null;
                            return DropdownButtonFormField<String?>(
                              initialValue: val,
                              hint: Text(l10n.get('category')),
                              items: categories.map((doc) {
                                return DropdownMenuItem(
                                  value: doc.id,
                                  child: Text((doc['name']?.toString() ?? l10n.get('noName'))),
                                );
                              }).toList(),
                              onChanged: (value) => setState(() => _selectedCategoryId = value),
                            );
                          },
                        ),
                      ),
                      //BOTON AÑADIR CATEGORÍA SOLO SI ES EL DUEÑO
                      if (widget.user.uid == widget.businessId)
                        IconButton(
                          icon: const Icon(Icons.add),
                          onPressed: _showAddCategoryDialog,
                          tooltip: l10n.get('addCategory'),
                        ),
                    ],
                  ),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        child: StreamBuilder<QuerySnapshot>(
                          stream: _suppliersStream,
                          builder: (context, snapshot) {
                            if (!snapshot.hasData) return const SizedBox.shrink();
                            final suppliers = snapshot.data!.docs;
                            // Validar que el proveedor seleccionado exista en la lista cargada
                            final val = _selectedSupplierId != null && suppliers.any((d) => d.id == _selectedSupplierId) ? _selectedSupplierId : null;
                            return DropdownButtonFormField<String?>(
                              initialValue: val,
                              hint: Text(l10n.get('supplier')),
                              items: suppliers.map((doc) {
                                return DropdownMenuItem(
                                  value: doc.id,
                                  child: Text((doc['name']?.toString() ?? l10n.get('noName'))),
                                );
                              }).toList(),
                              onChanged: (value) {
                                setState(() => _selectedSupplierId = value);
                              },
                            );
                          },
                        ),
                      ),
                      //BOTON AÑADIR PROVEEDOR SOLO SI ES EL DUEÑO
                      if (widget.user.uid == widget.businessId)
                        IconButton(
                          icon: const Icon(Icons.add),
                          onPressed: _showAddSupplierDialog,
                          tooltip: l10n.get('addSupplier'), // Ensure this key exists or use fallback
                        ),
                    ],
                  ),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _purchPriceController,
                          decoration: InputDecoration(labelText: l10n.get('purchasePrice'), prefixText: '\$'),
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(l10n.get('vatIncluded'), style: const TextStyle(fontSize: 12)),
                          Checkbox(
                            value: _purchasePriceIncludesVat,
                            onChanged: (value) => setState(() {
                              if (value == null) return;
                              _purchasePriceIncludesVat = value;
                              _recalculatePurchasePriceOnVatToggle(value, vatRate: _vatRateFromSettings);
                            }),
                            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                        ],
                      ),
                    ],
                  ),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _marginController,
                          decoration: InputDecoration(labelText: l10n.get('margin'), suffixText: '%'),
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        ),
                      ),
                    ],
                  ),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _priceController,
                          decoration: InputDecoration(labelText: l10n.get('salePrice'), prefixText: '\$'),
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          validator: (value) => value!.isEmpty ? l10n.get('required') : null,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(l10n.get('vatIncluded'), style: const TextStyle(fontSize: 12)),
                          Checkbox(
                            value: _salePriceIncludesVat,
                            onChanged: (value) => setState(() {
                              if (value == null) return;
                              _salePriceIncludesVat = value;
                              _recalculateSalePriceOnVatToggle(value);
                              _updateSuggestion();
                            }),
                            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                        ],
                      ),
                    ],
                  ),
                  ValueListenableBuilder<String?>(
                    valueListenable: _suggestedPriceTextNotifier,
                    builder: (context, suggestedText, child) {
                      if (suggestedText == null) return const SizedBox.shrink();
                      return Padding(
                        padding: const EdgeInsets.only(top: 4.0, left: 12.0, right: 12.0),
                        child: Text(
                          suggestedText,
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.blue.shade700),
                        ),
                      );
                    },
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _stockController,
                          decoration: InputDecoration(labelText: l10n.get('currentStock')),
                          keyboardType: TextInputType.number,
                          validator: (value) => value!.isEmpty ? l10n.get('required') : null,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextFormField(
                          controller: _safetyStockController,
                          decoration: InputDecoration(labelText: l10n.get('safetyStock')),
                          keyboardType: TextInputType.number,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  if (isEditing) ...[
                    const Divider(),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Padding(
                        padding: EdgeInsets.symmetric(vertical: 8.0),
                        child: Text(l10n.get('offersActive'), style: const TextStyle(fontWeight: FontWeight.bold)),
                      ),
                    ),
                    StreamBuilder<QuerySnapshot>(
                      stream: _offersStream,
                      builder: (context, snapshot) {
                        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 8.0),
                            child: Text(l10n.get('noOffers'), style: const TextStyle(color: Colors.grey)),
                          );
                        }
                        return Column(
                          mainAxisSize: MainAxisSize.min,
                          children: snapshot.data!.docs.map((offer) {
                            final data = offer.data() as Map<String, dynamic>;
                            final netPrice = (data['price'] as num?)?.toDouble() ?? 0.0;
                            final priceWithVat = netPrice * (1 + _vatRateFromSettings);
                            return ListTile(
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              title: Text('${data['name']} (Min: ${data['quantity']})'),
                              subtitle: Text('\$${priceWithVat.toStringAsFixed(2)} (Neto: \$${netPrice.toStringAsFixed(2)})'),
                              trailing: IconButton(
                                icon: const Icon(Icons.delete, color: Colors.red, size: 20),
                                onPressed: () => widget.firestoreService.deleteOffer(offer.id),
                              ),
                            );
                          }).toList(),
                        );
                      },
                    ),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.local_offer),
                        label: Text(l10n.get('createOffer')),
                        onPressed: _showAddOfferDialog,
                      ),
                    ),
                  ],
                ],
              ),
            ),
      ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.get('cancel')),
        ),
        ElevatedButton(
          onPressed: _saveProduct,
          child: Text(l10n.get('save')),
        ),
      ],
    );
  }
}

class BarcodeScannerSimple extends StatelessWidget {
  const BarcodeScannerSimple({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Escanear Código')),
      body: MobileScanner(
        onDetect: (capture) {
          final List<Barcode> barcodes = capture.barcodes;
          if (barcodes.isNotEmpty && barcodes.first.rawValue != null) {
            Navigator.pop(context, barcodes.first.rawValue);
          }
        },
      ),
    );
  }
}