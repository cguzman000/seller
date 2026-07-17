import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:developer';
import 'package:intl/intl.dart';
import 'dart:async';
import 'firestore_service.dart';
import 'app_localizations.dart';
import 'products.dart'; // Importamos la página de productos para usar el diálogo.
import 'sales.dart';

// Modelo para representar los datos de un producto en una venta.
// Puede ser un producto existente o uno eliminado con datos históricos.
class SaleProduct {
  final String id;
  final String name;
  final int stock;

  SaleProduct({required this.id, required this.name, this.stock = 0});
}

// Modelo simple para representar un ítem en el carrito de venta
class SaleItem {
  final SaleProduct product;
  double salePrice; // Precio al momento de la venta
  int quantity;

  SaleItem({required this.product, required this.salePrice, this.quantity = 1});

  // Usa el precio de venta guardado para el cálculo, no el precio actual del producto.
  double get totalPrice => salePrice * quantity;
}

class AddSalePage extends StatefulWidget {
  final User user;
  final String businessId; // ID del dueño de la cuenta (para leer productos/config)
  final DocumentSnapshot? saleDocument; // Para modo edición
  final String? sellerId;
  final String role;
  const AddSalePage({super.key, required this.user, required this.businessId, required this.role, this.saleDocument, this.sellerId});

  @override
  State<AddSalePage> createState() => _AddSalePageState();
}

class _AddSalePageState extends State<AddSalePage> {
  final FirestoreService _firestoreService = FirestoreService();
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _customerController = TextEditingController();
  final FocusNode _customerFocusNode = FocusNode();
  final TextEditingController _productController = TextEditingController();
  final FocusNode _productFocusNode = FocusNode();
  final TextEditingController _noteController = TextEditingController();

  String? _selectedCustomerId;
  String? _selectedCustomerName;
  final List<SaleItem> _saleItems = [];
  double _totalAmount = 0.0;
  double _paidAmount = 0.0;
  bool _isLoading = false;
  int? _saleNumber;
  DateTime? _saleDate;
  StreamSubscription? _paymentsSubscription;
  String? _companyName;
  double _vatRate = 0.0; // Para almacenar la tasa de IVA
  String? _companyLogoUrl;
  String? _sellerNameFromDb;
  String? _originalSellerName; // Nombre del vendedor original (para mostrar al editar/ver)

  bool get _isEditing => widget.saleDocument != null;

  @override
  void initState() {
    super.initState();
    _loadCompanySettings();
    _fetchSellerName();
    if (_isEditing) {
      _loadSaleData();
      _listenToPayments();
    } else {
      // Para una nueva venta, usamos la fecha actual.
      _saleDate = DateTime.now();
    }

    // Listener para forzar la visualización de opciones al enfocar si está vacío
    _productFocusNode.addListener(() {
      if (_productFocusNode.hasFocus && _productController.text.isEmpty) {
        _productController.text = '';
        _productController.text = '';
      }
    });

    _customerFocusNode.addListener(() {
      if (_customerFocusNode.hasFocus && _customerController.text.isEmpty) {
        _customerController.text = ' ';
        _customerController.text = '';
      }
    });
  }

  @override
  void dispose() {
    _paymentsSubscription?.cancel();
    _customerController.dispose();
    _customerFocusNode.dispose();
    _productController.dispose();
    _productFocusNode.dispose();
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _fetchSellerName() async {
    // Si el usuario no es el dueño (es un vendedor), buscamos su nombre real en la BD
    if (widget.user.uid != widget.businessId && widget.user.email != null) {
      final name = await _firestoreService.getSellerName(widget.businessId, widget.user.email!);
      if (mounted && name != null) {
        setState(() {
          _sellerNameFromDb = name.toUpperCase();
        });
      }
    }
  }

  String get _effectiveSellerName {
    if (widget.user.uid == widget.businessId) return 'ADMINISTRADOR';
    // Priorizamos el nombre de la BD del negocio, luego el de Google, y finalmente 'Vendedor'
    return (_sellerNameFromDb ?? widget.user.displayName ?? 'VENDEDOR').toUpperCase();
  }

  Future<void> _loadCompanySettings() async {
    final settingsDoc = await _firestoreService.getCompanySettingsOnce(widget.businessId);
    if (mounted && settingsDoc.exists) {
      final settingsData = settingsDoc.data() as Map<String, dynamic>?;
      setState(() {
        // Usamos 21.0 como fallback si no está configurado
        _vatRate = (settingsData?['vat_rate'] as num? ?? 21.0) / 100.0;
        _companyName = (settingsData?['company_name'] as String?)?.toUpperCase();
        _companyLogoUrl = settingsData?['company_logo_url'] as String?;
      });
    }
  }

  void _listenToPayments() {
    if (!_isEditing) return;
    _paymentsSubscription = _firestoreService.getPaymentsForSale(widget.saleDocument!.id).listen((snapshot) {
      double totalPaid = 0.0;
      for (var doc in snapshot.docs) {
        final data = doc.data() as Map<String, dynamic>;
        
        // 1. Determinar si es un pago compartido (cubre más de una venta)
        final saleIds = data['saleIds'];
        final bool isShared = saleIds is List && saleIds.length > 1;

        // 2. Intentar leer la asignación específica (allocations)
        if (data.containsKey('allocations') && data['allocations'] is Map && (data['allocations'] as Map).containsKey(widget.saleDocument!.id)) {
          totalPaid += ((data['allocations'] as Map)[widget.saleDocument!.id] as num).toDouble();
        } else {
          // 3. Si no hay allocations explícito:
          if (!isShared) {
            // Si NO es compartido, asumimos que el total es para esta venta.
            // Si ES compartido pero no tiene allocations, sumamos 0 para seguridad (evitar duplicar montos).
            totalPaid += (data['amount'] as num).toDouble();
          }
        }
      }
      if (mounted) {
        setState(() {
          _paidAmount = totalPaid;
        });
      }
    });
  }

  Future<void> _loadSaleData() async {
    setState(() => _isLoading = true);
    final data = widget.saleDocument!.data() as Map<String, dynamic>;
    _selectedCustomerId = data['customerId'];
    _selectedCustomerName = (data['customerName'] as String?)?.toUpperCase();
    _customerController.text = _selectedCustomerName ?? '';
    _noteController.text = data['note'] ?? '';
    _originalSellerName = (data['sellerName'] as String?)?.toUpperCase(); // Cargamos el nombre real del vendedor
    _saleNumber = data['sale_number'] as int?;
    if (data['saleDate'] != null) {
      _saleDate = (data['saleDate'] as Timestamp).toDate();
    }


    List<Map<String, dynamic>> itemsFromDb = List<Map<String, dynamic>>.from(data['items'] ?? []);
    for (var itemMap in itemsFromDb) {
      final productDoc = await _firestoreService.getProductById(itemMap['productId']);
      if (productDoc.exists) {
        // Usamos el precio guardado en la venta, no el precio actual del producto.
        final historicPrice = (itemMap['price'] as num).toDouble();
        final productData = productDoc.data() as Map<String, dynamic>;
        final saleProduct = SaleProduct(id: productDoc.id, name: productData['name'], stock: productData['stock'] ?? 0);
        _saleItems.add(SaleItem(product: saleProduct, quantity: itemMap['quantity'], salePrice: historicPrice));
      } else {
        // El producto fue eliminado. Usamos los datos históricos.
        final historicPrice = (itemMap['price'] as num).toDouble();
        final saleProduct = SaleProduct(id: itemMap['productId'], name: itemMap['productName'] ?? 'Producto Eliminado');
        _saleItems.add(SaleItem(product: saleProduct, quantity: itemMap['quantity'], salePrice: historicPrice));
      }
    }
    _calculateTotal();
    setState(() => _isLoading = false);
  }

  void _addProductToSale(DocumentSnapshot product, {required double price, int quantity = 1}) {
    setState(() {
      // Verificar si el producto ya está en la lista
      final existingItemIndex = _saleItems.indexWhere((item) => item.product.id == product.id);

      if (existingItemIndex != -1) {
        // Si ya existe, incrementa la cantidad. No cambiamos el precio.
        _saleItems[existingItemIndex].quantity += quantity;
      } else {
        // Si no, añádelo a la lista
        final data = product.data() as Map<String, dynamic>?;
        final name = data?['name']?.toString() ?? 'Sin Nombre';
        final stockVal = data?['stock'];
        final stock = (stockVal is num) ? stockVal.toInt() : (int.tryParse(stockVal?.toString() ?? '0') ?? 0);
        final saleProduct = SaleProduct(id: product.id, name: name, stock: stock);
        _saleItems.add(SaleItem(product: saleProduct, quantity: quantity, salePrice: price));
      }
      _calculateTotal();
    });
  }

  void _calculateTotal() {
    double total = 0.0;
    for (var item in _saleItems) {
      total += item.totalPrice;
    }
    setState(() {
      _totalAmount = total;
    });
  }

  Future<void> _selectDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _saleDate ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null && picked != _saleDate) {
      setState(() {
        _saleDate = picked;
      });
    }
  }

  Future<void> _showPaymentDialog() async {
    final l10n = AppLocalizations.of(context);
    final grossTotal = _totalAmount * (1 + _vatRate);
    final paymentController = TextEditingController();
    String paymentType = 'Efectivo'; // Valor por defecto

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) {
        // Usamos un StatefulWidget para manejar el estado del RadioButton dentro del diálogo
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: Text(l10n.get('newPayment')),
              content: SizedBox(
                width: double.maxFinite,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('Deuda Total: \$${grossTotal.toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 16),
                      TextFormField(controller: paymentController, decoration: InputDecoration(labelText: l10n.get('amountToPay'), prefixText: '\$'), keyboardType: const TextInputType.numberWithOptions(decimal: true), autofocus: true),
                      const SizedBox(height: 8),
                      ElevatedButton(onPressed: () => paymentController.text = grossTotal.toStringAsFixed(2), child: Text(l10n.get('payOnAccount'))),
                      const SizedBox(height: 16),
                      Text(l10n.get('paymentMethod'), style: const TextStyle(fontWeight: FontWeight.bold)),
                      RadioGroup<String>(
                        groupValue: paymentType,
                        onChanged: (value) => setState(() => paymentType = value!),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            RadioListTile<String>(title: Text(l10n.get('cash')), value: 'Efectivo'),
                            RadioListTile<String>(title: Text(l10n.get('bank')), value: 'Banco'),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(l10n.get('cancel'))),
                ElevatedButton(
                  onPressed: () {
                    // Si el campo está vacío, se asume 0. Si no, se parsea.
                    final amount = double.tryParse(paymentController.text.trim()) ?? 0.0;
                    // Se permite guardar con 0 o más.
                    Navigator.of(context).pop({'amount': amount, 'type': paymentType});
                  },
                  child: Text(l10n.get('save')),
                ),
              ],
            );
          },
        );
      },
    );

    if (result != null) {
      _finalizeSale(result['amount'], result['type']);
    }
  }

  Future<void> _finalizeSale(double paymentAmount, String paymentType) async {
    // Prepara la lista de items para Firestore
    List<Map<String, dynamic>> itemsForFirestore = _saleItems.map((item) {
      return {
        'productId': item.product.id,
        'productName': item.product.name,
        'quantity': item.quantity,
        'price': item.salePrice, // Guardamos el precio de venta del item
      };
    }).toList();

    // 1. Obtener el siguiente número de venta
    final saleNumber = await _firestoreService.getNextSaleNumber(widget.businessId);

    final grossTotal = _totalAmount * (1 + _vatRate);
    // Guardar la venta y obtener su referencia
    final saleRef = await _firestoreService.addSale( // Esto devuelve un DocumentReference
      widget.businessId,
      saleNumber,
      _selectedCustomerId!,
      _selectedCustomerName!,
      grossTotal, // Guardamos el total bruto
      itemsForFirestore,
      sellerId: widget.sellerId, // Registramos quién hizo la venta
      sellerName: _effectiveSellerName,
      note: _noteController.text,
      saleDate: _saleDate,
    );

    // Si se ingresó un pago, registrarlo
    if (paymentAmount > 0) {
      await _firestoreService.addPayment(
        widget.businessId,
        saleRef.id,
        paymentAmount,
        paymentType,
        sellerId: widget.sellerId,
        sellerName: _effectiveSellerName,
        customerId: _selectedCustomerId,
        customerName: _selectedCustomerName,
      );
    }

    if (mounted) {
      final l10n = AppLocalizations.of(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.get('saleSavedSuccess'))),
      );
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(
          builder: (context) => SalesPage(
            user: widget.user,
            businessId: widget.businessId,
            sellerId: widget.sellerId,
            role: widget.role,
          ),
        ),
        (route) => route.isFirst,
      );
    }
  }

  Future<void> _updateSale() async {
    List<Map<String, dynamic>> itemsForFirestore = _saleItems.map((item) {
      return {
        'productId': item.product.id,
        'productName': item.product.name,
        'quantity': item.quantity,
        'price': item.salePrice, // Guardamos el precio de venta del item
      };
    }).toList();

    final grossTotal = _totalAmount * (1 + _vatRate);
    await _firestoreService.updateSale(
      widget.saleDocument!.id,
      _selectedCustomerId!,
      _selectedCustomerName!,
      grossTotal,
      itemsForFirestore,
      note: _noteController.text,
      saleDate: _saleDate,
    );

    if (mounted) {
      final l10n = AppLocalizations.of(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.get('saleUpdatedSuccess'))),
      );
      Navigator.of(context).pop();
    }
  }

  void _saveSale() async {
    final l10n = AppLocalizations.of(context);
    if (_formKey.currentState!.validate()) {
      if (_saleItems.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.get('addOneProductError'))),
        );
        return;
      }

      if (_isEditing) {
        _updateSale();
      } else {
        // La lógica de pago solo se aplica al crear una nueva venta
        _showPaymentDialog();
      }
    }
  }

  void _showEditSaleItemDialog(int index) {
    showDialog(
      context: context,
      builder: (context) {
        return _EditSaleItemDialog(
          item: _saleItems[index],
          vatRate: _vatRate,
          businessId: widget.businessId,
          firestoreService: _firestoreService,
          onDelete: () {
            setState(() => _saleItems.removeAt(index));
            _calculateTotal();
            Navigator.of(context).pop();
          },
          onUpdate: (quantity, price) {
            setState(() {
              _saleItems[index].quantity = quantity;
              _saleItems[index].salePrice = price;
            });
            _calculateTotal();
            Navigator.of(context).pop();
          },
        );
      });
  }



  void _showAddPaymentToSaleDialog() {
    final l10n = AppLocalizations.of(context);
    final grossTotal = _totalAmount * (1 + _vatRate);
    final remainingAmount = grossTotal - _paidAmount;
    if (remainingAmount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l10n.get('saleAlreadyPaid'))));
      return;
    }

    final paymentController = TextEditingController(text: remainingAmount.toStringAsFixed(2));
    String paymentType = 'Efectivo'; // Valor por defecto

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: Text(l10n.get('newPayment')),
              content: SizedBox(
                width: double.maxFinite,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextFormField(controller: paymentController, decoration: InputDecoration(labelText: l10n.get('amountToPay'), prefixText: '\$'), keyboardType: const TextInputType.numberWithOptions(decimal: true), autofocus: true),
                      const SizedBox(height: 16),
                      Text(l10n.get('paymentMethod'), style: const TextStyle(fontWeight: FontWeight.bold)),
                      RadioGroup<String>(
                        groupValue: paymentType,
                        onChanged: (value) => setState(() => paymentType = value!),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            RadioListTile<String>(title: Text(l10n.get('cash')), value: 'Efectivo'),
                            RadioListTile<String>(title: Text(l10n.get('bank')), value: 'Banco'),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(l10n.get('cancel'))),
                ElevatedButton(
                  onPressed: () async {
                    final amount = double.tryParse(paymentController.text);
                    if (amount != null && amount > 0) {
                      // Primero, guarda el context en una variable local
                      final navigator = Navigator.of(context);
                      final messenger = ScaffoldMessenger.of(context);
                      await _firestoreService.addPayment(
                        widget.businessId,
                        widget.saleDocument!.id,
                        amount,
                        paymentType,
                        sellerId: widget.sellerId,
                        sellerName: _effectiveSellerName,
                        customerId: _selectedCustomerId, // ID del cliente
                        customerName: _selectedCustomerName, // Nombre del cliente
                      );
                      if (mounted) { // Luego, comprueba si el widget sigue montado
                        navigator.pop();
                        messenger.showSnackBar(SnackBar(content: Text('${l10n.get('paymentLabel')} ${l10n.get('settingsSaved')}')));
                      }
                    }
                  },
                  child: Text(l10n.get('save')),
                ),
              ],
            );
          },
        );
      });
  }

  Future<void> _deletePayment(String paymentId) async {
    final l10n = AppLocalizations.of(context);
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.get('delete')),
        content: Text(l10n.get('confirmDeletePayment')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(l10n.get('cancel'))),
          TextButton(onPressed: () => Navigator.pop(context, true), child: Text(l10n.get('delete'), style: const TextStyle(color: Colors.red))),
        ],
      ),
    );

    if (confirm == true) {
      await _firestoreService.deletePayment(paymentId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Pago eliminado')));
      }
    }
  }

  void _showEditPaymentDialog(DocumentSnapshot paymentDoc) {
    final l10n = AppLocalizations.of(context);
    final data = paymentDoc.data() as Map<String, dynamic>;
    final amountController = TextEditingController(text: (data['amount'] as num).toString());
    String paymentType = data['payment_type'] ?? 'Efectivo';

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setStateDialog) {
          return AlertDialog(
            title: Text(l10n.get('editPayment')),
            content: SizedBox(
              width: double.maxFinite,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: amountController,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(labelText: l10n.get('amountToPay'), prefixText: '\$'),
                  ),
                  const SizedBox(height: 16),
                  Text(l10n.get('paymentMethod'), style: const TextStyle(fontWeight: FontWeight.bold)),
                  RadioGroup<String>(
                    groupValue: paymentType,
                    onChanged: (val) => setStateDialog(() => paymentType = val!),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        RadioListTile<String>(title: Text(l10n.get('cash')), value: 'Efectivo'),
                        RadioListTile<String>(title: Text(l10n.get('bank')), value: 'Banco'),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context), child: Text(l10n.get('cancel'))),
              ElevatedButton(
                onPressed: () async {
                  final amount = double.tryParse(amountController.text);
                  if (amount != null) {
                    await _firestoreService.updatePayment(paymentDoc.id, amount, paymentType: paymentType);
                    if (context.mounted) {
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l10n.get('settingsSaved'))));
                    }
                  }
                },
                child: Text(l10n.get('save')),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _showAddCustomerDialog() async {
    final l10n = AppLocalizations.of(context);
    final formKey = GlobalKey<FormState>();
    final nameController = TextEditingController();
    final dniController = TextEditingController();
    final contactController = TextEditingController();
    final phoneController = TextEditingController();
    final emailController = TextEditingController();
    final addressController = TextEditingController();
    final cityController = TextEditingController();

    final newCustomerData = await showDialog<Map<String, String>>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.get('addCustomer')),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                TextFormField(controller: nameController, decoration: InputDecoration(labelText: l10n.get('name')), validator: (v) => v!.isEmpty ? l10n.get('required') : null, textCapitalization: TextCapitalization.characters),
                  TextFormField(controller: dniController, decoration: InputDecoration(labelText: l10n.get('dni')), textCapitalization: TextCapitalization.characters),
                TextFormField(controller: contactController, decoration: InputDecoration(labelText: l10n.get('contactPerson')), textCapitalization: TextCapitalization.characters),
                  TextFormField(controller: phoneController, decoration: InputDecoration(labelText: l10n.get('phone')), keyboardType: TextInputType.phone),
                  TextFormField(controller: emailController, decoration: InputDecoration(labelText: l10n.get('email')), keyboardType: TextInputType.emailAddress),
                TextFormField(controller: addressController, decoration: InputDecoration(labelText: l10n.get('address')), textCapitalization: TextCapitalization.characters),
                TextFormField(controller: cityController, decoration: InputDecoration(labelText: l10n.get('city')), textCapitalization: TextCapitalization.characters),
                ],
              ),
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(l10n.get('cancel'))),
          ElevatedButton(
            onPressed: () {
              if (formKey.currentState!.validate()) {
                Navigator.of(context).pop({
                  'name': nameController.text,
                  'dni': dniController.text,
                  'contact': contactController.text,
                  'phone': phoneController.text,
                  'email': emailController.text,
                  'address': addressController.text,
                  'city': cityController.text,
                });
              }
            },
            child: Text(l10n.get('save')),
          ),
        ],
      ),
    );

    if (newCustomerData != null) {
      final docRef = await _firestoreService.addCustomer(widget.businessId, newCustomerData['name']!, newCustomerData['dni']!, newCustomerData['contact']!, newCustomerData['phone']!, newCustomerData['email']!, newCustomerData['address']!, newCustomerData['city']!, sellerId: widget.sellerId, creatorName: widget.user.displayName ?? 'Usuario');
      // Una vez creado, lo seleccionamos automáticamente en el dropdown.
      setState(() {
        _selectedCustomerId = docRef.id;
        _selectedCustomerName = newCustomerData['name']?.toUpperCase();
        _customerController.text = _selectedCustomerName ?? '';
      });
    }
  }

  Future<void> _scanBarcodeAndAddProduct() async {
    // 1. Abrir el escáner
    final barcode = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (context) => const BarcodeScannerSimple()),
    );

    if (barcode == null || !mounted) return;

    // 2. Buscar el producto por código de barras
    final productDoc = await _firestoreService.getProductByBarcode(widget.businessId, barcode);

    if (productDoc == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Producto no encontrado.')));
      return;
    }

    // 3. Comprobar si el producto ya está en la lista
    final existingItemIndex = _saleItems.indexWhere((item) => item.product.id == productDoc.id);
    if (existingItemIndex != -1) {
      // Si ya existe, solo incrementa la cantidad
      setState(() => _saleItems[existingItemIndex].quantity++);
    } else {
      // Si es nuevo, usa la lógica existente que maneja las ofertas
      _handleProductSelection(productDoc, null);
    }
  }
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Row(
                children: [
                  if (_companyLogoUrl != null && _companyLogoUrl!.isNotEmpty) ...[
                    CircleAvatar(
                      radius: 25,
                      backgroundImage: NetworkImage(_companyLogoUrl!),
                    ),
                    const SizedBox(width: 8),
                  ],
                  if (_companyName != null && _companyName!.isNotEmpty)
                    Flexible(
                      child: Text(_companyName!, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis),
                    ),
                ],
              ),
            ),
            InkWell(
              onTap: _selectDate,
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    if (_isEditing)
                      Text(
                        'Venta N°${_saleNumber ?? ''}',
                        style: const TextStyle(fontSize: 14),
                      )
                    else
                      Text(
                        l10n.get('saleNumberSN'),
                        style: const TextStyle(fontSize: 14),
                      ),
                    if (_saleDate != null)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.edit_calendar, size: 14, color: Colors.blueGrey),
                          const SizedBox(width: 4),
                          Text(
                            DateFormat('dd/MM/yyyy').format(_saleDate!),
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.normal,
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      body: GestureDetector(
        onTap: () {
          FocusScope.of(context).unfocus();
        },
        behavior: HitTestBehavior.translucent,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                          '${l10n.get('sellerLabel')}${_isEditing ? (_originalSellerName ?? l10n.get('sellerUnknown')) : _effectiveSellerName}',
                          style: const TextStyle(
                              fontSize: 16, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 10),
                      // Selector de Cliente
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Expanded(
                            child: LayoutBuilder(
                              builder: (context, constraints) {
                                return RawAutocomplete<DocumentSnapshot>(
                                  textEditingController: _customerController,
                                  focusNode: _customerFocusNode,
                                  optionsBuilder:
                                      (TextEditingValue textEditingValue) async {
                                    // Si el texto coincide exactamente con el seleccionado, no mostramos el menú
                                    if (_selectedCustomerName != null &&
                                        textEditingValue.text ==
                                            _selectedCustomerName) {
                                      return const Iterable<DocumentSnapshot>
                                          .empty();
                                    }

                                    // Obtenemos todos los clientes ordenados por nombre para filtrar localmente.
                                    // Esto permite encontrar coincidencias parciales (ej. "Guzman" en "Carlos Guzman").
                                    final snapshot =
                                        await _firestoreService.getCustomers(
                                      widget.businessId,
                                      searchTerm: '', // Traemos todos para filtrar en memoria
                                      sellerId: widget.sellerId,
                                      orderBy: 'name',
                                      descending: false,
                                    ).first;

                                    final searchTerm = textEditingValue.text
                                        .trim()
                                        .toUpperCase();
                                    if (searchTerm.isEmpty) {
                                      return snapshot.docs;
                                    }

                                    return snapshot.docs.where((doc) {
                                      final data =
                                          doc.data() as Map<String, dynamic>;
                                      final name =
                                          (data['name'] as String? ?? '')
                                              .toUpperCase();
                                      final dni = (data['dni'] as String? ?? '')
                                          .toUpperCase();
                                      return name.contains(searchTerm) ||
                                          dni.contains(searchTerm);
                                    });
                                  },
                                  displayStringForOption:
                                      (DocumentSnapshot option) {
                                    final data =
                                        option.data() as Map<String, dynamic>;
                                    return (data['name'] as String? ?? '').toUpperCase();
                                  },
                                  onSelected: (DocumentSnapshot selection) {
                                    final data = selection.data()
                                        as Map<String, dynamic>;
                                    setState(() {
                                      _selectedCustomerId = selection.id;
                                      _selectedCustomerName = (data['name'] as String? ?? '').toUpperCase();
                                    });
                                  },
                                  fieldViewBuilder: (context,
                                      textEditingController,
                                      focusNode,
                                      onFieldSubmitted) {
                                    return TextFormField(
                                      controller: textEditingController,
                                      focusNode: focusNode,
                                      textCapitalization: TextCapitalization.characters,
                                      decoration: InputDecoration(
                                        labelText: l10n.get('customers'),
                                        hintText: l10n.get('customerSearchHint'),
                                        suffixIcon: ValueListenableBuilder<
                                            TextEditingValue>(
                                          valueListenable:
                                              textEditingController,
                                          builder: (context, value, child) {
                                            return value.text.isNotEmpty
                                                ? IconButton(
                                                    icon: const Icon(
                                                        Icons.clear),
                                                    onPressed: () {
                                                      textEditingController
                                                          .clear();
                                                      setState(() {
                                                        _selectedCustomerId =
                                                            null;
                                                        _selectedCustomerName =
                                                            null;
                                                      });
                                                    },
                                                  )
                                                : const Icon(
                                                    Icons.arrow_drop_down);
                                          },
                                        ),
                                      ),
                                      validator: (value) =>
                                          _selectedCustomerId == null
                                              ? l10n.get('selectCustomerError')
                                              : null,
                                      onChanged: (text) {
                                        // Si el usuario edita el texto y ya no coincide, limpiamos la selección
                                        if (_selectedCustomerId != null &&
                                            text != _selectedCustomerName) {
                                          setState(() {
                                            _selectedCustomerId = null;
                                            _selectedCustomerName = null;
                                          });
                                        }
                                      },
                                    );
                                  },
                                  optionsViewBuilder: (BuildContext context,
                                      AutocompleteOnSelected<DocumentSnapshot>
                                          onSelected,
                                      Iterable<DocumentSnapshot> options) {
                                    return Align(
                                      alignment: Alignment.topLeft,
                                      child: Material(
                                        elevation: 4.0,
                                        child: SizedBox(
                                          width: constraints.maxWidth,
                                          child: ConstrainedBox(
                                            constraints: const BoxConstraints(
                                                maxHeight: 200),
                                            child: ListView.builder(
                                              padding: EdgeInsets.zero,
                                              shrinkWrap: true,
                                              itemCount: options.length,
                                              itemBuilder:
                                                  (BuildContext context,
                                                      int index) {
                                                final option =
                                                    options.elementAt(index);
                                                final data = option.data()
                                                    as Map<String, dynamic>;
                                                return ListTile(
                                                  title: Text((data['name'] as String? ?? '').toUpperCase()),
                                                  subtitle: data['dni'] !=
                                                              null &&
                                                          data['dni']
                                                              .toString()
                                                              .isNotEmpty
                                                      ? Text(data['dni'])
                                                      : null,
                                                  onTap: () {
                                                    onSelected(option);
                                                  },
                                                );
                                              },
                                            ),
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
                            icon: const Icon(Icons.person_add_alt_1),
                            onPressed: _showAddCustomerDialog,
                            tooltip: l10n.get('addNewCustomer'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),

                      // Lista de productos en la venta
                      Text('${l10n.get('products')}:',
                          style: const TextStyle(
                              fontSize: 18, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      Column(
                        children: [
                          if (_saleItems.isNotEmpty)
                            // Cabecera de la tabla
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 16.0, vertical: 8.0),
                              color: Colors.blueGrey.shade50,
                              child: Row(
                                children: [
                                  Expanded(
                                      child: Text(l10n.get('productHeader'),
                                          style: const TextStyle(
                                              fontWeight: FontWeight.bold))),
                                  SizedBox(
                                      width: 50,
                                      child: Text(l10n.get('quantityHeader'),
                                          textAlign: TextAlign.center,
                                          style: const TextStyle(
                                              fontWeight: FontWeight.bold))),
                                  SizedBox(
                                      width: 90,
                                      child: Text(l10n.get('totalHeader'),
                                          textAlign: TextAlign.right,
                                          style: const TextStyle(
                                              fontWeight: FontWeight.bold))),
                                ],
                              ),
                            ),
                          // Lista unificada (Productos + Buscador)
                          ListView.builder(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(), // Permite que el SingleChildScrollView padre maneje el scroll
                            itemCount: _saleItems.length,
                            itemBuilder: (context, index) {
                              final item = _saleItems[index];
                              final bool isLowStock =
                                  item.quantity >= item.product.stock;

                              return Dismissible(
                                key: Key(item.product.id),
                                direction: DismissDirection.endToStart,
                                background: Container(
                                  color: Colors.red,
                                  alignment: Alignment.centerRight,
                                  padding: const EdgeInsets.symmetric(horizontal: 20.0),
                                  child: const Icon(Icons.delete, color: Colors.white),
                                ),
                                confirmDismiss: (direction) async {
                                  return await showDialog<bool>(
                                    context: context,
                                    builder: (dialogContext) => AlertDialog(
                                      title: Text(l10n.get('delete')),
                                      content: Text(l10n.get('confirmDelete')),
                                      actions: [
                                        TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: Text(l10n.get('cancel'))),
                                        TextButton(onPressed: () => Navigator.of(dialogContext).pop(true), child: Text(l10n.get('delete'), style: const TextStyle(color: Colors.red))),
                                      ],
                                    ),
                                  ) ?? false;
                                },
                                onDismissed: (direction) {
                                  setState(() {
                                    _saleItems.removeAt(index);
                                    _calculateTotal();
                                  });
                                },
                                child: InkWell(
                                  onTap: () => _showEditSaleItemDialog(index),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                                    decoration: BoxDecoration(
                                      color: index.isEven ? Colors.grey.shade50 : Colors.white,
                                      border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
                                    ),
                                    child: Row(
                                      children: [
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(item.product.name.toUpperCase(), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                                              if (isLowStock)
                                                Text('Stock máx: ${item.product.stock}', style: const TextStyle(color: Colors.deepOrange, fontSize: 11)),
                                              Text('\$${(item.salePrice * (1 + _vatRate)).toStringAsFixed(0)}', style: const TextStyle(color: Colors.grey, fontSize: 12)),
                                            ],
                                          ),
                                        ),
                                        SizedBox(
                                          width: 50,
                                          child: Text(
                                            '${item.quantity}',
                                            textAlign: TextAlign.center,
                                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                                          ),
                                        ),
                                        SizedBox(
                                          width: 80,
                                          child: Text(
                                            '\$${(item.totalPrice * (1 + _vatRate)).toStringAsFixed(0)}',
                                            textAlign: TextAlign.right,
                                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                          // Buscador de productos (ahora fuera de la lista para evitar errores de renderizado)
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 4.0, vertical: 4.0),
                            child: Card(
                              elevation: 1,
                              child: Padding(
                                padding: const EdgeInsets.all(8.0),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.center,
                                  children: [
                                    Expanded(
                                      child: LayoutBuilder(
                                        builder: (context, constraints) {
                                          return RawAutocomplete<DocumentSnapshot>(
                                            textEditingController:
                                                _productController,
                                            focusNode: _productFocusNode,
                                            optionsBuilder: (TextEditingValue
                                                textEditingValue) async {
                                              final snapshot =
                                                  await _firestoreService
                                                      .getProducts(
                                                          widget.businessId)
                                                      .first;
                                              final searchTerm = textEditingValue
                                                  .text
                                                  .trim()
                                                  .toLowerCase();
                                              if (searchTerm.isEmpty) {
                                                return snapshot.docs;
                                              }

                                              return snapshot.docs.where((doc) {
                                                final data = doc.data()
                                                    as Map<String, dynamic>;
                                                final name = (data['name'] as String? ?? '')
                                                    .toLowerCase();
                                                final barcode = (data['bar_code']
                                                            as String? ??
                                                        '')
                                                    .toLowerCase();
                                                return name
                                                        .contains(searchTerm) ||
                                                    barcode
                                                        .contains(searchTerm);
                                              });
                                            },
                                            displayStringForOption:
                                                (DocumentSnapshot option) {
                                              final data = option.data()
                                                  as Map<String, dynamic>;
                                              return data['name'] ?? '';
                                            },
                                            onSelected:
                                                (DocumentSnapshot selection) {
                                              _handleProductSelection(
                                                  selection, null);
                                              _productController.clear();
                                              _productFocusNode.unfocus();
                                            },
                                            fieldViewBuilder: (context,
                                                textEditingController,
                                                focusNode,
                                                onFieldSubmitted) {
                                              return TextFormField(
                                                controller:
                                                    textEditingController,
                                                focusNode: focusNode,
                                                textCapitalization: TextCapitalization.characters,
                                                decoration: InputDecoration(
                                                  labelText: l10n.get('products'),
                                                  hintText:
                                                      l10n.get('searchProductHint'),
                                                  border: InputBorder.none,
                                                  isDense: true,
                                                  contentPadding:
                                                      EdgeInsets.zero,
                                                  suffixIcon:
                                                      ValueListenableBuilder<
                                                          TextEditingValue>(
                                                    valueListenable:
                                                        textEditingController,
                                                    builder:
                                                        (context, value, child) {
                                                      return value.text.isNotEmpty
                                                          ? IconButton(
                                                              icon: const Icon(
                                                                  Icons.clear),
                                                              onPressed: () {
                                                                textEditingController
                                                                    .clear();
                                                              },
                                                            )
                                                          : const Icon(
                                                              Icons.search);
                                                    },
                                                  ),
                                                ),
                                              );
                                            },
                                            optionsViewBuilder: (BuildContext
                                                    context,
                                                AutocompleteOnSelected<
                                                        DocumentSnapshot>
                                                    onSelected,
                                                Iterable<DocumentSnapshot>
                                                    options) {
                                              return Align(
                                                alignment: Alignment.topLeft,
                                                child: Material(
                                                  elevation: 4.0,
                                                  child: SizedBox(
                                                    width: constraints.maxWidth,
                                                    child: ConstrainedBox(
                                                      constraints:
                                                          const BoxConstraints(
                                                              maxHeight: 300),
                                                      child: ListView.builder(
                                                        padding: EdgeInsets.zero,
                                                        shrinkWrap: true,
                                                        itemCount:
                                                            options.length,
                                                        itemBuilder:
                                                            (BuildContext
                                                                    context,
                                                                int index) {
                                                          final option = options
                                                              .elementAt(index);
                                                          final data = option
                                                                  .data()
                                                              as Map<String,
                                                                  dynamic>;
                                                          final name =
                                                              data['name'] ??
                                                                  'Sin Nombre';
                                                          final stock =
                                                              data['stock']
                                                                      ?.toString() ??
                                                                  '0';
                                                          dynamic rawPrice =
                                                              data['price'];
                                                          double price = (rawPrice
                                                                  is num)
                                                              ? rawPrice
                                                                  .toDouble()
                                                              : (double.tryParse(
                                                                      rawPrice
                                                                              ?.toString() ??
                                                                          '0') ??
                                                                  0.0);

                                                          return ListTile(
                                                            title: Text(name.toUpperCase()),
                                                            subtitle: Text(
                                                                'Stock: $stock'),
                                                            trailing: Text(
                                                                '\$${price.toStringAsFixed(0)}'),
                                                            onTap: () =>
                                                                onSelected(
                                                                    option),
                                                          );
                                                        },
                                                      ),
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
                                      onPressed: _scanBarcodeAndAddProduct,
                                      tooltip: l10n.get('scanBarcode'),
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.add_box),
                                      onPressed: () {
                                        showDialog(
                                          context: context,
                                          builder: (context) {
                                            return ProductDialog(
                                              user: widget.user,
                                              businessId: widget.businessId,
                                              firestoreService:
                                                  _firestoreService,
                                            );
                                          },
                                        );
                                      },
                                      tooltip: 'Crear nuevo producto',
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),

                      const Divider(),
                      // Resumen de montos
                      Align(
                        alignment: Alignment.centerRight,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              '${l10n.get('netLabel')}: \$${_totalAmount.toStringAsFixed(2)}',
                              style: const TextStyle(fontSize: 16),
                            ),
                            Text(
                              '${l10n.get('vatLabel')} (${(_vatRate * 100).toStringAsFixed(0)}%): \$${(_totalAmount * _vatRate).toStringAsFixed(2)}',
                              style: const TextStyle(fontSize: 16),
                            ),
                            const Divider(),
                            Text(
                              '${l10n.get('total')}: \$${(_totalAmount * (1 + _vatRate)).toStringAsFixed(0)}',
                              style: const TextStyle(
                                  fontSize: 20, fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 8),
                            if (_isEditing) ...[
                              Text(
                                '${l10n.get('paidLabel')}: \$${_paidAmount.toStringAsFixed(2)}',
                                style: const TextStyle(
                                    fontSize: 16, color: Colors.green),
                              ),
                              Text(
                                '${l10n.get('balanceLabel')}: \$${((_totalAmount * (1 + _vatRate)) - _paidAmount).toStringAsFixed(2)}',
                                style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.orange),
                              ),
                            ]
                          ],
                        ),
                      ),
                      if (_isEditing) ...[
                        const SizedBox(height: 20),
                        const Divider(),
                        Text(l10n.get('recordedPayments'),
                            style: const TextStyle(
                                fontSize: 18, fontWeight: FontWeight.bold)),
                        StreamBuilder<QuerySnapshot>(
                          stream: _firestoreService
                              .getPaymentsForSale(widget.saleDocument!.id),
                          builder: (context, snapshot) {
                            if (!snapshot.hasData) {
                              return const Padding(
                                  padding: EdgeInsets.all(8.0),
                                  child: Text('...'));
                            }
                            if (snapshot.data!.docs.isEmpty) {
                              return const Padding(
                                  padding: EdgeInsets.all(8.0),
                                  child: Text('...'));
                            }

                            return ListView.builder(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              itemCount: snapshot.data!.docs.length,
                              itemBuilder: (context, index) {
                                final paymentDoc = snapshot.data!.docs[index];
                                final paymentData =
                                    paymentDoc.data() as Map<String, dynamic>;

                                final saleIds = paymentData['saleIds'];
                                final isSharedPayment = saleIds is List && saleIds.length > 1;
                                final currentSaleId = widget.saleDocument!.id;
                                final totalAmountDoc = (paymentData['amount'] as num).toDouble();

                                double amount = 0.0;
                                if (paymentData.containsKey('allocations') && paymentData['allocations'] is Map && (paymentData['allocations'] as Map).containsKey(currentSaleId)) {
                                  amount = ((paymentData['allocations'] as Map)[currentSaleId] as num).toDouble();
                                } else {
                                  // Si es compartido y no tiene allocation, mostramos 0 (o el total si no es compartido)
                                  amount = isSharedPayment ? 0.0 : totalAmountDoc;
                                }
                                
                                final isShared = amount < totalAmountDoc;
                                
                                final paymentType = paymentData['payment_type'] ?? 'Desconocido';
                                IconData paymentIcon;
                                if (paymentType == 'Efectivo') {
                                  paymentIcon = Icons.payments;
                                } else if (paymentType == 'Banco') {
                                  paymentIcon = Icons.credit_card;
                                } else {
                                  paymentIcon = Icons.help_outline;
                                }

                                final date =
                                    (paymentData['date'] as Timestamp?)
                                        ?.toDate();

                                return ListTile(
                                  dense: true,
                                  contentPadding: EdgeInsets.zero,
                                  title: Text(
                                      '${l10n.get('paymentLabel')}: \$${amount.toStringAsFixed(2)} ${isShared ? "(${l10n.get('of')} \$${totalAmountDoc.toStringAsFixed(2)})" : ""}'),
                                  subtitle: date != null
                                      ? Text(DateFormat('dd/MM/yyyy HH:mm')
                                          .format(date))
                                      : null,
                                  trailing: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(paymentIcon, color: Theme.of(context).colorScheme.primary, size: 20),
                                      const SizedBox(width: 8),
                                      IconButton(
                                          icon: const Icon(Icons.edit,
                                              color: Colors.blue),
                                          onPressed: () =>
                                              _showEditPaymentDialog(
                                                  paymentDoc)),
                                      IconButton(
                                          icon: const Icon(Icons.delete,
                                              color: Colors.red),
                                          onPressed: () =>
                                              _deletePayment(paymentDoc.id)),
                                    ],
                                  ),
                                );
                              },
                            );
                          },
                        ),
                      ],
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _noteController,
                        decoration: const InputDecoration(
                          labelText: '...', // Se traduce abajo
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.note),
                        ),
                        maxLines: 3,
                        minLines: 1,
                        textCapitalization: TextCapitalization.characters,
                      ),
                      const SizedBox(height: 80),
                    ],
                  ),
                ),
        ),
      ),
      bottomNavigationBar: BottomAppBar(
        child: Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(l10n.get('cancel')),
            ),
            const SizedBox(width: 8),
            ElevatedButton(
              onPressed: _saveSale,
              child: Text(l10n.get('save')),
            ),
          ],
        ),
      ),
      floatingActionButton: _isEditing
          ? FloatingActionButton(onPressed: _showAddPaymentToSaleDialog, tooltip: 'Añadir Pago', child: const Icon(Icons.payment))
          : null,
    );
  }

  void _handleProductSelection(DocumentSnapshot product, BuildContext? selectionContext) async {
    final data = product.data() as Map<String, dynamic>;
    dynamic rawPrice = data['price'];
    final regularPrice = (rawPrice is num) ? rawPrice.toDouble() : (double.tryParse(rawPrice?.toString() ?? '0') ?? 0.0);

    // Mostrar indicador de carga para evitar toques múltiples y dar feedback
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (c) => const Center(child: CircularProgressIndicator()),
    );

    // Consultar si hay ofertas para este producto
    QuerySnapshot? offersSnapshot;
    String? errorForDialog; // Variable para capturar CUALQUIER error y mostrarlo en un diálogo.

    try {
      offersSnapshot = await _firestoreService.getOffersOnce(product.id, widget.businessId);
    } catch (e, stackTrace) {
      // Guardamos el error para mostrarlo en un diálogo, sea cual sea.
      errorForDialog = e.toString();

      log(
        'Error al obtener las ofertas. El detalle se mostrará en un diálogo en la app.',
        name: 'FirestoreService.getOffersOnce',
        error: e,
        stackTrace: stackTrace,
      );
      offersSnapshot = null;
    }

    // Cerrar el indicador de carga
    if (mounted) Navigator.of(context).pop();

    // Si se capturó un error, lo mostramos en un diálogo para asegurar que el usuario lo vea.
    if (errorForDialog != null && mounted) {
      // Determinamos si es el error de índice para personalizar el título.
      final isIndexError = errorForDialog.contains('firestore/failed-precondition');
      final isPermissionError = errorForDialog.contains('permission-denied');

      await showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(isIndexError ? '⚠️ Falta Índice en Firestore' : 
                      isPermissionError ? '⛔ Permiso Denegado' : '❌ Error Inesperado'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (isIndexError) ...[
                  const Text('Para que esta consulta funcione, Firestore requiere un índice. Copia el siguiente enlace y ábrelo en un navegador para crearlo:'),
                  const SizedBox(height: 15),
                ] else if (isPermissionError) ...[
                  const Text('Firebase ha bloqueado esta consulta por seguridad.'),
                  const SizedBox(height: 10),
                  const Text('Asegúrate de que las Reglas de Seguridad en la consola de Firebase permitan leer la colección "offers" cuando se filtra por "userId".'),
                  const SizedBox(height: 15),
                ] else ... [
                  const Text('Se produjo un error al consultar las ofertas. Este es el detalle técnico:'),
                  const SizedBox(height: 15),
                ],
                SelectableText(
                  errorForDialog!,
                  style: TextStyle(color: isIndexError ? Colors.blue : null, decoration: isIndexError ? TextDecoration.underline : null, fontFamily: 'monospace', fontSize: 12),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Entendido'),
            ),
          ],
        ),
      );
    }

    if (offersSnapshot == null || offersSnapshot.docs.isEmpty) {
      // Si no hay ofertas o hubo error, añade el producto con el precio regular.
      _addProductToSale(product, price: regularPrice);
      if (selectionContext != null && selectionContext.mounted) Navigator.of(selectionContext).pop(); // Cierra el diálogo de selección de productos.
      return;
    }

    if (!mounted) return;

    // Si hay ofertas, muestra un diálogo para elegir.
    await showDialog(
      context: context,
      builder: (dialogContext) {
        final l10n = AppLocalizations.of(dialogContext);
        return AlertDialog(
          title: Text(l10n.get('offersForProduct').replaceFirst('{product}', data['name'] ?? 'Producto')),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView(
              shrinkWrap: true,
              children: [
                ListTile(
                  title: Text(l10n.get('regularPrice')),
                  trailing: Text('\$${(regularPrice * (1 + _vatRate)).toStringAsFixed(0)} (Neto: \$${regularPrice.toStringAsFixed(2)})'),
                  onTap: () {
                    Navigator.of(dialogContext).pop();
                    if (selectionContext != null && selectionContext.mounted) Navigator.of(selectionContext).pop();
                    _addProductToSale(product, price: regularPrice);
                  },
                ),
                const Divider(),
                ...offersSnapshot!.docs.map((offerDoc) {
                  final offerData = offerDoc.data() as Map<String, dynamic>;
                  final offerPrice = (offerData['price'] as num?)?.toDouble() ?? 0.0;
                  final minQty = (offerData['quantity'] as num?)?.toDouble() ?? 0.0;
                  final offerPriceWithVat = offerPrice * (1 + _vatRate);
                  return ListTile(
                    title: Text('${offerData['name'] ?? 'Oferta'} (Min: $minQty)'),
                    trailing: Text('\$${offerPriceWithVat.toStringAsFixed(0)} (Neto: \$${offerPrice.toStringAsFixed(2)})'),
                    subtitle: Text(l10n.get('takingMinQty').replaceFirst('{qty}', minQty.toInt().toString())),
                    onTap: () {
                      Navigator.of(dialogContext).pop();
                      if (selectionContext != null && selectionContext.mounted) Navigator.of(selectionContext).pop();
                      
                      int quantityToAdd = minQty > 0 ? minQty.toInt() : 1;
                      _addProductToSale(product, price: offerPrice, quantity: quantityToAdd);
                    },
                  );
                }),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancelar'),
            ),
          ],
        );
      },
    );
  }
}

class _EditSaleItemDialog extends StatefulWidget {
  final SaleItem item;
  final double vatRate;
  final String businessId;
  final FirestoreService firestoreService;
  final Function(int quantity, double price) onUpdate;
  final VoidCallback onDelete;

  const _EditSaleItemDialog({
    required this.item,
    required this.vatRate,
    required this.businessId,
    required this.firestoreService,
    required this.onUpdate,
    required this.onDelete,
  });

  @override
  State<_EditSaleItemDialog> createState() => _EditSaleItemDialogState();
}

class _EditSaleItemDialogState extends State<_EditSaleItemDialog> {
  late TextEditingController _quantityController;
  late TextEditingController _priceController;
  bool _isLoading = true;
  double _basePrice = 0.0;
  List<Map<String, dynamic>> _offers = [];
  bool _priceIncludesVat = true;

  @override
  void initState() {
    super.initState();
    _quantityController = TextEditingController(text: widget.item.quantity.toString());
    final initialGrossPrice = widget.item.salePrice * (1 + widget.vatRate);
    _priceController = TextEditingController(text: initialGrossPrice.toStringAsFixed(2));
    _loadData();
  }

  @override
  void dispose() {
    _quantityController.dispose();
    _priceController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    try {
      final productDoc = await widget.firestoreService.getProductById(widget.item.product.id);
      if (productDoc.exists) {
        final data = productDoc.data() as Map<String, dynamic>;
        dynamic rawPrice = data['price'];
        _basePrice = (rawPrice is num) ? rawPrice.toDouble() : (double.tryParse(rawPrice?.toString() ?? '0') ?? 0.0);
      } else {
        _basePrice = widget.item.salePrice;
      }

      final offersSnapshot = await widget.firestoreService.getOffersOnce(widget.item.product.id, widget.businessId);
      _offers = offersSnapshot.docs.map((d) => d.data() as Map<String, dynamic>).toList();
    } catch (e) {
      debugPrint('Error loading product data: $e');
      _basePrice = widget.item.salePrice;
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _onQuantityChanged(String value) {
    final qty = int.tryParse(value);
    if (qty != null && !_isLoading) {
      double bestPrice = _basePrice;
      for (var offer in _offers) {
        final minQty = (offer['quantity'] as num).toDouble();
        final offerPrice = (offer['price'] as num).toDouble();
        if (qty >= minQty) {
          bestPrice = offerPrice;
        }
      }
      if (_priceIncludesVat) {
        final grossPrice = bestPrice * (1 + widget.vatRate);
        _priceController.text = grossPrice.toStringAsFixed(2);
      } else {
        _priceController.text = bestPrice.toStringAsFixed(2);
      }
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final inputValue = double.tryParse(_priceController.text) ?? 0.0;
    double displayValue;
    String displayLabel;

    if (_priceIncludesVat) {
      displayValue = inputValue / (1 + widget.vatRate);
      displayLabel = l10n.get('netLabel');
    } else {
      displayValue = inputValue * (1 + widget.vatRate);
      displayLabel = l10n.get('totalIvaInc');
    }

    return AlertDialog(
      title: Text('${l10n.get('editProduct')}: ${widget.item.product.name}'),
      content: _isLoading
          ? const SizedBox(
              height: 100, child: Center(child: CircularProgressIndicator()))
          : SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: _quantityController,
                    keyboardType: TextInputType.number,
                    decoration:
                        InputDecoration(labelText: l10n.get('quantityLabel')),
                    autofocus: true,
                    onChanged: _onQuantityChanged,
                  ),
                  TextField(
                    controller: _priceController,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      labelText: _priceIncludesVat
                          ? l10n.get('salePriceIvaInc')
                          : l10n.get('salePriceNet'),
                      prefixText: '\$',
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                  CheckboxListTile(
                    title: Text(l10n.get('priceIncludesVat')),
                    value: _priceIncludesVat,
                    onChanged: (val) {
                      setState(() {
                        _priceIncludesVat = val ?? true;
                        // Recalcular el valor en el campo para mantener el precio real constante
                        final currentVal =
                            double.tryParse(_priceController.text) ?? 0.0;
                        if (_priceIncludesVat) {
                          _priceController.text =
                              (currentVal * (1 + widget.vatRate))
                                  .toStringAsFixed(2);
                        } else {
                          _priceController.text =
                              (currentVal / (1 + widget.vatRate))
                                  .toStringAsFixed(2);
                        }
                      });
                    },
                    controlAffinity: ListTileControlAffinity.leading,
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                  ),
                  const SizedBox(height: 10),
                  Text(
                    '$displayLabel: \$${displayValue.toStringAsFixed(2)}',
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, color: Colors.blueGrey),
                  ),
                ],
              ),
            ),
      actions: [
        TextButton(
          onPressed: widget.onDelete,
          child: Text(l10n.get('delete'), style: const TextStyle(color: Colors.red)),
        ),
        const Spacer(), // Empuja los siguientes botones a la derecha
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextButton(
                child: Text(l10n.get('cancel')),
                onPressed: () => Navigator.of(context).pop()),
            const SizedBox(width: 8),
            ElevatedButton(
              onPressed: _isLoading
                  ? null
                  : () {
                  final newQuantity = int.tryParse(_quantityController.text) ?? widget.item.quantity;
                  final inputValue = double.tryParse(_priceController.text) ?? 0.0;
                  double finalNetPrice;
                  if (_priceIncludesVat) {
                    finalNetPrice = inputValue / (1 + widget.vatRate);
                  } else {
                    finalNetPrice = inputValue;
                  }
                  widget.onUpdate(newQuantity, finalNetPrice);
                },
              child: Text(l10n.get('save')),
            ),
          ],
        ),
      ],
    );
  }
}