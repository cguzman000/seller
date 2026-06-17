import 'dart:io';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:image_picker/image_picker.dart';
import 'package:seller/firestore_service.dart';
import 'app_localizations.dart';

class SettingsPage extends StatefulWidget {
  final User user;
  const SettingsPage({super.key, required this.user});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final FirestoreService _firestoreService = FirestoreService();
  final _formKey = GlobalKey<FormState>();
  final _companyNameController = TextEditingController();
  final _companyAddressController = TextEditingController();
  final _vatRateController = TextEditingController();
  final _profitMarginController = TextEditingController();
  final _companyPhoneController = TextEditingController();
  final _decimalPlacesController = TextEditingController();
  final ImagePicker _picker = ImagePicker();

  String? _logoUrl;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  @override
  void dispose() {
    _companyNameController.dispose();
    _companyAddressController.dispose();
    _vatRateController.dispose();
    _profitMarginController.dispose();
    _companyPhoneController.dispose();
    _decimalPlacesController.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    final settingsDoc = await _firestoreService.getCompanySettings(widget.user.uid).first;
    if (settingsDoc.exists) {
      final data = settingsDoc.data() as Map<String, dynamic>;
      _companyNameController.text = data['company_name'] ?? '';
      _companyAddressController.text = data['company_address'] ?? '';
      _vatRateController.text = (data['vat_rate'] ?? '21.0').toString();
      _profitMarginController.text = (data['profit_margin'] ?? '30.0').toString();
      _companyPhoneController.text = data['company_phone'] ?? '';
      _decimalPlacesController.text = (data['decimal_places'] ?? '0').toString();
      if (mounted) {
        setState(() {
          _logoUrl = data['company_logo_url'];
        });
      }
    }
  }

  Future<void> _pickAndUploadLogo() async {
    final XFile? image = await _picker.pickImage(source: ImageSource.gallery, imageQuality: 70, maxWidth: 800);
    if (image == null) return;

    setState(() => _isLoading = true);

    try {
      final file = File(image.path);
      // El businessId para un admin es su propio user.uid
      final newLogoUrl = await _firestoreService.uploadCompanyLogo(file, widget.user.uid);

      // Guardar la nueva URL en la configuración de la empresa
      await _firestoreService.updateCompanySettings(widget.user.uid, {'company_logo_url': newLogoUrl});

      if (mounted) {
        setState(() {
          _logoUrl = newLogoUrl;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context).get('logoUpdated'))),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${AppLocalizations.of(context).get('errorUpload')}$e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _removeLogo() async {
    final l10n = AppLocalizations.of(context);
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.get('deleteLogo')),
        content: Text(l10n.get('confirmDeleteLogo')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(l10n.get('cancel'))),
          TextButton(onPressed: () => Navigator.pop(context, true), child: Text(l10n.get('delete'), style: const TextStyle(color: Colors.red))),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _isLoading = true);
    try {
      await _firestoreService.deleteCompanyLogo(widget.user.uid);
      if (mounted) {
        setState(() => _logoUrl = null);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l10n.get('logoDeleted'))));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${l10n.get('error')}$e')));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _saveSettings() async {
    if (_formKey.currentState!.validate()) {
      final companyName = _companyNameController.text;
      final companyAddress = _companyAddressController.text;
      final vatRate = double.tryParse(_vatRateController.text) ?? 21.0;
      final profitMargin = double.tryParse(_profitMarginController.text) ?? 30.0;
      final companyPhone = _companyPhoneController.text;
      final decimalPlaces = int.tryParse(_decimalPlacesController.text) ?? 0;

      await _firestoreService.updateCompanySettings(widget.user.uid, {
        'company_name': companyName,
        'company_address': companyAddress,
        'vat_rate': vatRate,
        'profit_margin': profitMargin,
        'company_phone': companyPhone,
        'decimal_places': decimalPlaces,
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context).get('settingsSaved'))),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.get('settingsTitle')),
        actions: [
          IconButton(icon: const Icon(Icons.save), onPressed: _saveSettings, tooltip: l10n.get('save')),
        ],
      ),
      body: Stack(
        children: [
          Form(
            key: _formKey,
            child: ListView(
              padding: const EdgeInsets.all(16.0),
              children: [
                Text(l10n.get('companyLogo'), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 10),
                Center(
                  child: Stack(
                    children: [
                      GestureDetector(
                        onTap: _pickAndUploadLogo,
                        child: CircleAvatar(
                          radius: 60,
                          backgroundColor: Colors.grey.shade200,
                          backgroundImage: _logoUrl != null ? NetworkImage(_logoUrl!) : null,
                          child: _logoUrl == null
                              ? Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    const Icon(Icons.camera_alt, size: 30, color: Colors.grey),
                                    Text(l10n.get('uploadLogo'), style: const TextStyle(fontSize: 12, color: Colors.grey)),
                                  ],
                                )
                              : null,
                        ),
                      ),
                      if (_logoUrl != null)
                        Positioned(
                          bottom: 0,
                          right: 0,
                          child: CircleAvatar(
                            radius: 20,
                            backgroundColor: Colors.white,
                            child: IconButton(
                              icon: const Icon(Icons.delete, color: Colors.red, size: 20),
                              onPressed: _removeLogo,
                              tooltip: l10n.get('deleteLogo'),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                TextFormField(controller: _companyNameController, decoration: InputDecoration(labelText: l10n.get('companyName'), border: const OutlineInputBorder()), validator: (v) => v!.isEmpty ? l10n.get('enterName') : null),
                const SizedBox(height: 16),
                TextFormField(controller: _companyAddressController, decoration: InputDecoration(labelText: l10n.get('companyAddress'), border: const OutlineInputBorder())),
                const SizedBox(height: 16),
                TextFormField(controller: _companyPhoneController, decoration: InputDecoration(labelText: l10n.get('companyPhone'), border: const OutlineInputBorder()), keyboardType: TextInputType.phone),
                const SizedBox(height: 16),
                TextFormField(controller: _vatRateController, decoration: InputDecoration(labelText: l10n.get('vatRate'), border: const OutlineInputBorder(), hintText: l10n.get('vatRateHint')), keyboardType: const TextInputType.numberWithOptions(decimal: true), validator: (v) => double.tryParse(v!) == null ? l10n.get('enterValidNumber') : null),
                const SizedBox(height: 16),
                TextFormField(controller: _profitMarginController, decoration: InputDecoration(labelText: l10n.get('profitMargin'), border: const OutlineInputBorder(), hintText: l10n.get('profitMarginHint')), keyboardType: const TextInputType.numberWithOptions(decimal: true), validator: (v) => double.tryParse(v!) == null ? l10n.get('enterValidNumber') : null),
                const SizedBox(height: 16),
                TextFormField(controller: _decimalPlacesController, decoration: InputDecoration(labelText: l10n.get('decimalPlaces'), border: const OutlineInputBorder(), hintText: l10n.get('decimalPlacesHint')), keyboardType: TextInputType.number, validator: (v) => int.tryParse(v!) == null ? l10n.get('enterValidNumber') : null),
              ],
            ),
          ),
          if (_isLoading)
            Container(color: Colors.black.withValues(alpha: 0.5), child: const Center(child: CircularProgressIndicator())),
        ],
      ),
    );
  }
}