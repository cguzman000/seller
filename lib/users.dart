import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'firestore_service.dart';

class UsersPage extends StatefulWidget {
  final User user;

  const UsersPage({super.key, required this.user});

  @override
  State<UsersPage> createState() => _UsersPageState();
}

class _UsersPageState extends State<UsersPage> {
  final FirestoreService _firestoreService = FirestoreService();

  void _addUser(String name, String email, String role) async {
    final userId = widget.user.uid;
    await _firestoreService.addUser(userId, name, email, role);
  }

  void _updateUser(String docId, String name, String email, String role) async {
    await _firestoreService.updateUser(docId, name, email, role);
  }

  void _deleteUser(String userId) async {
    // Opcional: Mostrar un diálogo de confirmación antes de eliminar
    await _firestoreService.deleteUser(userId);
  }

  void _showEditUserDialog(DocumentSnapshot document) {
    Map<String, dynamic> data = document.data()! as Map<String, dynamic>;
    final String userId = document.id;

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Editar Usuario'),
          content: _UserForm(
            initialData: data,
            onSave: (name, email, role) {
              _updateUser(userId, name, email, role); // userId aquí es el ID del documento
              Navigator.of(context).pop();
            },
          ),
        );
      },
    );
  }

  void _showAddUserDialog() {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Añadir Usuario'),
          content: _UserForm(
            onSave: (name, email, role) {
              _addUser(name, email, role);
              Navigator.of(context).pop();
            },
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Usuarios'),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: _firestoreService.getUsers(widget.user.uid),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const Center(child: Text('Algo salió mal'));
          }
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.data!.docs.isEmpty) {
            return const Center(child: Text('No hay usuarios. ¡Añade uno!'));
          }

          return ListView(
            children: snapshot.data!.docs.map((DocumentSnapshot document) {
              Map<String, dynamic> data = document.data()! as Map<String, dynamic>;
              return ListTile(
                onTap: () => _showEditUserDialog(document),
                leading: const CircleAvatar(child: Icon(Icons.person_outline)),
                title: Text(data['name'] ?? 'Sin nombre'),
                subtitle: Text(data['role'] ?? 'Sin rol'),
                trailing: IconButton(
                  icon: const Icon(Icons.delete_outline, color: Colors.red),
                  onPressed: () => _deleteUser(document.id),
                ),
              );
            }).toList(),
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddUserDialog,
        tooltip: 'Añadir Usuario',
        child: const Icon(Icons.add),
      ),
    );
  }
}

class _UserForm extends StatefulWidget {
  final Map<String, dynamic>? initialData;
  final Function(String name, String email, String role) onSave;

  const _UserForm({this.initialData, required this.onSave});

  @override
  __UserFormState createState() => __UserFormState();
}

class __UserFormState extends State<_UserForm> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameController;
  late TextEditingController _emailController;
  late TextEditingController _roleController;

  @override
  void initState() {
    super.initState();
    final data = widget.initialData;

    _nameController = TextEditingController(text: data?['name'] ?? '');
    _emailController = TextEditingController(text: data?['email'] ?? '');
    _roleController = TextEditingController(text: data?['role'] ?? 'user');
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _roleController.dispose();
    super.dispose();
  }

  void _handleSave() {
    if (_formKey.currentState!.validate()) {
      widget.onSave(
        _nameController.text,
        _emailController.text,
        _roleController.text,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: _nameController,
              decoration: const InputDecoration(labelText: 'Nombre'),
              validator: (value) => (value?.isEmpty ?? true) ? 'Este campo es requerido' : null,
            ),
            TextFormField(
              controller: _emailController,
              decoration: const InputDecoration(labelText: 'Email'),
              keyboardType: TextInputType.emailAddress,
              validator: (value) => (value?.isEmpty ?? true) ? 'Este campo es requerido' : null,
            ),
            TextFormField(
              controller: _roleController,
              decoration: const InputDecoration(labelText: 'Rol (ej: admin, user)'),
              validator: (value) => (value?.isEmpty ?? true) ? 'Este campo es requerido' : null,
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancelar'),
                ),
                ElevatedButton(
                  onPressed: _handleSave,
                  child: const Text('Guardar'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}