import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'services/background_service.dart';
import 'presentation/screens/splash_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 백그라운드 서비스 초기화
  await initBackgroundService();

  runApp(const UbiTokenApp());
}

class UbiTokenApp extends StatelessWidget {
  const UbiTokenApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Ubi-Token',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1B3A5C),
        ),
        useMaterial3: true,
        fontFamily: 'pretendard',
      ),
      home: const SplashScreen(),
    );
  }
}