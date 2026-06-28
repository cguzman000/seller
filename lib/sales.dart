import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:seller/main.dart';
import 'app_localizations.dart';
import 'firestore_service.dart';
import 'add_sale_page.dart';

class SalesPage extends StatefulWidget {
  final User user;
  final String businessId;
  final String? sellerId;
  final String role;
  const SalesPage({super.key, required this.user, required this.businessId, this.sellerId, required this.role}); // sellerId puede ser null para admin

  @override
  State<SalesPage> createState() => _SalesPageState();
}

enum DateFilter { today, week, month, year, all, custom }

class _SalesPageState extends State<SalesPage> {
  final FirestoreService _firestoreService = FirestoreService();
  DateFilter _selectedFilter = DateFilter.all;
  DateTime? _startDate;
  DateTime? _endDate;
  String? _filterCustomerId;
  String? _filterCustomerName;
  String? _filterSellerId;
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _filterSellerId = widget.sellerId;
    _updateDateRange();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _updateDateRange() {
    final now = DateTime.now();
    switch (_selectedFilter) {
      case DateFilter.today:
        _startDate = DateTime(now.year, now.month, now.day);
        _endDate = DateTime(now.year, now.month, now.day, 23, 59, 59);
        break;
      case DateFilter.week:
        _startDate = DateTime(now.year, now.month, now.day).subtract(Duration(days: now.weekday - 1));
        _startDate = DateTime(_startDate!.year, _startDate!.month, _startDate!.day);
        _endDate = DateTime(now.year, now.month, now.day, 23, 59, 59).add(Duration(days: 7 - now.weekday));
        break;
      case DateFilter.month:
        _startDate = DateTime(now.year, now.month, 1);
        _endDate = DateTime(now.year, now.month + 1, 0, 23, 59, 59);
        break;
      case DateFilter.year:
        _startDate = DateTime(now.year, 1, 1);
        _endDate = DateTime(now.year, 12, 31, 23, 59, 59);
        break;
      case DateFilter.all:
        _startDate = null;
        _endDate = null;
        break;
      case DateFilter.custom:
        // No recalculamos nada, mantenemos las fechas seleccionadas manualmente
        break;
    }
    if (mounted) setState(() {});
  }

  Future<bool?> _showDeleteConfirmationDialog(String saleId) async {
    final l10n = AppLocalizations.of(context);
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text(l10n.get('confirmDelete')),
          content: SingleChildScrollView(
            child: ListBody(
              children: <Widget>[
                Text(l10n.get('confirmDeleteSale')),
              ],
            ),
          ),
          actions: <Widget>[
            TextButton(
              child: Text(l10n.get('cancel')),
              onPressed: () {
                Navigator.of(context).pop(false);
              },
            ),
            TextButton(
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: Text(l10n.get('delete')),
              onPressed: () async {
                // Captura el Navigator ANTES del await.
                final navigator = Navigator.of(context);
                try {
                  await _firestoreService.deleteSale(saleId);
                  if (mounted) {
                    navigator.pop(true);
                  }
                } catch (e) {
                  if (mounted) {
                    navigator.pop(false);
                  }
                }
              },
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
        title: Text(l10n.get('sales')),
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
        stream: _firestoreService.getSales(
          widget.businessId, 
          sellerId: _filterSellerId, 
          startDate: _startDate, 
          endDate: _endDate,
          customerId: _filterCustomerId,
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
                      const Text('Falta un índice en Firebase', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
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
            return Center(child: Text('Error: ${snapshot.error}'));
          }
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return Center(child: Text(l10n.get('noSalesRegistered')));
          }

          final salesDocs = snapshot.data!.docs;
          final groupedSales = <String, List<DocumentSnapshot>>{};

          final searchTerm = _searchController.text.toLowerCase().trim();

          for (final sale in salesDocs) {
            final saleData = sale.data() as Map<String, dynamic>;
            final customerName = (saleData['customerName'] as String? ?? '').toLowerCase();

            if (searchTerm.isNotEmpty && !customerName.contains(searchTerm)) continue;

            final saleDate = (saleData['saleDate'] as Timestamp?)?.toDate();
            if (saleDate != null) {
              final monthYear = DateFormat.yMMMM(l10n.locale.languageCode).format(saleDate);
              if (groupedSales[monthYear] == null) {
                groupedSales[monthYear] = [];
              }
              groupedSales[monthYear]!.add(sale);
            }
          }

          final sortedMonths = groupedSales.keys.toList();

          return ListView.builder(
            padding: const EdgeInsets.only(bottom: 80),
            itemCount: sortedMonths.length,
            itemBuilder: (context, index) {
              final month = sortedMonths[index];
              final salesForMonth = groupedSales[month]!;

              double monthTotal = 0.0;
              for (final sale in salesForMonth) {
                final saleData = sale.data() as Map<String, dynamic>;
                monthTotal += (saleData['totalAmount'] as num?)?.toDouble() ?? 0.0;
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
                          NumberFormat.currency(locale: 'es_CL', symbol: '\$', decimalDigits: 0, customPattern: '\u00A4 #,##0').format(monthTotal),
                          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: Theme.of(context).colorScheme.primary,
                              ),
                        ),
                      ],
                    ),
                  ),
                  ListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: salesForMonth.length,
                    itemBuilder: (context, saleIndex) {
                      final sale = salesForMonth[saleIndex];
                      final itemWidget = Dismissible(
                        key: Key(sale.id),
                        direction: DismissDirection.endToStart,
                        confirmDismiss: (direction) => _showDeleteConfirmationDialog(sale.id),
                        background: Container(
                            color: Colors.red,
                            alignment: Alignment.centerRight,
                            padding: const EdgeInsets.symmetric(horizontal: 20.0),
                            child: const Icon(Icons.delete, color: Colors.white)),
                        child: _SaleListItem(firestoreService: _firestoreService, user: widget.user, sale: sale, businessId: widget.businessId, role: widget.role, sellerId: widget.sellerId),
                      );

                      return Column(
                        children: [
                          itemWidget,
                          if (saleIndex < salesForMonth.length - 1) const Divider(height: 1, indent: 72, endIndent: 16),
                        ],
                      );
                    },
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
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => AddSalePage(
                user: widget.user,
                businessId: widget.businessId,
                role: widget.role,
                sellerId: _filterSellerId,
              ),
            ),
          );
        },
        tooltip: l10n.get('newSale'),
        label: Text(l10n.get('newSale')),
        icon: const Icon(Icons.shopping_cart_checkout),
      ),
      bottomNavigationBar: SellerBottomNavigationBar(
        user: widget.user,
        businessId: widget.businessId,
        role: widget.role,
        sellerId: widget.sellerId,
        currentIndex: 1, // Sales
      ),
    );
  }

  Widget _buildFilterButton(AppLocalizations l10n) {
    bool hasActiveFilters = _filterCustomerId != null || 
                           _filterSellerId != widget.sellerId || 
                           _selectedFilter != DateFilter.all;
    return PopupMenuButton<String>(
      icon: Icon(Icons.filter_list, color: hasActiveFilters ? Colors.orange : null),
      onSelected: _handleFilterSelection,
      itemBuilder: (context) => [
        PopupMenuItem(value: 'today', child: Text(l10n.get('filterToday'))),
        PopupMenuItem(value: 'week', child: Text(l10n.get('filterThisWeek'))),
        PopupMenuItem(value: 'month', child: Text(l10n.get('filterThisMonth'))),
        PopupMenuItem(value: 'year', child: Text(l10n.get('filterThisYear'))),
        PopupMenuItem(value: 'custom', child: Text(l10n.get('filterCustomEllipsis'))),
        const PopupMenuDivider(),
        PopupMenuItem(value: 'customer', child: Text(l10n.get('selectCustomer'))),
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
    switch (value) {
      case 'today':
        _selectedFilter = DateFilter.today;
        _updateDateRange();
        break;
      case 'week':
        _selectedFilter = DateFilter.week;
        _updateDateRange();
        break;
      case 'month':
        _selectedFilter = DateFilter.month;
        _updateDateRange();
        break;
      case 'year':
        _selectedFilter = DateFilter.year;
        _updateDateRange();
        break;
      case 'custom':
        _selectCustomRange();
        break;
      case 'customer':
        _showCustomerFilterDialog();
        break;
      case 'seller':
        _showSellerFilterDialog();
        break;
      case 'clear':
        setState(() {
          _selectedFilter = DateFilter.all;
          _updateDateRange();
          _filterCustomerId = null;
          _filterCustomerName = null;
          _searchController.clear();
          _filterSellerId = widget.user.uid == widget.businessId ? null : widget.sellerId;
        });
        break;
    }
  }

  Future<void> _selectCustomRange() async {
    final DateTimeRange? picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      initialDateRange: _startDate != null && _endDate != null
          ? DateTimeRange(start: _startDate!, end: _endDate!)
          : null,
    );
    if (picked != null) {
      setState(() {
        _selectedFilter = DateFilter.custom;
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

  void _showCustomerFilterDialog() async {
    final messenger = ScaffoldMessenger.of(context);
    final l10n = AppLocalizations.of(context);

    final result = await showDialog<DocumentSnapshot>(
      context: context,
      builder: (context) => _CustomerSearchDialog(
        businessId: widget.businessId,
        firestoreService: _firestoreService,
        sellerId: widget.sellerId,
      ),
    );

    if (result != null) {
      final data = result.data() as Map<String, dynamic>;
      setState(() {
        _filterCustomerId = result.id;
        _filterCustomerName = data['name'];
      });
    } else if (_filterCustomerId != null) {
      // Opción para limpiar filtro si ya había uno
      messenger.showSnackBar(
        SnackBar(
          content: Text('${l10n.get('filter')}: $_filterCustomerName'),
          action: SnackBarAction(
            label: l10n.get('filterAll'),
            onPressed: () => setState(() {
              _filterCustomerId = null;
              _filterCustomerName = null;
            }),
          ),
        ),
      );
    }
  }

}

class _SaleListItem extends StatelessWidget {
  final FirestoreService firestoreService;
  final DocumentSnapshot sale;
  final User user;
  final String businessId;
  final String role;
  final String? sellerId;

  const _SaleListItem({
    required this.firestoreService,
    required this.sale,
    required this.user,
    required this.businessId,
    required this.role,
    this.sellerId,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final saleData = sale.data() as Map<String, dynamic>;
    final saleDate = (saleData['saleDate'] as Timestamp?)?.toDate();
    final totalAmount = (saleData['totalAmount'] as num?)?.toDouble() ?? 0.0;

    return StreamBuilder<QuerySnapshot>(
      stream: firestoreService.getPaymentsForSale(sale.id),
      builder: (context, paymentSnapshot) {
        double paidAmount = 0.0;
        if (paymentSnapshot.hasData) {
          for (var doc in paymentSnapshot.data!.docs) {
            final data = doc.data() as Map<String, dynamic>;
            
            final saleIds = data['saleIds'];
            final bool isShared = saleIds is List && saleIds.length > 1;

            if (data.containsKey('allocations') && data['allocations'] is Map && (data['allocations'] as Map).containsKey(sale.id)) {
              paidAmount += ((data['allocations'] as Map)[sale.id] as num).toDouble();
            } else {
              if (!isShared) {
                paidAmount += (data['amount'] as num).toDouble();
              }
            }
          }
        }

        final balance = totalAmount - paidAmount;

        return InkWell(
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => AddSalePage(
                  user: user,
                  saleDocument: sale,
                  businessId: businessId,
                  role: role,
                  sellerId: sellerId,
                ),
              ),
            );
          },
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ListTile(
                leading: saleDate != null
                    ? SizedBox(
                        width: 50,
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              DateFormat.MMM(AppLocalizations.of(context).locale.languageCode).format(saleDate).toUpperCase(),
                              style: Theme.of(context).textTheme.bodyLarge,
                            ),
                            Text(
                              DateFormat.d(AppLocalizations.of(context).locale.languageCode).format(saleDate),
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                          ],
                        ),
                      )
                    : const SizedBox(width: 50),
                title: Text('${l10n.get('saleNumber')}${saleData['sale_number'] ?? ''}'),
                subtitle: Text((saleData['customerName'] as String? ?? l10n.get('noCustomer')).toUpperCase()),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (balance <= 0.01)
                      const Padding(
                        padding: EdgeInsets.only(right: 8.0),
                        child: Icon(Icons.check_circle, color: Colors.green),
                      ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          '\$${totalAmount.toStringAsFixed(0)}',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                        ),
                        Text(
                          '${l10n.get('paidLabel')}: \$${paidAmount.toStringAsFixed(0)}',
                          style: const TextStyle(color: Colors.green, fontSize: 12),
                        ),
                        if (balance > 0.01)
                          Text(
                            '${l10n.get('balanceLabel')}: \$${balance.toStringAsFixed(0)}',
                            style: const TextStyle(color: Colors.orange, fontWeight: FontWeight.bold, fontSize: 12),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              if (saleData['note'] != null && saleData['note'].toString().isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(left: 72.0, right: 16.0, bottom: 12.0),
                  child: Text(
                    saleData['note'],
                    style: const TextStyle(fontSize: 13, fontStyle: FontStyle.italic, color: Colors.grey),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
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
                stream: widget.firestoreService.getCustomers(widget.businessId, sellerId: widget.sellerId),
                builder: (context, snapshot) {
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
                        title: Text((data['name'] as String? ?? l10n.get('noName')).toUpperCase()),
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