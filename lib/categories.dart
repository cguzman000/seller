import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/services.dart';
import 'firestore_service.dart';
import 'app_localizations.dart';

class CategoriesPage extends StatefulWidget {
  final User user;
  final String businessId;

  const CategoriesPage({super.key, required this.user, required this.businessId});

  @override
  State<CategoriesPage> createState() => _CategoriesPageState();
}

class _CategoriesPageState extends State<CategoriesPage> {
  final FirestoreService _firestoreService = FirestoreService();
  final TextEditingController _categoryController = TextEditingController();

  void _showCategoryDialog({DocumentSnapshot? category}) {
    final l10n = AppLocalizations.of(context);
    final isEditing = category != null;
    _categoryController.text = isEditing ? category['name'] : '';
    final originalName = _categoryController.text;

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(isEditing ? l10n.get('editCategory') : l10n.get('addCategory')),
          content: TextField(
            controller: _categoryController,
            autofocus: true,
            textCapitalization: TextCapitalization.characters,
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z\s]'))],
            decoration: InputDecoration(labelText: l10n.get('categoryName')),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(l10n.get('cancel')),
            ),
            ElevatedButton(
              onPressed: () async {
                // Capturamos los objetos que dependen del context ANTES del 'await'.
                final navigator = Navigator.of(context);
                final messenger = ScaffoldMessenger.of(context);

                if (_categoryController.text.isNotEmpty && _categoryController.text != originalName) {
                  final isUnique = await _firestoreService.isCategoryNameUnique(
                    widget.businessId,
                    _categoryController.text,
                    currentCategoryId: category?.id,
                  );
                  if (!mounted) return; // Si el widget ya no está, no hacemos nada.
                  if (!isUnique) {
                    messenger.showSnackBar(
                      SnackBar(
                        content: Text(l10n.get('categoryExists')),
                        backgroundColor: Colors.red,
                      ),
                    );
                    return;
                  }

                  if (isEditing) {
                    _firestoreService.updateCategory(category.id, _categoryController.text);
                  } else {
                    _firestoreService.addCategory(widget.businessId, _categoryController.text);
                  }
                  navigator.pop();
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
      appBar: AppBar(
        title: Text(l10n.get('categories')),
      ),
      body: StreamBuilder<QuerySnapshot>( // StreamBuilder para los productos
        stream: _firestoreService.getProducts(widget.businessId),
        builder: (context, productSnapshot) {
          if (productSnapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (productSnapshot.hasError) {
            // Mostramos el error real para facilitar la depuración.
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Text('Error al cargar productos: ${productSnapshot.error}'),
              ));
          }

          // Creamos un mapa para contar productos por categoría
          final productCounts = <String, int>{};
          for (var productDoc in productSnapshot.data!.docs) {
            final categoryId = productDoc['categoryId'];
            if (categoryId != null) {
              productCounts[categoryId] = (productCounts[categoryId] ?? 0) + 1;
            }
          }

          return StreamBuilder<QuerySnapshot>( // StreamBuilder para las categorías
            stream: _firestoreService.getCategories(widget.businessId),
            builder: (context, categorySnapshot) {
              if (categorySnapshot.hasError) {
                return Center(child: Padding(padding: const EdgeInsets.all(16.0), child: Text('Algo salió mal: ${categorySnapshot.error}')));
              }
              if (categorySnapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (categorySnapshot.data!.docs.isEmpty) {
                return Center(child: Text(l10n.get('noCategories')));
              }

              final categories = categorySnapshot.data!.docs;

              return ListView.separated(
                itemCount: categories.length,
                separatorBuilder: (context, index) => const Divider(height: 1, indent: 16, endIndent: 16),
                itemBuilder: (context, index) {
                  final doc = categories[index];
                  final categoryId = doc.id;
                  final count = productCounts[categoryId] ?? 0;
                  final isAdmin = widget.user.uid == widget.businessId;

                  if (!isAdmin) {
                    return ListTile(
                      title: Text(doc['name'] as String),
                      subtitle: Text('${l10n.get('productsCount')}$count'),
                    );
                  }

                  return Dismissible(
                    key: Key(categoryId),
                    direction: DismissDirection.endToStart,
                    confirmDismiss: (direction) async {
                      if (count > 0) {
                        showDialog(
                          context: context,
                          builder: (context) => AlertDialog(
                            title: Text(l10n.get('error')),
                            content: Text(l10n.get('cannotDeleteCategory')),
                            actions: [TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(l10n.get('close')))],
                          ),
                        );
                        return false;
                      }
                      return await showDialog<bool>(
                        context: context,
                        builder: (context) => AlertDialog(
                          title: Text(l10n.get('delete')),
                          content: Text(l10n.get('confirmDeleteCategory')),
                          actions: [
                            TextButton(onPressed: () => Navigator.of(context).pop(false), child: Text(l10n.get('cancel'))),
                            TextButton(onPressed: () => Navigator.of(context).pop(true), child: Text(l10n.get('delete'), style: const TextStyle(color: Colors.red))),
                          ],
                        ),
                      ) ?? false;
                    },
                    onDismissed: (direction) async {
                      final scaffoldMessenger = ScaffoldMessenger.of(context);
                      try {
                        await _firestoreService.deleteCategory(categoryId);
                        scaffoldMessenger.showSnackBar(SnackBar(content: Text(l10n.get('categoryDeleted'))));
                      } catch (e) {
                        scaffoldMessenger.showSnackBar(SnackBar(content: Text('${l10n.get('errorDelete')}$e')));
                      }
                    },
                    background: Container(
                      color: Colors.red,
                      alignment: Alignment.centerRight,
                      padding: const EdgeInsets.symmetric(horizontal: 20.0),
                      child: const Icon(Icons.delete, color: Colors.white),
                    ),
                    child: ListTile(
                      title: Text(doc['name'] as String),
                      subtitle: Text('${l10n.get('productsCount')}$count'),
                      onTap: () => _showCategoryDialog(category: doc),
                    ),
                  );
                },
              );
            },
          );
        },
      ),
      floatingActionButton: widget.user.uid == widget.businessId
          ? FloatingActionButton(
              onPressed: () => _showCategoryDialog(),
              tooltip: l10n.get('addCategory'),
              child: const Icon(Icons.add),
            )
          : null,
    );
  }

  @override
  void dispose() {
    _categoryController.dispose();
    super.dispose();
  }
}