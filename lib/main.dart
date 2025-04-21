import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'screens/login_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: const FirebaseOptions(
      apiKey: "AIzaSyCNgMAa5Y0ldESp2tm-npejp3QhdVvrCH4",
      authDomain: "marksheet-project-f6255.firebaseapp.com",
      databaseURL: "https://marksheet-project-f6255-default-rtdb.firebaseio.com",
      projectId: "marksheet-project-f6255",
      storageBucket: "marksheet-project-f6255.firebasestorage.app",
      messagingSenderId: "570581629954",
      appId: "1:570581629954:web:b3868f3420179321847b1b",
      measurementId: "G-DZ5EYE0EDW",
    ),
  );
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Student Marksheet System',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: const LoginScreen(),
    );
  }
}
