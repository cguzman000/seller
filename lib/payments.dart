import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'firestore_service.dart';
import 'main.dart'; // Para SellerBottomNavigationBar
import 'app_localizations.dart';

class PaymentsPage extends StatefulWidget {
  final User user;
  final String businessId;
  final String? sellerId;
  final String role;

  const PaymentsPage({
    super.key,
    required this.user,
    required this.businessId,
    this.sellerId,
    required this.role,
  });

  @override
  State<PaymentsPage> createState() => _PaymentsPageState();
}

class _PaymentsPageState extends State<PaymentsPage> {
  final FirestoreService _firestoreService = FirestoreService();
  DateTime? _startDate;
  DateTime? _endDate;
  String? _filterSellerId;
  String? _filterPaymentType;
  String? _filterCustomerId;
  String? _sellerNameFromDb;
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _filterSellerId = widget.sellerId;
    _fetchSellerName();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _fetchSellerName() async {
    // Si el usuario no es el dueño (es un vendedor), buscamos su nombre real en la BD
    if (widget.user.uid != widget.businessId && widget.user.email != null) {
      final name = await _firestoreService.getSellerName(widget.businessId, widget.user.email!);
      if (context.mounted && name != null) {
        setState(() {
          _sellerNameFromDb = name;
        });
      }
    }
  }

  String get _effectiveSellerName {
    if (widget.user.uid == widget.businessId) return 'Administrador';
    // Priorizamos el nombre de la BD del negocio, luego el de Google, y finalmente 'Vendedor'
    return _sellerNameFromDb ?? widget.user.displayName ?? 'Vendedor';
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.get('payments')),
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
                      suffixIcon: _searchController.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear),
                              onPressed: () => setState(() => _searchController.clear()))
                          : null,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12.0)),
                    ),
                    onChanged: (value) => setState(() {}),
                  ),
                ),
                _buildFilterButton(l10n),
              ],
            ),
          ),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
        stream: _firestoreService.getPayments(
          widget.businessId,
          sellerId: _filterSellerId,
          startDate: _startDate,
          endDate: _endDate,
          customerId: _filterCustomerId,
          paymentType: _filterPaymentType,
        ),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            final error = snapshot.error.toString();
            if (error.contains('failed-precondition') || error.contains('index')) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 48),
                      const SizedBox(height: 16),
                      const Text('Falta un índice en Firebase',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      const Text('Selecciona y copia el siguiente enlace para crearlo:', textAlign: TextAlign.center),
                      const SizedBox(height: 16),
                      SelectableText(
                        error,
                        style: const TextStyle(color: Colors.blue),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              );
            }
            return Center(child: Text('Error: $error'));
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final payments = snapshot.data!.docs;
          final searchTerm = _searchController.text.toLowerCase().trim();

          final filteredPayments = payments.where((doc) {
            final data = doc.data() as Map<String, dynamic>;
            final customerName = (data['customerName'] as String? ?? '').toLowerCase();
            return searchTerm.isEmpty || customerName.contains(searchTerm);
          }).toList();

          if (filteredPayments.isEmpty) {
            return Center(child: Text(l10n.get('noPaymentsFound')));
          }

          // Agrupar pagos por mes
          final Map<String, List<QueryDocumentSnapshot>> groupedPayments = {};
          final monthFormat = DateFormat('MMMM yyyy', l10n.locale.languageCode);

          for (var doc in filteredPayments) {
            final data = doc.data() as Map<String, dynamic>;
            final date = (data['date'] as Timestamp?)?.toDate() ?? DateTime.now();
            final monthKey = monthFormat.format(date);
            groupedPayments.putIfAbsent(monthKey, () => []).add(doc);
          }

          final months = groupedPayments.keys.toList();

          return ListView.builder(
            itemCount: months.length,
            itemBuilder: (context, monthIndex) {
              final month = months[monthIndex];
              final items = groupedPayments[month]!;

              double monthTotal = 0.0;
              for (var doc in items) {
                final data = doc.data() as Map<String, dynamic>;
                monthTotal += (data['amount'] as num?)?.toDouble() ?? 0.0;
              }

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          month[0].toUpperCase() + month.substring(1),
                          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: Theme.of(context).colorScheme.primary,
                              ),
                        ),
                        Text(
                          NumberFormat.currency(locale: 'es_AR', symbol: '\$', decimalDigits: 0, customPattern: '\u00A4 #,##0').format(monthTotal),
                          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: Theme.of(context).colorScheme.primary,
                              ),
                        ),
                      ],
                    ),
                  ),
                  ...items.asMap().entries.map((entry) {
                    final index = entry.key;
                    final payment = entry.value;
                    final data = payment.data() as Map<String, dynamic>;
                    final amount = (data['amount'] as num?)?.toDouble() ?? 0.0;
                    final date = (data['date'] as Timestamp?)?.toDate() ?? DateTime.now();
                    final sellerName = data['sellerName'] as String? ?? 'N/A';
                    final customerName = data['customerName'] as String? ?? 'N/A';
                    final paymentType = data['payment_type'] as String? ?? 'Efectivo';

                    IconData paymentIcon;
                    if (paymentType == 'Efectivo') {
                      paymentIcon = Icons.payments;
                    } else if (paymentType == 'Banco') {
                      paymentIcon = Icons.credit_card;
                    } else {
                      paymentIcon = Icons.help_outline;
                    }

                    final itemWidget = Dismissible(
                      key: Key(payment.id),
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
                          builder: (dialogContext) {
                            return AlertDialog(
                              title: Text(l10n.get('confirmDelete')),
                              content: Text(l10n.get('confirmDeletePayment')),
                              actions: <Widget>[
                                TextButton(
                                  onPressed: () => Navigator.of(dialogContext).pop(false),
                                  child: Text(l10n.get('cancel')),
                                ),
                                TextButton(
                                  onPressed: () => Navigator.of(dialogContext).pop(true),
                                  child: Text(l10n.get('delete'), style: const TextStyle(color: Colors.red)),
                                ),
                              ],
                            );
                          },
                        );
                      },
                      onDismissed: (direction) {
                        _firestoreService.deletePayment(payment.id);
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l10n.get('paymentDeleted'))));
                      },
                      child: ListTile(
                        leading: SizedBox(
                          width: 50,
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                DateFormat.MMM(l10n.locale.languageCode).format(date).toUpperCase(),
                                style: Theme.of(context).textTheme.bodyLarge,
                              ),
                              Text(
                                DateFormat.d(l10n.locale.languageCode).format(date),
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                            ],
                          ),
                        ),
                        title: Text(
                          customerName.toUpperCase(),
                          style: const TextStyle(
                            //fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        trailing: Column(
                          mainAxisSize: MainAxisSize.min,
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Icon(paymentIcon, color: Theme.of(context).colorScheme.primary),
                            Text(
                              '\$${NumberFormat.currency(locale: 'es_AR', symbol: '', decimalDigits: 0).format(amount)}',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                        subtitle: Text('${l10n.get('seller')}: $sellerName'),
                        onTap: () => _showEditPaymentDialog(payment),
                      ),
                    );

                    return Column(
                      children: [
                        itemWidget,
                        if (index < items.length - 1)
                          const Divider(height: 1, indent: 72, endIndent: 16),
                      ],
                    );
                  }),
                ],
              );
            },
          );
        },
      ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _startNewPaymentFlow,
        icon: const Icon(Icons.payment),
        label: Text(l10n.get('newPayment')),
        //backgroundColor: Colors.green,
      ),
      bottomNavigationBar: SellerBottomNavigationBar(
        user: widget.user,
        businessId: widget.businessId,
        role: widget.role,
        sellerId: widget.sellerId,
        currentIndex: 2, // Índice para Pagos
        isMainPage: false,
      ),
    );
  }

  Widget _buildFilterButton(AppLocalizations l10n) {
    return PopupMenuButton<String>(
      icon: const Icon(Icons.filter_list),
      onSelected: _handleFilterSelection,
      itemBuilder: (context) => [
        PopupMenuItem(value: 'today', child: Text(l10n.get('filterToday'))),
        PopupMenuItem(value: 'thisWeek', child: Text(l10n.get('filterThisWeek'))),
        PopupMenuItem(value: 'thisMonth', child: Text(l10n.get('filterThisMonth'))),
        PopupMenuItem(value: 'custom', child: Text(l10n.get('filterCustom'))),
        const PopupMenuDivider(),
        PopupMenuItem(value: 'customer', child: Text(l10n.get('selectCustomer'))),
        PopupMenuItem(value: 'method', child: Text(l10n.get('paymentMethod'))),
        const PopupMenuDivider(),
        PopupMenuItem(value: 'clear', child: Text(l10n.get('filterAll'))),
        if (widget.user.uid == widget.businessId) ...[
          const PopupMenuDivider(),
          PopupMenuItem(value: 'seller', child: Text(l10n.get('filterBySeller'))),
        ]
      ],
    );
  }

  void _handleFilterSelection(String value) {
    final now = DateTime.now();
    switch (value) {
      case 'today':
        setState(() {
          _startDate = DateTime(now.year, now.month, now.day);
          _endDate = DateTime(now.year, now.month, now.day, 23, 59, 59);
        });
        break;
      case 'thisWeek':
        setState(() {
          final lastMonday = now.subtract(Duration(days: now.weekday - 1));
          _startDate = DateTime(lastMonday.year, lastMonday.month, lastMonday.day);
          _endDate = now;
        });
        break;
      case 'thisMonth':
        setState(() {
          _startDate = DateTime(now.year, now.month, 1);
          _endDate = now;
        });
        break;
      case 'clear':
        setState(() {
          _startDate = null;
          _endDate = null;
          _filterSellerId = widget.user.uid == widget.businessId ? null : widget.user.uid;
          _filterPaymentType = null;
          _filterCustomerId = null;
          _searchController.clear();
        });
        break;
      case 'customer':
        _showCustomerFilter();
        break;
      case 'method':
        _showPaymentMethodFilter();
        break;
      case 'custom':
        _selectCustomRange();
        break;
      case 'seller':
        _showSellerFilterDialog();
        break;
    }
  }

  void _showCustomerFilter() async {
    final result = await showDialog<DocumentSnapshot>(
      context: context,
      builder: (context) => _CustomerSearchDialog(
        businessId: widget.businessId,
        firestoreService: _firestoreService,
        sellerId: widget.sellerId,
      ),
    );
    if (result != null) {
      setState(() => _filterCustomerId = result.id);
    }
  }

  void _showPaymentMethodFilter() {
    final l10n = AppLocalizations.of(context);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.get('paymentMethod')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.all_inclusive),
              title: Text(l10n.get('filterAll')),
              onTap: () { setState(() => _filterPaymentType = null); Navigator.pop(context); },
            ),
            ListTile(
              leading: const Icon(Icons.payments),
              title: Text(l10n.get('cash')),
              onTap: () { setState(() => _filterPaymentType = 'Efectivo'); Navigator.pop(context); },
            ),
            ListTile(
              leading: const Icon(Icons.credit_card),
              title: Text(l10n.get('bank')),
              onTap: () { setState(() => _filterPaymentType = 'Banco'); Navigator.pop(context); },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _selectCustomRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
      initialDateRange: _startDate != null && _endDate != null
          ? DateTimeRange(start: _startDate!, end: _endDate!)
          : null,
    );
    if (picked != null) {
      setState(() {
        _startDate = picked.start;
        _endDate = DateTime(picked.end.year, picked.end.month, picked.end.day, 23, 59, 59);
      });
    }
  }

  void _showSellerFilterDialog() {
    final l10n = AppLocalizations.of(context);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.get('selectSeller')),
        content: SizedBox(
          width: double.maxFinite,
          child: StreamBuilder<QuerySnapshot>(
            stream: _firestoreService.getUsers(widget.businessId, role: 'seller'),
            builder: (context, snapshot) {
              if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
              final sellers = snapshot.data!.docs;
              return ListView.builder(
                shrinkWrap: true,
                itemCount: sellers.length + 1,
                itemBuilder: (context, index) {
                  if (index == 0) {
                    return ListTile(
                      title: Text(l10n.get('allSellers')),
                      onTap: () {
                        setState(() => _filterSellerId = null);
                        Navigator.pop(context);
                      },
                    );
                  }
                  final seller = sellers[index - 1];
                  final data = seller.data() as Map<String, dynamic>;
                  return ListTile(
                    title: Text(data['name'] ?? 'N/A'),
                    onTap: () {
                      setState(() => _filterSellerId = seller.id);
                      Navigator.pop(context);
                    },
                  );
                },
              );
            },
          ),
        ),
      ),
    );
  }

  Future<void> _startNewPaymentFlow() async {
    // 1. Seleccionar Cliente
    final customerDoc = await showDialog<DocumentSnapshot>(
      context: context,
      builder: (dialogContext) => _CustomerSearchDialog(
        businessId: widget.businessId,
        firestoreService: _firestoreService,
        sellerId: widget.role == 'admin' ? null : widget.sellerId,
      ),
    );

    if (customerDoc == null || !context.mounted) return;

    final l10n = AppLocalizations.of(context);

    // 2. Seleccionar Modo de Pago
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
    // Mostramos un indicador de carga mientras calculamos la deuda
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

  /// Obtiene todas las ventas con saldo pendiente para un cliente
  Future<List<_PendingSale>> _fetchPendingSales(String customerId) async {
    final salesSnapshot = await _firestoreService.getSalesForCustomer(
      widget.businessId,
      customerId,
      // No filtramos por sellerId aquí para ver toda la deuda del cliente con el negocio
    ).first;

    final List<_PendingSale> pendingList = [];

    for (final saleDoc in salesSnapshot.docs) {
      final saleData = saleDoc.data() as Map<String, dynamic>;
      final total = (saleData['totalAmount'] as num?)?.toDouble() ?? 0.0;
      
      // Obtener pagos
      final paymentsSnapshot = await _firestoreService.getPaymentsForSale(saleDoc.id).first;
      final paid = paymentsSnapshot.docs.fold<double>(0.0, (prev, doc) {
        final pData = doc.data() as Map<String, dynamic>;
        
        final saleIds = pData['saleIds'];
        final isShared = saleIds is List && saleIds.length > 1;

        if (pData.containsKey('allocations') && pData['allocations'] is Map && (pData['allocations'] as Map).containsKey(saleDoc.id)) {
          return prev + ((pData['allocations'] as Map)[saleDoc.id] as num? ?? 0.0).toDouble();
        }
        if (!isShared) {
          return prev + (pData['amount'] as num? ?? 0.0).toDouble();
        }
        return prev;
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
                        Navigator.of(sbContext).pop(); // Cerrar selector
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
                // Para pago global, pasamos todas las ventas pendientes para que el servicio distribuya
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
                    final messenger = ScaffoldMessenger.of(sbContext);
                    Navigator.pop(dialogContext); // Cerrar diálogo
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
                      messenger.showSnackBar(const SnackBar(content: Text('Pago registrado con éxito')));
                    } catch (e) {
                      if (mounted) {
                        showDialog(
                          context: context,
                          builder: (errContext) => AlertDialog(
                            title: const Text('Error al procesar'),
                            content: SingleChildScrollView(child: SelectableText(e.toString())),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.of(errContext).pop(),
                                child: const Text('Cerrar'),
                              ),
                            ],
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

  void _showEditPaymentDialog(DocumentSnapshot paymentDoc) {
    final l10n = AppLocalizations.of(context);
    final data = paymentDoc.data() as Map<String, dynamic>;
    final amountController = TextEditingController(text: (data['amount'] as num).toString());
    String paymentType = data['payment_type'] ?? 'Efectivo';

    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (sbContext, setStateDialog) {
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
                    decoration: InputDecoration(
                      labelText: l10n.get('amountToPay'),
                      prefixText: '\$ ',
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(l10n.get('paymentMethod'), style: const TextStyle(fontWeight: FontWeight.bold)),
                  RadioGroup<String>(
                    groupValue: paymentType,
                    onChanged: (val) => setStateDialog(() => paymentType = val!),
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
            ),
            actions: [
              TextButton(onPressed: () => Navigator.of(sbContext).pop(), child: Text(l10n.get('cancel'))),
              ElevatedButton(
                onPressed: () async {
                  final amount = double.tryParse(amountController.text);
                  if (amount != null) {
                    await _firestoreService.updatePayment(paymentDoc.id, amount, paymentType: paymentType);
                    if (sbContext.mounted) {
                      Navigator.of(sbContext).pop();
                      ScaffoldMessenger.of(sbContext).showSnackBar(const SnackBar(content: Text('Pago actualizado')));
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
}

class _PendingSale {
  final DocumentSnapshot doc;
  final double pendingAmount;
  _PendingSale(this.doc, this.pendingAmount);
}

class _CustomerSearchDialog extends StatefulWidget {
  final String businessId;
  final FirestoreService firestoreService;
  final String? sellerId;

  const _CustomerSearchDialog({required this.businessId, required this.firestoreService, this.sellerId});

  @override
  State<_CustomerSearchDialog> createState() => _CustomerSearchDialogState();
}

class _CustomerSearchDialogState extends State<_CustomerSearchDialog> {
  final TextEditingController _searchController = TextEditingController();
  String _searchTerm = '';

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(l10n.get('selectCustomer')),
      content: SizedBox(
        width: double.maxFinite,
        height: 400,
        child: Column(
          children: [
            TextField(
              controller: _searchController,
              decoration: InputDecoration(
                labelText: l10n.get('search'),
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchTerm.isNotEmpty 
                  ? IconButton(icon: const Icon(Icons.clear), onPressed: () {
                      _searchController.clear();
                      setState(() => _searchTerm = '');
                    }) 
                  : null,
              ),
              onChanged: (val) => setState(() => _searchTerm = val.toLowerCase()),
            ),
            const SizedBox(height: 10),
            Expanded(
              child: StreamBuilder<QuerySnapshot>(
                // Usamos getCustomers para traer la lista. 
                // Si quieres solo clientes con deuda, usa getCustomersWithSales pero requiere lógica extra.
                // Según el prompt: "lista de clientes de ese negocio y del vendedor".
                stream: widget.firestoreService.getCustomers(widget.businessId, sellerId: widget.sellerId, orderBy: 'name', descending: false),
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    final error = snapshot.error.toString();
                    if (error.contains('failed-precondition') || error.contains('index')) {
                      return Center(
                        child: Padding(
                          padding: const EdgeInsets.all(8.0),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 40),
                              const SizedBox(height: 10),
                              const Text(
                                'Falta un índice en Firebase',
                                style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 5),
                              const Text('Copia y abre este enlace para solucionarlo:', textAlign: TextAlign.center, style: TextStyle(fontSize: 11)),
                              const SizedBox(height: 10),
                              SelectableText(
                                error,
                                style: const TextStyle(color: Colors.blue, fontSize: 10),
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        ),
                      );
                    }
                    return Center(child: Text('Error: $error'));
                  }
                  if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
                  
                  final filtered = snapshot.data!.docs.where((doc) {
                    if (_searchTerm.isEmpty) return true;
                    final data = doc.data() as Map<String, dynamic>;
                    final name = (data['name'] as String? ?? '').toLowerCase();
                    final dni = (data['dni'] as String? ?? '').toLowerCase();
                    return name.contains(_searchTerm) || dni.contains(_searchTerm);
                  }).toList();

                  if (filtered.isEmpty) return Center(child: Text(l10n.get('noCustomers')));

                  return ListView.builder(
                    itemCount: filtered.length,
                    itemBuilder: (context, index) {
                      final doc = filtered[index];
                      final data = doc.data() as Map<String, dynamic>;
                      return ListTile(
                        title: Text((data['name'] as String? ?? l10n.get('noName'))),
                        subtitle: Text(data['dni'] ?? ''),
                        onTap: () => Navigator.pop(context, doc),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(l10n.get('cancel'))),
      ],
    );
  }
}
