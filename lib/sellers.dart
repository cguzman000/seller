import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'app_localizations.dart';
import 'firestore_service.dart';

class SellersPage extends StatefulWidget {
  final User user; // El usuario administrador
  final String businessId;
  const SellersPage({super.key, required this.user, required this.businessId, required String role, String? sellerId});

  @override
  State<SellersPage> createState() => _SellersPageState();
}

class _SellersPageState extends State<SellersPage> {
  final FirestoreService _firestoreService = FirestoreService();
  final TextEditingController _searchController = TextEditingController();
  String _searchTerm = '';

  @override
  void initState() {
    super.initState();
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

  void _showSellerDialog({DocumentSnapshot? seller}) {
    final isEditing = seller != null;
    final Map<String, dynamic>? data = isEditing ? (seller.data() as Map<String, dynamic>) : null;
    final nameController = TextEditingController(text: data?['name'] ?? '');
    final emailController = TextEditingController(text: data?['email'] ?? '');
    final phoneController = TextEditingController(text: data?['phone'] ?? '');
    final formKey = GlobalKey<FormState>();
    final l10n = AppLocalizations.of(context);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(isEditing ? l10n.get('editSeller') : l10n.get('newSeller')),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: nameController,
                decoration: InputDecoration(labelText: l10n.get('name')),
                validator: (v) => v!.isEmpty ? l10n.get('required') : null,
                textCapitalization: TextCapitalization.words,
              ),
              TextFormField(
                controller: emailController,
                decoration: InputDecoration(labelText: l10n.get('emailHint')),
                validator: (v) => v!.isEmpty || !v.contains('@') ? l10n.get('invalidEmail') : null,
                keyboardType: TextInputType.emailAddress,
                // Si estamos editando, quizás no queramos permitir cambiar el email fácilmente
                // o advertir que esto cambia el acceso.
              ),
              TextFormField(
                controller: phoneController,
                decoration: InputDecoration(labelText: l10n.get('phone')),
                keyboardType: TextInputType.phone,
              ),
              const SizedBox(height: 10),
              Text(
                l10n.get('sellerAccessInfo'),
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text(l10n.get('cancel'))),
          ElevatedButton(
            onPressed: () async {
              if (formKey.currentState!.validate()) {
                final navigator = Navigator.of(context);
                final messenger = ScaffoldMessenger.of(context);
                try {
                  if (isEditing) {
                    await _firestoreService.updateUser(
                      seller.id,
                      nameController.text,
                      emailController.text,
                      'seller', // El rol siempre es 'seller' en esta pantalla
                      phone: phoneController.text,
                    );
                    messenger.showSnackBar(SnackBar(content: Text(l10n.get('sellerUpdated'))));
                  } else {
                    await _firestoreService.addUser(
                      widget.businessId,
                      nameController.text,
                      emailController.text,
                      'seller',
                      phone: phoneController.text,
                    );
                    messenger.showSnackBar(SnackBar(content: Text(l10n.get('sellerAdded'))));
                  }
                  navigator.pop();
                } catch (e) {
                  messenger.showSnackBar(SnackBar(content: Text('${l10n.get('error')} $e')));
                }
              }
            },
            child: Text(l10n.get('save')),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.get('manageSellers'))),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                labelText: l10n.get('searchSellerHint'),
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchTerm.isNotEmpty ? IconButton(icon: const Icon(Icons.clear), onPressed: () => _searchController.clear()) : null,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12.0)),
              ),
            ),
          ),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: _firestoreService.getUsers(widget.businessId, role: 'seller'),
              builder: (context, snapshot) {
                if (snapshot.hasError) return Center(child: Text('Error: ${snapshot.error}'));
                if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());

                final docs = snapshot.data!.docs.where((doc) {
                  if (_searchTerm.isEmpty) return true;
                  final data = doc.data() as Map<String, dynamic>;
                  final name = (data['name'] ?? '').toString().toLowerCase();
                  final email = (data['email'] ?? '').toString().toLowerCase();
                  return name.contains(_searchTerm.toLowerCase()) || email.contains(_searchTerm.toLowerCase());
                }).toList();

                if (docs.isEmpty) {
                  return Center(child: Text(l10n.get('noSellersFound')));
                }

                return ListView.builder(
                  itemCount: docs.length,
                  itemBuilder: (context, index) {
                    final doc = docs[index];
                    final data = doc.data() as Map<String, dynamic>;
                    return Dismissible(
                      key: Key(doc.id),
                      direction: DismissDirection.endToStart,
                      background: Container(
                        color: Colors.red,
                        alignment: Alignment.centerRight,
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: const Icon(Icons.delete, color: Colors.white),
                      ),
                      confirmDismiss: (direction) async {
                        // Verificar clientes antes de borrar
                        final customersSnapshot = await _firestoreService.getCustomersOnce(widget.businessId, sellerId: doc.id);
                        final customerCount = customersSnapshot.docs.length;

                        if (!context.mounted) return false;

                        return await showDialog<bool>(
                          context: context,
                          builder: (context) => AlertDialog(
                            title: Text(l10n.get('deleteSeller')),
                            content: Text(customerCount > 0
                                ? l10n.get('deleteSellerConfirmation').replaceFirst('{customerCount}', customerCount.toString())
                                : l10n.get('deleteSellerConfirmationSimple')),
                            actions: [
                              TextButton(onPressed: () => Navigator.pop(context, false), child: Text(l10n.get('cancel'))),
                              TextButton(onPressed: () => Navigator.pop(context, true), child: Text(l10n.get('delete'), style: const TextStyle(color: Colors.red))),
                            ],
                          ),
                        ) ?? false;
                      },
                      onDismissed: (direction) async {
                        await _firestoreService.reassignSellerCustomersToAdmin(doc.id);
                        await _firestoreService.deleteUser(doc.id);
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l10n.get('sellerDeleted'))));
                        }
                      },
                      child: ListTile(
                        leading: CircleAvatar(child: Text(data['name'] != null && data['name'].isNotEmpty ? data['name'][0].toUpperCase() : '...')),
                        title: Text(data['name'] ?? l10n.get('noName')),
                        subtitle: Text(data['email'] ?? l10n.get('noEmail')),
                        onTap: () => _showSellerDialog(seller: doc),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(onPressed: () => _showSellerDialog(), child: const Icon(Icons.add)),
    );
  }
}