import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:io';
import 'package:flutter/foundation.dart';

class FirestoreService {
  // Obtener la instancia de Cloud Firestore
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseStorage _storage = FirebaseStorage.instance;

  /// Obtiene todos los perfiles disponibles para el usuario (Vendedor y/o Admin).
  Future<List<Map<String, dynamic>>> getUserProfiles(User user) async {
    List<Map<String, dynamic>> profiles = [];

    // 1. Buscar perfiles de Vendedor (por email)
    QuerySnapshot<Map<String, dynamic>> query = await _db.collection('users').where('email', isEqualTo: user.email).get();
    
    // Fallback minúsculas
    if (query.docs.isEmpty && user.email != null && user.email != user.email!.toLowerCase()) {
      final queryLower = await _db.collection('users').where('email', isEqualTo: user.email!.toLowerCase()).get();
      if (queryLower.docs.isNotEmpty) query = queryLower;
    }

    final sellerProfiles = await Future.wait(query.docs.map((doc) async {
      if (doc.id == user.uid) return null;

      final data = doc.data();
      String businessLabel = 'Negocio ${data['businessId']}';
      
      try {
        final settings = await _db.collection('company_settings').doc(data['businessId']).get();
        if (settings.exists && settings.data()?['company_name'] != null) {
          businessLabel = settings.data()!['company_name'];
        }
      } catch (e) {
        debugPrint("Error loading profile settings: $e");
      }

      return {
        'businessId': data['businessId'],
        'role': data['role'],
        'label': 'Vendedor en $businessLabel',
        'type': 'seller',
        'sellerId': doc.id,
      };
    }));

    profiles.addAll(sellerProfiles.whereType<Map<String, dynamic>>());

    // 2. Buscar perfil de Admin (por UID) - Esto representa "Su propio negocio"
    final adminDoc = await _db.collection('users').doc(user.uid).get();
    if (adminDoc.exists) {
      final data = adminDoc.data()!;

      String businessLabel = 'Mi Negocio';
      try {
        final settings = await _db.collection('company_settings').doc(data['businessId']).get();
        if (settings.exists && settings.data()!['company_name'] != null) {
          final name = settings.data()!['company_name'] as String;
          if (name.isNotEmpty) {
            businessLabel = name;
          }
        }
      } catch (_) {}

      profiles.add({
        'businessId': data['businessId'],
        'role': data['role'],
        'label': 'Mi Negocio ($businessLabel )',
        'type': 'admin',
        'sellerId': user.uid,
      });
    }

    return profiles;
  }

  /// Obtiene el nombre del vendedor registrado en la colección users del negocio actual.
  /// Esto evita usar el displayName de Google que podría ser "Admin" o incorrecto.
  Future<String?> getSellerName(String businessId, String email) async {
    var query = await _db.collection('users')
        .where('businessId', isEqualTo: businessId)
        .where('email', isEqualTo: email)
        .limit(1)
        .get();

    if (query.docs.isNotEmpty) return query.docs.first['name'] as String?;

    // Intento con minúsculas por si acaso
    if (email != email.toLowerCase()) {
      query = await _db.collection('users').where('businessId', isEqualTo: businessId).where('email', isEqualTo: email.toLowerCase()).limit(1).get();
      if (query.docs.isNotEmpty) return query.docs.first['name'] as String?;
    }
    return null;
  }

  /// Crea el perfil de administrador para el usuario actual (Abrir su propio negocio).
  Future<void> createOwnBusiness(User user) async {
    final batch = _db.batch();

    final userRef = _db.collection('users').doc(user.uid);
    batch.set(userRef, {
      'name': (user.displayName ?? 'Admin').toUpperCase(),
      'email': user.email,
      'role': 'admin',
      'businessId': user.uid, // El admin pertenece a su propio negocio
      'createdAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    // También creamos un documento de configuración inicial
    final settingsRef = _db.collection('company_settings').doc(user.uid);
    batch.set(settingsRef, {
      'is_initial_setup': true, // Bandera para la redirección
    });

    await batch.commit();
  }

  /// Añade un nuevo producto a la colección 'products'.
  Future<DocumentReference> addProduct(String userId, String name, String? description, String? barCode, double purchPrice, bool purchasePriceIncludesVat, double price, int stock, int safetyStock, int? unitsBox, String? imageUrl, String? categoryId, String? supplierId, bool state, {File? imageFile}) async {
    // Generamos la referencia primero para obtener el ID antes de guardar (necesario para el nombre de la imagen)
    DocumentReference ref = _db.collection('products').doc();
    
    String? finalImageUrl = imageUrl;

    // Si se proporciona un archivo, lo subimos y actualizamos la URL
    if (imageFile != null) {
      finalImageUrl = await uploadImage(imageFile, ref.id);
    }

    await ref.set({
      'categoryId': categoryId,
      'supplierId': supplierId,
      'name': name.trim().toUpperCase(),
      'description': description?.trim().toUpperCase(),
      'bar_code': barCode?.trim(),
      'purch_price': purchPrice,
      'purchase_price_includes_vat': purchasePriceIncludesVat,
      'price': price,
      'units_box': unitsBox,
      'stock': stock,
      'safety_stock': safetyStock,
      'createdAt': FieldValue.serverTimestamp(), // Añade la fecha de creación
      'imageUrl': finalImageUrl,
      'state': state,
      'userId': userId,
    });
    
    return ref;
  }

  /// Actualiza un producto existente en la colección 'products'.
  Future<void> updateProduct(String productId, String name, String? description, String? barCode, double purchPrice, bool purchasePriceIncludesVat, double price, int stock, int safetyStock, int? unitsBox, String? imageUrl, String? categoryId, String? supplierId, bool state, {File? imageFile}) async {
    String? finalImageUrl = imageUrl;

    if (imageFile != null) {
      finalImageUrl = await uploadImage(imageFile, productId);
    }

    return _db.collection('products').doc(productId).update({
      'categoryId': categoryId,
      'supplierId': supplierId,
      'name': name.trim().toUpperCase(),
      'description': description?.trim().toUpperCase(),
      'bar_code': barCode?.trim(),
      'purch_price': purchPrice,
      'purchase_price_includes_vat': purchasePriceIncludesVat,
      'price': price,
      'units_box': unitsBox,
      'stock': stock,
      'safety_stock': safetyStock,
      'imageUrl': finalImageUrl,
      'state': state,
      // Opcional: puedes añadir un campo 'updatedAt'
      // 'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Añade una nueva oferta a la colección 'offers'.
  Future<DocumentReference> addOffer(String userId, String productId, double quantity, double price, String name) {
    return _db.collection('offers').add({
      'userId': userId,
      'productId': productId,
      'quantity': quantity,
      'price': price,
      'name': name.trim(),
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  /// Obtiene un Stream de ofertas para un producto específico.
  Stream<QuerySnapshot> getOffers(String productId) {
    return _db.collection('offers').where('productId', isEqualTo: productId).orderBy('quantity', descending: false).snapshots();
  }

  /// Obtiene un Stream de todas las ofertas de un negocio.
  Stream<QuerySnapshot> getAllOffers(String userId) {
    return _db.collection('offers').where('userId', isEqualTo: userId).orderBy('createdAt', descending: true).snapshots();
    //return _db.collection('offers').where('userId', isEqualTo: userId).orderBy('name').snapshots();
  }
  
  /// Obtiene todas las ofertas de un negocio una sola vez (Future).
  Future<QuerySnapshot> getAllOffersOnce(String userId) {
    return _db.collection('offers').where('userId', isEqualTo: userId).get();
  }

  /// Actualiza una oferta existente.
  Future<void> updateOffer(String offerId, String productId, double quantity, double price, String name) {
    return _db.collection('offers').doc(offerId).update({
      'productId': productId,
      'quantity': quantity,
      'price': price,
      'name': name.trim(),
    });
  }

  /// Obtiene las ofertas de un producto una sola vez (Future).
  /// Nota: Requiere un índice compuesto en Firestore: userId ASC, productId ASC, quantity ASC.
  Future<QuerySnapshot> getOffersOnce(String productId, String businessId) {
    return _db.collection('offers')
        .where('userId', isEqualTo: businessId)
        .where('productId', isEqualTo: productId)
        .orderBy('quantity', descending: false)
        .get();
  }

  /// Obtiene los productos una sola vez (Future).
  Future<QuerySnapshot> getProductsOnce(String userId, {String? categoryId, String? supplierId}) {
    Query query = _db.collection('products').where('userId', isEqualTo: userId);
    if (categoryId != null && categoryId.isNotEmpty) {
      query = query.where('categoryId', isEqualTo: categoryId);
    }
    if (supplierId != null && supplierId.isNotEmpty) {
      query = query.where('supplierId', isEqualTo: supplierId);
    }
    return query.orderBy('createdAt', descending: true).get();
  }

  /// Elimina una oferta.
  Future<void> deleteOffer(String offerId) {
    return _db.collection('offers').doc(offerId).delete();
  }

  /// Actualiza solo el stock de un producto.
  Future<void> updateProductStock(String productId, int newStock) {
    return _db.collection('products').doc(productId).update({'stock': newStock});
  }

  /// Suma una cantidad al stock existente (puede ser negativa).
  Future<void> incrementProductStock(String productId, int amount) {
    return _db.collection('products').doc(productId).update({'stock': FieldValue.increment(amount)});
  }

  /// Sube el logo de una empresa a Firebase Storage y devuelve la URL de descarga.
  Future<String> uploadCompanyLogo(File imageFile, String businessId) async {
    // Primero, intenta borrar el logo existente para evitar archivos huérfanos.
    try {
      final existingSettings = await _db.collection('company_settings').doc(businessId).get();
      if (existingSettings.exists) {
        final data = existingSettings.data() as Map<String, dynamic>;
        final existingUrl = data['company_logo_url'] as String?;
        if (existingUrl != null && existingUrl.isNotEmpty) {
          final oldRef = _storage.refFromURL(existingUrl);
          await oldRef.delete();
        }
      }
    } on FirebaseException catch (e) {
      // Si la imagen antigua no se encuentra, no es un error crítico.
      if (e.code != 'object-not-found') {
        rethrow;
      }
    }
    try {
      // Crear una referencia a la ubicación donde se guardará la imagen
      final ref = _storage.ref().child('company_logos').child('$businessId.jpg');

      // Subir el archivo
      await ref.putFile(imageFile);

      // Obtener la URL de descarga
      return await ref.getDownloadURL();
    } catch (e) {
      rethrow;
    }
  }

  /// Elimina el logo de la empresa de Storage y de la configuración.
  Future<void> deleteCompanyLogo(String businessId) async {
    try {
      // 1. Obtener la URL actual para borrar el archivo
      final doc = await _db.collection('company_settings').doc(businessId).get();
      if (doc.exists) {
        final data = doc.data() as Map<String, dynamic>;
        final url = data['company_logo_url'] as String?;
        if (url != null && url.isNotEmpty) {
          try {
            await _storage.refFromURL(url).delete();
          } catch (_) {
            // Si falla el borrado del archivo (ej. no existe), continuamos para limpiar la BD.
          }
        }
      }
      // 2. Eliminar el campo de la base de datos
      await _db.collection('company_settings').doc(businessId).update({
        'company_logo_url': FieldValue.delete(),
      });
    } catch (e) {
      rethrow;
    }
  }

  /// Sube una imagen a Firebase Storage y devuelve la URL de descarga.
  Future<String> uploadImage(File imageFile, String productId) async {
    // Primero, intenta borrar la imagen existente para evitar archivos huérfanos.
    try {
      final existingDoc = await _db.collection('products').doc(productId).get();
      if (existingDoc.exists) {
        final data = existingDoc.data() as Map<String, dynamic>;
        final existingUrl = data['imageUrl'] as String?;
        if (existingUrl != null && existingUrl.isNotEmpty) {
          final oldRef = _storage.refFromURL(existingUrl);
          await oldRef.delete();
        }
      }
    } on FirebaseException catch (e) {
      // Si la imagen antigua no se encuentra, no es un error crítico.
      // Simplemente lo ignoramos y continuamos con la subida de la nueva.
      if (e.code != 'object-not-found') {
        rethrow; // Si es otro tipo de error, sí lo lanzamos.
      }
    }
    try {
      // Crear una referencia a la ubicación donde se guardará la imagen
      final ref = _storage.ref().child('product_images').child('$productId.jpg');

      // Subir el archivo
      await ref.putFile(imageFile);

      // Obtener la URL de descarga
      final downloadUrl = await ref.getDownloadURL();
      return downloadUrl;
    } catch (e) {
      // Manejar el error apropiadamente
      rethrow;
    }
  }

  /// Añade un nuevo cliente a la colección 'customers'.
  Future<DocumentReference> addCustomer(String userId, String name, String email, String phone, String address, String dni, String contact, String city, {String? sellerId, String? creatorName}) {
    return _db.collection('customers').add({
      'name': name.trim().toUpperCase(),
      'email': email.trim(),
      'phone': phone.trim(),
      'address': address.trim().toUpperCase(),
      'contact': contact.trim().toUpperCase(),
      'dni': dni.trim().toUpperCase(),
      'city': city.trim().toUpperCase(),
      'registeredAt': FieldValue.serverTimestamp(),
      'userId': userId,
      'sellerId': sellerId, // Quién creó el cliente (si es vendedor)
      'creatorName': creatorName,
    });
  }

  /// Añade una nueva venta a la colección 'sales'.
  ///
  /// [customerId] es el ID del documento del cliente.
  /// [items] es una lista de mapas, donde cada mapa representa un producto vendido.
  /// Ejemplo de un item: {'productId': 'xyz', 'quantity': 2, 'price': 99.99}
  Future<DocumentReference> addSale(String userId, int saleNumber, String customerId, String customerName, double totalAmount, List<Map<String, dynamic>> items, {String? sellerId, String? sellerName, String? note, DateTime? saleDate}) async {
    final WriteBatch batch = _db.batch();
    final DocumentReference saleRef = _db.collection('sales').doc();

    batch.set(saleRef, {
      'customerId': customerId,
      'customerName': customerName.trim().toUpperCase(),
      'totalAmount': totalAmount,
      'sale_number': saleNumber,
      'items': items,
      'saleDate': saleDate != null ? Timestamp.fromDate(saleDate) : FieldValue.serverTimestamp(),
      'userId': userId,
      'sellerId': sellerId, // Quién realizó la venta
      'sellerName': sellerName?.trim().toUpperCase(),
      'note': note?.trim(),
    });

    // Reducir stock de los productos
    for (var item in items) {
      final productRef = _db.collection('products').doc(item['productId']);
      batch.update(productRef, {'stock': FieldValue.increment(-item['quantity'])});
    }

    await batch.commit();
    return saleRef;
  }

  /// Actualiza una venta existente.
  Future<void> updateSale(String saleId, String customerId, String customerName, double totalAmount, List<Map<String, dynamic>> items, {String? note, DateTime? saleDate}) {
    final Map<String, dynamic> updates = {
      'customerId': customerId,
      'customerName': customerName.trim().toUpperCase(),
      'totalAmount': totalAmount,
      'items': items,
      'note': note?.trim(),
    };

    if (saleDate != null) {
      updates['saleDate'] = Timestamp.fromDate(saleDate);
    }

    return _db.collection('sales').doc(saleId).update(updates);
  }

  /// Obtiene el siguiente número de venta correlativo para un usuario.
  /// Utiliza una transacción para garantizar la atomicidad.
  Future<int> getNextSaleNumber(String userId) async {
    final counterRef = _db.collection('user_counters').doc(userId);

    return _db.runTransaction((transaction) async {
      final snapshot = await transaction.get(counterRef);

      int newSaleNumber;
      if (!snapshot.exists) {
        newSaleNumber = 1;
      } else {
        final data = snapshot.data() as Map<String, dynamic>;
        newSaleNumber = (data['last_sale_number'] as int) + 1;
      }

      transaction.set(counterRef, {'last_sale_number': newSaleNumber});
      return newSaleNumber;
    });
  }
  /// Añade un nuevo pago a la colección 'payments'.
  Future<void> addPayment(String userId, String saleId, double amount, String paymentType, {String? sellerId, String? sellerName, String? customerId, String? customerName}) {
    return _db.collection('payments').add({
      'userId': userId,
      'saleId': saleId,
      'amount': amount,
      'date': FieldValue.serverTimestamp(),
      'sellerId': sellerId,
      'sellerName': sellerName?.trim().toUpperCase(),
      'payment_type': paymentType.trim(),
      'customerId': customerId,
      'customerName': customerName?.trim().toUpperCase(),
    });
  }
  
  /// Añade un pago de un cliente y lo distribuye entre sus ventas pendientes.
  Future<void> addCustomerPayment(String userId, double totalPayment, List<DocumentSnapshot> pendingSales, String paymentType, String customerId, {String? sellerId, String? sellerName, String? customerName}) async {
    double remainingPayment = totalPayment;
    final Map<String, double> allocations = {};
    final List<String> saleIds = [];

    for (final saleDoc in pendingSales) {
      if (remainingPayment <= 0.01) break;

      final saleData = saleDoc.data() as Map<String, dynamic>;
      final saleTotal = (saleData['totalAmount'] as num?)?.toDouble() ?? 0.0;
      final paymentsSnapshot = await getPaymentsForSale(saleDoc.id).first;
      final paidAmount = paymentsSnapshot.docs.fold<double>(0.0, (total, doc) {
        final data = doc.data() as Map<String, dynamic>;
        
        final saleIds = data['saleIds'];
        final bool isShared = saleIds is List && saleIds.length > 1;

        if (data.containsKey('allocations') && data['allocations'] is Map && (data['allocations'] as Map).containsKey(saleDoc.id)) {
          return total + ((data['allocations'] as Map)[saleDoc.id] as num? ?? 0.0).toDouble();
        }
        return isShared ? total : total + (data['amount'] as num? ?? 0.0).toDouble();
      });
      final pendingOnSale = saleTotal - paidAmount;

      if (pendingOnSale > 0.01) {
        final amountToPay = remainingPayment < pendingOnSale ? remainingPayment : pendingOnSale;
        allocations[saleDoc.id] = double.parse(amountToPay.toStringAsFixed(2));
        saleIds.add(saleDoc.id);
        remainingPayment = double.parse((remainingPayment - amountToPay).toStringAsFixed(2));
      }
    }

    if (allocations.isNotEmpty) {
      // Calcular el total real pagado
      final actualTotal = allocations.values.fold(0.0, (a, b) => a + b);

      await _db.collection('payments').add({
        'userId': userId,
        'amount': actualTotal,
        'date': FieldValue.serverTimestamp(),
        'customerId': customerId,
        'customerName': customerName?.trim().toUpperCase(),
        'payment_type': paymentType.trim(),
        'sellerId': sellerId,
        'sellerName': sellerName?.trim().toUpperCase(),
        'saleIds': saleIds,
        'allocations': allocations,
        // Mantenemos saleId si es único para compatibilidad, o null si cubre varias ventas
        'saleId': saleIds.length == 1 ? saleIds.first : null,
      });
    }
  }

  /// Actualiza un pago existente.
  Future<void> updatePayment(String paymentId, double amount, {required String paymentType}) async {
    final docRef = _db.collection('payments').doc(paymentId);
    final snapshot = await docRef.get();

    if (!snapshot.exists) return;

    final data = snapshot.data() as Map<String, dynamic>;
    final Map<String, dynamic> updates = {
      'amount': amount,
      'payment_type': paymentType,
    };

    // Si el pago tiene un mapa de 'allocations' y solo está vinculado a una venta,
    // sincronizamos el monto para que se refleje en la deuda de esa venta específica.
    if (data.containsKey('allocations') && data['allocations'] is Map) {
      final allocations = Map<String, dynamic>.from(data['allocations']);
      if (allocations.length == 1) {
        allocations[allocations.keys.first] = amount;
        updates['allocations'] = allocations;
      }
    }

    return docRef.update(updates);
  }

  /// Actualiza un cliente existente en la colección 'customers'.
  Future<void> updateCustomer(String customerId, String name, String email, String phone, String address, String dni, String contact, String city, {String? sellerId, bool updateSeller = false}) async {
    final Map<String, dynamic> data = {
      'name': name.trim().toUpperCase(),
      'email': email.trim(),
      'phone': phone.trim(),
      'address': address.trim().toUpperCase(),
      'contact': contact.trim().toUpperCase(),
      'dni': dni.trim().toUpperCase(),
      'city': city.trim().toUpperCase(),
    };

    if (updateSeller) {
      data['sellerId'] = sellerId;
      // Si se reasigna el vendedor, actualizamos el 'creatorName' para que aparezca como si lo hubiera creado el nuevo vendedor.
      if (sellerId == null) {
        data['creatorName'] = 'Administrador';
      } else {
        try {
          final userDoc = await _db.collection('users').doc(sellerId).get();
          if (userDoc.exists) {
            data['creatorName'] = userDoc.data()?['name'] ?? 'Vendedor';
          }
        } catch (_) {
          // Si falla la obtención del nombre, mantenemos el anterior o no hacemos nada
        }
      }
    }

    return _db.collection('customers').doc(customerId).update(data);
  }

  /// Añade un nuevo usuario a la colección 'users'.
  Future<void> addUser(String businessId, String name, String email, String role, {String? phone}) {
    return _db.collection('users').add({
      'name': name.trim().toUpperCase(),
      'email': email.trim().toLowerCase(), // Guardar siempre en minúsculas
      'role': role,
      'phone': phone?.trim(),
      'createdAt': FieldValue.serverTimestamp(),
      'businessId': businessId, // ID del negocio al que pertenece
    });
  }

  /// Actualiza un usuario existente en la colección 'users'.
  Future<void> updateUser(String docId, String name, String email, String role, {String? phone}) {
    return _db.collection('users').doc(docId).update({
      'name': name.trim().toUpperCase(),
      'email': email.trim().toLowerCase(),
      'role': role,
      'phone': phone?.trim(),
    });
  }

  // --- Métodos para obtener datos ---

  /// Obtiene un Stream de todos los productos.
  Stream<QuerySnapshot> getProducts(String userId, {String? categoryId, String? supplierId, String? searchTerm}) {
    Query query = _db.collection('products').where('userId', isEqualTo: userId);

    // Si se proporciona un categoryId, filtramos por categoría.
    if (categoryId != null && categoryId.isNotEmpty) {
      query = query.where('categoryId', isEqualTo: categoryId);
    }
    
    // Si se proporciona un supplierId, filtramos por proveedor.
    if (supplierId != null && supplierId.isNotEmpty) {
      query = query.where('supplierId', isEqualTo: supplierId);
    }

    // Si se proporciona un término de búsqueda, filtramos por nombre.
    // La búsqueda por texto ahora se maneja en el lado del cliente para permitir búsquedas "contains".
    // Simplemente ordenamos por nombre para mantener un orden consistente.
    // Si no hay búsqueda, podemos ordenar por otro campo como la fecha de creación.
    // Ordenamos por 'createdAt' para asegurar que todos los productos se muestren,
    // incluso si no tienen el campo 'name_lowercase'.
    return query.orderBy('createdAt', descending: true).snapshots();
  }

  /// Obtiene productos específicos por sus IDs.
  Future<List<DocumentSnapshot>> getProductsByIds(String businessId, List<String> productIds) async {
    if (productIds.isEmpty) {
      return [];
    }

    final List<DocumentSnapshot> result = [];
    // whereIn tiene un límite de 30 elementos por consulta.
    for (var i = 0; i < productIds.length; i += 30) {
      final sublist = productIds.sublist(i, i + 30 > productIds.length ? productIds.length : i + 30);
      final snapshot = await _db
          .collection('products')
          .where('userId', isEqualTo: businessId)
          .where(FieldPath.documentId, whereIn: sublist)
          .get();
      result.addAll(snapshot.docs);
    }
    return result;
  }


  /// Obtiene un producto específico por su ID.
  Future<DocumentSnapshot> getProductById(String productId) {
    return _db.collection('products').doc(productId).get();
  }

  /// Obtiene un Stream de todas las categorías.
  Stream<QuerySnapshot> getCategories(String userId) {
    return _db.collection('categories').where('userId', isEqualTo: userId).orderBy('name').snapshots();
  }

  /// Obtiene un Stream de todas las ventas de un usuario.
  /// Si se proporciona [sellerId], filtra solo las ventas de ese vendedor.
  Stream<QuerySnapshot> getSales(String userId, {String? sellerId, DateTime? startDate, DateTime? endDate, String? customerId}) {
    Query query = _db
        .collection('sales')
        .where('userId', isEqualTo: userId);

    if (customerId != null && customerId.isNotEmpty) {
      query = query.where('customerId', isEqualTo: customerId);
    }

    // Si se filtra por un vendedor específico
    if (sellerId != null && sellerId != 'all' && sellerId.isNotEmpty) {
      if (sellerId == 'admin' || sellerId == 'null' || sellerId == userId || sellerId.length < 6) {
        // Filtro consistente para Ventas también
        query = query.where(Filter.or(
          Filter('sellerId', isEqualTo: userId),
          Filter('sellerId', isNull: true),
          Filter('sellerId', isEqualTo: ''),
        ));
      } else {
        query = query.where('sellerId', isEqualTo: sellerId);
      }
    }

    if (startDate != null) {
      query = query.where('saleDate', isGreaterThanOrEqualTo: startDate);
    }
    if (endDate != null) {
      query = query.where('saleDate', isLessThanOrEqualTo: endDate);
    }
        
    return query.orderBy('saleDate', descending: true).snapshots();
  }

  /// Obtiene un Stream de todas las ventas para un cliente específico.
  Stream<QuerySnapshot> getSalesForCustomer(String userId, String customerId, {String? sellerId}) {
    Query query = _db
        .collection('sales')
        .where('userId', isEqualTo: userId)
        .where('customerId', isEqualTo: customerId);

    if (sellerId != null) {
      query = query.where('sellerId', isEqualTo: sellerId);
    }

    return query.orderBy('saleDate', descending: false).snapshots();
  }

  /// Obtiene un Stream de todos los clientes.
  /// Si se proporciona [sellerId], filtra solo los clientes de ese vendedor.
  Stream<QuerySnapshot> getCustomers(String userId, {String? searchTerm, String? city, String? sellerId, String orderBy = 'registeredAt', bool descending = true}) {
    Query query = _db.collection('customers').where('userId', isEqualTo: userId);

    // Si se filtra por un vendedor específico
    if (sellerId != null && sellerId != 'all' && sellerId.isNotEmpty) {
      if (sellerId == 'admin' || sellerId == 'null' || sellerId == userId || sellerId.length < 6) {
        // Filtro para Administrador: muestra solo los clientes ingresados por el usuario conectado (admin).
        // Se consideran del admin si el sellerId coincide con el ID del negocio (userId), es nulo o está vacío.
        query = query.where(Filter.or(
          Filter('sellerId', isEqualTo: userId),
          Filter('sellerId', isNull: true),
          Filter('sellerId', isEqualTo: ''),
        ));
      } else {
        query = query.where('sellerId', isEqualTo: sellerId);
      }
    }

    if (kDebugMode) {
      print("QUERY INFO: userId=$userId, sellerId=$sellerId, city=$city");
    }

    if (city != null && city.isNotEmpty && city != 'Todas las ciudades' && city != 'All cities') {
      query = query.where('city', isEqualTo: city);
    }

    if (searchTerm == null || searchTerm.isEmpty) {
      // Cuando no se busca, ordenamos por fecha para mostrar todos los clientes.
      return query.orderBy(orderBy, descending: descending).snapshots();
    } else {
      final uppercasedTerm = searchTerm.toUpperCase();
      // Firestore no permite consultas 'OR' en diferentes campos.
      // La estrategia es realizar múltiples consultas y combinarlas en el cliente.
      // Sin embargo, para una búsqueda de prefijo simple, podemos elegir un campo principal.
      // Aquí, priorizamos la búsqueda por 'name_lowercase'.
      // Si un cliente no tiene 'name_lowercase', no aparecerá en la búsqueda por nombre.
      // Una alternativa es buscar también por DNI si el término de búsqueda parece un DNI.
      if (RegExp(r'^[0-9]+$').hasMatch(searchTerm)) {
        // Si el término de búsqueda son solo números, asumimos que es un DNI.
        return query.where('dni', isEqualTo: searchTerm.toUpperCase()).snapshots();
      }
      // Búsqueda por prefijo de nombre
      return query.where('name', isGreaterThanOrEqualTo: uppercasedTerm).where('name', isLessThan: '$uppercasedTerm\uf8ff').snapshots();
    }
  }

  /// Obtiene los clientes una sola vez (Future).
  Future<QuerySnapshot> getCustomersOnce(String userId, {String? sellerId}) {
    Query query = _db.collection('customers').where('userId', isEqualTo: userId);

    if (sellerId != null && sellerId != 'all' && sellerId.isNotEmpty) {
      if (sellerId == 'admin' || sellerId == 'null' || sellerId == userId || sellerId.length < 6) {
        query = query.where(Filter.or(
          Filter('sellerId', isEqualTo: userId),
          Filter('sellerId', isNull: true),
          Filter('sellerId', isEqualTo: ''),
        ));
      } else {
        query = query.where('sellerId', isEqualTo: sellerId);
      }
    }
    return query.get();
  }

  /// Obtiene un Stream de clientes que tienen al menos una venta.
  Stream<List<DocumentSnapshot>> getCustomersWithSales(String userId, {String? sellerId}) {
    // Se unifica la lógica para que sea consistente: tanto para un vendedor específico como para el 
    // administrador viendo "Todos" (sellerId == null), se devuelven los clientes registrados.
    // Esto asegura que el administrador vea a todos los clientes del negocio (incluidos los propios 
    // que suelen tener sellerId en null) y no solo aquellos que ya tienen una transacción, 
    // eliminando la confusión al cambiar entre filtros.
    return getCustomers(userId, sellerId: sellerId).map((snapshot) => snapshot.docs);
  }

  /// Obtiene una lista de ciudades únicas de los clientes.
  Future<List<String>> getCustomerCities(String businessId) async {
    final snapshot = await _db.collection('customers').where('userId', isEqualTo: businessId).get();
    final cities = <String>{};
    for (var doc in snapshot.docs) {
      final data = doc.data();
      if (data['city'] != null && (data['city'] as String).isNotEmpty) {
        cities.add(data['city'] as String);
      }
    }
    return cities.toList()..sort();
  }

  /// Obtiene un Stream de todos los proveedores.
  Stream<QuerySnapshot> getSuppliers(String userId, {String? searchTerm, String? city}) {
    Query query = _db.collection('suppliers').where('userId', isEqualTo: userId);

    if (city != null && city.isNotEmpty && city != 'Todas las ciudades') {
      query = query.where('city', isEqualTo: city);
    }
    return query.orderBy('name').snapshots();
  }

  /// Obtiene todas las categorías una sola vez (Future).
  Future<QuerySnapshot> getCategoriesOnce(String userId) {
    return _db.collection('categories').where('userId', isEqualTo: userId).orderBy('name').get();
  }

  /// Obtiene todos los proveedores una sola vez (Future).
  Future<QuerySnapshot> getSuppliersOnce(String userId) {
    return _db.collection('suppliers').where('userId', isEqualTo: userId).orderBy('name').get();
  }

  /// Obtiene un cliente específico por su ID.
  Future<DocumentSnapshot> getCustomerById(String customerId) {
    return _db.collection('customers').doc(customerId).get();
  }

  /// Obtiene un usuario específico por su ID.
  Future<DocumentSnapshot> getUserById(String userId) {
    return _db.collection('users').doc(userId).get();
  }

  /// Obtiene un Stream de todos los usuarios.
  Stream<QuerySnapshot> getUsers(String businessId, {String? role}) {
    Query query = _db.collection('users').where('businessId', isEqualTo: businessId);
    if (role != null) {
      query = query.where('role', isEqualTo: role);
    }
    return query.snapshots();
  }

  /// Obtiene un Stream de todos los pagos de un usuario.
  Stream<QuerySnapshot> getPayments(String userId, {String? sellerId, DateTime? startDate, DateTime? endDate, String? customerId, String? paymentType}) {
    Query query = _db
        .collection('payments')
        .where('userId', isEqualTo: userId);

    if (customerId != null && customerId.isNotEmpty) {
      query = query.where('customerId', isEqualTo: customerId);
    }

    if (paymentType != null && paymentType.isNotEmpty && paymentType != 'all') {
      query = query.where('payment_type', isEqualTo: paymentType);
    }

    // Si se filtra por un vendedor específico
    if (sellerId != null && sellerId != 'all' && sellerId.isNotEmpty) {
      if (sellerId == 'admin' || sellerId == 'null' || sellerId == userId || sellerId.length < 6) {
        // Filtro consistente para Pagos también
        query = query.where(Filter.or(
          Filter('sellerId', isEqualTo: userId),
          Filter('sellerId', isNull: true),
          Filter('sellerId', isEqualTo: ''),
        ));
      } else {
        query = query.where('sellerId', isEqualTo: sellerId);
      }
    }

    if (startDate != null) {
      query = query.where('date', isGreaterThanOrEqualTo: startDate);
    }
    if (endDate != null) {
      query = query.where('date', isLessThanOrEqualTo: endDate);
    }

    return query.orderBy('date', descending: true).snapshots();
  }

  /// Obtiene una venta específica por su ID.
  Future<DocumentSnapshot> getSaleById(String saleId) {
    return _db.collection('sales').doc(saleId).get();
  }

  /// Obtiene un Stream de todos los pagos para una venta específica.
  Stream<QuerySnapshot> getPaymentsForSale(String saleId) {
    return _db
        .collection('payments')
        .where(Filter.or(
          Filter('saleId', isEqualTo: saleId),
          Filter('saleIds', arrayContains: saleId),
        ))
        .snapshots();
  }

  /// Comprueba si un producto está incluido en alguna venta.
  /// Devuelve true si el producto se encuentra en al menos una venta.
  Future<bool> isProductInAnySale(String productId) async {
    // Firestore no soporta consultas complejas en arrays de mapas directamente ('array-contains-any' en un campo específico del mapa).
    // Por lo tanto, obtenemos todas las ventas y verificamos manualmente en el lado del cliente.
    // Esto puede ser ineficiente si hay muchas ventas. Considera una estructura de datos diferente si el rendimiento se convierte en un problema.
    final allSales = await _db.collection('sales').get();
    return allSales.docs.any((sale) => (sale.data()['items'] as List).any((item) => item['productId'] == productId));
  }

  /// Comprueba si el nombre de un producto ya existe para un usuario.
  /// Opcionalmente excluye un ID de producto para el caso de actualización.
  Future<bool> isProductNameUnique(String userId, String name, {String? currentProductId}) async {
    final query = _db
        .collection('products')
        .where('userId', isEqualTo: userId)
        .where('name', isEqualTo: name.trim().toLowerCase());

    final snapshot = await query.get();

    if (snapshot.docs.isEmpty) {
      return true; // El nombre es único porque no se encontró ningún producto.
    }

    // Si estamos editando, el nombre es válido si el único producto encontrado es el que estamos editando.
    if (currentProductId != null) {
      return snapshot.docs.length == 1 && snapshot.docs.first.id == currentProductId;
    }

    // Si estamos creando un producto nuevo y se encontró un producto, el nombre no es único.
    return false;
  }

  /// Comprueba si el código de barras es único para un usuario.
  /// Opcionalmente excluye un ID de producto para el caso de actualización.
  Future<bool> isBarcodeUnique(String userId, String barCode, {String? currentProductId}) async {
    if (barCode.trim().isEmpty) return true; // Permitir códigos vacíos
    final query = _db
        .collection('products')
        .where('userId', isEqualTo: userId)
        .where('bar_code', isEqualTo: barCode.trim());

    final snapshot = await query.get();

    if (snapshot.docs.isEmpty) return true;

    if (currentProductId != null) {
      return snapshot.docs.length == 1 && snapshot.docs.first.id == currentProductId;
    }
    return false;
  }

  /// Comprueba si el nombre de una categoría ya existe para un usuario.
  /// Opcionalmente excluye un ID de categoría para el caso de actualización.
  Future<bool> isCategoryNameUnique(String userId, String name, {String? currentCategoryId}) async {
    final query = _db
        .collection('categories')
        .where('userId', isEqualTo: userId)
        .where('name', isEqualTo: name.trim().toLowerCase());

    final snapshot = await query.get();

    if (snapshot.docs.isEmpty) return true;

    if (currentCategoryId != null) {
      return snapshot.docs.length == 1 && snapshot.docs.first.id == currentCategoryId;
    }

    return false;
  }

  /// Comprueba si el nombre de un cliente ya existe para un usuario.
  /// Opcionalmente excluye un ID de cliente para el caso de actualización.
  Future<bool> isCustomerNameUnique(String userId, String name, {String? currentCustomerId}) async {
    final query = _db
        .collection('customers')
        .where('userId', isEqualTo: userId)
        .where('name', isEqualTo: name.trim().toUpperCase());

    final snapshot = await query.get();

    if (snapshot.docs.isEmpty) return true;

    if (currentCustomerId != null) {
      return snapshot.docs.length == 1 && snapshot.docs.first.id == currentCustomerId;
    }
    return false;
  }
  // --- Métodos para eliminar datos ---

  /// Comprueba si un cliente tiene ventas asociadas.
  Future<bool> isCustomerInAnySale(String customerId) async {
    final salesSnapshot = await _db
        .collection('sales')
        .where('customerId', isEqualTo: customerId)
        .limit(1) // Solo necesitamos saber si existe al menos una.
        .get();
    return salesSnapshot.docs.isNotEmpty;
  }

  /// Elimina un producto.
  Future<void> deleteProduct(String productId) async {
    // Primero, obtén la URL de la imagen del documento del producto.
    DocumentSnapshot doc = await _db.collection('products').doc(productId).get();
    if (doc.exists) {
      Map<String, dynamic>? data = doc.data() as Map<String, dynamic>?;
      String? imageUrl = data?['imageUrl'];

      // No permitir eliminar si el producto está en una venta.
      if (await isProductInAnySale(productId)) {
        throw Exception('Este producto no se puede eliminar porque está asociado a una o más ventas.');
      }

      // Si hay una URL de imagen, intenta eliminar el archivo de Storage.
      if (imageUrl != null && imageUrl.isNotEmpty) {
        try {
          Reference photoRef = _storage.refFromURL(imageUrl);
          await photoRef.delete();
        } on FirebaseException catch (e) {
          // Si el objeto no se encuentra, lo ignoramos y continuamos.
          if (e.code != 'object-not-found') {
            rethrow; // Si es otro error de Firebase, sí lo lanzamos.
          }
        }
      }
    }

    // Finalmente, elimina el documento de Firestore.
    await _db.collection('products').doc(productId).delete();
  }

  /// Elimina un cliente.
  Future<void> deleteCustomer(String customerId) async {
    // No permitir eliminar si el cliente tiene ventas.
    if (await isCustomerInAnySale(customerId)) {
      throw Exception('Este cliente no se puede eliminar porque tiene ventas asociadas.');
    }
    await _db.collection('customers').doc(customerId).delete();
  }

  /// Añade un nuevo proveedor a la colección 'suppliers'.
  Future<DocumentReference> addSupplier(String userId, String name, String contact, String phone, String email, {String city = ''}) {
    return _db.collection('suppliers').add({ // Cambiado de Future<void> a Future<DocumentReference>
      'name': name.trim().toUpperCase(),
      'contact': contact.trim().toUpperCase(),
      'phone': phone.trim(),
      'email': email.trim(),
      'city': city.trim().toUpperCase(),
      'registeredAt': FieldValue.serverTimestamp(),
      'userId': userId,
    });
  }

  /// Actualiza un proveedor existente en la colección 'suppliers'.
  Future<void> updateSupplier(String supplierId, String name, String contact, String phone, String email, {String city = ''}) {
    return _db.collection('suppliers').doc(supplierId).update({
      'name': name.trim().toUpperCase(),
      'contact': contact.trim().toUpperCase(),
      'phone': phone.trim(),
      'email': email.trim(),
      'city': city.trim().toUpperCase(),
    });
  }

  /// Añade una nueva categoría.
  Future<DocumentReference> addCategory(String userId, String name) {
    return _db.collection('categories').add({
      'name': name.trim().toUpperCase(),
      'userId': userId
    });
  }

  /// Actualiza una categoría.
  Future<void> updateCategory(String categoryId, String name) {
    return _db.collection('categories').doc(categoryId).update({
      'name': name.trim().toUpperCase(),
    });
  }

  /// Comprueba si una categoría está asignada a algún producto del negocio.
  Future<bool> isCategoryInUse(String businessId, String categoryId) async {
    final snapshot = await _db
        .collection('products')
        .where('userId', isEqualTo: businessId)
        .where('categoryId', isEqualTo: categoryId)
        .limit(1) // Solo necesitamos saber si existe al menos uno
        .get();
    return snapshot.docs.isNotEmpty;
  }

  /// Elimina una categoría.
  Future<void> deleteCategory(String categoryId) {
    return _db.collection('categories').doc(categoryId).delete();
  }

  /// Elimina un proveedor.
  Future<void> deleteSupplier(String supplierId) {
    return _db.collection('suppliers').doc(supplierId).delete();
  }

  /// Elimina un usuario.
  Future<void> deleteUser(String userId) {
    return _db.collection('users').doc(userId).delete();
  }

  /// Elimina una venta.
  Future<void> deleteSale(String saleId) async {
    // Obtener la venta primero para restaurar el stock
    final saleDoc = await _db.collection('sales').doc(saleId).get();
    if (!saleDoc.exists) return;

    final saleData = saleDoc.data() as Map<String, dynamic>;
    final items = List<Map<String, dynamic>>.from(saleData['items'] ?? []);

    final WriteBatch batch = _db.batch();

    // 1. Encuentra y prepara la eliminación de los pagos asociados a la venta.
    final paymentsQuery = _db.collection('payments').where('saleId', isEqualTo: saleId);
    final paymentsSnapshot = await paymentsQuery.get();
    for (final doc in paymentsSnapshot.docs) {
      batch.delete(doc.reference);
    }

    // 2. Restaurar stock
    for (var item in items) {
      final productRef = _db.collection('products').doc(item['productId']);
      batch.update(productRef, {'stock': FieldValue.increment(item['quantity'])});
    }

    // 3. Prepara la eliminación de la venta.
    batch.delete(_db.collection('sales').doc(saleId));

    // 4. Ejecuta todas las operaciones de eliminación en el batch.
    return batch.commit();
  }
  
  /// Elimina todas las ofertas asociadas a un producto.
  Future<void> deleteProductOffers(String productId) async {
    final offers = await _db.collection('offers').where('productId', isEqualTo: productId).get();
    final batch = _db.batch();
    for (final doc in offers.docs) {
      batch.delete(doc.reference);
    }
    await batch.commit();
  }

  /// Elimina un pago.
  Future<void> deletePayment(String paymentId) {
    return _db.collection('payments').doc(paymentId).delete();
  }

  /// Obtiene un Stream de la configuración de la empresa.
  Stream<DocumentSnapshot> getCompanySettings(String userId) {
    return _db.collection('company_settings').doc(userId).snapshots();
  }

  /// Obtiene la configuración de la empresa una sola vez (Future).
  Future<DocumentSnapshot> getCompanySettingsOnce(String userId) {
    return _db.collection('company_settings').doc(userId).get();
  }

  /// Actualiza la configuración de la empresa.
  /// Usa SetOptions(merge: true) para crear o actualizar el documento.
  Future<void> updateCompanySettings(String userId, Map<String, dynamic> data) {
    return _db.collection('company_settings').doc(userId).set(data, SetOptions(merge: true));
  }

  /// Reasigna los clientes de un vendedor al administrador (sellerId = null).
  Future<void> reassignSellerCustomersToAdmin(String sellerId) async {
    final batch = _db.batch();
    final customersSnapshot = await _db
        .collection('customers')
        .where('sellerId', isEqualTo: sellerId)
        .get();

    for (final doc in customersSnapshot.docs) {
      batch.update(doc.reference, {'sellerId': null});
    }
    await batch.commit();
  }
}