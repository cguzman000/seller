import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:seller/firestore_service.dart';

/// Un proveedor que expone el servicio de Firestore.
final firestoreServiceProvider = Provider<FirestoreService>((ref) {
  return FirestoreService();
});

/// Un StreamProvider que obtiene y expone la configuración de la empresa.
///
/// `family` nos permite pasarle un parámetro (el businessId) al proveedor.
/// Automáticamente gestionará el estado de carga, error y datos del Stream.
final companySettingsProvider = StreamProvider.family<DocumentSnapshot, String>((ref, businessId) {
  // Escucha al proveedor de FirestoreService
  final firestoreService = ref.watch(firestoreServiceProvider);
  
  // Devuelve el stream de la configuración de la empresa
  return firestoreService.getCompanySettings(businessId);
});