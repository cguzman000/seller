import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import 'firestore_service.dart';
import 'main.dart'; // Importar para usar SellerBottomNavigationBar
import 'util/text_formatter.dart';
import 'app_localizations.dart';
import 'pdf_generator.dart';

// Formateadores globales para los reportes
final NumberFormat currencyFormat = NumberFormat.currency(
  locale: 'es_AR',
  symbol: '\$',
  decimalDigits: 0,
  customPattern: '\u00A4 #,##0',
);
final DateFormat dateFormat = DateFormat('dd/MM/yyyy');
final DateFormat dateTimeFormat = DateFormat('dd/MM/yyyy HH:mm');

/// Extensión para convertir un texto a "Title Case" (Ej: JUAN PEREZ -> Juan Perez)
extension StringTitleCase on String {
  String toTitleCase() {
    if (isEmpty) return this;
    return split(' ')
        .map((word) => word.isNotEmpty ? '${word[0].toUpperCase()}${word.substring(1).toLowerCase()}' : '')
        .join(' ');
  }
}

// -----------------------------------------------------------------------------
// 5. INFORME DE VENTAS POR PRODUCTO
// -----------------------------------------------------------------------------
class SalesByProductReportPage extends StatefulWidget {
  final String businessId;
  final String? sellerId;
  final User user;

  const SalesByProductReportPage({super.key, required this.businessId, this.sellerId, required this.user});

  @override
  State<SalesByProductReportPage> createState() => _SalesByProductReportPageState();
}

class _SalesByProductReportPageState extends State<SalesByProductReportPage> {
  DateTime _startDate = DateTime(DateTime.now().year, 1, 1);
  DateTime _endDate = DateTime.now();
  final FirestoreService _service = FirestoreService();
  String? _filterSellerId;
  String? _filterProductId;
  int _touchedIndex = -1;

  Future<void> _showProductPicker() async {
    final result = await showDialog<Map<String, dynamic>?>(
      context: context,
      builder: (context) => ProductSelectionDialog(businessId: widget.businessId),
    );
    if (result != null) {
      setState(() {
        _filterProductId = result['id'];
      });
    }
  }

  Future<void> _selectDateRange(BuildContext context) async {
    final DateTimeRange? picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      initialDateRange: DateTimeRange(start: _startDate, end: _endDate),
    );
    if (picked != null) {
      setState(() {
        _startDate = picked.start;
        _endDate = picked.end;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final endQueryDate = DateTime(_endDate.year, _endDate.month, _endDate.day, 23, 59, 59);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.get('salesByProduct'))),
      body: Column(
        children: [
          // Filtro de Fechas
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              children: [
                Expanded(
                  child: Card(
                    elevation: 2,
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                      leading: const Icon(Icons.date_range, color: Colors.purple, size: 20),
                      title: Text(
                        '${dateFormat.format(_startDate)} - ${dateFormat.format(_endDate)}',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                      onTap: () => _selectDateRange(context),
                    ),
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.filter_list, color: _filterProductId != null ? Colors.blue : null),
                  onPressed: _showProductPicker,
                  tooltip: l10n.get('selectProduct'),
                ),
              ],
            ),
          ),
          
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: _service.getSales(widget.businessId, sellerId: widget.sellerId ?? _filterSellerId, startDate: _startDate, endDate: endQueryDate),
              builder: (context, snapshot) {
                if (snapshot.hasError) return Center(child: Text('Error: ${snapshot.error}'));
                if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());

                final sales = snapshot.data!.docs;
                
                // Agregación de datos
                final Map<String, Map<String, dynamic>> productStats = {};

                for (var saleDoc in sales) {
                  final saleData = saleDoc.data() as Map<String, dynamic>;
                  final items = List<Map<String, dynamic>>.from(saleData['items'] ?? []);

                  for (var item in items) {
                    final productId = item['productId'] ?? 'unknown';
                    
                    if (_filterProductId != null && productId != _filterProductId) continue;

                    final productName = item['productName'] ?? item['name'] ?? 'Desconocido';
                    final quantity = (item['quantity'] as num).toDouble();
                    final price = (item['price'] as num).toDouble();
                    final total = quantity * price;

                    if (!productStats.containsKey(productId)) {
                      productStats[productId] = {
                        'name': productName,
                        'quantity': 0.0,
                        'total': 0.0,
                      };
                    }
                    productStats[productId]!['quantity'] += quantity;
                    productStats[productId]!['total'] += total;
                  }
                }

                // Convertir a lista y ordenar por total vendido (descendente)
                final statsList = productStats.values.toList();
                statsList.sort((a, b) => b['total'].compareTo(a['total']));

                if (statsList.isEmpty) {
                  return Center(child: Text(l10n.get('noSalesInPeriod')));
                }

                // --- Preparación de datos para el gráfico ---
                final topN = 5;
                final chartStats = statsList.take(topN).toList();
                final otherTotal = statsList.skip(topN).fold(0.0, (prev, item) => prev + item['total']);
                if (otherTotal > 0.01) {
                  chartStats.add({'name': 'Otros', 'total': otherTotal});
                }
                final totalRevenue = statsList.fold(0.0, (prev, item) => prev + item['total']);

                final List<Color> pieColors = [
                  Colors.blue.shade400,
                  Colors.green.shade400,
                  Colors.orange.shade400,
                  Colors.red.shade400,
                  Colors.purple.shade400,
                  Colors.grey.shade400,
                ];

                return Column(
                  children: [
                    SizedBox(
                      height: 220,
                      child: Card(
                        elevation: 2,
                        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: PieChart(
                            PieChartData(
                              pieTouchData: PieTouchData(
                                touchCallback: (FlTouchEvent event, pieTouchResponse) {
                                  setState(() {
                                    if (!event.isInterestedForInteractions || pieTouchResponse == null || pieTouchResponse.touchedSection == null) {
                                      _touchedIndex = -1;
                                      return;
                                    }
                                    _touchedIndex = pieTouchResponse.touchedSection!.touchedSectionIndex;
                                  });
                                },
                              ),
                              borderData: FlBorderData(show: false),
                              sectionsSpace: 2,
                              centerSpaceRadius: 40,
                              sections: List.generate(chartStats.length, (i) {
                                final isTouched = i == _touchedIndex;
                                final radius = isTouched ? 60.0 : 50.0;
                                final stat = chartStats[i];
                                final percentage = totalRevenue > 0 ? (stat['total'] / totalRevenue) * 100 : 0;

                                return PieChartSectionData(
                                  color: pieColors[i % pieColors.length],
                                  value: stat['total'],
                                  title: '${percentage.toStringAsFixed(0)}%',
                                  radius: radius,
                                  titleStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white, shadows: [Shadow(color: Colors.black, blurRadius: 2)]),
                                );
                              }),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const Divider(indent: 16, endIndent: 16),
                    Expanded(
                      child: ListView.builder(
                        itemCount: statsList.length,
                        itemBuilder: (context, index) {
                          final stat = statsList[index];
                          return ListTile(
                            leading: CircleAvatar(
                              backgroundColor: pieColors[index % pieColors.length].withValues(alpha: 0.3),
                              child: Text('${index + 1}', style: TextStyle(color: pieColors[index % pieColors.length], fontWeight: FontWeight.bold)),
                            ),
                            title: Text((stat['name'] as String? ?? '').toUpperCase()),
                            subtitle: Text('${stat['quantity'].toStringAsFixed(0)} un.'),
                            trailing: Text(
                              '\$${currencyFormat.format(stat['total']).replaceAll('\$', '').trim()}',
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
      bottomNavigationBar: SellerBottomNavigationBar(
        user: widget.user,
        businessId: widget.businessId,
        sellerId: widget.sellerId ?? (widget.user.uid == widget.businessId ? null : widget.user.uid),
        currentIndex: 3, // Productos
        allowSamePageNavigation: true,
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// 6. RANKING DE CLIENTES
// -----------------------------------------------------------------------------
class CustomerRankingPage extends StatefulWidget {
  final String businessId;
  final String? sellerId;
  final User user;

  const CustomerRankingPage({super.key, required this.businessId, this.sellerId, required this.user});

  @override
  State<CustomerRankingPage> createState() => _CustomerRankingPageState();
}

class _CustomerRankingPageState extends State<CustomerRankingPage> {
  DateTime _startDate = DateTime(DateTime.now().year, 1, 1);
  DateTime _endDate = DateTime.now();
  final FirestoreService _service = FirestoreService();
  String? _filterSellerId;

  Future<void> _selectDateRange(BuildContext context) async {
    final DateTimeRange? picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      initialDateRange: DateTimeRange(start: _startDate, end: _endDate),
    );
    if (picked != null) {
      setState(() {
        _startDate = picked.start;
        _endDate = picked.end;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final endQueryDate = DateTime(_endDate.year, _endDate.month, _endDate.day, 23, 59, 59);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.get('customerRanking'))),
      body: Column(
        children: [
          // Filtro de Fechas
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Card(
              child: ListTile(
                leading: const Icon(Icons.date_range, color: Colors.teal),
                title: Text(
                  '${dateFormat.format(_startDate)} - ${dateFormat.format(_endDate)}',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                trailing: const Icon(Icons.arrow_drop_down),
                onTap: () => _selectDateRange(context),
              ),
            ),
          ),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: _service.getSales(widget.businessId, sellerId: widget.sellerId ?? _filterSellerId, startDate: _startDate, endDate: endQueryDate),
              builder: (context, snapshot) {
                if (snapshot.hasError) return Center(child: Text('Error: ${snapshot.error}'));
                if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());

                final sales = snapshot.data!.docs;
                
                // Agregación por cliente
                final Map<String, Map<String, dynamic>> customerStats = {};

                for (var saleDoc in sales) {
                  final saleData = saleDoc.data() as Map<String, dynamic>;
                  final customerId = saleData['customerId'] ?? 'unknown';
                  final customerName = saleData['customerName'] ?? 'CLIENTE FINAL';
                  final total = (saleData['totalAmount'] as num).toDouble();

                  if (!customerStats.containsKey(customerId)) {
                    customerStats[customerId] = {
                      'name': customerName,
                      'count': 0,
                      'total': 0.0,
                    };
                  }
                  customerStats[customerId]!['count'] += 1;
                  customerStats[customerId]!['total'] += total;
                }

                // Convertir a lista y ordenar
                final statsList = customerStats.values.toList();
                statsList.sort((a, b) => b['total'].compareTo(a['total']));

                if (statsList.isEmpty) {
                  return Center(child: Text(l10n.get('noSalesInPeriod')));
                }

                return ListView.builder(
                  itemCount: statsList.length,
                  itemBuilder: (context, index) {
                    final stat = statsList[index];
                    // Top 3 highlight
                    Color? avatarColor;
                    if (index == 0) {
                      avatarColor = Colors.amber; // Gold
                    } else if (index == 1) {
                      avatarColor = Colors.grey.shade400; // Silver
                    } else if (index == 2) {
                      avatarColor = Colors.brown.shade300; // Bronze
                    } else {
                      avatarColor = Colors.teal.shade100;
                    }

                    return ListTile(
                      leading: CircleAvatar(
                        backgroundColor: avatarColor,
                        child: Text('${index + 1}', style: TextStyle(color: index < 3 ? Colors.white : Colors.teal.shade900, fontWeight: FontWeight.bold)),
                      ),
                      title: Text((stat['name'] as String? ?? '').toUpperCase()),
                      subtitle: Text('${stat['count']} ${l10n.get('purchases')}'),
                      trailing: Text(
                        '\$${currencyFormat.format(stat['total']).replaceAll('\$', '').trim()}',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                      ),
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
        sellerId: widget.sellerId ?? (widget.user.uid == widget.businessId ? null : widget.user.uid),
        currentIndex: 2, // Clientes
        allowSamePageNavigation: true,
      ),
    );
  }
}

// Diálogo para seleccionar producto con búsqueda
class ProductSelectionDialog extends StatefulWidget {
  final String businessId;
  const ProductSelectionDialog({super.key, required this.businessId});

  @override
  State<ProductSelectionDialog> createState() => _ProductSelectionDialogState();
}

class _ProductSelectionDialogState extends State<ProductSelectionDialog> {
  final TextEditingController _searchController = TextEditingController();
  String _searchTerm = '';

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      setState(() {
        _searchTerm = _searchController.text.toUpperCase();
      });
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Dialog(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(l10n.get('selectProduct'), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            TextField(
              controller: _searchController,
              decoration: InputDecoration(labelText: l10n.get('search'), prefixIcon: const Icon(Icons.search), border: const OutlineInputBorder()),
              inputFormatters: [UpperCaseTextFormatter()],
              textCapitalization: TextCapitalization.characters,
            ),
            const SizedBox(height: 10),
            SizedBox(
              height: 300,
              child: StreamBuilder<QuerySnapshot>(
                stream: FirestoreService().getProducts(widget.businessId),
                builder: (context, snapshot) {
                  if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
                  final allDocs = snapshot.data!.docs;
                  final filteredDocs = allDocs.where((doc) {
                    if (_searchTerm.isEmpty) return true;
                    final data = doc.data() as Map<String, dynamic>;
                    final name = (data['name'] ?? '').toString().toUpperCase();
                    return name.contains(_searchTerm);
                  }).toList();

                  return ListView.builder(
                    itemCount: filteredDocs.length + 1,
                    itemBuilder: (context, index) {
                      if (index == 0) {
                        return ListTile(
                          leading: const Icon(Icons.inventory_2_outlined),
                          title: Text(l10n.get('allProducts')),
                          onTap: () => Navigator.pop(context, {'id': null, 'name': null}),
                        );
                      }
                      final doc = filteredDocs[index - 1];
                      final data = doc.data() as Map<String, dynamic>;
                      return ListTile(
                        leading: const Icon(Icons.inventory_2),
                        title: Text((data['name'] as String? ?? 'Sin nombre').toUpperCase()),
                        subtitle: Text('Stock: ${data['stock']}'),
                        onTap: () => Navigator.pop(context, {'id': doc.id, 'name': data['name']}),
                      );
                    },
                  );
                },
              ),
            ),
            TextButton(onPressed: () => Navigator.pop(context), child: Text(l10n.get('cancel'))),
          ],
        ),
      ),
    );
  }
}

// Diálogo para seleccionar cliente con búsqueda
class CustomerSelectionDialog extends StatefulWidget {
  final String businessId;
  final String? sellerId;
  const CustomerSelectionDialog({super.key, required this.businessId, this.sellerId});

  @override
  State<CustomerSelectionDialog> createState() => _CustomerSelectionDialogState();
}

class _CustomerSelectionDialogState extends State<CustomerSelectionDialog> {
  final TextEditingController _searchController = TextEditingController();
  String _searchTerm = '';

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      setState(() {
        _searchTerm = _searchController.text.toUpperCase();
      });
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Dialog(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(l10n.get('selectCustomer'), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            TextField(
              controller: _searchController,
              decoration: InputDecoration(labelText: l10n.get('search'), prefixIcon: const Icon(Icons.search), border: const OutlineInputBorder()),
              inputFormatters: [UpperCaseTextFormatter()],
              textCapitalization: TextCapitalization.characters,
            ),
            const SizedBox(height: 10),
            SizedBox(
              height: 300,
              child: StreamBuilder<QuerySnapshot>(
                stream: FirestoreService().getCustomers(widget.businessId, sellerId: widget.sellerId),
                builder: (context, snapshot) {
                  if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
                  final allDocs = snapshot.data!.docs;
                  final filteredDocs = allDocs.where((doc) {
                    if (_searchTerm.isEmpty) return true;
                    final data = doc.data() as Map<String, dynamic>;
                    final name = (data['name'] ?? '').toString().toUpperCase();
                    final dni = (data['dni'] ?? '').toString().toUpperCase();
                    return name.contains(_searchTerm) || dni.contains(_searchTerm);
                  }).toList();

                  return ListView.builder(
                    itemCount: filteredDocs.length + 1,
                    itemBuilder: (context, index) {
                      if (index == 0) {
                        return ListTile(
                          leading: const Icon(Icons.people),
                          title: Text(l10n.get('allCustomers')),
                          onTap: () => Navigator.pop(context, {'id': null, 'name': null}),
                        );
                      }
                      final doc = filteredDocs[index - 1];
                      final data = doc.data() as Map<String, dynamic>;
                      return ListTile(
                        leading: const Icon(Icons.person),
                        title: Text((data['name'] as String? ?? 'Sin nombre').toUpperCase()),
                        subtitle: Text(data['dni'] ?? ''),
                        onTap: () => Navigator.pop(context, {'id': doc.id, 'name': data['name']}),
                      );
                    },
                  );
                },
              ),
            ),
            TextButton(onPressed: () => Navigator.pop(context), child: Text(l10n.get('cancel'))),
          ],
        ),
      ),
    );
  }
}


// -----------------------------------------------------------------------------
// 3. CUENTAS POR COBRAR
// -----------------------------------------------------------------------------
class AccountsReceivablePage extends StatefulWidget {
  final String businessId;
  final String? sellerId;
  final User user;

  const AccountsReceivablePage({super.key, required this.businessId, this.sellerId, required this.user});

  @override
  State<AccountsReceivablePage> createState() => _AccountsReceivablePageState();
}

class _AccountsReceivablePageState extends State<AccountsReceivablePage> {
  final FirestoreService _service = FirestoreService();
  String? _filterSellerId;
  String? _filterCustomerId;

  Future<void> _showCustomerPicker() async {
    final result = await showDialog<Map<String, dynamic>?>(
      context: context,
      builder: (context) => CustomerSelectionDialog(businessId: widget.businessId, sellerId: widget.sellerId ?? _filterSellerId),
    );
    if (result != null) {
      setState(() {
        _filterCustomerId = result['id'];
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.get('accountsReceivable'))),
      body: Column(
        children: [
          // Filtros
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              children: [
                if (widget.sellerId == null)
                  Expanded(
                    child: Card(
                      elevation: 2,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12.0),
                        child: StreamBuilder<QuerySnapshot>(
                          stream: _service.getUsers(widget.businessId),
                          builder: (context, snapshot) {
                            if (!snapshot.hasData) return const SizedBox(height: 48);
                            final users = snapshot.data!.docs;
                            return DropdownButtonHideUnderline(
                              child: DropdownButton<String?>(
                                isExpanded: true,
                                value: _filterSellerId,
                                hint: Text('${l10n.get('sellerLabel')}${l10n.get('all')}'),
                                items: [
                                  DropdownMenuItem(value: null, child: Text('${l10n.get('sellerLabel')}${l10n.get('all')}')),
                                  ...users.map((doc) {
                                    final data = doc.data() as Map<String, dynamic>;
                                    return DropdownMenuItem(
                                      value: doc.id,
                                      child: Text(data['name'] ?? 'Sin nombre', overflow: TextOverflow.ellipsis),
                                    );
                                  }),
                                ],
                                onChanged: (val) => setState(() => _filterSellerId = val),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                if (widget.sellerId == null) const SizedBox(width: 8),
                IconButton(
                  icon: Icon(Icons.filter_list, color: _filterCustomerId != null ? Colors.blue : null),
                  onPressed: _showCustomerPicker,
                  tooltip: l10n.get('selectCustomer'),
                ),
              ],
            ),
          ),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: _service.getSales(widget.businessId, sellerId: widget.sellerId ?? _filterSellerId),
              builder: (context, salesSnap) {
                if (salesSnap.hasError) return Center(child: Text('Error: ${salesSnap.error}'));
                if (!salesSnap.hasData) return const Center(child: CircularProgressIndicator());
                
                return StreamBuilder<QuerySnapshot>(
                  stream: _service.getPayments(widget.businessId, sellerId: widget.sellerId),
                  builder: (context, paymentsSnap) {
                    if (paymentsSnap.hasError) return Center(child: Text('Error: ${paymentsSnap.error}'));
                    if (!paymentsSnap.hasData) return const Center(child: CircularProgressIndicator());

                    final allSales = salesSnap.data!.docs;
                    final payments = paymentsSnap.data!.docs;

                    final sales = _filterCustomerId == null 
                        ? allSales 
                        : allSales.where((doc) => (doc.data() as Map<String, dynamic>)['customerId'] == _filterCustomerId).toList();

              // 1. Calcular lo pagado por venta
              Map<String, double> paidPerSale = {};
              for (var p in payments) {
                final data = p.data() as Map<String, dynamic>;
                final saleId = data['saleId'] as String;
                final amount = (data['amount'] as num).toDouble();
                paidPerSale[saleId] = (paidPerSale[saleId] ?? 0) + amount;
              }

              // 2. Calcular deuda por cliente
              Map<String, Map<String, dynamic>> customerDebt = {};

              for (var s in sales) {
                final data = s.data() as Map<String, dynamic>;
                final saleId = s.id;
                final total = (data['totalAmount'] as num).toDouble();
                final paid = paidPerSale[saleId] ?? 0;
                final debt = total - paid;

                // Tolerancia para errores de punto flotante
                if (debt > 1.0) { 
                  final customerId = data['customerId'] as String;
                  final customerName = data['customerName'] as String;
                  
                  if (!customerDebt.containsKey(customerId)) {
                    customerDebt[customerId] = {'name': customerName, 'debt': 0.0, 'count': 0};
                  }
                  customerDebt[customerId]!['debt'] += debt;
                  customerDebt[customerId]!['count'] += 1;
                }
              }

              final debtList = customerDebt.values.toList();
              // Ordenar de mayor deuda a menor
              debtList.sort((a, b) => b['debt'].compareTo(a['debt']));

              if (debtList.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.check_circle_outline, size: 80, color: Colors.green),
                      const SizedBox(height: 16),
                      Text(l10n.get('allUpToDate'), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                      Text(l10n.get('noPendingDebts'), style: const TextStyle(color: Colors.grey)),
                    ],
                  ),
                );
              }

              final totalDebt = debtList.fold(0.0, (total, item) => total + item['debt']);

              return Column(
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    color: Colors.red.shade50,
                    width: double.infinity,
                    child: Column(
                      children: [
                        Text(l10n.get('totalPendingCollection'), style: const TextStyle(fontSize: 14, color: Colors.red)),
                        Text(
                          '\$${currencyFormat.format(totalDebt).replaceAll('\$', '').trim()}',
                          style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: Colors.red),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: ListView.builder(
                      itemCount: debtList.length,
                      itemBuilder: (context, index) {
                        final item = debtList[index];
                        return ListTile(
                          leading: CircleAvatar(
                            backgroundColor: Colors.red.shade100,
                            child: Text(item['name'].substring(0, 1).toUpperCase(), style: TextStyle(color: Colors.red.shade900)),
                          ),
                          title: Text((item['name'] as String? ?? '').toUpperCase()),
                          subtitle: Text('${item['count']} ${l10n.get('salesWithDebt')}'),
                          trailing: Text(
                            currencyFormat.format(item['debt']),
                            style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold, fontSize: 16),
                          ),
                          onTap: () {
                            // Aquí podrías navegar al detalle del cliente si lo deseas
                          },
                        );
                      },
                    ),
                  ),
                ],
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
        sellerId: widget.sellerId ?? (widget.user.uid == widget.businessId ? null : widget.user.uid),
        currentIndex: 1, // Pagos / Dinero
        allowSamePageNavigation: true,
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// 4. INFORME DE STOCK
// -----------------------------------------------------------------------------
class StockReportPage extends StatelessWidget {
  final String businessId;
  final User user;
  final FirestoreService _service = FirestoreService();

  StockReportPage({super.key, required this.businessId, required this.user});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.get('stockReport'))),
      body: StreamBuilder<QuerySnapshot>(
        stream: _service.getProducts(businessId),
        builder: (context, snapshot) {
          if (snapshot.hasError) return Center(child: Text('Error: ${snapshot.error}'));
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          
          final products = snapshot.data!.docs;
          double totalCostValue = 0;
          double totalPriceValue = 0;
          
          for(var p in products) {
            final data = p.data() as Map<String, dynamic>;
            final stock = (data['stock'] as num).toInt();
            final cost = (data['purch_price'] as num?)?.toDouble() ?? 0.0;
            final price = (data['price'] as num?)?.toDouble() ?? 0.0;
            
            if (stock > 0) {
              totalCostValue += stock * cost;
              totalPriceValue += stock * price;
            }
          }

          return Column(
            children: [
               Card(
                 margin: const EdgeInsets.all(12),
                 elevation: 3,
                 child: Padding(
                   padding: const EdgeInsets.all(16.0),
                   child: Row(
                     mainAxisAlignment: MainAxisAlignment.spaceAround,
                     children: [
                       Column(
                         children: [
                           Text(l10n.get('costValue'), style: const TextStyle(color: Colors.grey)),
                           Text('\$${currencyFormat.format(totalCostValue).replaceAll('\$', '').trim()}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.blueGrey)),
                         ],
                       ),
                       Container(width: 1, height: 40, color: Colors.grey.shade300),
                       Column(
                         children: [
                           Text(l10n.get('saleValue'), style: const TextStyle(color: Colors.grey)),
                           Text('\$${currencyFormat.format(totalPriceValue).replaceAll('\$', '').trim()}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.green)),
                         ],
                       ),
                     ],
                   ),
                 ),
               ),
              Expanded(
                child: ListView.builder(
                  itemCount: products.length,
                  itemBuilder: (context, index) {
                    final data = products[index].data() as Map<String, dynamic>;
                    final stock = (data['stock'] as num).toInt();
                    final safetyStock = (data['safety_stock'] as num?)?.toInt() ?? 0;
                    final isLow = stock <= safetyStock;

                    return ListTile(
                      title: Text(data['name']),
                      subtitle: Text('Stock: $stock | Mín: $safetyStock'),
                      trailing: isLow 
                        ? Chip(
                            label: Text(l10n.get('low'), style: const TextStyle(color: Colors.white, fontSize: 10)), 
                            backgroundColor: Colors.orange,
                            padding: EdgeInsets.all(0),
                            visualDensity: VisualDensity.compact,
                          )
                        : Text('$stock un.', style: const TextStyle(fontWeight: FontWeight.bold)),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
      bottomNavigationBar: SellerBottomNavigationBar(
        user: user,
        businessId: businessId,
        sellerId: user.uid == businessId ? null : user.uid,
        currentIndex: 5, // Stock
        allowSamePageNavigation: true,
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// 7. RENDIMIENTO DE VENDEDORES
// -----------------------------------------------------------------------------
class SellerPerformancePage extends StatefulWidget {
  final String businessId;
  final User user;

  const SellerPerformancePage({super.key, required this.businessId, required this.user});

  @override
  State<SellerPerformancePage> createState() => _SellerPerformancePageState();
}

class _SellerPerformancePageState extends State<SellerPerformancePage> {
  DateTime _startDate = DateTime(DateTime.now().year, DateTime.now().month, 1);
  DateTime _endDate = DateTime.now();
  final FirestoreService _service = FirestoreService();

  Future<void> _selectDateRange(BuildContext context) async {
    final DateTimeRange? picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      initialDateRange: DateTimeRange(start: _startDate, end: _endDate),
    );
    if (picked != null) {
      setState(() {
        _startDate = picked.start;
        _endDate = picked.end;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final endQueryDate = DateTime(_endDate.year, _endDate.month, _endDate.day, 23, 59, 59);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.get('sellerPerformance'))),
      body: Column(
        children: [
          // Filtro de Fechas
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Card(
              child: ListTile(
                leading: const Icon(Icons.date_range, color: Colors.indigo),
                title: Text(
                  '${dateFormat.format(_startDate)} - ${dateFormat.format(_endDate)}',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                trailing: const Icon(Icons.arrow_drop_down),
                onTap: () => _selectDateRange(context),
              ),
            ),
          ),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: _service.getUsers(widget.businessId),
              builder: (context, userSnapshot) {
                if (!userSnapshot.hasData) return const Center(child: CircularProgressIndicator());
                
                final usersDoc = userSnapshot.data!.docs;
                final userMap = <String, String>{};
                for (var doc in usersDoc) {
                    final data = doc.data() as Map<String, dynamic>;
                    userMap[doc.id] = data['name'] ?? 'Desconocido';
                }

                return StreamBuilder<QuerySnapshot>(
                  stream: _service.getSales(widget.businessId, startDate: _startDate, endDate: endQueryDate),
                  builder: (context, salesSnapshot) {
                    if (salesSnapshot.hasError) return Center(child: Text('Error: ${salesSnapshot.error}'));
                    if (salesSnapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());

                    final sales = salesSnapshot.data!.docs;
                    final Map<String, Map<String, dynamic>> sellerStats = {};

                    for (var saleDoc in sales) {
                       final data = saleDoc.data() as Map<String, dynamic>;
                       // Intentamos obtener el ID del vendedor (userId o sellerId)
                       final userId = data['userId'] ?? data['sellerId'] ?? 'unknown';
                       final total = (data['totalAmount'] as num).toDouble();
                       
                       if (!sellerStats.containsKey(userId)) {
                         sellerStats[userId] = {
                           'name': userMap[userId] ?? 'Usuario Eliminado',
                           'count': 0,
                           'total': 0.0
                         };
                       }
                       sellerStats[userId]!['count'] += 1;
                       sellerStats[userId]!['total'] += total;
                    }

                    final statsList = sellerStats.values.toList();
                    statsList.sort((a, b) => b['total'].compareTo(a['total']));

                    if (statsList.isEmpty) return Center(child: Text(l10n.get('noSalesInPeriod')));

                    return ListView.builder(
                      itemCount: statsList.length,
                      itemBuilder: (context, index) {
                        final stat = statsList[index];
                        return ListTile(
                          leading: CircleAvatar(
                            backgroundColor: index == 0 ? Colors.amber : Colors.indigo.shade100,
                            foregroundColor: index == 0 ? Colors.white : Colors.indigo.shade900,
                            child: Text('${index + 1}'),
                          ),
                          title: Text(stat['name']),
                          subtitle: Text('${stat['count']} ${l10n.get('salesCountLabel')}'),
                          trailing: Text(
                            '\$${currencyFormat.format(stat['total']).replaceAll('\$', '').trim()}',
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                          ),
                        );
                      },
                    );
                  }
                );
              }
            ),
          ),
        ],
      ),
      bottomNavigationBar: SellerBottomNavigationBar(
        user: widget.user,
        businessId: widget.businessId,
        sellerId: widget.user.uid == widget.businessId ? null : widget.user.uid,
        currentIndex: 0, // General
        allowSamePageNavigation: true,
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// 8. INFORME DE FLUJO DE CAJA (Cash Flow)
// -----------------------------------------------------------------------------
class CashFlowReportPage extends StatefulWidget {
  final String businessId;
  final String? sellerId;
  final User user;

  const CashFlowReportPage({super.key, required this.businessId, this.sellerId, required this.user});

  @override
  State<CashFlowReportPage> createState() => _CashFlowReportPageState();
}

class _CashFlowReportPageState extends State<CashFlowReportPage> {
  DateTime _startDate = DateTime(DateTime.now().year, DateTime.now().month, 1);
  DateTime _endDate = DateTime.now();
  final FirestoreService _service = FirestoreService();
  String? _filterSellerId;

  Future<void> _selectDateRange(BuildContext context) async {
    final DateTimeRange? picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      initialDateRange: DateTimeRange(start: _startDate, end: _endDate),
    );
    if (picked != null) {
      setState(() {
        _startDate = picked.start;
        _endDate = picked.end;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final endQueryDate = DateTime(_endDate.year, _endDate.month, _endDate.day, 23, 59, 59);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.get('cashFlow'))),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Card(
              child: ListTile(
                leading: const Icon(Icons.account_balance_wallet, color: Colors.green),
                title: Text('${dateFormat.format(_startDate)} - ${dateFormat.format(_endDate)}'),
                trailing: const Icon(Icons.date_range),
                onTap: () => _selectDateRange(context),
              ),
            ),
          ),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: _service.getPayments(widget.businessId, sellerId: widget.sellerId ?? _filterSellerId, startDate: _startDate, endDate: endQueryDate),
              builder: (context, snapshot) {
                if (snapshot.hasError) return Center(child: Text('Error: ${snapshot.error}'));
                if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());

                final payments = snapshot.data!.docs;
                double totalCash = 0;
                double totalBank = 0;
                Map<String, double> dailyTotals = {};

                for (var doc in payments) {
                  final data = doc.data() as Map<String, dynamic>;
                  final amount = (data['amount'] as num?)?.toDouble() ?? 0.0;
                  final type = data['payment_type'] ?? 'Efectivo';
                  final date = (data['date'] as Timestamp?)?.toDate() ?? DateTime.now();
                  final dateKey = DateFormat('yyyy-MM-dd').format(date);

                  if (type == 'Efectivo') {
                    totalCash += amount;
                  } else {
                    totalBank += amount;
                  }
                  dailyTotals[dateKey] = (dailyTotals[dateKey] ?? 0) + amount;
                }

                final totalIncome = totalCash + totalBank;

                return ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Row(
                      children: [
                        Expanded(child: _CashFlowStatCard(title: l10n.get('total'), value: totalIncome, color: Colors.blue, icon: Icons.account_balance)),
                        const SizedBox(width: 8),
                        Expanded(child: _CashFlowStatCard(title: l10n.get('cash'), value: totalCash, color: Colors.green, icon: Icons.payments)),
                        const SizedBox(width: 8),
                        Expanded(child: _CashFlowStatCard(title: l10n.get('bank'), value: totalBank, color: Colors.orange, icon: Icons.credit_card)),
                      ],
                    ),
                    const SizedBox(height: 24),
                    Text(l10n.get('salesVsPaymentsMonthly'), style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: 16),
                    _buildChart(dailyTotals, l10n),
                    const SizedBox(height: 24),
                    Text(l10n.get('payments'), style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: 8),
                    ...payments.map((p) {
                      final data = p.data() as Map<String, dynamic>;
                      return ListTile(
                        leading: Icon(
                          data['payment_type'] == 'Efectivo' ? Icons.payments : Icons.credit_card,
                          color: data['payment_type'] == 'Efectivo' ? Colors.green : Colors.orange,
                        ),
                        title: Text(data['customerName'] ?? 'N/A'),
                        subtitle: Text(dateTimeFormat.format((data['date'] as Timestamp).toDate())),
                        trailing: Text(
                          currencyFormat.format(data['amount']),
                          style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.green),
                        ),
                      );
                    }),
                  ],
                );
              },
            ),
          ),
        ],
      ),
      bottomNavigationBar: SellerBottomNavigationBar(
        user: widget.user,
        businessId: widget.businessId,
        sellerId: widget.sellerId ?? (widget.user.uid == widget.businessId ? null : widget.user.uid),
        currentIndex: 0, 
        allowSamePageNavigation: true,
      ),
    );
  }

  Widget _buildChart(Map<String, double> dailyTotals, AppLocalizations l10n) {
    if (dailyTotals.isEmpty) return SizedBox(height: 150, child: Center(child: Text(l10n.get('noMovements'))));
    final sortedKeys = dailyTotals.keys.toList()..sort();
    final spots = sortedKeys.asMap().entries.map((e) => FlSpot(e.key.toDouble(), dailyTotals[e.value]!)).toList();
    return SizedBox(height: 180, child: LineChart(LineChartData(gridData: const FlGridData(show: false), titlesData: const FlTitlesData(show: false), borderData: FlBorderData(show: false), lineBarsData: [LineChartBarData(spots: spots, isCurved: true, color: Colors.green, barWidth: 3, dotData: const FlDotData(show: true), belowBarData: BarAreaData(show: true, color: Colors.green.withValues(alpha: 0.1)))])));
  }
}

class _CashFlowStatCard extends StatelessWidget {
  final String title;
  final double value;
  final Color color;
  final IconData icon;
  const _CashFlowStatCard({required this.title, required this.value, required this.color, required this.icon});
  @override
  Widget build(BuildContext context) {
    return Card(elevation: 2, child: Padding(padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8), child: Column(children: [Icon(icon, color: color, size: 20), const SizedBox(height: 4), Text(title, style: const TextStyle(fontSize: 12, color: Colors.grey)), const SizedBox(height: 4), FittedBox(child: Text(currencyFormat.format(value), style: TextStyle(fontWeight: FontWeight.bold, color: color, fontSize: 14)))])));
  }
}

// -----------------------------------------------------------------------------
// 9. INFORME COMBINADO DE VENTAS Y PAGOS
// -----------------------------------------------------------------------------
class SalesAndPaymentsReportPage extends StatefulWidget {
  final String businessId;
  final String? sellerId;
  final User user;

  const SalesAndPaymentsReportPage({super.key, required this.businessId, this.sellerId, required this.user});

  @override
  State<SalesAndPaymentsReportPage> createState() => _SalesAndPaymentsReportPageState();
}

class _SalesAndPaymentsReportPageState extends State<SalesAndPaymentsReportPage> {
  DateTime _startDate = DateTime(DateTime.now().year, 1, 1);
  DateTime _endDate = DateTime.now();
  final FirestoreService _service = FirestoreService();
  String? _filterSellerId;
  String? _filterCustomerId;

  Future<void> _showCustomerPicker() async {
    final result = await showDialog<Map<String, dynamic>?>(
      context: context,
      builder: (context) => CustomerSelectionDialog(
        businessId: widget.businessId, 
        sellerId: widget.sellerId ?? _filterSellerId
      ),
    );
    if (result != null) {
      setState(() {
        _filterCustomerId = result['id'];
      });
    }
  }

  Future<void> _selectDateRange(BuildContext context) async {
    final DateTimeRange? picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      initialDateRange: DateTimeRange(start: _startDate, end: _endDate),
    );
    if (picked != null) {
      setState(() {
        _startDate = picked.start;
        _endDate = picked.end;
      });
    }
  }

  Future<void> _printReport() async {
    final l10n = AppLocalizations.of(context);
    final endQueryDate = DateTime(_endDate.year, _endDate.month, _endDate.day, 23, 59, 59);

    // Indicador de carga
    showDialog(context: context, barrierDismissible: false, builder: (c) => const Center(child: CircularProgressIndicator()));

    try {
      final salesSnap = await _service.getSales(
        widget.businessId, 
        sellerId: widget.sellerId ?? _filterSellerId, 
        startDate: _startDate, 
        endDate: endQueryDate,
        customerId: _filterCustomerId,
      ).first;
      
      final paymentsSnap = await _service.getPayments(
        widget.businessId, 
        sellerId: widget.sellerId ?? _filterSellerId, 
        startDate: _startDate, 
        endDate: endQueryDate,
        customerId: _filterCustomerId,
      ).first;

      if (mounted) {
        Navigator.pop(context); // Quitar loader
        await PdfGenerator.generateFinancialSummaryReport(
          l10n: l10n,
          businessId: widget.businessId,
          sales: salesSnap.docs,
          payments: paymentsSnap.docs,
          startDate: _startDate,
          endDate: _endDate,
        );
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final endQueryDate = DateTime(_endDate.year, _endDate.month, _endDate.day, 23, 59, 59);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.get('salesAndPaymentsReport')),
        actions: [
          IconButton(
            icon: const Icon(Icons.print_outlined),
            onPressed: _printReport,
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
                  child: Card(
                    elevation: 2,
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                      leading: const Icon(Icons.date_range, color: Colors.green, size: 20),
                      title: Text(
                        '${dateFormat.format(_startDate)} - ${dateFormat.format(_endDate)}',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                      onTap: () => _selectDateRange(context),
                    ),
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.filter_list, color: _filterCustomerId != null ? Colors.blue : null),
                  onPressed: _showCustomerPicker,
                  tooltip: l10n.get('selectCustomer'),
                ),
              ],
            ),
          ),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: _service.getSales(widget.businessId, sellerId: widget.sellerId ?? _filterSellerId, startDate: _startDate, endDate: endQueryDate),
              builder: (context, salesSnap) {
                if (salesSnap.hasError) {
                  final error = salesSnap.error.toString();
                  if (error.contains('failed-precondition') || error.contains('index')) {
                    return _buildIndexErrorWidget(error);
                  }
                  return Center(child: Text(l10n.get('error')));
                }

                return StreamBuilder<QuerySnapshot>(
                  stream: _service.getPayments(widget.businessId, sellerId: widget.sellerId ?? _filterSellerId, startDate: _startDate, endDate: endQueryDate),
                  builder: (context, paymentsSnap) {
                    if (paymentsSnap.hasError) {
                      final error = paymentsSnap.error.toString();
                      if (error.contains('failed-precondition') || error.contains('index')) {
                        return _buildIndexErrorWidget(error);
                      }
                      return Center(child: Text(l10n.get('error')));
                    }

                    if (!salesSnap.hasData || !paymentsSnap.hasData) return const Center(child: CircularProgressIndicator());

                    // Filtrado por cliente en memoria
                    final allSales = salesSnap.data!.docs;
                    final allPayments = paymentsSnap.data!.docs;

                    final sales = _filterCustomerId == null 
                        ? allSales 
                        : allSales.where((doc) => (doc.data() as Map<String, dynamic>)['customerId'] == _filterCustomerId).toList();
                    
                    final payments = _filterCustomerId == null 
                        ? allPayments 
                        : allPayments.where((doc) => (doc.data() as Map<String, dynamic>)['customerId'] == _filterCustomerId).toList();

                    double totalSales = 0;
                    double totalPayments = 0;

                    final List<Map<String, dynamic>> combinedList = [];

                    // Mapeo rápido para obtener el número de venta por ID
                    final Map<String, String> saleNumMap = {
                      for (var doc in sales) doc.id: (doc.data() as Map<String, dynamic>)['sale_number']?.toString() ?? ''
                    };

                    for (var doc in sales) {
                      final data = doc.data() as Map<String, dynamic>;
                      final amount = (data['totalAmount'] as num).toDouble();
                      totalSales += amount;
                      combinedList.add({
                        'date': (data['saleDate'] as Timestamp).toDate(),
                        'title': (data['customerName'] as String? ?? 'CLIENTE FINAL').toUpperCase(),
                        'amount': amount,
                        'isSale': true,
                        'type': l10n.get('sales'),
                        'saleNumber': data['sale_number']?.toString() ?? '',
                      });
                    }

                    for (var doc in payments) {
                      final data = doc.data() as Map<String, dynamic>;
                      final amount = (data['amount'] as num).toDouble();
                      totalPayments += amount;
                      combinedList.add({
                        'date': (data['date'] as Timestamp?)?.toDate() ?? DateTime.now(),
                        'title': (data['customerName'] as String? ?? 'CLIENTE FINAL').toUpperCase(),
                        'amount': amount,
                        'isSale': false,
                        'type': data['payment_type'] ?? l10n.get('payments'),
                        'saleNumber': saleNumMap[data['saleId']] ?? data['sale_number']?.toString() ?? '',
                      });
                    }

                    combinedList.sort((a, b) => b['date'].compareTo(a['date']));

                    return Column(
                      children: [
                        // KPIs
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          child: Row(
                            children: [
                              Expanded(
                                child: _SummaryMiniCard(
                                  title: l10n.get('totalSales'),
                                  value: totalSales,
                                  color: Colors.blue,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: _SummaryMiniCard(
                                  title: l10n.get('totalPayments'),
                                  value: totalPayments,
                                  color: Colors.green,
                                ),
                              ),
                            ],
                          ),
                        ),
                        // Encabezados de Columna
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                          child: Row(
                            children: [
                              Expanded(flex: 2, child: Text(l10n.get('date'), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11))),
                              Expanded(flex: 1, child: const Text('ID', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11))),
                              Expanded(flex: 3, child: Text(l10n.get('customerLabel'), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11))),
                              Expanded(flex: 2, child: Text(l10n.get('sales'), textAlign: TextAlign.right, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11))),
                              Expanded(flex: 2, child: Text(l10n.get('payments'), textAlign: TextAlign.right, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11))),
                            ],
                          ),
                        ),
                        const Divider(),
                        Expanded(
                          child: ListView.builder(
                            itemCount: combinedList.length,
                            itemBuilder: (context, index) {
                              final item = combinedList[index];
                              final isSale = item['isSale'] as bool;
                              return Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                                child: Row(
                                  children: [
                                    Expanded(flex: 2, child: Text(DateFormat('dd/MM/yy').format(item['date'] as DateTime), style: const TextStyle(fontSize: 10))),
                                    Expanded(flex: 1, child: Text(item['saleNumber'].toString(), style: const TextStyle(fontSize: 10))),
                                    Expanded(
                                      flex: 3, 
                                      child: Text(
                                        item['title'], 
                                        style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold), 
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    Expanded(
                                      flex: 2, 
                                      child: Text(isSale ? currencyFormat.format(item['amount']) : '', textAlign: TextAlign.right, style: TextStyle(fontSize: 10, color: Colors.blue.shade700)),
                                    ),
                                    Expanded(
                                      flex: 2, 
                                      child: Text(!isSale ? currencyFormat.format(item['amount']) : '', textAlign: TextAlign.right, style: TextStyle(fontSize: 10, color: Colors.green.shade700)),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildIndexErrorWidget(String error) {
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
}

class _SummaryMiniCard extends StatelessWidget {
  final String title;
  final double value;
  final Color color;
  const _SummaryMiniCard({required this.title, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          children: [
            Text(title, style: const TextStyle(fontSize: 11, color: Colors.grey)),
            const SizedBox(height: 4),
            FittedBox(child: Text(currencyFormat.format(value), style: TextStyle(fontWeight: FontWeight.bold, color: color, fontSize: 16))),
          ],
        ),
      ),
    );
  }
}