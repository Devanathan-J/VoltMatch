import 'package:flutter/material.dart';
import 'services/catalog_service.dart';
import 'screens/home_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await CatalogService.loadCatalog();
  runApp(const VoltMatchApp());
}

class VoltMatchApp extends StatelessWidget {
  const VoltMatchApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'VoltMatch',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF101419),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF22BFA2),
          secondary: Color(0xFF3DDDB5),
          surface: Color(0xFF161D23),
          error: Color(0xFFEF6464),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF101419),
          elevation: 0,
        ),
      ),
      home: const HomeScreen(),
    );
  }
}