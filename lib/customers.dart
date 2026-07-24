import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'firestore_service.dart';
import 'app_localizations.dart';
// Importar para usar SellerBottomNavigationBar
import 'main.dart';

class CustomersPage extends StatefulWidget {
  final User user;
  final String businessId;
  final String role;
  final String? sellerId;

  const CustomersPage({super.key, required this.user, required this.businessId, required this.role, this.sellerId});

  @override
  State<CustomersPage> createState() => _CustomersPageState();
}

class _CustomersPageState extends State<CustomersPage> {
  final FirestoreService _firestoreService = FirestoreService();
  final TextEditingController _searchController = TextEditingController();
  String _searchTerm = '';
  String? _selectedCity;
  String _selectedSellerId = 'all'; // Cambiado a String no opcional para consistencia

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      setState(() {
        _searchTerm = _searchController.text;
      });
    });
  }

  String get _effectiveSellerName {
    if (widget.user.uid == widget.businessId) return 'Administrador';
    return widget.user.displayName ?? 'Vendedor';
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _showCustomerDialog({DocumentSnapshot? customer}) {
    final l10n = AppLocalizations.of(context);
    final formKey = GlobalKey<FormState>();
    final isEditing = customer != null;
    final nameController = TextEditingController(text: isEditing ? customer['name'] : '');
    final emailController = TextEditingController(text: isEditing ? customer['email'] : '');
    final phoneController = TextEditingController(text: isEditing ? customer['phone'] : '');
    final addressController = TextEditingController(text: isEditing ? customer['address'] : '');
    final dniController = TextEditingController(text: isEditing ? customer['dni'] : '');
    final contactController = TextEditingController(text: isEditing ? customer['contact'] : '');
    final cityController = TextEditingController(text: isEditing ? customer['city'] : '');

    String? selectedSellerId;
    if (isEditing) {
      final data = customer.data() as Map<String, dynamic>;
      selectedSellerId = data['sellerId'];
    } else {
      if (widget.role != 'admin') {
        selectedSellerId = widget.sellerId;
      }
    }

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
          title: Text(isEditing ? l10n.get('editCustomer') : l10n.get('addCustomer')),
          content: Form(
            key: formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(controller: nameController, decoration: InputDecoration(labelText: l10n.get('customerName')), validator: (v) => v!.isEmpty ? l10n.get('required') : null, textCapitalization: TextCapitalization.characters, inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z\s]'))]),
                  TextFormField(controller: dniController, decoration: InputDecoration(labelText: l10n.get('dni')), textCapitalization: TextCapitalization.characters),
                  TextFormField(controller: contactController, decoration: InputDecoration(labelText: l10n.get('contactPerson')), textCapitalization: TextCapitalization.characters, inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z\s]'))]),
                  TextFormField(controller: phoneController, decoration: InputDecoration(labelText: l10n.get('phone')), keyboardType: TextInputType.phone),
                  TextFormField(
                    controller: emailController,
                    decoration: InputDecoration(labelText: l10n.get('email')),
                    keyboardType: TextInputType.emailAddress,
                    validator: (value) {
                      if (value == null || value.isEmpty) return null; // El email es opcional
                      final emailRegex = RegExp(r"^[a-zA-Z0-9.a-zA-Z0-9.!#$%&'*+-/=?^_`{|}~]+@[a-zA-Z0-9]+\.[a-zA-Z]+");
                      if (!emailRegex.hasMatch(value)) {
                        return l10n.get('validEmail');
                      }
                      return null;
                    },
                  ),
                  TextFormField(controller: addressController, decoration: InputDecoration(labelText: l10n.get('address')), textCapitalization: TextCapitalization.characters),
                  TextFormField(controller: cityController, decoration: InputDecoration(labelText: l10n.get('city')), textCapitalization: TextCapitalization.characters),
                  if (widget.role == 'admin') ...[
                    const SizedBox(height: 16),
                    StreamBuilder<QuerySnapshot>(
                      stream: _firestoreService.getUsers(widget.businessId, role: 'seller'),
                      builder: (context, snapshot) {
                        if (!snapshot.hasData) return const SizedBox.shrink();
                        final sellers = snapshot.data!.docs;

                        final items = [
                          DropdownMenuItem<String?>(
                            value: null,
                            child: Text(l10n.get('adminUnassigned')),
                          ),
                          ...sellers.map((doc) => DropdownMenuItem<String?>(
                                value: doc.id,
                                child: Text(doc['name'] ?? 'Sin nombre'),
                              )),
                        ];

                        // Si el vendedor asignado no está en la lista (ej. fue eliminado), agregamos una opción temporal para evitar el crash.
                        if (selectedSellerId != null && !items.any((item) => item.value == selectedSellerId)) {
                          items.add(DropdownMenuItem<String?>(
                            value: selectedSellerId,
                            child: Text(l10n.get('sellerNotExist'), style: const TextStyle(color: Colors.red)),
                          ));
                        }

                        return DropdownButtonFormField<String?>(
                          initialValue: selectedSellerId,
                          decoration: InputDecoration(labelText: l10n.get('assignSeller'), border: const OutlineInputBorder()),
                          items: items,
                          onChanged: (value) => setState(() => selectedSellerId = value),
                        );
                      },
                    ),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(l10n.get('cancel'))),
            ElevatedButton(
              onPressed: () async {
                if (formKey.currentState!.validate()) {
                  final isUnique = await _firestoreService.isCustomerNameUnique(
                    widget.businessId,
                    nameController.text,
                    currentCustomerId: customer?.id,
                  );

                  if (!isUnique && context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar( // This context is from the dialog
                      SnackBar(
                        content: Text(l10n.get('customerExists')),
                        backgroundColor: Colors.red,
                      ),
                    );
                    return;
                  }

                  if (isEditing) {
                    await _firestoreService.updateCustomer(customer.id, nameController.text, emailController.text, phoneController.text, addressController.text, dniController.text, contactController.text, cityController.text, sellerId: selectedSellerId, updateSeller: widget.role == 'admin');
                  } else {
                    // Usamos businessId como dueño, y pasamos sellerId si el usuario no es el dueño
                    await _firestoreService.addCustomer(widget.businessId, nameController.text, emailController.text, phoneController.text, addressController.text, dniController.text, contactController.text, cityController.text, sellerId: selectedSellerId, creatorName: widget.user.displayName ?? (widget.role == 'admin' ? 'Admin' : 'Vendedor'));
                  }

                  if (!context.mounted) return;
                  Navigator.of(context).pop(); 
                }
              },
              child: Text(l10n.get('save')),
            ),
          ],
        );
      },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.get('customers')),
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
                      labelText: l10n.get('searchCustomer'),
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: _searchTerm.isNotEmpty ? IconButton(icon: const Icon(Icons.clear), onPressed: () => _searchController.clear()) : null,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12.0)),
                    ),
                  ),
                ),
                if (widget.role == 'admin')
                  StreamBuilder<QuerySnapshot>(
                    stream: _firestoreService.getUsers(widget.businessId, role: 'seller'),
                    builder: (context, snapshot) {
                      if (!snapshot.hasData) {
                        return const IconButton(icon: Icon(Icons.person_search), onPressed: null);
                      }
                      final sellers = snapshot.data!.docs;
                      return PopupMenuButton<String>(
                        icon: Icon(Icons.person_search, color: (_selectedSellerId != 'all') ? Theme.of(context).colorScheme.primary : null),
                        tooltip: l10n.get('filterSeller'),
                        onSelected: (sellerId) {
                          setState(() {
                            _selectedSellerId = sellerId;
                          });
                        },
                        itemBuilder: (context) {
                          return [
                            PopupMenuItem<String>(
                              value: 'all',
                              child: Text(l10n.get('allCustomers')), // Asegura que esto mande 'all'
                            ),
                            PopupMenuItem<String>(
                              value: widget.businessId,
                              child: Text(l10n.get('admin')),
                            ),
                            ...sellers.map((doc) => PopupMenuItem<String>(
                                  value: doc.id,
                                  child: Text(doc['name'] ?? 'Sin nombre'),
                                )),
                          ];
                        },
                      );
                    },
                  ),
                StreamBuilder<QuerySnapshot>(
                  stream: _firestoreService.getCustomers(widget.businessId, sellerId: widget.role == 'admin' ? _selectedSellerId : widget.sellerId),
                  builder: (context, snapshot) {
                    if (!snapshot.hasData) {
                      return const IconButton(icon: Icon(Icons.filter_list), onPressed: null);
                    }
                    final cities = snapshot.data!.docs
                        .map((doc) => (doc.data() as Map<String, dynamic>)['city'] as String?)
                        .where((city) => city != null && city.isNotEmpty)
                        .toSet()
                        .toList()..sort();

                    return PopupMenuButton<String?>(
                      icon: Icon(Icons.filter_list, color: (_selectedCity != null && _selectedCity != 'Todas las ciudades') ? Theme.of(context).colorScheme.primary : null),
                      onSelected: (city) {
                        setState(() {
                          _selectedCity = city;
                        });
                      },
                      itemBuilder: (context) {
                        return [
                          PopupMenuItem<String?>(
                            value: 'Todas las ciudades',
                            child: Text(l10n.get('allCities')),
                          ),
                          ...cities.map((city) => PopupMenuItem<String>(
                                value: city,
                                child: Text(city!),
                              )),
                        ];
                      },
                    );
                  },
                ),
              ],
            ),
          ),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: _firestoreService.getCustomers(widget.businessId, searchTerm: _searchTerm, city: _selectedCity, sellerId: widget.role == 'admin' ? _selectedSellerId : widget.sellerId),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  // Esto forzará el error a la consola de VS Code/Android Studio
                  debugPrint("DEBUG: Error en Stream de Clientes: ${snapshot.error}");
                  return Center(child: Text('Algo salió mal: ${snapshot.error}'));
                }
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                var filteredDocs = snapshot.data!.docs;

                if (filteredDocs.isEmpty) {
                  return Center(child: Text(_searchTerm.isEmpty && (_selectedCity == null || _selectedCity == 'Todas las ciudades') ? l10n.get('noCustomersAdd') : l10n.get('noCustomers')));
                }

                return ListView.separated(
                  padding: const EdgeInsets.only(bottom: 80),
                  itemCount: filteredDocs.length,
                  separatorBuilder: (context, index) => const Divider(height: 1, indent: 16, endIndent: 16),
                  itemBuilder: (context, index) {
                    final doc = filteredDocs[index];
                    final data = doc.data() as Map<String, dynamic>;
                    final isByAdmin = data['sellerId'] == null;
                    return Dismissible(
                      key: Key(doc.id),
                      direction: DismissDirection.endToStart,
                      background: Container(
                        color: Colors.red,
                        alignment: Alignment.centerRight,
                        padding: const EdgeInsets.symmetric(horizontal: 20.0),
                        child: const Icon(Icons.delete, color: Colors.white),
                      ),
                      confirmDismiss: (direction) async {
                        final isAssociated = await _firestoreService.isCustomerInAnySale(doc.id);

                        if (!context.mounted) return false;

                        if (isAssociated) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(l10n.get('cannotDeleteCustomer')),
                              backgroundColor: Colors.red,
                            ),
                          );
                          return false;
                        }
                        return await showDialog<bool>(
                          context: context,
                          builder: (dialogContext) => AlertDialog(
                            title: Text(l10n.get('delete')),
                            content: Text(l10n.get('confirmDeleteCustomer')),
                            actions: [
                              TextButton(
                                  onPressed: () => Navigator.of(dialogContext).pop(false),
                                  child: Text(l10n.get('cancel'))),
                              TextButton(
                                  onPressed: () => Navigator.of(dialogContext).pop(true),
                                  child: Text(l10n.get('delete'), style: const TextStyle(color: Colors.red))),
                            ],
                          ),
                        ) ?? false;
                      },
                      onDismissed: (direction) async {
                        try {
                          await _firestoreService.deleteCustomer(doc.id);
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l10n.get('customerDeleted'))));
                        } catch (e) {
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${l10n.get('errorDelete')}$e')));
                        }
                      },
                      child: ListTile(
                        leading: Icon(
                          isByAdmin ? Icons.business_center : Icons.person,
                          color: isByAdmin ? Colors.deepPurple : Theme.of(context).colorScheme.primary,
                        ),
                        title: Text(data['name'] ?? 'Sin nombre'),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (data['phone'] != null && data['phone'].isNotEmpty) Text(data['phone']),
                            if (data['email'] != null && data['email'].isNotEmpty) Text(data['email']),
                            if (data['city'] != null && data['city'].isNotEmpty) Text(data['city'], style: const TextStyle(fontStyle: FontStyle.italic)),
                            if (data['creatorName'] != null) Text('${l10n.get('createdBy')}${data['creatorName']}', style: const TextStyle(fontSize: 12, color: Colors.grey)),
                          ],
                        ),
                        trailing: IconButton(
                          icon: const Icon(Icons.monetization_on, color: Colors.green),
                          tooltip: l10n.get('payOnAccount'),
                          onPressed: () => _startPaymentFlowForCustomer(doc),
                        ),
                        onTap: () => _showCustomerDialog(customer: doc),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showCustomerDialog(),
        tooltip: l10n.get('addCustomer'),
        child: const Icon(Icons.add),
      ),
      bottomNavigationBar: SellerBottomNavigationBar(
        user: widget.user,
        businessId: widget.businessId,
        role: widget.role,
        sellerId: widget.sellerId,
        currentIndex: 3, // Índice para Clientes
      ),
    );
  }

  Future<void> _startPaymentFlowForCustomer(DocumentSnapshot customerDoc) async {
    final l10n = AppLocalizations.of(context);

    // 1. Seleccionar Modo de Pago
    final paymentMode = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.get('selectPaymentMode')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.list_alt),
              title: Text(l10n.get('paySpecificSales')),
              subtitle: const Text('Selecciona facturas puntuales'),
              onTap: () => Navigator.pop(context, 'specific'),
            ),
            ListTile(
              leading: const Icon(Icons.account_balance_wallet),
              title: Text(l10n.get('payOnAccount')),
              subtitle: const Text('Abona un monto al total de la deuda'),
              onTap: () => Navigator.pop(context, 'global'),
            ),
          ],
        ),
      ),
    );

    if (paymentMode == null || !mounted) return;

    // Calcular deudas
    showDialog(context: context, barrierDismissible: false, builder: (c) => const Center(child: CircularProgressIndicator()));
    
    List<_PendingSale> pendingSales = [];
    try {
      pendingSales = await _fetchPendingSales(customerDoc.id);
      if (mounted) Navigator.of(context).pop(); // Cerrar loading
    } catch (e) {
      if (mounted) {
        Navigator.of(context).pop(); // Cerrar loading
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Error'),
            content: SingleChildScrollView(child: SelectableText('Error al calcular deuda: $e')),
            actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cerrar'))],
          ),
        );
      }
      return;
    }
    
    if (pendingSales.isEmpty && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l10n.get('noPendingDebts'))));
      return;
    }

    if (!mounted) return;

    // 3. Flujo según el modo seleccionado
    if (paymentMode == 'specific') {
      await _showSpecificSalesDialog(customerDoc, pendingSales);
    } else {
      await _showGlobalPaymentDialog(customerDoc, pendingSales);
    }
  }

  Future<List<_PendingSale>> _fetchPendingSales(String customerId) async {
    final salesSnapshot = await _firestoreService.getSalesForCustomer(
      widget.businessId,
      customerId,
    ).first;

    final List<_PendingSale> pendingList = [];

    for (final saleDoc in salesSnapshot.docs) {
      final saleData = saleDoc.data() as Map<String, dynamic>;
      final total = (saleData['totalAmount'] as num?)?.toDouble() ?? 0.0;
      
      final paymentsSnapshot = await _firestoreService.getPaymentsForSale(saleDoc.id).first;
      final paid = paymentsSnapshot.docs.fold<double>(0.0, (prev, doc) {
        final pData = doc.data() as Map<String, dynamic>;
        final saleIds = pData['saleIds'];
        final isShared = saleIds is List && saleIds.length > 1;

        if (pData.containsKey('allocations') && pData['allocations'] is Map && (pData['allocations'] as Map).containsKey(saleDoc.id)) {
          return prev + ((pData['allocations'] as Map)[saleDoc.id] as num? ?? 0.0).toDouble();
        }
        return isShared ? prev : prev + (pData['amount'] as num? ?? 0.0).toDouble();
      });

      final pending = total - paid;
      if (pending > 0.01) {
        pendingList.add(_PendingSale(saleDoc, pending));
      }
    }
    return pendingList;
  }

  Future<void> _showSpecificSalesDialog(DocumentSnapshot customerDoc, List<_PendingSale> pendingSales) async {
    final l10n = AppLocalizations.of(context);
    final selectedSales = <String, bool>{};
    double totalSelected = 0.0;

    await showDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (sbContext, setState) {
            return AlertDialog(
              title: Text(l10n.get('paySpecificSales')),
              content: SizedBox(
                width: double.maxFinite,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('Total Seleccionado: \$${totalSelected.toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.bold)),
                    const Divider(),
                    Expanded(
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: pendingSales.length,
                        itemBuilder: (itemContext, index) {
                          final item = pendingSales[index];
                          final data = item.doc.data() as Map<String, dynamic>;
                          final date = (data['saleDate'] as Timestamp?)?.toDate() ?? DateTime.now();
                          
                          return CheckboxListTile(
                            title: Text('Venta #${data['sale_number'] ?? 'S/N'}'),
                            subtitle: Text('${DateFormat('dd/MM/yyyy').format(date)} - Pend: \$${item.pendingAmount.toStringAsFixed(2)}'),
                            value: selectedSales[item.doc.id] ?? false,
                            onChanged: (val) {
                              setState(() {
                                selectedSales[item.doc.id] = val ?? false;
                                totalSelected = pendingSales
                                    .where((s) => selectedSales[s.doc.id] == true)
                                    .fold(0.0, (prev, s) => prev + s.pendingAmount);
                              });
                            },
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.of(sbContext).pop(), child: Text(l10n.get('cancel'))),
                ElevatedButton(
                  onPressed: totalSelected > 0 
                    ? () {
                        Navigator.of(sbContext).pop(); 
                        final salesToPay = pendingSales.where((s) => selectedSales[s.doc.id] == true).map((s) => s.doc).toList();
                        _showFinalizePaymentDialog(customerDoc, totalSelected, salesToPay);
                      }
                    : null,
                  child: Text(l10n.get('continueToPay')),
                ),
              ],
            );
          }
        );
      }
    );
  }

  Future<void> _showGlobalPaymentDialog(DocumentSnapshot customerDoc, List<_PendingSale> pendingSales) async {
    final l10n = AppLocalizations.of(context);
    final totalDebt = pendingSales.fold(0.0, (prev, s) => prev + s.pendingAmount);
    final controller = TextEditingController();

    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.get('payOnAccount')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('${l10n.get('totalPending')}: \$${totalDebt.toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: l10n.get('amountToPay'),
                prefixText: '\$ ',
                border: const OutlineInputBorder(),
              ),
              autofocus: true,
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text(l10n.get('cancel'))),
          ElevatedButton(
            onPressed: () {
              final amount = double.tryParse(controller.text);
              if (amount != null && amount > 0) {
                Navigator.pop(context);
                final allSalesDocs = pendingSales.map((s) => s.doc).toList();
                _showFinalizePaymentDialog(customerDoc, amount, allSalesDocs);
              }
            },
            child: Text(l10n.get('continueToPay')),
          ),
        ],
      ),
    );
  }

  Future<void> _showFinalizePaymentDialog(DocumentSnapshot customerDoc, double amount, List<DocumentSnapshot> salesToPay) async {
    final l10n = AppLocalizations.of(context);
    String paymentType = 'Efectivo';

    await showDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (sbContext, setState) {
            return AlertDialog(
              title: Text(l10n.get('newPayment')),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${l10n.get('amountToPay')}: \$${amount.toStringAsFixed(2)}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 16),
                  Text(l10n.get('paymentMethod'), style: const TextStyle(fontWeight: FontWeight.bold)),
                  RadioGroup<String>(
                    groupValue: paymentType,
                    onChanged: (v) => setState(() => paymentType = v!),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        RadioListTile<String>(
                          title: Text(l10n.get('cash')),
                          value: 'Efectivo',
                          contentPadding: EdgeInsets.zero,
                        ),
                        RadioListTile<String>(
                          title: Text(l10n.get('bank')),
                          value: 'Banco',
                          contentPadding: EdgeInsets.zero,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(dialogContext), child: Text(l10n.get('cancel'))),
                ElevatedButton(
                  onPressed: () async {
                    Navigator.pop(dialogContext); 
                    try {
                      await _firestoreService.addCustomerPayment(
                        widget.businessId,
                        amount,
                        salesToPay,
                        paymentType,
                        customerDoc.id,
                        customerName: (customerDoc.data() as Map<String, dynamic>?)?['name']?.toString(),
                        sellerId: widget.sellerId,
                        sellerName: _effectiveSellerName,
                      );
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Pago registrado con éxito')));
                      }
                    } catch (e) {
                      if (mounted) {
                        showDialog(
                          context: context,
                          builder: (errContext) => AlertDialog(
                            title: const Text('Error al procesar'),
                            content: SingleChildScrollView(child: SelectableText(e.toString())),
                            actions: [TextButton(onPressed: () => Navigator.of(errContext).pop(), child: const Text('Cerrar'))],
                          ),
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
      },
    );
  }
}

class _PendingSale {
  final DocumentSnapshot doc;
  final double pendingAmount;
  _PendingSale(this.doc, this.pendingAmount);
}