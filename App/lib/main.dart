import 'package:flutter/material.dart';
import 'package:workmanager/workmanager.dart';
import 'package:flutter/foundation.dart';
import 'services/background_worker.dart';
import 'package:provider/provider.dart';
// removed unused import
import 'services/api_service.dart';
import 'screens/map_page.dart';
import 'screens/landmarks_page.dart';
import 'screens/activity_page.dart';
import 'screens/add_view_page.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  Workmanager().initialize(callbackDispatcher);
  // register a periodic sync (runs approx every 15 minutes on Android)
  // Avoid registering periodic background tasks during debug to prevent
  // headless/background Flutter engines from coexisting with the main
  // engine (which can cause plugin lifecycle conflicts like Geolocator).
  if (!kDebugMode) {
    try {
      Workmanager().registerPeriodicTask(
        'periodic-sync',
        kSyncTask,
        frequency: const Duration(minutes: 15),
      );
    } catch (_) {}
  }

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) {
        final svc = ApiService();
        svc.startVisitWatcher();
        return svc;
      },
      child: MaterialApp(
        title: 'Smart Geo-Tagged Landmarks',
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
          useMaterial3: true,
        ),
        home: const HomeShell(),
      ),
    );
  }
}

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _selectedIndex = 0;

  static const List<Widget> _pages = <Widget>[
    MapPage(),
    LandmarksPage(),
    ActivityPage(),
    AddViewPage(),
  ];

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(child: _pages[_selectedIndex]),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: _onItemTapped,
        destinations: const [
          NavigationDestination(icon: Icon(Icons.map), label: 'Map'),
          NavigationDestination(icon: Icon(Icons.list), label: 'Landmarks'),
          NavigationDestination(icon: Icon(Icons.history), label: 'Activity'),
          NavigationDestination(icon: Icon(Icons.add), label: 'Add/View'),
        ],
      ),
      floatingActionButton: kDebugMode
          ? FloatingActionButton.extended(
              onPressed: () async {
                try {
                  await Workmanager().registerOneOffTask(
                    'debug-sync-${DateTime.now().millisecondsSinceEpoch}',
                    kSyncTask,
                  );
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Background sync scheduled')),
                  );
                } catch (e) {
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Failed to schedule sync: $e')),
                  );
                }
              },
              label: const Text('Run Sync Now'),
              icon: const Icon(Icons.sync),
            )
          : null,
    );
  }
}
