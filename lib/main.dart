import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'firebase_options.dart';
import 'theme/app_theme.dart';
import 'login.dart';
import 'pages/landing_page.dart';
import 'register.dart';
import 'pages/home_page.dart';
import 'pages/settings.dart';
import 'pages/forgot_password.dart';
import 'pages/password_change.dart';
import 'pages/swipe_page.dart';
import 'pages/explore.dart';
import 'pages/list_page.dart';
import 'pages/profile.dart';
import 'pages/movies.dart';
import 'pages/series.dart';
import 'package:flutter_web_plugins/url_strategy.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  // usePathUrlStrategy(); // Disabled for GitHub Pages compatibility

  // Initialize Firebase
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    debugPrint('Firebase initialized successfully');
  } catch (e) {
    debugPrint('Error initializing Firebase: $e');
  }

  // Load environment
  await dotenv.load(fileName: 'assets/credentials.env').catchError((err) {
    debugPrint('Could not load .env file: $err');
  });

  final supabaseUrl = dotenv.env['SUPABASE_URL'];
  final supabaseAnonKey = dotenv.env['SUPABASE_ANON_KEY'];

  if (supabaseUrl != null && supabaseAnonKey != null) {
    await Supabase.initialize(
      url: supabaseUrl,
      anonKey: supabaseAnonKey,
      debug: true,
    );
    debugPrint('Supabase initialized (Debug Mode)');
  } else {
    debugPrint('Supabase not initialized: missing keys');
  }

  // Listen for password recovery event (Standard Supabase)
  Supabase.instance.client.auth.onAuthStateChange.listen((data) {
    final event = data.event;
    debugPrint('MAIN: AuthEvent: $event');
    if (event == AuthChangeEvent.passwordRecovery) {
      debugPrint('MAIN: Password Recovery Event Detected! Navigating...');
      navigatorKey.currentState?.pushNamedAndRemoveUntil(
        '/password_change',
        (route) => false,
      );
    }
  });

  runApp(const MyApp());
}

final ValueNotifier<ThemeMode> themeNotifier = ValueNotifier(ThemeMode.dark);

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: themeNotifier,
      builder: (context, currentMode, child) {
        return MaterialApp(
          title: 'ViewPick',
          navigatorKey: navigatorKey,
          theme: AppTheme.lightTheme,
          darkTheme: AppTheme.darkTheme,
          themeMode: currentMode,
          initialRoute: '/',
          navigatorObservers: [
            FirebaseAnalyticsObserver(analytics: FirebaseAnalytics.instance),
          ],
          onGenerateRoute: (settings) {
            // AUTH GUARD
            final session = Supabase.instance.client.auth.currentSession;
            final isPublicRoute =
                settings.name == '/' ||
                settings.name == '/landing' ||
                settings.name == '/login' ||
                settings.name == '/register' ||
                settings.name == '/forgot_password' ||
                settings.name == '/password_change' ||
                settings.name == '/home' ||
                settings.name == '/explore' ||
                (settings.name != null && settings.name!.startsWith('/movie/')) ||
                (settings.name != null && settings.name!.startsWith('/series/'));

            if (session == null && !isPublicRoute) {
              return MaterialPageRoute(builder: (context) => const LoginPage());
            }

            if (settings.name == '/swipe')
              return MaterialPageRoute(builder: (_) => const SwipePage());
            if (settings.name == '/home')
              return MaterialPageRoute(builder: (_) => HomePage());
            if (settings.name == '/explore')
              return MaterialPageRoute(builder: (_) => const ExplorePage());
            if (settings.name == '/list')
              return MaterialPageRoute(builder: (_) => const ListPage());
            if (settings.name == '/profile')
              return MaterialPageRoute(builder: (_) => const ProfilePage());
            if (settings.name == '/settings')
              return MaterialPageRoute(builder: (_) => const SettingsPage());

            if (settings.name != null && settings.name!.startsWith('/movie/')) {
              final idStr = settings.name!.replaceFirst('/movie/', '');
              final id = int.tryParse(idStr);
              if (id != null)
                return MaterialPageRoute(
                  builder: (_) => MoviePage(movieId: id),
                );
            }
            if (settings.name != null &&
                settings.name!.startsWith('/series/')) {
              final idStr = settings.name!.replaceFirst('/series/', '');
              final id = int.tryParse(idStr);
              if (id != null)
                return MaterialPageRoute(builder: (_) => SeriesPage(tvId: id));
            }

            return null; // fallback to routes table
          },
          routes: {
            '/': (context) => const AuthHandler(),
            '/landing': (context) => const LandingPage(),
            '/login': (context) => const LoginPage(),
            '/register': (context) => const RegisterPage(),
            '/forgot_password': (context) => const ForgotPasswordPage(),
            '/password_change': (context) => const PasswordChangePage(),
          },
        );
      },
    );
  }
}

class AuthHandler extends StatefulWidget {
  const AuthHandler({super.key});

  @override
  State<AuthHandler> createState() => _AuthHandlerState();
}

class _AuthHandlerState extends State<AuthHandler> {
  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AuthState>(
      stream: Supabase.instance.client.auth.onAuthStateChange,
      builder: (context, snapshot) {
        if (snapshot.hasData) {
          final session = snapshot.data?.session;
          if (session != null) {
            return HomePage();
          }
        }
        // Show landing page for unauthenticated users
        return const LandingPage();
      },
    );
  }
}
