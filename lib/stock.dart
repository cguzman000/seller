import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'firestore_service.dart';
import 'products.dart';
import 'app_localizations.dart';
import 'main.dart'; // Importar para usar SellerBottomNavigationBar

class StockPage extends StatefulWidget {
  final User user;
  final String businessId;
  final String? role;
  final String? sellerId;

  const StockPage({super.key, 
    required this.user, 
    required this.businessId, 
    this.sellerId, 
    required this.role});
  @override
  State<StockPage> createState() => _StockPageState(); 
}

class _StockPageState extends State<StockPage> {
  final FirestoreService _firestoreService = FirestoreService();
  final TextEditingController _searchController = TextEditingController();
  String _searchTerm = '';
  String? _selectedSupplierId;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _scanBarcode() async {
    final result = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (context) => const BarcodeScannerSimple()),
    );

    if (result != null && mounted) {
      setState(() {
        _searchController.text = result;
        _searchTerm = result.toLowerCase();
      });

      final snapshot = await FirebaseFirestore.instance
          .collection('products')
          .where('userId', isEqualTo: widget.businessId)
          .where('bar_code', isEqualTo: result.trim())
          .limit(1)
          .get();

      if (snapshot.docs.isNotEmpty && mounted) {
        _showUpdateStockDialog(snapshot.docs.first);
      }
    }
  }

  void _showUpdateStockDialog(DocumentSnapshot product) {
    final l10n = AppLocalizations.of(context);
    final currentStock = (product.data() as Map<String, dynamic>)['stock'] as int? ?? 0;
    final controller = TextEditingController();

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(l10n.get('addStockTo').replaceFirst('{productName}', product['name'])),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l10n.get('currentStockIs').replaceFirst('{stock}', currentStock.toString()), style: const TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              TextField(
                controller: controller,
                keyboardType: const TextInputType.numberWithOptions(signed: true),
                decoration: InputDecoration(
                  labelText: l10n.get('amountToAdd'),
                  helperText: l10n.get('negativeToSubtract'),
                  border: const OutlineInputBorder(),
                ),
                autofocus: true,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(l10n.get('cancel')),
            ),
            ElevatedButton(
              onPressed: () async {
                final amountToAdd = int.tryParse(controller.text);
                if (amountToAdd != null) {
                  await _firestoreService.incrementProductStock(product.id, amountToAdd);
                  if (context.mounted) {
                    Navigator.of(context).pop();
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(l10n.get('stockUpdated').replaceFirst('{amount}', amountToAdd.toString()))),
                    );
                  }
                }
              },
              child: Text(l10n.get('save')),
            ),
          ],
        );
      },
    );
  }
  
  void _showFilterSelectionDialog({required String title, required Stream<QuerySnapshot> stream, required Function(String?) onSelected}) {
    final l10n = AppLocalizations.of(context);
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
                    final data = doc.data() as Map<String, dynamic>;
                    return ListTile(
                      title: Text(data['name']),
                      onTap: () {
                        onSelected(doc.id);
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
              child: Text(l10n.get('cancel')),
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
        title: Text(l10n.get('stockManagement')),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      labelText: l10n.get('searchProduct'),
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.qr_code_scanner),
                        onPressed: _scanBarcode,
                        tooltip: l10n.get('scanBarcode'),
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      filled: true,
                      fillColor: Colors.grey.shade100,
                    ),
                    onChanged: (value) {
                      setState(() {
                        _searchTerm = value.toLowerCase();
                      });
                    },
                  ),
                ),
                const SizedBox(width: 8),
                PopupMenuButton<String>(
                  icon: Icon(
                    Icons.filter_list,
                    color: _selectedSupplierId != null ? Theme.of(context).colorScheme.primary : Colors.black,
                  ),
                  tooltip: l10n.get('filterProducts'),
                  onSelected: (value) {
                    if (value == 'supplier') {
                      _showFilterSelectionDialog(
                        title: l10n.get('selectSupplier'),
                        stream: _firestoreService.getSuppliers(widget.businessId),
                        onSelected: (id) => setState(() {
                          _selectedSupplierId = id;
                        }),
                      );
                    } else if (value == 'clear') {
                      setState(() {
                        _selectedSupplierId = null;
                      });
                    }
                  },
                  itemBuilder: (context) => [
                    PopupMenuItem(value: 'supplier', child: Text(l10n.get('bySupplier'))),
                    const PopupMenuDivider(),
                    PopupMenuItem(value: 'clear', child: Text(l10n.get('viewAll'))),
                  ],
                ),
              ],
            ),
          ),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: _firestoreService.getProducts(widget.businessId),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(child: Text('Error: ${snapshot.error}'));
                }
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                var products = snapshot.data!.docs;

                // Filtrado local por término de búsqueda
                if (_searchTerm.isNotEmpty) {
                  products = products.where((doc) {
                    final data = doc.data() as Map<String, dynamic>;
                    final name = (data['name'] as String).toLowerCase();
                    final barCode = (data['bar_code'] as String?)?.toLowerCase() ?? '';
                    return name.contains(_searchTerm) || barCode.contains(_searchTerm);
                  }).toList();
                }

                if (_selectedSupplierId != null) {
                  products = products.where((doc) {
                    final data = doc.data() as Map<String, dynamic>;
                    return data['supplierId'] == _selectedSupplierId;
                  }).toList();
                }

                if (products.isEmpty) {
                  return Center(child: Text(l10n.get('noProductsFound')));
                }

                return ListView.separated(
                  padding: const EdgeInsets.only(bottom: 100),
                  itemCount: products.length,
                  separatorBuilder: (context, index) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final product = products[index];
                    final data = product.data() as Map<String, dynamic>;
                    final stock = data['stock'] as int? ?? 0;
                    final unitsBox = data['units_box'] as int? ?? 0;
                    final safetyStock = (data['safety_stock'] as num?)?.toInt() ?? 5;
                    final isLowStock = stock <= safetyStock;

                    return ListTile(
                      title: Row(
                        children: [
                          Expanded(
                            child: Text(
                              data['name'],
                              style: const TextStyle(fontWeight: FontWeight.bold),
                            ),
                          ),
                          Text(
                            stock.toString(),
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: isLowStock ? Colors.red : Colors.blue.shade700,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            'uds',
                            style: TextStyle(
                              fontSize: 12,
                              color: isLowStock ? Colors.red.withValues(alpha: 0.7) : Colors.grey,
                            ),
                          ),
                        ],
                      ),
                      subtitle: unitsBox > 1
                          ? Align(
                              alignment: Alignment.centerRight,
                              child: Text(
                                l10n.get('inBoxes').replaceFirst('{boxes}', (stock / unitsBox).toStringAsFixed(1))
                                    .replaceAll('(', '').replaceAll(')', '').trim(),
                                style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                              ),
                            )
                          : null,
             
                      onTap: () => _showUpdateStockDialog(product),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
      bottomNavigationBar: SellerBottomNavigationBar(
        user: widget.user,
        businessId: widget.businessId,
        role: widget.role,
        sellerId: widget.sellerId,
        currentIndex: 6, // Índice correcto para Stock
        allowSamePageNavigation: true,
      ),
    );
  }
}

Future<void> incrementProductStock(String productId, int quantity) async {
  try {
    await FirebaseFirestore.instance
        .collection('products')
        .doc(productId)
        .update({
          'stock': FieldValue.increment(quantity),
        });
  } catch (e) {
    // ignore: avoid_print
    print('Error incrementing stock: $e');
    rethrow;
  }
}
