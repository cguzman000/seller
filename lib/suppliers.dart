import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'firestore_service.dart';
import 'app_localizations.dart';
import 'main.dart'; // Importar para usar SellerBottomNavigationBar

class SuppliersPage extends StatefulWidget {
  final User user;
  final String businessId;

  const SuppliersPage({super.key, required this.user, required this.businessId});

  @override
  State<SuppliersPage> createState() => _SuppliersPageState();
}

class _SuppliersPageState extends State<SuppliersPage> {
  final FirestoreService _firestoreService = FirestoreService();
  final TextEditingController _searchController = TextEditingController();
  String _searchTerm = '';
  Stream<QuerySnapshot>? _suppliersStream;

  @override
  void initState() {
    super.initState();
    _suppliersStream = _firestoreService.getSuppliers(widget.businessId);
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

  void _showSupplierDialog({DocumentSnapshot? supplier}) {
    final formKey = GlobalKey<FormState>();
    final isEditing = supplier != null;
    final data = isEditing ? supplier.data() as Map<String, dynamic> : <String, dynamic>{};
    
    final nameController = TextEditingController(text: data['name'] ?? '');
    final contactController = TextEditingController(text: data['contact'] ?? '');
    final phoneController = TextEditingController(text: data['phone'] ?? '');
    final emailController = TextEditingController(text: data['email'] ?? '');
    final cityController = TextEditingController(text: data['city'] ?? '');

    showDialog(
      context: context,
      builder: (context) {
        final l10n = AppLocalizations.of(context);
        return AlertDialog(
          title: Text(isEditing ? l10n.get('editSupplier') : l10n.get('addSupplier')),
          content: Form(
            key: formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(controller: nameController, decoration: InputDecoration(labelText: l10n.get('name')), validator: (v) => v!.isEmpty ? l10n.get('required') : null, textCapitalization: TextCapitalization.characters),
                  TextFormField(controller: contactController, decoration: InputDecoration(labelText: l10n.get('contactPerson')), textCapitalization: TextCapitalization.characters),
                  TextFormField(controller: phoneController, decoration: InputDecoration(labelText: l10n.get('phone')), keyboardType: TextInputType.phone),
                  TextFormField(controller: emailController, decoration: InputDecoration(labelText: l10n.get('email')), keyboardType: TextInputType.emailAddress),
                  TextFormField(controller: cityController, decoration: InputDecoration(labelText: l10n.get('city')), textCapitalization: TextCapitalization.characters),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(l10n.get('cancel'))),
            ElevatedButton(
              onPressed: () async {
                if (formKey.currentState!.validate()) {
                  if (isEditing) {
                    await _firestoreService.updateSupplier(supplier.id, nameController.text, contactController.text, phoneController.text, emailController.text, city: cityController.text);
                  } else {
                    await _firestoreService.addSupplier(widget.businessId, nameController.text, contactController.text, phoneController.text, emailController.text, city: cityController.text);
                  }
                if (context.mounted) Navigator.of(context).pop();
                }
              },
              child: Text(l10n.get('save')),
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
      appBar: AppBar(title: Text(l10n.get('suppliers'))),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                labelText: l10n.get('searchSupplierHint'),
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchTerm.isNotEmpty ? IconButton(icon: const Icon(Icons.clear), onPressed: () => _searchController.clear()) : null,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12.0)),
              ),
            ),
          ),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: _suppliersStream ?? _firestoreService.getSuppliers(widget.businessId),
              builder: (context, snapshot) {
                if (snapshot.hasError) return Center(child: Text('Error: ${snapshot.error}'));
                if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
                
                final docs = snapshot.data!.docs.where((doc) {
                  if (_searchTerm.isEmpty) return true;
                  final data = doc.data() as Map<String, dynamic>;
                  final name = (data['name'] ?? '').toString().toLowerCase();
                  return name.contains(_searchTerm.toLowerCase());
                }).toList();

                if (docs.isEmpty) return Center(child: Text(l10n.get('noSuppliersFound')));

                return ListView.separated(
                  itemCount: docs.length,
                  separatorBuilder: (context, index) => Divider(
                    height: 1,
                    thickness: 1,
                    color: Theme.of(context).dividerColor.withValues(alpha: 0.5),
                    indent: 16,
                    endIndent: 16,
                  ),
                  itemBuilder: (context, index) {
                    final doc = docs[index];
                    final data = doc.data() as Map<String, dynamic>;
                    return Dismissible(
                      key: Key(doc.id),
                      direction: DismissDirection.endToStart,
                      background: Container(color: Colors.red, alignment: Alignment.centerRight, padding: const EdgeInsets.symmetric(horizontal: 20), child: const Icon(Icons.delete, color: Colors.white)),
                      confirmDismiss: (direction) async {
                         return await showDialog<bool>(
                          context: context,
                          builder: (alertContext) => AlertDialog(
                            title: Text(l10n.get('confirmDelete')),
                            content: Text(l10n.get('confirmDeleteSupplier')),
                            actions: [
                              TextButton(onPressed: () => Navigator.of(alertContext).pop(false), child: Text(l10n.get('cancel'))),
                              TextButton(onPressed: () => Navigator.of(alertContext).pop(true), child: Text(l10n.get('delete'), style: const TextStyle(color: Colors.red))),
                            ],
                          ),
                        ) ?? false;
                      },
                      onDismissed: (direction) => _firestoreService.deleteSupplier(doc.id),
                      child: ListTile(
                        leading: const Icon(Icons.business),
                        title: Text(data['name'] ?? l10n.get('noName')),
                        subtitle: Text(data['contact'] ?? ''),
                        onTap: () => _showSupplierDialog(supplier: doc),
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
        onPressed: () => _showSupplierDialog(),
        tooltip: l10n.get('addSupplier'),
        child: const Icon(Icons.add),
      ),
      bottomNavigationBar: SellerBottomNavigationBar(
        user: widget.user,
        businessId: widget.businessId,
        sellerId: widget.user.uid == widget.businessId ? null : widget.user.uid,
        currentIndex: 6,
      ),
    );
  }
}