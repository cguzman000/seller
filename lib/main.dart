import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:seller/payments.dart';
import 'login_page.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'products.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'categories.dart';
import 'customers.dart';
import 'sales.dart';
import 'suppliers.dart';
import 'firestore_service.dart';
import 'package:intl/intl.dart';
import 'settings_page.dart';
import 'sellers.dart';
import 'stock.dart';
import 'offers.dart';
import 'detailed_reports.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'app_localizations.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  await FirebaseAppCheck.instance.activate(
    // Usamos 'debug' para desarrollo. Para producción usa 'AndroidProvider.playIntegrity'.
    androidProvider: AndroidProvider.debug,
    appleProvider: AppleProvider.appAttest,
  );
  await initializeDateFormatting(
    null,
    null,
  ); // Inicializa los datos de localización
  runApp(const MyApp());
}

class SellerBottomNavigationBar extends StatefulWidget {
  final User user;
  final String businessId;
  final String? sellerId;
  final String? role;
  final int currentIndex;
  final bool isMainPage;
  final bool allowSamePageNavigation;

  const SellerBottomNavigationBar({
    super.key,
    required this.user,
    required this.businessId,
    required this.sellerId,
    this.role,
    required this.currentIndex,
    this.isMainPage = false,
    this.allowSamePageNavigation = false,
  });

  @override
  State<SellerBottomNavigationBar> createState() => _SellerBottomNavigationBarState();
}

class _SellerBottomNavigationBarState extends State<SellerBottomNavigationBar> {
  late ScrollController _scrollController;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    // Al iniciar, deslizamos la barra para centrar el elemento seleccionado
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        double screenWidth = MediaQuery.of(context).size.width;
        const double itemWidth = 85.0; // Ancho definido para cada botón
        double offset = (widget.currentIndex * itemWidth) - (screenWidth / 2) + (itemWidth / 2);
        
        if (offset < 0) offset = 0;
        _scrollController.animateTo(
          offset,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colorScheme = Theme.of(context).colorScheme;

    final List<_NavItem> items = [
      _NavItem(Icons.home, l10n.get('home'), 0),
      _NavItem(Icons.point_of_sale, l10n.get('sales'), 1),
      _NavItem(Icons.attach_money, l10n.get('payments'), 2),
      _NavItem(Icons.people, l10n.get('customers'), 3),
      _NavItem(Icons.inventory_2, l10n.get('products'), 4),
      _NavItem(Icons.local_offer, l10n.get('offers'), 5),
      _NavItem(Icons.inventory, l10n.get('stock'), 6),
      _NavItem(Icons.business, l10n.get('suppliers'), 7),
     // _NavItem(Icons.bar_chart, l10n.get('reports'), 8),
    ];

    return Container(
      height: 85,
      decoration: BoxDecoration(
        color: colorScheme.surface,
        border: Border(top: BorderSide(color: colorScheme.outlineVariant, width: 0.5)),
      ),
      child: SafeArea(
        child: SingleChildScrollView(
          controller: _scrollController,
          scrollDirection: Axis.horizontal,
          child: Row(
            children: items.map((item) {
              final bool isSelected = widget.currentIndex == item.index;
              return InkWell(
                onTap: () => _onItemTapped(item.index),
                child: Container(
                  width: 75,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        item.icon,
                        color: isSelected ? colorScheme.primary : colorScheme.onSurfaceVariant,
                        size: 24,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        item.label,
                        style: TextStyle(
                          fontSize: 11,
                          color: isSelected ? colorScheme.primary : colorScheme.onSurfaceVariant,
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                        ),
                        textAlign: TextAlign.center,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
        ),
      ),
    );
  }

  void _onItemTapped(int index) {
    if (index == widget.currentIndex && !widget.isMainPage && !widget.allowSamePageNavigation) return;

    // Si estamos en cualquier subpágina y presionamos Home (index 0), 
    // simplemente volvemos a la raíz de la navegación (MyHomePage original).
    if (!widget.isMainPage && index == 0) {
      Navigator.of(context).popUntil((route) => route.isFirst);
      return;
    }

    final String effectiveRole = widget.role ?? (widget.user.uid == widget.businessId ? 'admin' : 'seller');

    Widget page;
    switch (index) {
      case 0: page = MyHomePage(user: widget.user, businessId: widget.businessId, role: effectiveRole, sellerId: widget.sellerId); break;
      case 1: page = SalesPage(user: widget.user, businessId: widget.businessId, sellerId: widget.sellerId, role: effectiveRole); break;
      case 2: page = PaymentsPage(user: widget.user, businessId: widget.businessId, sellerId: widget.sellerId, role: effectiveRole); break;
      case 3: page = CustomersPage(user: widget.user, businessId: widget.businessId, role: effectiveRole, sellerId: widget.sellerId); break;
      case 4: page = ProductsPage(user: widget.user, businessId: widget.businessId, role: effectiveRole, sellerId: widget.sellerId); break;
      case 5: page = OffersPage(user: widget.user, businessId: widget.businessId); break;
      case 6: page = StockPage(user: widget.user, businessId: widget.businessId); break;
      case 7: page = SuppliersPage(user: widget.user, businessId: widget.businessId); break;
      //case 8: page = ReportsHubPage(user: widget.user, businessId: widget.businessId, role: effectiveRole, sellerId: widget.sellerId); break;
      default: return;
    }

    if (widget.isMainPage) {
      Navigator.push(context, MaterialPageRoute(builder: (context) => page));
    } else {
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => page));
    }
  }
}

class _NavItem {
  final IconData icon;
  final String label;
  final int index;
  _NavItem(this.icon, this.label, this.index);
}

class _ReportItem {
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  _ReportItem(this.label, this.icon, this.color, this.onTap);
}

class ReportsHubPage extends StatelessWidget {
  final User user;
  final String businessId;
  final String? sellerId;
  final String role;

  const ReportsHubPage({
    super.key,
    required this.user,
    required this.businessId,
    this.sellerId,
    required this.role,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.get('reports')),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          ListTile(
            leading: const Icon(Icons.pie_chart),
            title: Text(l10n.get('salesByProduct')),
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => SalesByProductReportPage(businessId: businessId, sellerId: sellerId, user: user))),
          ),
          ListTile(
            leading: const Icon(Icons.summarize),
            title: Text(l10n.get('salesAndPaymentsReport')),
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => SalesAndPaymentsReportPage(businessId: businessId, sellerId: sellerId, user: user))),
          ),
          ListTile(
            leading: const Icon(Icons.star),
            title: Text(l10n.get('customerRanking')),
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => CustomerRankingPage(businessId: businessId, sellerId: sellerId, user: user))),
          ),
          ListTile(
            leading: const Icon(Icons.money_off),
            title: Text(l10n.get('accountsReceivable')),
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => AccountsReceivablePage(businessId: businessId, sellerId: sellerId, user: user))),
          ),
          ListTile(
            leading: const Icon(Icons.inventory),
            title: Text(l10n.get('stockReport')),
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => StockReportPage(businessId: businessId, user: user))),
          ),
          if (role == 'admin')
            ListTile(
              leading: const Icon(Icons.badge),
              title: Text(l10n.get('sellerPerformance')),
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => SellerPerformancePage(businessId: businessId, user: user))),
            ),
        ],
      ),
      bottomNavigationBar: SellerBottomNavigationBar(
        user: user,
        businessId: businessId,
        sellerId: sellerId,
        role: role,
        currentIndex: 8,
      ),
    );
  }
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  static void setLocale(BuildContext context, Locale newLocale) {
    _MyAppState? state = context.findAncestorStateOfType<_MyAppState>();
    state?.setLocale(newLocale);
  }

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  Locale? _locale;

  void setLocale(Locale newLocale) {
    setState(() {
      _locale = newLocale;
    });
  }

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      onGenerateTitle: (context) => AppLocalizations.of(context).get('appName'),
      locale: _locale,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.lightBlue),
        useMaterial3: true,
      ),
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [
        Locale('es'), // Español
        Locale('en'), // English
      ],
      home: StreamBuilder<User?>(
        stream: FirebaseAuth.instance.authStateChanges(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          } else if (snapshot.hasData) {
       return SessionResolver(user: snapshot.data!);
          }
          return const LoginPageWrapper();
        },
      ),
    );
  }
}

class LoginPageWrapper extends StatelessWidget {
  const LoginPageWrapper({super.key});

  @override
  Widget build(BuildContext context) {
    // Este wrapper añade la selección de idioma a la página de login
    // sin modificar el archivo login_page.dart directamente.
    final l10n = AppLocalizations.of(context);
    return Stack(
      children: [
        const LoginPage(),
        Positioned(
          top: 80,
          left: 0,
          right: 0,
          child: Center(
            child: Image.asset(
              'assets/icon.png',
              width: 150,
              height: 150,
            ),
          ),
        ),
        Positioned(
          top: 40, // Ajusta este valor para que coincida con la altura del AppBar si es necesario
          right: 16,
          child: Material(
            color: Colors.transparent,
            child: PopupMenuButton<Locale>(
              tooltip: l10n.get('selectLanguage'),
              icon: const Icon(Icons.language),
              onSelected: (Locale locale) {
                MyApp.setLocale(context, locale);
              },
              itemBuilder: (BuildContext context) => <PopupMenuEntry<Locale>>[
                const PopupMenuItem<Locale>(
                  value: Locale('es'),
                  child: Text('Español'),
                ),
                const PopupMenuItem<Locale>(
                  value: Locale('en'),
                  child: Text('English'),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class SessionResolver extends StatefulWidget {
  final User user;
  const SessionResolver({super.key, required this.user});

  @override
  State<SessionResolver> createState() => _SessionResolverState();
}

class _SessionResolverState extends State<SessionResolver> {
  late final Future<List<Map<String, dynamic>>> _profilesFuture;
  final FirestoreService _firestoreService = FirestoreService();
  Map<String, dynamic>? _selectedProfile;

  void _onProfileSelected(Map<String, dynamic> profile) {
    setState(() {
      _selectedProfile = profile;
    });
  }

  @override
  void initState() {
    super.initState();
    _profilesFuture = _firestoreService.getUserProfiles(widget.user);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _profilesFuture,
      builder: (context, snapshot) {
        final l10n = AppLocalizations.of(context);
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        if (snapshot.hasError || !snapshot.hasData) {
          return Scaffold(
            body: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(l10n.get('loadingProfilesError').replaceFirst('{error}', snapshot.error.toString())),
                  const SizedBox(height: 20),
                  ElevatedButton(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (context) => const SigningOutPage()),
                    ),
                    child: Text(l10n.get('logout')),
                  ),
                ],
              ),
            ),
          );
        }

        final profiles = snapshot.data!;

        if (_selectedProfile != null) {
          return MyHomePage(
            user: widget.user,
            businessId: _selectedProfile!['businessId'],
            role: _selectedProfile!['role'],
            sellerId: _selectedProfile!['sellerId'],
          );
        }

        if (profiles.length > 1) {
          return ProfileSelectionPage(user: widget.user, profiles: profiles, onProfileSelected: _onProfileSelected);
        }

        if (profiles.length == 1) {
          final profile = profiles.first;
          return MyHomePage(
            user: widget.user,
            businessId: profile['businessId'],
            role: profile['role'],
            sellerId: profile['sellerId'],
          );
        }

        return CreateBusinessPage(user: widget.user, onProfileCreated: _onProfileSelected);
      },
    );
  }
}

class ProfileSelectionPage extends StatelessWidget {
  final User user;
  final List<Map<String, dynamic>> profiles;
  final ValueChanged<Map<String, dynamic>> onProfileSelected;

  const ProfileSelectionPage({
    super.key,
    required this.user,
    required this.profiles,
    required this.onProfileSelected,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    // Ordenar los perfiles para que el rol 'admin' aparezca siempre primero
    final sortedProfiles = List<Map<String, dynamic>>.from(profiles)
      ..sort((a, b) {
        final roleA = a['role']?.toString().toLowerCase() ?? '';
        final roleB = b['role']?.toString().toLowerCase() ?? '';
        if (roleA == 'admin' && roleB != 'admin') return -1;
        if (roleA != 'admin' && roleB == 'admin') return 1;
        return 0;
      });

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.get('selectProfile')),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: l10n.get('logout'),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (context) => const SigningOutPage()),
            ),
          ),
        ],
      ),
      body: GridView.builder(
        padding: const EdgeInsets.all(12.0),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          childAspectRatio: 0.85,
        ),
        itemCount: sortedProfiles.length,
        itemBuilder: (context, index) {
          final profile = sortedProfiles[index];
          final label = profile['label'] as String? ?? l10n.get('unknownProfile');
          final role = profile['role']?.toString().toLowerCase() ?? '';

          final bool isAdmin = role == 'admin';
          final Color roleColor = isAdmin ? Colors.blue : Colors.orange;

          return Card(
            margin: EdgeInsets.zero,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: roleColor.withValues(alpha: 0.5), width: 1.5),
            ),
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: () => onProfileSelected(profile),
              child: Padding(
                padding: const EdgeInsets.all(12.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(isAdmin ? Icons.business : Icons.person, color: roleColor, size: 40),
                    const SizedBox(height: 12),
                    Text(
                      label,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${l10n.get('role')}: ${isAdmin ? l10n.get('admin') : l10n.get('seller')}',
                      style: TextStyle(color: roleColor, fontWeight: FontWeight.w600, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class CreateBusinessPage extends StatefulWidget {
  final User user;
  final ValueChanged<Map<String, dynamic>>? onProfileCreated;

  const CreateBusinessPage({super.key, required this.user, this.onProfileCreated});

  @override
  State<CreateBusinessPage> createState() => _CreateBusinessPageState();
}

class _CreateBusinessPageState extends State<CreateBusinessPage> {
  final FirestoreService _firestoreService = FirestoreService();
  bool _isLoading = false;

  Future<void> _createBusiness() async {
    setState(() => _isLoading = true);
    try {
      await _firestoreService.createOwnBusiness(widget.user);
      final profiles = await _firestoreService.getUserProfiles(widget.user);
      if (mounted && profiles.isNotEmpty) {
        final profile = profiles.firstWhere((p) => p['type'] == 'admin');
        if (widget.onProfileCreated != null) {
          widget.onProfileCreated!(profile);
        }
      }
    } catch (e) {
      if (mounted) {
        final l10n = AppLocalizations.of(context);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l10n.get('errorCreatingBusiness').replaceFirst('{error}', e.toString()))));
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.get('welcome'))),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(l10n.get('createBusinessHello').replaceFirst('{userName}', widget.user.displayName ?? l10n.get('user')), style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 16),
              Text(l10n.get('createBusinessMessage'), textAlign: TextAlign.center),
              const SizedBox(height: 32),
              if (_isLoading) const CircularProgressIndicator() else ElevatedButton.icon(onPressed: _createBusiness, icon: const Icon(Icons.add_business), label: Text(l10n.get('createOwnBusiness')), style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12))),
              const SizedBox(height: 20),
              const Divider(),
              const SizedBox(height: 20),
              Text(l10n.get('createBusinessInfo'), textAlign: TextAlign.center, style: const TextStyle(color: Colors.grey)),
              const SizedBox(height: 16),
              TextButton(
                  onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (context) => const SigningOutPage()),
                      ),
                  child: Text(l10n.get('logout')))
            ],
          ),
        ),
      ),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({
    super.key,
    required this.user,
    required this.businessId,
    required this.role,
    this.sellerId,
  });

  final User user;
  final String businessId;
  final String role;
  final String? sellerId;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  final FirestoreService _firestoreService = FirestoreService();

  // Declaramos los streams para mantenerlos en memoria y no recargarlos constantemente
  late Stream<QuerySnapshot> _monthlySalesStream;
  late Stream<QuerySnapshot> _allSalesStream;
  late Stream<QuerySnapshot> _allPaymentsStream;
  late Stream<QuerySnapshot> _monthlyPaymentsStream;
  late Stream<QuerySnapshot> _lowStockProductsStream;
  late Stream<QuerySnapshot> _todaySalesStream;
  late Stream<QuerySnapshot> _customersStream;

  String? _companyLogoUrl;
  late Stream<DocumentSnapshot> _companySettingsStream;

  late String? _filterSellerId;

  @override
  void initState() {
    super.initState();
    _filterSellerId = widget.role == 'admin' ? null : widget.sellerId;

    // Configuramos el rango de fechas para cubrir todo el año actual (Enero a Diciembre)
    final now = DateTime.now();
    final startOfPeriod = DateTime(now.year, 1, 1);
    final endOfPeriod = DateTime(now.year, 12, 31, 23, 59, 59);
    final startOfToday = DateTime(now.year, now.month, now.day);

    _todaySalesStream = _firestoreService.getSales(
      widget.businessId,
      sellerId: _filterSellerId,
      startDate: startOfToday,
      endDate: endOfPeriod,
    );

    _monthlySalesStream = _firestoreService.getSales(
      widget.businessId,
      sellerId: _filterSellerId,
      startDate: startOfPeriod,
      endDate: endOfPeriod,
    );
    
    _monthlyPaymentsStream = _firestoreService.getPayments(
      widget.businessId,
      sellerId: _filterSellerId,
      startDate: startOfPeriod,
      endDate: endOfPeriod,
    );

    // Para la deuda total, sí necesitamos todo el historial
    _allSalesStream = _firestoreService.getSales(
      widget.businessId,
      sellerId: _filterSellerId,
    );
    _allPaymentsStream = _firestoreService.getPayments(
      widget.businessId,
      sellerId: _filterSellerId,
    );

    _customersStream = _firestoreService.getCustomers(
      widget.businessId,
      sellerId: _filterSellerId,
    );


    _lowStockProductsStream = _firestoreService.getProducts(widget.businessId);
    
    _companySettingsStream = _firestoreService.getCompanySettings(widget.businessId);

    _companySettingsStream.listen((snapshot) {
      if (snapshot.exists && snapshot.data() != null) {
        final data = snapshot.data() as Map<String, dynamic>;
        setState(() {
          _companyLogoUrl = data['company_logo_url'] as String?;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final l10n = AppLocalizations.of(context);

    final bool isSeller = widget.role == 'seller';

    return Scaffold(
      appBar: AppBar(
        // PRUEBA ESTO: Intenta cambiar el color aquí a un color específico (a
        // Colors.amber, ¿quizás?) y activa la recarga en caliente para ver cómo la AppBar
        // cambia de color mientras los otros colores permanecen igual.
        backgroundColor: isSeller
            ? Colors.orange.shade200
            : Theme.of(context).colorScheme.inversePrimary,
        title: Row(
          children: [
            Flexible(
              child: Text(
                widget.user.displayName ?? 'Usuario',
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w500),
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: widget.role == 'admin' ? Colors.blue : Colors.orange,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Text(
                widget.role == 'admin' ? l10n.get('admin') : l10n.get('seller'),
                style: const TextStyle(fontSize: 12, color: Colors.white, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      ),

      drawer: Drawer(
        child: ListView(
          padding: EdgeInsets.zero,
          children: <Widget>[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.only(top: 40.0, left: 16.0, right: 16.0, bottom: 16.0),
              decoration: BoxDecoration(
                color: isSeller
                    ? Colors.orange
                    : Theme.of(context).colorScheme.primary,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.start,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (_companyLogoUrl != null && _companyLogoUrl!.isNotEmpty) ...[
                        CircleAvatar(
                          radius: 30,
                          backgroundImage: NetworkImage(_companyLogoUrl!),
                          // Si la imagen falla en cargar, el CircleAvatar mostrará su color de fondo.
                          // Para un ícono de error personalizado, se necesitaría una lógica más compleja (ej. FadeInImage).
                        ),
                        const SizedBox(width: 8),
                      ],
                      CircleAvatar(
                        radius: 30,
                        backgroundImage: widget.user.photoURL != null
                            ? NetworkImage(widget.user.photoURL!)
                            : null,
                        child: widget.user.photoURL == null
                            ? const Icon(Icons.person, size: 40)
                            : null,
                      ),
                      const Spacer(),
                      IconButton(
                          onPressed: () => Navigator.of(context).push(
                                MaterialPageRoute(builder: (context) => const SigningOutPage()),
                              ),
                          icon: const Icon(Icons.logout, color: Colors.white),
                          tooltip: 'Cerrar Sesión'),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text(widget.user.displayName ?? l10n.get('noName'), style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                  Text('${widget.user.email ?? l10n.get('noEmail')}\n${l10n.get('role')}: ${widget.role == 'admin' ? l10n.get('admin') : l10n.get('seller')}', style: const TextStyle(color: Colors.white70, fontSize: 14)),
                ],
              ),
            ),
            if (widget.role == 'admin')
              ListTile(
                leading: const Icon(Icons.supervisor_account),
                title: Text(l10n.get('sellers')),
                onTap: () {
                  Navigator.pop(context); // Cierra el drawer
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => SellersPage(
                        user: widget.user,
                        businessId: widget.businessId,
                      ),
                    ),
                  );
                },
              ),
            ListTile(
              leading: const Icon(Icons.shopping_bag_outlined),
              title: Text(l10n.get('products')),
              onTap: () {
                Navigator.pop(context); // Cierra el drawer
                // Los productos son compartidos, usamos businessId
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => ProductsPage(
                      user: widget.user,
                      businessId: widget.businessId,
                        role: widget.role,
                            sellerId: _filterSellerId,
                    ),
                  ),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.inventory),
              title: Text(l10n.get('stock')),
              onTap: () {
                Navigator.pop(context); // Cierra el drawer
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => StockPage(
                      user: widget.user,
                      businessId: widget.businessId,
                    ),
                  ),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.local_offer),
              title: Text(l10n.get('offers')),
              onTap: () {
                Navigator.pop(context); // Cierra el drawer
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => OffersPage(
                      user: widget.user,
                      businessId: widget.businessId,
                    ),
                  ),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.category),
              title: Text(l10n.get('categories')),
              onTap: () {
                Navigator.pop(context); // Cierra el drawer
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => CategoriesPage(
                      user: widget.user,
                      businessId: widget.businessId,
                    ),
                  ),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.people),
              title: Text(l10n.get('customers')),
              onTap: () {
                Navigator.pop(context); // Cierra el drawer
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => CustomersPage(
                      user: widget.user,
                      businessId: widget.businessId,
                        role: widget.role,
                            sellerId: _filterSellerId,
                    ),
                  ),
                );
              },
            ),
            if (widget.role == 'admin')
              ListTile(
                leading: const Icon(Icons.business),
                title: Text(l10n.get('suppliers')),
                onTap: () {
                  Navigator.pop(context); // Cierra el drawer
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => SuppliersPage(
                        user: widget.user,
                        businessId: widget.businessId,
                      ),
                    ),
                  );
                },
              ),
            ListTile(
              leading: const Icon(Icons.point_of_sale),
              title: Text(l10n.get('sales')),
              onTap: () {
                Navigator.pop(context); // Cierra el drawer
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => SalesPage(
                      user: widget.user,
                      businessId: widget.businessId,
                      sellerId: _filterSellerId,
                        role: widget.role,
                    ),
                  ),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.payment),
              title: Text(l10n.get('payments')),
              onTap: () {
                Navigator.pop(context); // Cierra el drawer
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => PaymentsPage(
                      user: widget.user,
                      businessId: widget.businessId,
                      sellerId: _filterSellerId,
                        role: widget.role,
                    ),
                  ),
                );
              },
            ),
            ExpansionTile(
              leading: const Icon(Icons.bar_chart),
              title: Text(l10n.get('reports')),
              children: [
                ListTile(
                  title: Text(l10n.get('salesAndPaymentsReport')),
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => SalesAndPaymentsReportPage(
                          businessId: widget.businessId,
                          sellerId: _filterSellerId,
                          user: widget.user,
                        ),
                      ),
                    );
                  },
                ),
                ListTile(
                  title: Text(l10n.get('salesByProduct')),
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => SalesByProductReportPage(
                          businessId: widget.businessId,
                          sellerId: _filterSellerId,
                          user: widget.user,
                        ),
                      ),
                    );
                  },
                ),
                ListTile(
                  title: Text(l10n.get('customerRanking')),
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => CustomerRankingPage(
                          businessId: widget.businessId,
                          sellerId: _filterSellerId,
                          user: widget.user,
                        ),
                      ),
                    );
                  },
                ),
                ListTile(
                  title: Text(l10n.get('accountsReceivable')),
                  onTap: () {
                    Navigator.pop(context); // Cierra el drawer
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => AccountsReceivablePage(
                          businessId: widget.businessId,
                          sellerId: _filterSellerId,
                          user: widget.user,
                        ),
                      ),
                    );
                  },
                ),
                ListTile(
                  title: Text(l10n.get('stockReport')),
                  onTap: () {
                    Navigator.pop(context); // Cierra el drawer
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => StockReportPage(
                          businessId: widget.businessId,
                          user: widget.user,
                        ),
                      ),
                    );
                  },
                ),
                if (widget.role == 'admin')
                  ListTile(
                    title: Text(l10n.get('sellerPerformance')),
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => SellerPerformancePage(
                            businessId: widget.businessId,
                            user: widget.user,
                          ),
                        ),
                      );
                    },
                  ),
              ],
            ),
            ExpansionTile(
              leading: const Icon(Icons.language),
              title: Text(l10n.get('language')),
              children: <Widget>[
                ListTile(
                  title: const Text('Español'),
                  onTap: () {
                    MyApp.setLocale(context, const Locale('es'));
                    Navigator.pop(context); // Cierra el drawer
                  },
                ),
                ListTile(
                  title: const Text('English'),
                  onTap: () {
                    MyApp.setLocale(context, const Locale('en'));
                    Navigator.pop(context); // Cierra el drawer
                  },
                ),
              ],
            ),
            const Divider(),
            if (widget.role == 'admin')
              ListTile(
                leading: const Icon(Icons.settings),
                title: Text(l10n.get('settings')),
                onTap: () {
                  Navigator.pop(context); // Cierra el drawer
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => SettingsPage(user: widget.user),
                    ),
                  );
                },
              ),
            ListTile(
              leading: const Icon(Icons.info_outline),
              title: Text(l10n.get('about')),
              onTap: () {
                Navigator.pop(context); // Cierra el drawer
                showDialog(
                  context: context,
                  builder: (context) {
                    return AlertDialog(
                      content: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Aquí puedes controlar el tamaño exacto sin restricciones
                          Image.asset('assets/icon.png', width: 100, height: 100),
                          const SizedBox(height: 16),
                          const Text('Seller App', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                          Text('${l10n.get('version')} 1.0.0'),
                          const Text('© 2025 Seller App'),
                          const SizedBox(height: 16),
                          Text(l10n.get('systemDescription'), textAlign: TextAlign.center),
                        ],
                      ),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(context), child: Text(l10n.get('close'))),
                      ],
                    );
                  },
                );
              },
            ),
          ],
        ),
      ),

      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [

          // --- SECCIÓN 1: KPIs DINÁMICOS ---
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: 1.6,
            children: [
              _buildTodaySalesCard(l10n),
              _buildMonthlySalesCard(l10n),
              _buildTotalDebtCard(l10n),
              _buildActiveCustomersCard(l10n),
            ],
          ),
          const SizedBox(height: 24),

          // --- SECCIÓN 3: GRÁFICO COMPARATIVO ---
          Text(l10n.get('salesVsPaymentsMonthly'), style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          _buildMonthlySalesChart(context),
          const SizedBox(height: 24),

          // --- SECCIÓN 4: VENTAS RECIENTES ---
          Text(l10n.get('recentSales'), style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          _buildRecentSalesList(l10n),
          const SizedBox(height: 24),
      
          // --- SECCIÓN 5: BAJO STOCK ---
          if (widget.role == 'admin') ...[
            Text(l10n.get('lowStockProductsTitle'), style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            _buildLowStockList(context),
            const SizedBox(height: 24),
          ],

           // --- SECCIÓN 2: REPORTES ---
          Text(l10n.get('reports'), style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          _buildReportsGrid(context, l10n),
          const SizedBox(height: 24),
        ],
      ),

      bottomNavigationBar: SellerBottomNavigationBar(
        user: widget.user,
        businessId: widget.businessId,
        sellerId: _filterSellerId,
        role: widget.role,
        currentIndex: 0,
        isMainPage: true,
      ),
    );
  }

  Widget _buildReportsGrid(BuildContext context, AppLocalizations l10n) {
    final List<_ReportItem> reportItems = [
      _ReportItem(l10n.get('salesAndPaymentsReport'), Icons.summarize, Colors.green, 
        () => Navigator.push(context, MaterialPageRoute(builder: (context) => SalesAndPaymentsReportPage(businessId: widget.businessId, sellerId: _filterSellerId, user: widget.user)))),
      _ReportItem(l10n.get('salesByProduct'), Icons.pie_chart, Colors.purple, 
        () => Navigator.push(context, MaterialPageRoute(builder: (context) => SalesByProductReportPage(businessId: widget.businessId, sellerId: _filterSellerId, user: widget.user)))),
      _ReportItem(l10n.get('customerRanking'), Icons.star, Colors.teal, 
        () => Navigator.push(context, MaterialPageRoute(builder: (context) => CustomerRankingPage(businessId: widget.businessId, sellerId: _filterSellerId, user: widget.user)))),
      _ReportItem(l10n.get('accountsReceivable'), Icons.money_off, Colors.red, 
        () => Navigator.push(context, MaterialPageRoute(builder: (context) => AccountsReceivablePage(businessId: widget.businessId, sellerId: _filterSellerId, user: widget.user)))),
      _ReportItem(l10n.get('stockReport'), Icons.inventory, Colors.orange, 
        () => Navigator.push(context, MaterialPageRoute(builder: (context) => StockReportPage(businessId: widget.businessId, user: widget.user)))),
    ];

    if (widget.role == 'admin') {
      reportItems.add(_ReportItem(l10n.get('sellerPerformance'), Icons.badge, Colors.indigo, 
        () => Navigator.push(context, MaterialPageRoute(builder: (context) => SellerPerformancePage(businessId: widget.businessId, user: widget.user)))));
    }

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
        childAspectRatio: 1.1,
      ),
      itemCount: reportItems.length,
      itemBuilder: (context, index) {
        final item = reportItems[index];
        return Card(
          elevation: 1,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: InkWell(
            onTap: item.onTap,
            borderRadius: BorderRadius.circular(12),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(item.icon, color: item.color, size: 28),
                const SizedBox(height: 4),
                Text(item.label, textAlign: TextAlign.center, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold), maxLines: 2, overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
        );
      },
    );
  }
  // --- WIDGETS PARA EL NUEVO DISEÑO ---

  Widget _buildTodaySalesCard(AppLocalizations l10n) {
    return StreamBuilder<QuerySnapshot>(
      stream: _todaySalesStream,
      builder: (context, snapshot) {
        double todayTotal = 0.0;
        if (snapshot.hasData) {
          for (var doc in snapshot.data!.docs) {
            todayTotal += (doc.data() as Map<String, dynamic>)['totalAmount'] as num;
          }
        }
        return _buildSummaryCard(
          title: l10n.get('todaySales'),
          value: '\$${NumberFormat.currency(locale: 'es_AR', symbol: '', decimalDigits: 0).format(todayTotal).trim()}',
          icon: Icons.today,
          color: Colors.blueAccent,
        );
      },
    );
  }

  Widget _buildActiveCustomersCard(AppLocalizations l10n) {
    return StreamBuilder<QuerySnapshot>(
      stream: _customersStream,
      builder: (context, snapshot) {
        final count = snapshot.hasData ? snapshot.data!.docs.length : 0;
        return _buildSummaryCard(
          title: l10n.get('customers'),
          value: count.toString(),
          icon: Icons.group,
          color: Colors.purple,
        );
      },
    );
  }



  Widget _buildMonthlySalesCard(AppLocalizations l10n) {
    return StreamBuilder<QuerySnapshot>(
      stream: _monthlySalesStream,
      builder: (context, snapshot) {
        double monthlySales = 0.0;
        final now = DateTime.now();
        if (snapshot.hasData) {
          for (var sale in snapshot.data!.docs) {
            final data = sale.data() as Map<String, dynamic>;
            final saleDate = (data['saleDate'] as Timestamp).toDate();
            if (saleDate.year == now.year && saleDate.month == now.month) {
              monthlySales += data['totalAmount'] as num? ?? 0.0;
            }
          }
        }
        final formattedSales = '\$${NumberFormat.currency(locale: 'es_AR', symbol: '', decimalDigits: 0).format(monthlySales).trim()}';
        return _buildSummaryCard(title: l10n.get('monthlySales'), value: formattedSales, icon: Icons.trending_up, color: Colors.green);
      },
    );
  }

  Widget _buildTotalDebtCard(AppLocalizations l10n) {
    return StreamBuilder<QuerySnapshot>(
      stream: _allSalesStream,
      builder: (context, salesSnapshot) {
        return StreamBuilder<QuerySnapshot>(
          stream: _allPaymentsStream,
          builder: (context, paymentsSnapshot) {
            if (!salesSnapshot.hasData || !paymentsSnapshot.hasData) {
              return _buildSummaryCard(title: l10n.get('totalDebt'), value: '...', icon: Icons.money_off, color: Colors.orange);
            }
            final sales = salesSnapshot.data!.docs;
            final payments = paymentsSnapshot.data!.docs;
            final paymentsPerSale = <String, double>{};
            for (var payment in payments) {
              final data = payment.data() as Map<String, dynamic>;
              if (data.containsKey('allocations') && data['allocations'] is Map) {
                final allocations = data['allocations'] as Map;
                allocations.forEach((saleId, amount) {
                  final sId = saleId.toString();
                  final amt = (amount as num).toDouble();
                  paymentsPerSale.update(sId, (value) => value + amt, ifAbsent: () => amt);
                });
              } else if (data['saleId'] != null) {
                final saleId = data['saleId'] as String;
                final amt = (data['amount'] as num).toDouble();
                paymentsPerSale.update(saleId, (value) => value + amt, ifAbsent: () => amt);
              }
            }
            double totalDebt = 0.0;
            for (var sale in sales) {
              final balance = (sale['totalAmount'] as num) - (paymentsPerSale[sale.id] ?? 0.0);
              if (balance > 0.01) totalDebt += balance;
            }
            return _buildSummaryCard(
              title: l10n.get('totalDebt'),
              value: '\$${NumberFormat.currency(locale: 'es_AR', symbol: '', decimalDigits: 0).format(totalDebt).trim()}',
              icon: Icons.money_off,
              color: Colors.orange,
            );
          },
        );
      },
    );
  }


  Widget _buildMonthlySalesChart(BuildContext context) {
    return SizedBox(
      height: 200,
      child: Card(
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: StreamBuilder<QuerySnapshot>(
            stream: _monthlySalesStream,
            builder: (context, snapshot) {
              return StreamBuilder<QuerySnapshot>(
                stream: _monthlyPaymentsStream,
                builder: (context, paymentsSnapshot) {
                  if (!snapshot.hasData || !paymentsSnapshot.hasData) return const Center(child: CircularProgressIndicator());

                  final sales = snapshot.data!.docs;
                  final payments = paymentsSnapshot.data!.docs;
                  final now = DateTime.now();
                  
                  // 12 meses (0..11)
                  const monthsCount = 12;
                  final monthlySales = <int, double>{};
                  final monthlyPayments = <int, double>{};

                  int getMonthIndex(DateTime date) {
                    if (date.year != now.year) return -1;
                    return date.month - 1; // Enero = 0, Diciembre = 11
                  }

                  for (var sale in sales) {
                    final saleDate = (sale['saleDate'] as Timestamp).toDate();
                    final index = getMonthIndex(saleDate);
                    if (index >= 0 && index < monthsCount) {
                      monthlySales.update(index, (value) => value + (sale['totalAmount'] as num), ifAbsent: () => (sale['totalAmount'] as num).toDouble());
                    }
                  }

                  for (var payment in payments) {
                    final paymentDate = (payment['date'] as Timestamp).toDate();
                    final index = getMonthIndex(paymentDate);
                    if (index >= 0 && index < monthsCount) {
                      monthlyPayments.update(index, (value) => value + (payment['amount'] as num), ifAbsent: () => (payment['amount'] as num).toDouble());
                    }
                  }

                  final barGroups = List.generate(monthsCount, (index) {
                    final salesTotal = monthlySales[index] ?? 0;
                    final paymentsTotal = monthlyPayments[index] ?? 0;
                    
                    return BarChartGroupData(
                      x: index,
                      barsSpace: 4,
                      barRods: [
                        BarChartRodData(
                          toY: salesTotal,
                          color: Colors.blue,
                          width: 8,
                          borderRadius: const BorderRadius.only(topLeft: Radius.circular(4), topRight: Radius.circular(4)),
                        ),
                        BarChartRodData(
                          toY: paymentsTotal,
                          color: Colors.green,
                          width: 8,
                          borderRadius: const BorderRadius.only(topLeft: Radius.circular(4), topRight: Radius.circular(4)),
                        ),
                      ],
                    );
                  });

                  return BarChart(
                    BarChartData(
                      alignment: BarChartAlignment.spaceAround,
                      barGroups: barGroups,
                      titlesData: FlTitlesData(
                        bottomTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            getTitlesWidget: (value, meta) {
                              final index = value.toInt();
                              if (index >= 0 && index < monthsCount) {
                                final date = DateTime(now.year, index + 1, 1);
                                return Padding(
                                  padding: const EdgeInsets.only(top: 4.0),
                                  child: Text(DateFormat.MMM(AppLocalizations.of(context).locale.languageCode).format(date), style: const TextStyle(fontSize: 10)),
                                );
                              }
                              return const SizedBox.shrink();
                            },
                          ),
                        ),
                        leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                        topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                        rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                      ),
                      borderData: FlBorderData(show: false),
                      gridData: const FlGridData(show: false),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ),
    );
  }



  Widget _buildLowStockList(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return StreamBuilder<QuerySnapshot>(
      stream: _lowStockProductsStream,
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const SizedBox.shrink();
        final lowStockProducts = snapshot.data!.docs.where((doc) {
          final data = doc.data() as Map<String, dynamic>;
          final stock = (data['stock'] as num?) ?? 0;
          final safetyStock = (data['safety_stock'] as num?) ?? 5;
          return stock <= safetyStock;
        }).toList();

        if (lowStockProducts.isEmpty) {
          return Card(child: ListTile(leading: const Icon(Icons.check_circle_outline, color: Colors.green), title: Text(l10n.get('allStockInOrder'))));
        }

        return ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: lowStockProducts.length > 5 ? 5 : lowStockProducts.length, // Limitar a 5 para no alargar mucho
          itemBuilder: (context, index) {
            final product = lowStockProducts[index];
            final data = product.data() as Map<String, dynamic>;
            return Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                leading: const Icon(Icons.warning_amber_rounded, color: Colors.amber),
                title: Text(data['name'] ?? l10n.get('noName')),
                trailing: Text(l10n.get('stockValue').replaceFirst('{value}', (data['stock'] ?? 0).toString()), style: const TextStyle(fontWeight: FontWeight.bold)),
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => StockPage(user: widget.user, businessId: widget.businessId))),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildRecentSalesList(AppLocalizations l10n) {
    return StreamBuilder<QuerySnapshot>(
      stream: _todaySalesStream,
      builder: (context, snapshot) {
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return Card(child: ListTile(leading: const Icon(Icons.info_outline), title: Text(l10n.get('noSales'))));
        }
        final sales = snapshot.data!.docs.take(5).toList();
        return ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: sales.length,
          itemBuilder: (context, index) {
            final sale = sales[index];
            final data = sale.data() as Map<String, dynamic>;
            final customerName = data['customerName'] ?? l10n.get('noName');
            final totalAmount = data['totalAmount'] ?? 0;
            final saleDate = data['saleDate'] is Timestamp ? (data['saleDate'] as Timestamp).toDate() : DateTime.now();
            return Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                leading: const Icon(Icons.receipt, color: Colors.blue),
                title: Text(customerName),
                subtitle: Text(DateFormat('dd/MM/yyyy HH:mm').format(saleDate)),
                trailing: Text('\$${NumberFormat.currency(locale: 'es_AR', symbol: '', decimalDigits: 0).format(totalAmount).trim()}', style: const TextStyle(fontWeight: FontWeight.bold)),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildSummaryCard({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    final textTheme = Theme.of(context).textTheme;
    return Card(
      elevation: 1.5,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 24, color: color),
            const SizedBox(height: 8),
            Flexible(
              child: Text(
                value,
                style: textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Flexible(
              child: Text(
                title,
                style: textTheme.bodyMedium,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Página intermedia para manejar el cierre de sesión de forma segura
/// y evitar PlatformExceptions por condiciones de carrera.
class SigningOutPage extends StatefulWidget {
  const SigningOutPage({super.key});

  @override
  State<SigningOutPage> createState() => _SigningOutPageState();
}

class _SigningOutPageState extends State<SigningOutPage> {
  @override
  void initState() {
    super.initState();
    _signOut();
  }

  Future<void> _signOut() async {
    try {
      await GoogleSignIn().signOut();
      await FirebaseAuth.instance.signOut();
      if (mounted) {
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
    } catch (e) {
      // Fallback por si ocurre un error inesperado
      if (mounted) {
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(child: CircularProgressIndicator()),
    );
  }
}
