import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'bootstrap/ocr_template_bootstrap.dart';
import 'firebase_options.dart';
import 'utils/constants.dart';
import 'screens/login_screen.dart';
import 'screens/home_screen.dart';
import 'services/sync_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (!Platform.isWindows) {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  }
  await OcrTemplateBootstrap.ensureBundledTemplates();
  runApp(const ReceiptIQApp());
}

class ReceiptIQApp extends StatelessWidget {
  const ReceiptIQApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: AppConstants.appName,
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: AppColors.primary,
          primary: AppColors.primary,
          secondary: AppColors.accent,
          surface: AppColors.surface,
          error: AppColors.error,
        ),
        scaffoldBackgroundColor: AppColors.background,
        appBarTheme: AppBarTheme(
          backgroundColor: AppColors.primary,
          foregroundColor: AppColors.surface,
          elevation: 0,
          titleTextStyle: GoogleFonts.poppins(
            fontSize: 20,
            fontWeight: FontWeight.w600,
            color: AppColors.surface,
          ),
        ),
        cardTheme: CardThemeData(
          color: AppColors.surface,
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        floatingActionButtonTheme: const FloatingActionButtonThemeData(
          backgroundColor: AppColors.accent,
          foregroundColor: AppColors.surface,
        ),
        textTheme: GoogleFonts.poppinsTextTheme(),
        useMaterial3: true,
      ),
      home: const AuthWrapper(),
      routes: {
        '/home': (context) => const HomeScreen(),
        '/login': (context) => const LoginScreen(),
      },
    );
  }
}

class AuthWrapper extends StatelessWidget {
  const AuthWrapper({super.key});

  @override
  Widget build(BuildContext context) {
    // Windows has no Firebase config — skip auth and go straight to HomeScreen
    if (Platform.isWindows) return const HomeScreen();

    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        if (snapshot.hasData) {
          SyncService.instance.handleLogin(snapshot.data!.uid);
          return const HomeScreen();
        }
        return const LoginScreen();
      },
    );
  }
}
