import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'providers/keuangan_provider.dart';
import 'screens/login_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => KeuanganProvider()),
      ],
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Helena Finance',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        fontFamily: 'Arial',
        useMaterial3: true,
      ),
      home: const LoginScreen(),
    );
  }
}