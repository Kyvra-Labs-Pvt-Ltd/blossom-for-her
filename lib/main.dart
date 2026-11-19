import 'dart:async';
import 'dart:math' as math;
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:kyvra_app/chat/chat_api.dart';
import 'package:kyvra_app/chat/local_chat_responder.dart';
import 'package:kyvra_app/lfa_ble_reader.dart';
import 'package:kyvra_app/reports/test_record.dart';
import 'package:kyvra_app/reports/test_reports_screen.dart';
import 'package:video_player/video_player.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
    ),
  );
  runApp(const BlossomApp());
}

/// Stores onboarding details on this device. Sign-in remains a demo flow
/// until a real authentication service is configured.
class BlossomProfileStore {
  static const _channel = MethodChannel('blossom/profile_store');

  static String _key(String email) => email.trim().toLowerCase();

  static Future<Map<String, dynamic>?> load(String email) async {
    final raw = await _channel.invokeMethod<String>('loadProfile', {
      'email': _key(email),
    });
    if (raw == null || raw.isEmpty) return null;
    return jsonDecode(raw) as Map<String, dynamic>;
  }

  static Future<void> save(String email, Map<String, dynamic> profile) async {
    await _channel.invokeMethod<void>('saveProfile', {
      'email': _key(email),
      'profile': jsonEncode(profile),
    });
  }

  static Future<Map<String, dynamic>?> loadTrackingData(String email) async {
    final raw = await _channel.invokeMethod<String>('loadTrackingData', {
      'email': _key(email),
    });
    if (raw == null || raw.isEmpty) return null;
    return jsonDecode(raw) as Map<String, dynamic>;
  }

  static Future<void> saveTrackingData(
    String email,
    Map<String, dynamic> data,
  ) async {
    await _channel.invokeMethod<void>('saveTrackingData', {
      'email': _key(email),
      'data': jsonEncode(data),
    });
  }
}

// ---------------------------------------------------------------------------
// EDITORIAL BOTANICAL PALETTE & TYPOGRAPHY
// ---------------------------------------------------------------------------
const ink = Color(0xFF4A3740); // Soft plum charcoal
const deepInk = Color(0xFF34262C);
const alabaster = Color(0xFFFFFAF8); // Warm ivory paper
const sand = Color(0xFFFBF0F1); // Blush card surface
const sandDark = Color(0xFFF3E0E4);
const borderStone = Color(0xFFEBD8DE);
const stoneMuted = Color(0xFF8C7A81);

// Phase & Hormone Accents
const terracotta = Color(0xFFB84E70); // Rose / primary accent
const roseClay = Color(0xFFD98297); // Menstrual / E3G
const sageLeaf = Color(0xFF768F7A); // FSH / Follicular
const lutealIndigo = Color(0xFF9585A1); // PdG / Luteal
const goldWarm = Color(0xFFD8B185);

TextStyle serifStyle({
  double size = 24,
  FontWeight weight = FontWeight.w600,
  Color color = ink,
  double height = 1.15,
  double letterSpacing = -0.4,
  FontStyle? fontStyle,
}) => GoogleFonts.fraunces(
  fontSize: size,
  fontWeight: weight,
  color: color,
  height: height,
  letterSpacing: letterSpacing,
  fontStyle: fontStyle,
);

TextStyle sansStyle({
  double size = 14,
  FontWeight weight = FontWeight.w500,
  Color color = ink,
  double height = 1.4,
  double letterSpacing = 0,
}) => GoogleFonts.plusJakartaSans(
  fontSize: size,
  fontWeight: weight,
  color: color,
  height: height,
  letterSpacing: letterSpacing,
);

class BlossomApp extends StatelessWidget {
  const BlossomApp({super.key});

  @override
  Widget build(BuildContext context) {
    final baseTheme = ThemeData(
      useMaterial3: true,
      scaffoldBackgroundColor: alabaster,
      colorScheme: ColorScheme.fromSeed(
        seedColor: terracotta,
        primary: terracotta,
        secondary: sageLeaf,
        tertiary: roseClay,
        surface: alabaster,
      ),
      textTheme: GoogleFonts.plusJakartaSansTextTheme(),
      appBarTheme: const AppBarTheme(
        backgroundColor: alabaster,
        foregroundColor: ink,
        elevation: 0,
      ),
    );

    return MaterialApp(
      title: 'Blossom • Cycle & Hormone Intelligence',
      debugShowCheckedModeBanner: false,
      theme: baseTheme,
      home: const BlossomVideoIntroScreen(),
    );
  }
}

class BlossomVideoIntroScreen extends StatefulWidget {
  const BlossomVideoIntroScreen({super.key});

  static const videoPath = 'assets/videos/blossom_intro.mp4';
  static const introDuration = Duration(milliseconds: 3600);

  @override
  State<BlossomVideoIntroScreen> createState() =>
      _BlossomVideoIntroScreenState();
}

class _BlossomVideoIntroScreenState extends State<BlossomVideoIntroScreen> {
  late final VideoPlayerController _videoController;
  Timer? _introTimer;
  bool _ready = false;
  bool _hasTransitioned = false;

  @override
  void initState() {
    super.initState();
    _videoController = VideoPlayerController.asset(
      BlossomVideoIntroScreen.videoPath,
    );
    _initializeAndPlay();
  }

  Future<void> _initializeAndPlay() async {
    try {
      await _videoController.initialize();
      if (!mounted) return;
      await _videoController.setVolume(0);
      await _videoController.play();
      if (!mounted) return;
      setState(() => _ready = true);
      _introTimer = Timer(
        BlossomVideoIntroScreen.introDuration,
        _showWelcomeScreen,
      );
    } catch (_) {
      _showWelcomeScreen();
    }
  }

  void _showWelcomeScreen() {
    if (!mounted || _hasTransitioned) return;
    _hasTransitioned = true;
    _introTimer?.cancel();
    Navigator.of(context).pushReplacement(
      PageRouteBuilder<void>(
        pageBuilder: (_, animation, secondaryAnimation) =>
            const WelcomeScreen(),
        transitionDuration: const Duration(milliseconds: 350),
        transitionsBuilder: (_, animation, secondaryAnimation, child) =>
            FadeTransition(opacity: animation, child: child),
      ),
    );
  }

  @override
  void dispose() {
    _introTimer?.cancel();
    _videoController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: alabaster,
      body: _ready
          ? SizedBox.expand(
              child: ClipRect(
                child: FittedBox(
                  fit: BoxFit.cover,
                  child: SizedBox(
                    width: _videoController.value.size.width,
                    height: _videoController.value.size.height,
                    child: VideoPlayer(_videoController),
                  ),
                ),
              ),
            )
          : const ColoredBox(color: alabaster),
    );
  }
}

// ---------------------------------------------------------------------------
// WELCOME SCREEN (BLOSSOM INTRO ARTWORK)
// ---------------------------------------------------------------------------
class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key});

  static const String backgroundImagePath = 'assets/images/blossom_intro.png';

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _buttonCtrl;
  late final Animation<double> _buttonFade;
  late final Animation<Offset> _buttonSlide;
  Timer? _buttonDelay;

  @override
  void initState() {
    super.initState();
    _buttonCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 450),
    );
    final entrance = CurvedAnimation(
      parent: _buttonCtrl,
      curve: Curves.easeOutCubic,
    );
    _buttonFade = entrance;
    _buttonSlide = Tween<Offset>(
      begin: const Offset(0, 0.18),
      end: Offset.zero,
    ).animate(entrance);
    _buttonDelay = Timer(const Duration(seconds: 1), () {
      if (mounted) _buttonCtrl.forward();
    });
  }

  @override
  void dispose() {
    _buttonDelay?.cancel();
    _buttonCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: alabaster,
      body: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset(
            WelcomeScreen.backgroundImagePath,
            fit: BoxFit.cover,
            alignment: Alignment.center,
            semanticLabel: 'Blossom for Her floral introduction artwork',
            errorBuilder: (context, error, stackTrace) => const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [alabaster, sand, sandDark],
                ),
              ),
            ),
          ),
          SafeArea(
            child: Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 22),
                child: FadeTransition(
                  opacity: _buttonFade,
                  child: SlideTransition(
                    position: _buttonSlide,
                    child: SizedBox(
                      width: double.infinity,
                      height: 58,
                      child: ElevatedButton(
                        onPressed: () => Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const AuthScreen()),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: terracotta,
                          foregroundColor: Colors.white,
                          shape: const StadiumBorder(),
                          elevation: 6,
                          shadowColor: terracotta.withAlpha(90),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              'Begin your journey',
                              style: sansStyle(
                                color: Colors.white,
                                size: 15,
                                weight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(width: 10),
                            const Icon(Icons.arrow_forward_rounded, size: 18),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class BotanicalOrb extends StatelessWidget {
  final double size;
  final Color color;
  const BotanicalOrb({super.key, required this.size, required this.color});

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      gradient: RadialGradient(
        colors: [color.withAlpha(89), color.withAlpha(0)],
      ),
    ),
  );
}

class FlowerMark extends StatelessWidget {
  final double size;
  const FlowerMark({super.key, this.size = 34});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size * 1.15,
      child: Stack(
        alignment: Alignment.center,
        children: [
          for (int i = 0; i < 6; i++)
            Transform.rotate(
              angle: i * (math.pi / 3),
              child: Align(
                alignment: const Alignment(0, -0.46),
                child: Container(
                  width: size * 0.3,
                  height: size * 0.48,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [terracotta, roseClay],
                    ),
                    borderRadius: BorderRadius.circular(30),
                  ),
                ),
              ),
            ),
          CircleAvatar(
            radius: size * 0.12,
            backgroundColor: const Color(0xFFF6E3BA),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// AUTH SCREEN
// ---------------------------------------------------------------------------
class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});
  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final name = TextEditingController(),
      email = TextEditingController(),
      password = TextEditingController();
  bool login = false, hide = true;

  void _exploreDemo() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => BlossomDashboard(
          name: 'Aria',
          profileEmail: '',
          age: 28,
          cycleLength: 28,
          periodLength: 5,
          lastPeriod: DateTime.now().subtract(const Duration(days: 11)),
          goals: const [
            'Understand my cycle',
            'Monitor hormone trends',
            'Explore fertile days',
          ],
        ),
      ),
    );
  }

  void _showGoogleSignInNotConfigured() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Google sign-in is not connected in this demo yet. Use email or explore the demo.',
        ),
      ),
    );
  }

  @override
  void dispose() {
    name.dispose();
    email.dispose();
    password.dispose();
    super.dispose();
  }

  Future<void> submit() async {
    if (email.text.trim().isEmpty ||
        password.text.length < 6 ||
        (!login && name.text.trim().isEmpty)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Enter your details. Password must be at least 6 characters.',
          ),
        ),
      );
      return;
    }
    if (!email.text.contains('@')) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a valid email address.')),
      );
      return;
    }
    final emailAddress = email.text.trim();
    if (login) {
      Map<String, dynamic>? saved;
      try {
        saved = await BlossomProfileStore.load(emailAddress);
      } on PlatformException {
        saved = null;
      } on MissingPluginException {
        saved = null;
      }
      if (!mounted) return;
      final profile = saved;
      if (profile != null) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => BlossomDashboard(
              name: profile['name'] as String? ?? 'Aria',
              profileEmail: emailAddress,
              age: (profile['age'] as num?)?.toInt() ?? 27,
              cycleLength: (profile['cycleLength'] as num?)?.toInt() ?? 28,
              periodLength: (profile['periodLength'] as num?)?.toInt() ?? 5,
              lastPeriod:
                  DateTime.tryParse(profile['lastPeriod'] as String? ?? '') ??
                  DateTime.now().subtract(const Duration(days: 11)),
              goals:
                  (profile['goals'] as List<dynamic>?)?.cast<String>() ??
                  const [],
            ),
          ),
        );
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Complete setup once on this device to save your profile for next time.',
          ),
        ),
      );
    }
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => OnboardingScreen(
          initialName: name.text.trim().isEmpty ? 'Aria' : name.text.trim(),
          profileEmail: emailAddress,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Stack(
        children: [
          const Positioned(
            right: -80,
            top: -80,
            child: BotanicalOrb(size: 250, color: terracotta),
          ),
          SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(25, 12, 25, 28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(
                    Icons.arrow_back_ios_new_rounded,
                    color: ink,
                    size: 18,
                  ),
                ),
                const SizedBox(height: 8),
                const Center(child: FlowerMark(size: 36)),
                const SizedBox(height: 8),
                Center(
                  child: Text(
                    'Blossom',
                    style: serifStyle(size: 32, color: ink),
                  ),
                ),
                const SizedBox(height: 4),
                Center(
                  child: Text(
                    'YOUR PERSONAL CYCLE COMPANION',
                    style: sansStyle(
                      color: stoneMuted,
                      size: 9,
                      weight: FontWeight.w700,
                      letterSpacing: 1.6,
                    ),
                  ),
                ),
                const SizedBox(height: 32),
                Text(
                  login ? 'Welcome back' : 'Create your profile',
                  style: serifStyle(size: 30, color: ink),
                ),
                const SizedBox(height: 6),
                Text(
                  login ? 'Return to your saved cycle profile on this device.' : 'Create your profile to save your details on this device.',
                  style: sansStyle(color: stoneMuted, size: 13),
                ),
                const SizedBox(height: 24),
                if (!login) ...[
                  const FieldLabel('Preferred name'),
                  const SizedBox(height: 7),
                  StyledField(
                    controller: name,
                    hint: 'What should we call you?',
                    icon: Icons.person_outline_rounded,
                  ),
                  const SizedBox(height: 15),
                ],
                const FieldLabel('Email address'),
                const SizedBox(height: 7),
                StyledField(
                  controller: email,
                  hint: 'you@example.com',
                  icon: Icons.mail_outline_rounded,
                  type: TextInputType.emailAddress,
                ),
                const SizedBox(height: 15),
                const FieldLabel('Password'),
                const SizedBox(height: 7),
                StyledField(
                  controller: password,
                  hint: 'At least 6 characters',
                  icon: Icons.lock_outline_rounded,
                  obscure: hide,
                  suffix: IconButton(
                    onPressed: () => setState(() => hide = !hide),
                    icon: Icon(
                      hide
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                      color: ink,
                      size: 19,
                    ),
                  ),
                ),
                const SizedBox(height: 26),
                PrimaryButton(
                  label: login ? 'Sign In' : 'Continue to setup',
                  onTap: submit,
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    const Expanded(child: Divider(color: borderStone)),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Text(
                        'OR',
                        style: sansStyle(
                          color: stoneMuted,
                          size: 10,
                          weight: FontWeight.w700,
                          letterSpacing: 1,
                        ),
                      ),
                    ),
                    const Expanded(child: Divider(color: borderStone)),
                  ],
                ),
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: OutlinedButton.icon(
                    onPressed: _showGoogleSignInNotConfigured,
                    icon: const Text(
                      'G',
                      style: TextStyle(
                        color: Color(0xFF4285F4),
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    label: Text(
                      'Continue with Google',
                      style: sansStyle(
                        size: 13,
                        weight: FontWeight.w700,
                        color: ink,
                      ),
                    ),
                    style: OutlinedButton.styleFrom(
                      backgroundColor: Colors.white,
                      side: const BorderSide(color: borderStone),
                      shape: const StadiumBorder(),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Center(
                  child: TextButton.icon(
                    onPressed: _exploreDemo,
                    icon: const Icon(Icons.explore_outlined, size: 17),
                    label: Text(
                      'Explore Demo',
                      style: sansStyle(
                        color: terracotta,
                        size: 13,
                        weight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
                Center(
                  child: Text(
                    'Take a look around with a sample cycle profile.',
                    textAlign: TextAlign.center,
                    style: sansStyle(color: stoneMuted, size: 11),
                  ),
                ),
                const SizedBox(height: 10),
                Center(
                  child: TextButton(
                    onPressed: () => setState(() => login = !login),
                    child: Text(
                      login
                          ? 'New to Blossom? Create an account'
                          : 'Already have an account? Sign in',
                      style: sansStyle(
                        color: terracotta,
                        size: 13,
                        weight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

class FieldLabel extends StatelessWidget {
  final String text;
  const FieldLabel(this.text, {super.key});
  @override
  Widget build(BuildContext context) => Text(
    text,
    style: sansStyle(size: 12, weight: FontWeight.w700, color: ink),
  );
}

class StyledField extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final IconData icon;
  final TextInputType type;
  final bool obscure;
  final Widget? suffix;

  const StyledField({
    super.key,
    required this.controller,
    required this.hint,
    required this.icon,
    this.type = TextInputType.text,
    this.obscure = false,
    this.suffix,
  });

  @override
  Widget build(BuildContext context) => TextField(
    controller: controller,
    keyboardType: type,
    obscureText: obscure,
    style: sansStyle(color: ink, size: 14, weight: FontWeight.w600),
    decoration: InputDecoration(
      hintText: hint,
      hintStyle: sansStyle(color: stoneMuted.withAlpha(153), size: 13),
      prefixIcon: Icon(icon, color: stoneMuted, size: 20),
      suffixIcon: suffix,
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(vertical: 17, horizontal: 16),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: borderStone),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: borderStone),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: terracotta, width: 1.6),
      ),
    ),
  );
}

class PrimaryButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  final Color? backgroundColor;
  const PrimaryButton({
    super.key,
    required this.label,
    required this.onTap,
    this.backgroundColor,
  });

  @override
  Widget build(BuildContext context) => SizedBox(
    width: double.infinity,
    height: 56,
    child: ElevatedButton(
      onPressed: onTap,
      style: ElevatedButton.styleFrom(
        backgroundColor: backgroundColor ?? ink,
        foregroundColor: alabaster,
        shape: const StadiumBorder(),
        elevation: 0,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            label,
            style: sansStyle(
              color: alabaster,
              size: 14,
              weight: FontWeight.w700,
            ),
          ),
          const SizedBox(width: 8),
          const Icon(Icons.arrow_forward_rounded, size: 17),
        ],
      ),
    ),
  );
}

// ---------------------------------------------------------------------------
// ONBOARDING SCREEN
// ---------------------------------------------------------------------------
class OnboardingScreen extends StatefulWidget {
  final String initialName;
  final String profileEmail;
  const OnboardingScreen({
    super.key,
    this.initialName = '',
    this.profileEmail = '',
  });
  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  int step = 0, age = 27, cycleLength = 28, periodLength = 5;
  late final TextEditingController name;
  DateTime lastPeriod = DateTime.now().subtract(const Duration(days: 11));
  String regularity = 'Regular';
  final Set<String> goals = {'Understand my cycle', 'Monitor hormone trends'};

  final goalOptions = <({String title, String description, IconData icon})>[
    (
      title: 'Understand my cycle',
      description: 'Period dates and cycle patterns.',
      icon: Icons.insights_rounded,
    ),
    (
      title: 'Monitor hormone trends',
      description: 'View hormone readings over time.',
      icon: Icons.biotech_outlined,
    ),
    (
      title: 'Explore fertile days',
      description: 'Estimate your potential fertile window.',
      icon: Icons.spa_outlined,
    ),
    (
      title: 'Manage PMS & symptoms',
      description: 'Track symptoms and identify patterns.',
      icon: Icons.healing_outlined,
    ),
    (
      title: 'Pregnancy planning',
      description: 'Track cycle information while trying to conceive.',
      icon: Icons.favorite_border_rounded,
    ),
    (
      title: 'Energy & sleep',
      description: 'Explore changes in sleep and energy.',
      icon: Icons.wb_twilight_rounded,
    ),
  ];

  @override
  void initState() {
    super.initState();
    name = TextEditingController(
      text: widget.initialName.isEmpty ? 'Aria' : widget.initialName,
    );
  }

  @override
  void dispose() {
    name.dispose();
    super.dispose();
  }

  Future<void> _finishOnboarding() async {
    final profile = <String, dynamic>{
      'name': name.text.trim().isEmpty ? 'Aria' : name.text.trim(),
      'age': age,
      'cycleLength': cycleLength,
      'periodLength': periodLength,
      'lastPeriod': lastPeriod.toIso8601String(),
      'goals': goals.toList(),
    };
    if (widget.profileEmail.isNotEmpty) {
      try {
        await BlossomProfileStore.save(widget.profileEmail, profile);
      } on PlatformException {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Could not save this profile on the device.'),
            ),
          );
        }
      } on MissingPluginException {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Profile saving is not available on this platform yet.',
              ),
            ),
          );
        }
      }
    }
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => BlossomDashboard(
          name: profile['name'] as String,
          profileEmail: widget.profileEmail,
          age: age,
          cycleLength: cycleLength,
          periodLength: periodLength,
          lastPeriod: lastPeriod,
          goals: goals.toList(),
        ),
      ),
    );
  }

  Future<void> next() async {
    if (step == 0 && name.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add a preferred name to continue.')),
      );
      return;
    }
    if (step < 3) {
      setState(() => step++);
    } else {
      await _finishOnboarding();
    }
  }

  @override
  Widget build(BuildContext context) {
    final titles = [
      'Your cycle basics',
      'When did your last period start?',
      'Your usual cycle length',
      'What would you like to track?',
    ];
    final subtitles = [
      'A few details help us personalize your cycle estimates.',
      'Tap the first day of full flow. You can edit or add dates anytime.',
      'We’ll adjust your estimates as you log more cycles.',
      'Choose all that apply. You can change your choices later.',
    ];

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 22, 0),
              child: Row(
                children: [
                  IconButton(
                    onPressed: step == 0
                        ? () => Navigator.pop(context)
                        : () => setState(() => step--),
                    icon: const Icon(
                      Icons.arrow_back_ios_new_rounded,
                      color: ink,
                      size: 18,
                    ),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'STEP ${step + 1} OF 4',
                          style: sansStyle(
                            size: 10,
                            weight: FontWeight.w700,
                            color: stoneMuted,
                            letterSpacing: 1.5,
                          ),
                        ),
                        const SizedBox(height: 6),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: LinearProgressIndicator(
                            value: (step + 1) / 4,
                            minHeight: 5,
                            backgroundColor: borderStone,
                            color: terracotta,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  TextButton(
                    onPressed: _finishOnboarding,
                    child: Text(
                      'Skip',
                      style: sansStyle(
                        size: 12,
                        weight: FontWeight.w700,
                        color: stoneMuted,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 280),
                child: SingleChildScrollView(
                  key: ValueKey(step),
                  padding: const EdgeInsets.fromLTRB(25, 22, 25, 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(titles[step], style: serifStyle(size: 30)),
                      const SizedBox(height: 8),
                      Text(
                        subtitles[step],
                        style: sansStyle(color: stoneMuted, size: 13),
                      ),
                      const SizedBox(height: 26),
                      if (step == 0) ...[
                        const FieldLabel('Preferred first name'),
                        const SizedBox(height: 8),
                        StyledField(
                          controller: name,
                          hint: 'Your name',
                          icon: Icons.person_outline_rounded,
                        ),
                        const SizedBox(height: 24),
                        Container(
                          padding: const EdgeInsets.all(18),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: borderStone),
                          ),
                          child: Column(
                            children: [
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  const FieldLabel('Age'),
                                  Text(
                                    '$age years',
                                    style: serifStyle(
                                      size: 20,
                                      color: terracotta,
                                    ),
                                  ),
                                ],
                              ),
                              Slider(
                                value: age.toDouble(),
                                min: 16,
                                max: 55,
                                divisions: 37,
                                activeColor: terracotta,
                                inactiveColor: sand,
                                onChanged: (v) =>
                                    setState(() => age = v.round()),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                        infoCard(
                          Icons.shield_outlined,
                          'Local-first privacy',
                          'Your cycle math and hormone simulations are computed on-device.',
                        ),
                      ],
                      if (step == 1) ...[
                        Container(
                          padding: const EdgeInsets.all(18),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(24),
                            border: Border.all(color: borderStone),
                          ),
                          child: Column(
                            children: [
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  IconButton(
                                    onPressed: () => setState(() {
                                      lastPeriod = DateTime(
                                        lastPeriod.year,
                                        lastPeriod.month - 1,
                                        1,
                                      );
                                    }),
                                    icon: const Icon(
                                      Icons.chevron_left_rounded,
                                      color: ink,
                                    ),
                                  ),
                                  Text(
                                    '${_month(lastPeriod.month)} ${lastPeriod.year}',
                                    style: serifStyle(size: 18),
                                  ),
                                  IconButton(
                                    onPressed:
                                        DateTime(
                                          lastPeriod.year,
                                          lastPeriod.month + 1,
                                          1,
                                        ).isAfter(DateTime.now())
                                        ? null
                                        : () => setState(() {
                                            lastPeriod = DateTime(
                                              lastPeriod.year,
                                              lastPeriod.month + 1,
                                              1,
                                            );
                                          }),
                                    icon: const Icon(
                                      Icons.chevron_right_rounded,
                                      color: ink,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              CalendarGrid(
                                month: DateTime(
                                  lastPeriod.year,
                                  lastPeriod.month,
                                ),
                                selected: lastPeriod,
                                maxDate: DateTime.now(),
                                onSelect: (d) => setState(() => lastPeriod = d),
                              ),
                            ],
                          ),
                        ),
                      ],
                      if (step == 2) ...[
                        Container(
                          padding: const EdgeInsets.all(22),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(24),
                            border: Border.all(color: borderStone),
                          ),
                          child: Column(
                            children: [
                              Text(
                                'AVERAGE CYCLE LENGTH',
                                style: sansStyle(
                                  size: 10,
                                  weight: FontWeight.w700,
                                  color: stoneMuted,
                                  letterSpacing: 1.4,
                                ),
                              ),
                              const SizedBox(height: 12),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  roundControl(
                                    Icons.remove,
                                    () => setState(() {
                                      cycleLength = (cycleLength - 1).clamp(
                                        21,
                                        35,
                                      );
                                    }),
                                  ),
                                  const SizedBox(width: 28),
                                  Column(
                                    children: [
                                      Text(
                                        '$cycleLength',
                                        style: serifStyle(
                                          size: 52,
                                          color: terracotta,
                                        ),
                                      ),
                                      Text(
                                        'days',
                                        style: sansStyle(
                                          size: 12,
                                          color: stoneMuted,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(width: 28),
                                  roundControl(
                                    Icons.add,
                                    () => setState(() {
                                      cycleLength = (cycleLength + 1).clamp(
                                        21,
                                        35,
                                      );
                                    }),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 22),
                              const Divider(color: borderStone),
                              const SizedBox(height: 14),
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  const FieldLabel('Typical bleed duration'),
                                  Text(
                                    '$periodLength days',
                                    style: serifStyle(
                                      size: 18,
                                      color: roseClay,
                                    ),
                                  ),
                                ],
                              ),
                              Slider(
                                value: periodLength.toDouble(),
                                min: 3,
                                max: 8,
                                divisions: 5,
                                activeColor: roseClay,
                                inactiveColor: sand,
                                onChanged: (v) =>
                                    setState(() => periodLength = v.round()),
                              ),
                            ],
                          ),
                        ),
                      ],
                      if (step == 3) ...[
                        Wrap(
                          spacing: 12,
                          runSpacing: 12,
                          children: [
                            for (final option in goalOptions)
                              SizedBox(
                                width:
                                    (MediaQuery.of(context).size.width - 62) /
                                    2,
                                child: GoalTile(
                                  title: option.title,
                                  description: option.description,
                                  icon: option.icon,
                                  selected: goals.contains(option.title),
                                  onTap: () => setState(() {
                                    if (goals.contains(option.title)) {
                                      if (goals.length > 1) {
                                        goals.remove(option.title);
                                      }
                                    } else {
                                      goals.add(option.title);
                                    }
                                  }),
                                ),
                              ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 10, 24, 20),
              child: PrimaryButton(
                label: step == 3 ? 'Launch Blossom Studio' : 'Continue',
                onTap: next,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _month(int m) => const [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
][(m - 1).clamp(0, 11)];

class CalendarGrid extends StatelessWidget {
  final DateTime month;
  final DateTime selected;
  final DateTime? maxDate;
  final ValueChanged<DateTime> onSelect;

  const CalendarGrid({
    super.key,
    required this.month,
    required this.selected,
    this.maxDate,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final first = DateTime(month.year, month.month, 1);
    final offset = first.weekday - 1;
    final count = DateTime(month.year, month.month + 1, 0).day;
    final lastDate = maxDate == null ? null : dateOnly(maxDate!);

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 7,
        mainAxisSpacing: 6,
        crossAxisSpacing: 4,
      ),
      itemCount: offset + count,
      itemBuilder: (context, i) {
        if (i < offset) return const SizedBox();
        final date = DateTime(month.year, month.month, i - offset + 1);
        final isSelected = sameDate(date, selected);
        final enabled = lastDate == null || !dateOnly(date).isAfter(lastDate);
        return InkWell(
          borderRadius: BorderRadius.circular(30),
          onTap: enabled ? () => onSelect(date) : null,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isSelected ? roseClay : null,
            ),
            alignment: Alignment.center,
            child: Text(
              '${date.day}',
              style: sansStyle(
                size: 13,
                color: !enabled
                    ? stoneMuted.withAlpha(77)
                    : (isSelected ? alabaster : ink),
                weight: isSelected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ),
        );
      },
    );
  }
}

class GoalTile extends StatelessWidget {
  final String title;
  final String description;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;
  const GoalTile({
    super.key,
    required this.title,
    required this.description,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => Material(
    color: selected ? const Color(0xFFFAF0EA) : Colors.white,
    borderRadius: BorderRadius.circular(20),
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        height: 150,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? terracotta : borderStone,
            width: selected ? 1.6 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Icon(icon, size: 22, color: selected ? terracotta : ink),
                if (selected)
                  const Icon(
                    Icons.check_circle_rounded,
                    size: 18,
                    color: terracotta,
                  ),
              ],
            ),
            Text(
              title,
              style: sansStyle(
                color: ink,
                size: 13,
                weight: selected ? FontWeight.w700 : FontWeight.w600,
                height: 1.25,
              ),
            ),
            const SizedBox(height: 5),
            Expanded(
              child: Align(
                alignment: Alignment.topLeft,
                child: Text(
                  description,
                  style: sansStyle(
                    color: stoneMuted,
                    size: 10,
                    weight: FontWeight.w500,
                    height: 1.3,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

Widget roundControl(IconData icon, VoidCallback onTap) => Material(
  color: sand,
  shape: const CircleBorder(),
  child: InkWell(
    customBorder: const CircleBorder(),
    onTap: onTap,
    child: SizedBox(width: 44, height: 44, child: Icon(icon, color: ink)),
  ),
);

Widget infoCard(IconData icon, String title, String text) => Container(
  padding: const EdgeInsets.all(16),
  decoration: BoxDecoration(
    color: sand,
    borderRadius: BorderRadius.circular(18),
    border: Border.all(color: borderStone),
  ),
  child: Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Icon(icon, color: terracotta, size: 21),
      const SizedBox(width: 12),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: sansStyle(color: ink, size: 13, weight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            Text(
              text,
              style: sansStyle(color: stoneMuted, size: 12, height: 1.45),
            ),
          ],
        ),
      ),
    ],
  ),
);

// ---------------------------------------------------------------------------
// DATE & CYCLE LOGIC HELPERS
// ---------------------------------------------------------------------------
DateTime dateOnly(DateTime date) => DateTime(date.year, date.month, date.day);

bool sameDate(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

String formatDateShort(DateTime date) =>
    '${_month(date.month).substring(0, 3)} ${date.day}';

String formatDateLong(DateTime date) =>
    '${_month(date.month)} ${date.day}, ${date.year}';

String _weekdayName(int weekday) => const [
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
  'Sunday',
][(weekday - 1).clamp(0, 6)];

enum CyclePhase {
  menstrual(
    label: 'Menstrual Phase',
    shortLabel: 'Menstrual',
    color: roseClay,
    tagline: 'Hormones reset to baseline; rest & iron-rich nourishment help.',
  ),
  follicular(
    label: 'Follicular Phase',
    shortLabel: 'Follicular',
    color: sageLeaf,
    tagline: 'FSH stimulates follicles as E3G steadily climbs; energy rises.',
  ),
  ovulatory(
    label: 'Ovulatory Window',
    shortLabel: 'Ovulatory',
    color: terracotta,
    tagline: 'Peak E3G triggers a rapid LH surge 24–36h before egg release.',
  ),
  luteal(
    label: 'Luteal Phase',
    shortLabel: 'Luteal',
    color: lutealIndigo,
    tagline: 'Corpus luteum secretes progesterone (PdG); metabolism warms.',
  );

  final String label;
  final String shortLabel;
  final Color color;
  final String tagline;
  const CyclePhase({
    required this.label,
    required this.shortLabel,
    required this.color,
    required this.tagline,
  });
}

// ---------------------------------------------------------------------------
// MAIN DASHBOARD STATE (WITH MULTI-CYCLE DATE MATH & HORMONE SYNC)
// ---------------------------------------------------------------------------
class BlossomDashboard extends StatefulWidget {
  final String name;
  final String profileEmail;
  final int age;
  final int cycleLength;
  final int periodLength;
  final DateTime lastPeriod;
  final List<String> goals;

  const BlossomDashboard({
    super.key,
    required this.name,
    this.profileEmail = '',
    required this.age,
    required this.cycleLength,
    required this.periodLength,
    required this.lastPeriod,
    required this.goals,
  });

  @override
  State<BlossomDashboard> createState() => _BlossomDashboardState();
}

class _BlossomDashboardState extends State<BlossomDashboard> {
  int tab = 0;
  late DateTime selectedDate;
  late DateTime visibleMonth;
  late Set<DateTime> periodDays;
  final Map<DateTime, Set<String>> symptomLogs = {};
  final Map<DateTime, String> moodLogs = {};
  final Map<DateTime, String> notes = {};
  final Map<int, Map<String, double>> scannedTestResults = {};
  final Map<int, Map<String, double>> demoTestResults = {};
  final List<TestRecord> testRecords = [];

  @override
  void initState() {
    super.initState();
    final today = dateOnly(DateTime.now());
    selectedDate = today;
    visibleMonth = DateTime(today.year, today.month);
    final firstPeriodDay = dateOnly(widget.lastPeriod);

    // Start with the period the user entered during setup. Earlier cycles and
    // check-ins are restored from the device when they have actually been logged.
    periodDays = {
      for (var i = 0; i < widget.periodLength; i++)
        firstPeriodDay.add(Duration(days: i)),
    };
    _loadTrackingData();
  }

  String _dateKey(DateTime date) => dateOnly(date).toIso8601String();

  Future<void> _loadTrackingData() async {
    if (widget.profileEmail.isEmpty) return;
    try {
      final saved = await BlossomProfileStore.loadTrackingData(
        widget.profileEmail,
      );
      if (!mounted || saved == null) return;

      DateTime? parseDay(dynamic value) {
        if (value is! String) return null;
        final parsed = DateTime.tryParse(value);
        return parsed == null ? null : dateOnly(parsed);
      }

      final savedPeriodDays = (saved['periodDays'] as List<dynamic>? ?? [])
          .map(parseDay)
          .whereType<DateTime>()
          .toSet();
      final savedSymptoms = <DateTime, Set<String>>{};
      final symptomData = saved['symptomLogs'];
      if (symptomData is Map) {
        for (final entry in symptomData.entries) {
          final day = parseDay(entry.key);
          final values = entry.value;
          if (day != null && values is List) {
            savedSymptoms[day] = values.whereType<String>().toSet();
          }
        }
      }
      final savedMoods = <DateTime, String>{};
      final moodData = saved['moodLogs'];
      if (moodData is Map) {
        for (final entry in moodData.entries) {
          final day = parseDay(entry.key);
          if (day != null && entry.value is String) {
            savedMoods[day] = entry.value as String;
          }
        }
      }
      final savedNotes = <DateTime, String>{};
      final noteData = saved['notes'];
      if (noteData is Map) {
        for (final entry in noteData.entries) {
          final day = parseDay(entry.key);
          if (day != null && entry.value is String) {
            savedNotes[day] = entry.value as String;
          }
        }
      }
      final savedScans = <int, Map<String, double>>{};
      final scanData = saved['scannedTestResults'];
      if (scanData is Map) {
        for (final entry in scanData.entries) {
          final day = int.tryParse(entry.key.toString());
          final values = entry.value;
          if (day != null && values is Map) {
            savedScans[day] = {
              for (final value in values.entries)
                if (value.value is num)
                  value.key.toString(): (value.value as num).toDouble(),
            };
          }
        }
      }
      final savedDemo = <int, Map<String, double>>{};
      final demoData = saved['demoTestResults'];
      if (demoData is Map) {
        for (final entry in demoData.entries) {
          final day = int.tryParse(entry.key.toString());
          final values = entry.value;
          if (day != null && values is Map) {
            savedDemo[day] = {
              for (final value in values.entries)
                if (value.value is num)
                  value.key.toString(): (value.value as num).toDouble(),
            };
          }
        }
      }

      final savedTests = <TestRecord>[];
      final testData = saved['testRecords'];
      if (testData is List) {
        for (final value in testData) {
          if (value is! Map) continue;
          try {
            savedTests.add(
              TestRecord.fromJson(Map<String, dynamic>.from(value)),
            );
          } on FormatException {
            // A damaged record should not hide the other saved tests.
          }
        }
      }

      setState(() {
        if (saved.containsKey('periodDays')) periodDays = savedPeriodDays;
        symptomLogs
          ..clear()
          ..addAll(savedSymptoms);
        moodLogs
          ..clear()
          ..addAll(savedMoods);
        notes
          ..clear()
          ..addAll(savedNotes);
        scannedTestResults
          ..clear()
          ..addAll(savedScans);
        demoTestResults
          ..clear()
          ..addAll(savedDemo);
        testRecords
          ..clear()
          ..addAll(savedTests);
      });
    } on PlatformException {
      // Keep the current session usable if local storage is unavailable.
    } on MissingPluginException {
      // Web and other unsupported platforms still keep this session in memory.
    } on FormatException {
      // Ignore a malformed saved payload rather than blocking the dashboard.
    }
  }

  Future<bool> _saveTrackingData() async {
    if (widget.profileEmail.isEmpty) return false;
    final data = <String, dynamic>{
      'periodDays': periodDays.map(_dateKey).toList(),
      'symptomLogs': {
        for (final entry in symptomLogs.entries)
          _dateKey(entry.key): entry.value.toList(),
      },
      'moodLogs': {
        for (final entry in moodLogs.entries) _dateKey(entry.key): entry.value,
      },
      'notes': {
        for (final entry in notes.entries) _dateKey(entry.key): entry.value,
      },
      'scannedTestResults': {
        for (final entry in scannedTestResults.entries)
          entry.key.toString(): entry.value,
      },
      'demoTestResults': {
        for (final entry in demoTestResults.entries)
          entry.key.toString(): entry.value,
      },
      'testRecords': testRecords.map((record) => record.toJson()).toList(),
    };
    try {
      await BlossomProfileStore.saveTrackingData(widget.profileEmail, data);
      return true;
    } on PlatformException {
      // Tracking remains available in memory if local storage is unavailable.
    } on MissingPluginException {
      // Web and other unsupported platforms still keep this session in memory.
    }
    return false;
  }

  Future<bool> _recordTest(TestRecord record) async {
    setState(() => testRecords.add(record));
    final saved = await _saveTrackingData();
    if (!saved && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'This test is available for this session only. Local storage is unavailable; export a PDF to keep a copy.',
          ),
        ),
      );
    }
    return saved;
  }

  void _openTestReports() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => TestReportsScreen(
          records: List.unmodifiable(testRecords),
          patientName: widget.name,
          patientAge: widget.age,
        ),
      ),
    );
  }

  /// Extracts distinct first-days of contiguous period blocks.
  List<DateTime> _periodStarts() {
    final days = periodDays.toList()..sort();
    return days
        .where(
          (day) => !periodDays.contains(day.subtract(const Duration(days: 1))),
        )
        .toList();
  }

  /// Dynamically computes average cycle length from logged period starts,
  /// falling back to the user's onboarding setting.
  int get _effectiveCycleLength {
    final starts = _periodStarts();
    if (starts.length >= 2) {
      final diffs = <int>[];
      for (var i = 1; i < starts.length; i++) {
        final d = starts[i].difference(starts[i - 1]).inDays;
        if (d >= 18 && d <= 42) diffs.add(d);
      }
      if (diffs.isNotEmpty) {
        final avg = diffs.reduce((a, b) => a + b) / diffs.length;
        return avg.round().clamp(21, 35);
      }
    }
    return widget.cycleLength;
  }

  DateTime _cycleStartFor(DateTime date) {
    final target = dateOnly(date);
    final starts = _periodStarts()
        .where((start) => !start.isAfter(target))
        .toList();
    if (starts.isNotEmpty) return starts.last;
    if (_periodStarts().isNotEmpty) return _periodStarts().first;
    return dateOnly(widget.lastPeriod);
  }

  int _cycleDayFor(DateTime date) {
    final len = _effectiveCycleLength;
    final elapsed = dateOnly(date).difference(_cycleStartFor(date)).inDays;
    return ((elapsed % len) + len) % len + 1;
  }

  DateTime _nextPeriodFor(DateTime date) {
    final len = _effectiveCycleLength;
    var next = _cycleStartFor(date).add(Duration(days: len));
    final target = dateOnly(date);
    while (!next.isAfter(target)) {
      next = next.add(Duration(days: len));
    }
    return next;
  }

  int get _ovulationCycleDay =>
      (_effectiveCycleLength - 14).clamp(8, _effectiveCycleLength - 5);

  bool _isFertileWindow(DateTime date) {
    final day = _cycleDayFor(date);
    return day >= (_ovulationCycleDay - 4) && day <= (_ovulationCycleDay + 1);
  }

  bool _isOvulationEstimate(DateTime date) =>
      _cycleDayFor(date) == _ovulationCycleDay;

  CyclePhase _phaseEnumFor(DateTime date) {
    final day = dateOnly(date);
    final cDay = _cycleDayFor(day);
    if (periodDays.contains(day) || cDay <= widget.periodLength) {
      return CyclePhase.menstrual;
    }
    if (_isFertileWindow(day)) {
      return CyclePhase.ovulatory;
    }
    if (cDay > _ovulationCycleDay + 1) {
      return CyclePhase.luteal;
    }
    return CyclePhase.follicular;
  }

  /// Projects future period days across the next 3 cycles so browsing future
  /// months on the calendar shows accurate forecasts.
  Set<DateTime> _forecastPeriodDays() {
    final starts = _periodStarts();
    final anchor = starts.isNotEmpty
        ? starts.last
        : dateOnly(widget.lastPeriod);
    final len = _effectiveCycleLength;
    final forecast = <DateTime>{};
    for (int cycle = 1; cycle <= 4; cycle++) {
      final start = anchor.add(Duration(days: len * cycle));
      for (var i = 0; i < widget.periodLength; i++) {
        forecast.add(start.add(Duration(days: i)));
      }
    }
    return forecast;
  }

  void _setSelectedDate(DateTime date) {
    final normalized = dateOnly(date);
    setState(() {
      selectedDate = normalized;
      visibleMonth = DateTime(normalized.year, normalized.month);
    });
  }

  void _togglePeriodDay(DateTime date) {
    final normalized = dateOnly(date);
    final wasLogged = periodDays.contains(normalized);
    setState(() {
      if (wasLogged) {
        periodDays.remove(normalized);
      } else {
        periodDays.add(normalized);
      }
    });
    _saveTrackingData();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          wasLogged
              ? 'Removed ${formatDateShort(normalized)} from period log.'
              : 'Logged flow on ${formatDateShort(normalized)} • Cycle model updated.',
        ),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _showDemoHormoneData(Map<int, Map<String, double>> values) {
    setState(() {
      demoTestResults
        ..clear()
        ..addAll(values);
    });
    _saveTrackingData();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Demo readings added to the chart. They are sample data.',
        ),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _editSymptoms(DateTime date) async {
    final day = dateOnly(date);
    final chosen = {...(symptomLogs[day] ?? <String>{})};
    const signalCategories = <String, List<String>>{
      'Body': [
        'Cramps',
        'Pelvic pain',
        'Low back pain',
        'Bloating',
        'Breast tenderness',
        'Headache',
        'Migraine',
        'Nausea',
        'Dizziness',
        'Hot flashes',
        'Joint or muscle aches',
        'Acne',
        'Abdominal tenderness',
        'Cramping during sex',
        'Swelling',
        'Water retention',
        'Skin oiliness',
        'Dry skin',
        'Hair changes',
        'Body aches',
      ],
      'Mood & energy': [
        'Anxiety',
        'Low mood',
        'Irritability',
        'Mood swings',
        'Stress',
        'Brain fog',
        'Trouble concentrating',
        'High energy',
        'Low energy',
        'Fatigue',
        'Calm',
        'Focused',
        'Changes in sex drive',
        'Feeling social',
        'Feeling withdrawn',
        'Emotional sensitivity',
        'Restlessness',
        'Motivated',
        'Feeling overwhelmed',
        'Low confidence',
      ],
      'Digestion & appetite': [
        'Cravings',
        'Increased appetite',
        'Decreased appetite',
        'Constipation',
        'Diarrhea',
        'Stomach discomfort',
        'Gas',
        'Heartburn',
        'Food aversions',
        'Bowel changes',
        'Thirst',
      ],
      'Sleep': [
        'Deep sleep',
        'Poor sleep',
        'Insomnia',
        'Vivid dreams',
        'Night sweats',
        'Waking during the night',
        'Sleepy during the day',
        'Restless sleep',
      ],
      'Flow & discharge': [
        'Light flow',
        'Medium flow',
        'Heavy flow',
        'Spotting',
        'Watery cervical mucus',
        'Egg-white cervical mucus',
        'Creamy discharge',
        'Vaginal dryness',
        'Brown spotting',
        'Blood clots',
        'Unusual bleeding',
        'Change in discharge',
        'Vaginal itching',
      ],
      'Fertility signals': [
        'Ovulation pain',
        'Positive ovulation test',
        'Higher basal temperature',
        'Sexual activity',
        'Cervical position changes',
        'Positive pregnancy test',
        'Negative pregnancy test',
      ],
    };
    final saved = await showModalBottomSheet<Set<String>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: alabaster,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 14, 24, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Center(child: _SheetHandle()),
                const SizedBox(height: 18),
                Text(
                  'Physical Signals • ${formatDateShort(day)}',
                  style: serifStyle(size: 24),
                ),
                const SizedBox(height: 6),
                Text(
                  'Logging physical biomarkers refines your phase insights.',
                  style: sansStyle(color: stoneMuted, size: 13),
                ),
                const SizedBox(height: 18),
                SizedBox(
                  height: MediaQuery.sizeOf(context).height * 0.46,
                  child: ListView(
                    children: [
                      for (final category in signalCategories.entries) ...[
                        Padding(
                          padding: const EdgeInsets.only(bottom: 6, top: 8),
                          child: Text(
                            category.key,
                            style: sansStyle(
                              size: 12,
                              weight: FontWeight.w700,
                              color: stoneMuted,
                            ),
                          ),
                        ),
                        Wrap(
                          spacing: 8,
                          runSpacing: 2,
                          children: category.value.map((option) {
                            final selected = chosen.contains(option);
                            return FilterChip(
                              label: Text(option),
                              selected: selected,
                              selectedColor: terracotta.withAlpha(41),
                              backgroundColor: Colors.white,
                              checkmarkColor: terracotta,
                              side: BorderSide(
                                color: selected ? terracotta : borderStone,
                              ),
                              labelStyle: sansStyle(
                                size: 12,
                                weight: selected
                                    ? FontWeight.w700
                                    : FontWeight.w500,
                                color: selected ? terracotta : ink,
                              ),
                              onSelected: (value) => setSheetState(() {
                                if (value) {
                                  chosen.add(option);
                                } else {
                                  chosen.remove(option);
                                }
                              }),
                            );
                          }).toList(),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 22),
                PrimaryButton(
                  label: 'Save Signals (${chosen.length})',
                  onTap: () => Navigator.pop(context, chosen),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (saved != null) {
      setState(() {
        if (saved.isEmpty) {
          symptomLogs.remove(day);
        } else {
          symptomLogs[day] = saved;
        }
      });
      _saveTrackingData();
    }
  }

  Future<void> _editMood(DateTime date) async {
    final day = dateOnly(date);
    const options = <(String, String, String)>[
      ('Radiant', '✨', 'Social, clear-headed & outward'),
      ('Calm', '🌿', 'Grounded, steady nervous system'),
      ('Focused', '🎯', 'Analytical & task-oriented'),
      ('Reflective', '🌙', 'Inward, needing quiet space'),
      ('Sensitive', '🌊', 'Heightened emotional receptivity'),
      ('Fatigued', '☁️', 'Low battery, craving rest'),
    ];
    final mood = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: alabaster,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 14, 24, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Center(child: _SheetHandle()),
              const SizedBox(height: 16),
              Text(
                'Emotional State • ${formatDateShort(day)}',
                style: serifStyle(size: 24),
              ),
              const SizedBox(height: 12),
              ...options.map(
                (entry) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Container(
                    width: 42,
                    height: 42,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: sand,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(entry.$2, style: const TextStyle(fontSize: 20)),
                  ),
                  title: Text(
                    entry.$1,
                    style: sansStyle(weight: FontWeight.w700, size: 14),
                  ),
                  subtitle: Text(
                    entry.$3,
                    style: sansStyle(color: stoneMuted, size: 12),
                  ),
                  trailing: moodLogs[day] == entry.$1
                      ? const Icon(Icons.check_circle, color: terracotta)
                      : const Icon(
                          Icons.chevron_right_rounded,
                          color: stoneMuted,
                        ),
                  onTap: () => Navigator.pop(context, entry.$1),
                ),
              ),
              if (moodLogs.containsKey(day))
                Center(
                  child: TextButton(
                    onPressed: () => Navigator.pop(context, ''),
                    child: Text(
                      'Clear mood entry',
                      style: sansStyle(color: roseClay, size: 12),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
    if (mood != null) {
      setState(() {
        if (mood.isEmpty) {
          moodLogs.remove(day);
        } else {
          moodLogs[day] = mood;
        }
      });
      _saveTrackingData();
    }
  }

  Future<void> _editNote(DateTime date) async {
    final day = dateOnly(date);
    final controller = TextEditingController(text: notes[day] ?? '');
    final note = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: alabaster,
        title: Text(
          'Journal • ${formatDateShort(day)}',
          style: serifStyle(size: 22),
        ),
        content: TextField(
          controller: controller,
          maxLines: 4,
          maxLength: 240,
          autofocus: true,
          style: sansStyle(size: 14),
          decoration: InputDecoration(
            hintText:
                'Basal temperature, sleep quality, or personal reflections...',
            filled: true,
            fillColor: Colors.white,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: borderStone),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel', style: sansStyle(color: stoneMuted)),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: ink),
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Save Entry'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (note != null) {
      setState(() {
        if (note.isEmpty) {
          notes.remove(day);
        } else {
          notes[day] = note;
        }
      });
      _saveTrackingData();
    }
  }

  /// Describe logged context without inferring hormone values from a calendar.
  String _reactiveInsightFor(DateTime date) {
    final day = dateOnly(date);
    final cDay = _cycleDayFor(day);
    final phase = _phaseEnumFor(day);
    final daySymptoms = symptomLogs[day] ?? {};
    final mood = moodLogs[day];

    final parts = <String>[];

    if (phase == CyclePhase.ovulatory) {
      parts.add(
        'Cycle day $cDay falls near a calendar-estimated ovulation window. This estimate does not confirm ovulation.',
      );
    } else if (phase == CyclePhase.luteal) {
      parts.add(
        'The calendar model places cycle day $cDay after estimated ovulation. Measured hormone levels are not available.',
      );
    } else if (phase == CyclePhase.menstrual) {
      parts.add(
        'Cycle day $cDay is within the period window based on your logged dates. Keep a record of flow and symptoms.',
      );
    } else {
      parts.add(
        'Cycle day $cDay is before calendar-estimated ovulation. Actual timing can vary between cycles.',
      );
    }

    if (daySymptoms.isNotEmpty) {
      parts.add(
        'You logged ${daySymptoms.join(" & ").toLowerCase()}. Keep these observations for comparison and discussion with your clinician.',
      );
    } else if (mood != null) {
      parts.add(
        'Feeling ${mood.toLowerCase()} is a helpful anchor to compare against next month’s Day $cDay.',
      );
    } else {
      parts.add(
        'Log symptoms to build a clearer history, and review individual tests in Tests & reports.',
      );
    }

    return parts.join(' ');
  }

  Widget _homePage() {
    final cDay = _cycleDayFor(selectedDate);
    final cycleLen = _effectiveCycleLength;
    final phase = _phaseEnumFor(selectedDate);
    final nextPeriod = _nextPeriodFor(selectedDate);
    final daysUntil = nextPeriod.difference(dateOnly(selectedDate)).inDays;
    final weekStart = dateOnly(selectedDate)
        .subtract(Duration(days: dateOnly(selectedDate).weekday - 1));
    final isToday = sameDate(selectedDate, DateTime.now());

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Top Header Bar
          Row(
            children: [
              const FlowerMark(size: 28),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Blossom',
                    style: serifStyle(size: 21, weight: FontWeight.w700),
                  ),
                  Text(
                    isToday
                        ? 'TODAY • ${formatDateShort(selectedDate).toUpperCase()}'
                        : 'VIEWING • ${formatDateShort(selectedDate).toUpperCase()}',
                    style: sansStyle(
                      size: 9,
                      weight: FontWeight.w700,
                      color: terracotta,
                      letterSpacing: 1.4,
                    ),
                  ),
                ],
              ),
              const Spacer(),
              if (!isToday)
                TextButton.icon(
                  onPressed: () => _setSelectedDate(DateTime.now()),
                  icon: const Icon(Icons.today_rounded, size: 15),
                  label: const Text('Today'),
                  style: TextButton.styleFrom(
                    foregroundColor: terracotta,
                    backgroundColor: terracotta.withAlpha(26),
                  ),
                ),
              const SizedBox(width: 4),
              InkWell(
                borderRadius: BorderRadius.circular(24),
                onTap: () => setState(() => tab = 4),
                child: CircleAvatar(
                  radius: 19,
                  backgroundColor: sand,
                  child: Text(
                    (widget.name.isEmpty ? 'A' : widget.name[0]).toUpperCase(),
                    style: serifStyle(size: 16, color: ink),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),

          // Interactive Week Scrubber Strip
          SizedBox(
            height: 76,
            child: Row(
              children: List.generate(7, (index) {
                final date = weekStart.add(Duration(days: index));
                final selected = sameDate(date, selectedDate);
                final isPeriod = periodDays.contains(date);
                final isFertile = _isFertileWindow(date) && !isPeriod;
                final hasLog =
                    (symptomLogs[date]?.isNotEmpty ?? false) ||
                    moodLogs.containsKey(date) ||
                    notes.containsKey(date);

                return Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2.5),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(18),
                      onTap: () => _setSelectedDate(date),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        decoration: BoxDecoration(
                          color: selected ? ink : Colors.white,
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(
                            color: selected
                                ? ink
                                : (isPeriod
                                      ? roseClay.withAlpha(128)
                                      : borderStone),
                          ),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              _weekdayName(date.weekday).substring(0, 1),
                              style: sansStyle(
                                size: 10,
                                weight: FontWeight.w600,
                                color: selected ? Colors.white60 : stoneMuted,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${date.day}',
                              style: serifStyle(
                                size: 16,
                                color: selected ? alabaster : ink,
                              ),
                            ),
                            const SizedBox(height: 5),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                if (isPeriod || isFertile || hasLog)
                                  Container(
                                    width: 5,
                                    height: 5,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: isPeriod
                                          ? roseClay
                                          : (isFertile
                                                ? terracotta
                                                : (selected
                                                      ? goldWarm
                                                      : lutealIndigo)),
                                    ),
                                  )
                                else
                                  const SizedBox(height: 5),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              }),
            ),
          ),
          const SizedBox(height: 20),

          // Hero Cycle Wheel & Phase Card
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              color: ink,
              borderRadius: BorderRadius.circular(28),
              boxShadow: [
                BoxShadow(
                  color: ink.withAlpha(36),
                  blurRadius: 24,
                  offset: const Offset(0, 12),
                ),
              ],
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: phase.color.withAlpha(56),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: phase.color.withAlpha(128)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 6,
                            height: 6,
                            decoration: BoxDecoration(
                              color: phase.color,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            phase.label.toUpperCase(),
                            style: sansStyle(
                              size: 9,
                              weight: FontWeight.w700,
                              color: alabaster,
                              letterSpacing: 1.1,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Spacer(),
                    InkWell(
                      onTap: () => setState(() => tab = 2),
                      child: Row(
                        children: [
                          Text(
                            'Hormone curves',
                            style: sansStyle(
                              size: 11,
                              color: const Color(0xFFD6CEC2),
                              weight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(width: 4),
                          const Icon(
                            Icons.arrow_outward_rounded,
                            size: 14,
                            color: terracotta,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    // Animated 360° Cycle Phase Ring
                    TweenAnimationBuilder<double>(
                      key: ValueKey('wheel-$cDay-$cycleLen'),
                      tween: Tween(begin: 0.0, end: cDay / cycleLen),
                      duration: const Duration(milliseconds: 650),
                      curve: Curves.easeOutCubic,
                      builder: (context, progress, _) => SizedBox(
                        width: 126,
                        height: 126,
                        child: CustomPaint(
                          painter: CycleWheelPainter(
                            progress: progress,
                            cycleLength: cycleLen,
                            periodLength: widget.periodLength,
                            ovulationDay: _ovulationCycleDay,
                            activeColor: phase.color,
                          ),
                          child: Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  'DAY',
                                  style: sansStyle(
                                    size: 9,
                                    weight: FontWeight.w700,
                                    color: Colors.white54,
                                    letterSpacing: 1.5,
                                  ),
                                ),
                                Text(
                                  '$cDay',
                                  style: serifStyle(
                                    size: 38,
                                    color: alabaster,
                                    height: 1.05,
                                  ),
                                ),
                                Text(
                                  'of $cycleLen',
                                  style: sansStyle(
                                    size: 10,
                                    color: Colors.white60,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 20),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            phase.tagline,
                            style: serifStyle(
                              size: 16,
                              color: alabaster,
                              weight: FontWeight.w400,
                              height: 1.38,
                            ),
                          ),
                          const SizedBox(height: 14),
                          Row(
                            children: [
                              const Icon(
                                Icons.water_drop_outlined,
                                size: 15,
                                color: roseClay,
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  'Next flow in $daysUntil d (${formatDateShort(nextPeriod)})',
                                  style: sansStyle(
                                    size: 11,
                                    color: const Color(0xFFD6CEC2),
                                    weight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              const Icon(
                                Icons.flare_rounded,
                                size: 15,
                                color: terracotta,
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  _isOvulationEstimate(selectedDate)
                                      ? 'Estimated ovulation day'
                                      : (_isFertileWindow(selectedDate)
                                            ? 'Inside 6-day fertile window'
                                            : 'Peak LH est. Cycle Day $_ovulationCycleDay'),
                                  style: sansStyle(
                                    size: 11,
                                    color: const Color(0xFFD6CEC2),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 22),

          // Live Hormone Snapshot Bar (Clickable -> Jumps to Graph)
          InkWell(
            borderRadius: BorderRadius.circular(22),
            onTap: () => setState(() => tab = 2),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: borderStone),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        'DAY $cDay HORMONE PROFILE',
                        style: sansStyle(
                          size: 10,
                          weight: FontWeight.w700,
                          color: stoneMuted,
                          letterSpacing: 1.2,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        'Interactive spline →',
                        style: sansStyle(
                          size: 11,
                          weight: FontWeight.w700,
                          color: terracotta,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: hormoneNames.map((h) {
                      final vals = simulatedHormoneValues(h, cycleLen);
                      final val = vals[(cDay - 1).clamp(0, vals.length - 1)];
                      final col = hormoneColor(h);
                      return Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    h,
                                    style: sansStyle(
                                      size: 11,
                                      weight: FontWeight.w700,
                                      color: col,
                                    ),
                                  ),
                                  Text(
                                    '${val.round()}',
                                    style: serifStyle(size: 15, color: ink),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 5),
                              ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: LinearProgressIndicator(
                                  value: (val / 100).clamp(0.0, 1.0),
                                  minHeight: 5,
                                  backgroundColor: sand,
                                  color: col,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),

          // Daily Check-in Grid
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Daily Check-In', style: serifStyle(size: 22)),
              Text(
                formatDateShort(selectedDate),
                style: sansStyle(
                  size: 12,
                  weight: FontWeight.w700,
                  color: stoneMuted,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _checkInCard(
                  title: 'Period Flow',
                  subtitle: periodDays.contains(dateOnly(selectedDate))
                      ? 'Flow logged'
                      : 'Tap to log bleed',
                  icon: Icons.water_drop_outlined,
                  accent: roseClay,
                  active: periodDays.contains(dateOnly(selectedDate)),
                  onTap: () => _togglePeriodDay(selectedDate),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _checkInCard(
                  title: 'Symptoms',
                  subtitle:
                      (symptomLogs[dateOnly(selectedDate)]?.isNotEmpty ?? false)
                      ? symptomLogs[dateOnly(selectedDate)]!.join(', ')
                      : 'Add body signals',
                  icon: Icons.bolt_rounded,
                  accent: terracotta,
                  active:
                      symptomLogs[dateOnly(selectedDate)]?.isNotEmpty ?? false,
                  onTap: () => _editSymptoms(selectedDate),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _checkInCard(
                  title: 'Mood State',
                  subtitle:
                      moodLogs[dateOnly(selectedDate)] ?? 'How do you feel?',
                  icon: Icons.spa_outlined,
                  accent: sageLeaf,
                  active: moodLogs.containsKey(dateOnly(selectedDate)),
                  onTap: () => _editMood(selectedDate),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _checkInCard(
                  title: 'Journal Note',
                  subtitle:
                      notes[dateOnly(selectedDate)] ?? 'Write a private note',
                  icon: Icons.edit_note_rounded,
                  accent: lutealIndigo,
                  active: notes.containsKey(dateOnly(selectedDate)),
                  onTap: () => _editNote(selectedDate),
                ),
              ),
            ],
          ),
          const SizedBox(height: 22),

          // A shared-phone activity for a quick partner check-in
          Material(
            color: const Color(0xFFF9F1E8),
            borderRadius: BorderRadius.circular(20),
            child: InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const PartnerCheckInScreen(),
                ),
              ),
              child: Container(
                padding: const EdgeInsets.all(17),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0xFFEAD9CA)),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: terracotta.withAlpha(30),
                        borderRadius: BorderRadius.circular(13),
                      ),
                      child: const Icon(
                        Icons.diversity_1_rounded,
                        color: terracotta,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'A little closer, together',
                            style: serifStyle(size: 17),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            'Play a 3-round check-in and see how well you know each other',
                            style: sansStyle(color: stoneMuted, size: 11),
                          ),
                        ],
                      ),
                    ),
                    const Icon(Icons.chevron_right_rounded, color: stoneMuted),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Cycle history and logged symptom patterns
          Card(
            color: Colors.white,
            margin: const EdgeInsets.only(bottom: 12),
            child: ListTile(
              contentPadding: const EdgeInsets.all(16),
              leading: const Icon(
                Icons.description_outlined,
                color: terracotta,
              ),
              title: const Text('Tests & reports'),
              subtitle: const Text(
                'Understand your tests and create a PDF for your clinician',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: _openTestReports,
            ),
          ),
          Material(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            child: InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => CycleReportsScreen(
                    periodStarts: _periodStarts(),
                    periodDays: Set<DateTime>.of(periodDays),
                    symptomLogs: {
                      for (final entry in symptomLogs.entries)
                        entry.key: Set<String>.of(entry.value),
                    },
                    moodLogs: Map<DateTime, String>.of(moodLogs),
                    fallbackCycleLength: widget.cycleLength,
                    fallbackPeriodLength: widget.periodLength,
                  ),
                ),
              ),
              child: Container(
                padding: const EdgeInsets.all(17),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: borderStone),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: terracotta.withAlpha(28),
                        borderRadius: BorderRadius.circular(13),
                      ),
                      child: const Icon(
                        Icons.insights_rounded,
                        color: terracotta,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Cycle history & patterns',
                            style: serifStyle(size: 17),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            'Review logged cycle lengths, symptoms, and moods',
                            style: sansStyle(color: stoneMuted, size: 11),
                          ),
                        ],
                      ),
                    ),
                    const Icon(Icons.chevron_right_rounded, color: stoneMuted),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Reactive Pattern Synthesis Card
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: sand,
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: borderStone),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.auto_awesome_rounded,
                      color: terracotta,
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'YOUR CYCLE CONTEXT',
                      style: sansStyle(
                        size: 10,
                        weight: FontWeight.w700,
                        color: ink,
                        letterSpacing: 1.2,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  _reactiveInsightFor(selectedDate),
                  style: sansStyle(color: ink, size: 13, height: 1.5),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _checkInCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color accent,
    required bool active,
    required VoidCallback onTap,
  }) {
    return Material(
      color: active ? accent.withAlpha(26) : Colors.white,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.all(15),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: active ? accent : borderStone,
              width: active ? 1.5 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: active ? accent.withAlpha(51) : sand,
                      borderRadius: BorderRadius.circular(11),
                    ),
                    child: Icon(icon, color: active ? accent : ink, size: 19),
                  ),
                  Icon(
                    active
                        ? Icons.check_circle_rounded
                        : Icons.add_circle_outline_rounded,
                    color: active ? accent : stoneMuted,
                    size: 18,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                title,
                style: sansStyle(size: 13, weight: FontWeight.w700, color: ink),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: sansStyle(
                  size: 11,
                  color: active ? accent : stoneMuted,
                  weight: active ? FontWeight.w600 : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final todayCycleDay = _cycleDayFor(selectedDate);
    final effLen = _effectiveCycleLength;

    final pages = <Widget>[
      _homePage(),
      LfaTestScreen(
        onBack: () => setState(() => tab = 0),
        onViewChart: () => setState(() => tab = 2),
        cycleLength: effLen,
        cycleDay: todayCycleDay,
        onShowDemoData: _showDemoHormoneData,
        onRecordTest: _recordTest,
        onOpenReports: _openTestReports,
        patientName: widget.name,
        patientAge: widget.age,
        captureCycleDay: _cycleDayFor(dateOnly(DateTime.now())),
      ),
      HormoneInsightsScreen(
        cycleLength: effLen,
        cycleDay: todayCycleDay,
        periodLength: widget.periodLength,
        ovulationDay: _ovulationCycleDay,
        scannedResults: scannedTestResults,
        demoResults: demoTestResults,
        onOpenReports: _openTestReports,
        onBack: () => setState(() => tab = 0),
      ),
      CycleCalendarScreen(
        visibleMonth: visibleMonth,
        selectedDate: selectedDate,
        cycleDay: todayCycleDay,
        cycleLength: effLen,
        phase: _phaseEnumFor(selectedDate),
        nextPeriod: _nextPeriodFor(selectedDate),
        periodDays: periodDays,
        forecastPeriodDays: _forecastPeriodDays(),
        isFertileWindow: _isFertileWindow,
        isOvulationEstimate: _isOvulationEstimate,
        onBack: () => setState(() => tab = 0),
        onMonthChanged: (month) => setState(() => visibleMonth = month),
        onSelectDate: _setSelectedDate,
        onTogglePeriod: () => _togglePeriodDay(selectedDate),
        onEditSymptoms: () => _editSymptoms(selectedDate),
      ),
      ProfileScreen(
        name: widget.name,
        age: widget.age,
        cycleLength: effLen,
        periodLength: widget.periodLength,
        loggedPeriodsCount: _periodStarts().length,
        goals: widget.goals,
        onBack: () => setState(() => tab = 0),
      ),
    ];

    return Scaffold(
      body: SafeArea(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 260),
          switchInCurve: Curves.easeOutCubic,
          child: KeyedSubtree(key: ValueKey(tab), child: pages[tab]),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'dashboardAskBlossom',
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => BlossomChatPage(
              scannedResults: Map<int, Map<String, double>>.fromEntries(
                scannedTestResults.entries.map(
                  (entry) => MapEntry(
                    entry.key,
                    Map<String, double>.from(entry.value),
                  ),
                ),
              ),
            ),
          ),
        ),
        backgroundColor: ink,
        foregroundColor: alabaster,
        icon: const Icon(Icons.chat_bubble_outline_rounded),
        label: Text(
          'Ask OVA',
          style: sansStyle(color: alabaster, size: 13, weight: FontWeight.w700),
        ),
      ),
      bottomNavigationBar: NavigationBar(
        backgroundColor: alabaster,
        surfaceTintColor: Colors.transparent,
        indicatorColor: terracotta.withAlpha(41),
        selectedIndex: tab,
        onDestinationSelected: (index) => setState(() => tab = index),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.wb_sunny_outlined),
            selectedIcon: Icon(Icons.wb_sunny_rounded, color: terracotta),
            label: 'Today',
          ),
          NavigationDestination(
            icon: Icon(Icons.biotech_outlined),
            selectedIcon: Icon(Icons.biotech_rounded, color: terracotta),
            label: 'Assay Scan',
          ),
          NavigationDestination(
            icon: Icon(Icons.ssid_chart_rounded),
            selectedIcon: Icon(Icons.ssid_chart_rounded, color: terracotta),
            label: 'Hormones',
          ),
          NavigationDestination(
            icon: Icon(Icons.calendar_month_outlined),
            selectedIcon: Icon(Icons.calendar_month_rounded, color: terracotta),
            label: 'Calendar',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline_rounded),
            selectedIcon: Icon(Icons.person_rounded, color: terracotta),
            label: 'Profile',
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// SHARED-PHONE PARTNER CHECK-IN
// ---------------------------------------------------------------------------
class _TogetherPrompt {
  final String question;
  final List<String> choices;

  const _TogetherPrompt({required this.question, required this.choices});
}

class PartnerCheckInScreen extends StatefulWidget {
  const PartnerCheckInScreen({super.key});

  @override
  State<PartnerCheckInScreen> createState() => _PartnerCheckInScreenState();
}

class _PartnerCheckInScreenState extends State<PartnerCheckInScreen> {
  static const _prompts = [
    _TogetherPrompt(
      question: 'When I want support, what helps me most?',
      choices: [
        'Listen without trying to fix it',
        'Help with one practical thing',
        'Quiet time together',
        'Check in with me a little later',
      ],
    ),
    _TogetherPrompt(
      question: 'Which small gesture would feel thoughtful today?',
      choices: [
        'Make me a snack or tea',
        'Take one task off my plate',
        'Send me a kind message',
        'Give me some breathing room',
      ],
    ),
    _TogetherPrompt(
      question: 'How would I enjoy spending 20 minutes together?',
      choices: [
        'Take a short walk',
        'Play a quick game',
        'Share a snack',
        'Put our phones away and talk',
      ],
    ),
  ];

  late final List<int?> _myAnswers = List<int?>.filled(_prompts.length, null);
  late final List<int?> _partnerAnswers = List<int?>.filled(
    _prompts.length,
    null,
  );
  int _round = 0;
  int _step = 0; // 0: user's answer, 1: partner's guess, 2: reveal.
  int? _selectedChoice;

  bool get _isFinished => _round >= _prompts.length;

  int get _matches => List.generate(
    _prompts.length,
    (index) => _myAnswers[index] == _partnerAnswers[index] ? 1 : 0,
  ).reduce((a, b) => a + b);

  void _continueRound() {
    setState(() {
      if (_step == 0) {
        _myAnswers[_round] = _selectedChoice;
        _step = 1;
      } else if (_step == 1) {
        _partnerAnswers[_round] = _selectedChoice;
        _step = 2;
      } else {
        _round++;
        _step = 0;
      }
      _selectedChoice = null;
    });
  }

  void _playAgain() {
    setState(() {
      for (var i = 0; i < _prompts.length; i++) {
        _myAnswers[i] = null;
        _partnerAnswers[i] = null;
      }
      _round = 0;
      _step = 0;
      _selectedChoice = null;
    });
  }

  Future<void> _copyTakeaway() async {
    final recap = StringBuffer(
      'We matched on $_matches of ${_prompts.length} partner check-in prompts.\n',
    );
    for (var i = 0; i < _prompts.length; i++) {
      recap.writeln(_prompts[i].question);
      recap.writeln('My answer: ${_prompts[i].choices[_myAnswers[i]!]}');
      recap.writeln(
        'Partner guessed: ${_prompts[i].choices[_partnerAnswers[i]!]}',
      );
    }
    await Clipboard.setData(ClipboardData(text: recap.toString()));
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Check-in recap copied.')));
  }

  @override
  Widget build(BuildContext context) {
    final prompt = _isFinished ? null : _prompts[_round];
    final picked = _selectedChoice;
    final answeredMatch =
        !_isFinished && _myAnswers[_round] == _partnerAnswers[_round];

    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DashboardPageHeader(
                title: 'Together',
                subtitle: 'A small check-in for the two of you',
                onBack: () => Navigator.of(context).pop(),
              ),
              if (!_isFinished) ...[
                const SizedBox(height: 12),
                Row(
                  children: [
                    Text(
                      'ROUND ${_round + 1} OF ${_prompts.length}',
                      style: sansStyle(
                        size: 10,
                        weight: FontWeight.w700,
                        color: stoneMuted,
                        letterSpacing: 1.2,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      _step == 0
                          ? 'Your turn'
                          : (_step == 1 ? 'Partner’s turn' : 'Reveal'),
                      style: sansStyle(
                        size: 11,
                        weight: FontWeight.w700,
                        color: terracotta,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: LinearProgressIndicator(
                    value: (_round + (_step == 2 ? 1 : 0.35)) / _prompts.length,
                    minHeight: 5,
                    backgroundColor: sand,
                    color: terracotta,
                  ),
                ),
                const SizedBox(height: 22),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: ink,
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        _step == 1
                            ? Icons.phone_android_rounded
                            : Icons.favorite_border_rounded,
                        color: terracotta,
                        size: 22,
                      ),
                      const SizedBox(height: 14),
                      Text(
                        _step == 1
                            ? 'Pass the phone to your partner'
                            : prompt!.question,
                        style: serifStyle(size: 23, color: alabaster),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _step == 0
                            ? 'Choose what feels right for you today. Your answer will be hidden on the next screen.'
                            : (_step == 1
                                  ? 'Ask your partner to guess your answer. Your choice is hidden until you reveal it.'
                                  : (answeredMatch
                                        ? 'You were on the same wavelength. Keep talking about what makes that support feel good.'
                                        : 'A chance to learn something new. Ask each other what would feel helpful next time.')),
                        style: sansStyle(
                          size: 12,
                          color: Colors.white70,
                          height: 1.5,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                if (_step < 2)
                  ...prompt!.choices.asMap().entries.map((entry) {
                    final isSelected = picked == entry.key;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 9),
                      child: Material(
                        color: isSelected
                            ? terracotta.withAlpha(24)
                            : Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(16),
                          onTap: () =>
                              setState(() => _selectedChoice = entry.key),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 15,
                              vertical: 14,
                            ),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: isSelected ? terracotta : borderStone,
                                width: isSelected ? 1.5 : 1,
                              ),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    entry.value,
                                    style: sansStyle(
                                      size: 13,
                                      weight: isSelected
                                          ? FontWeight.w700
                                          : FontWeight.w500,
                                      color: isSelected ? terracotta : ink,
                                    ),
                                  ),
                                ),
                                Icon(
                                  isSelected
                                      ? Icons.check_circle_rounded
                                      : Icons.circle_outlined,
                                  color: isSelected ? terracotta : borderStone,
                                  size: 20,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  })
                else ...[
                  _TogetherAnswerRow(
                    label: 'You chose',
                    answer: prompt!.choices[_myAnswers[_round]!],
                    color: terracotta,
                  ),
                  const SizedBox(height: 9),
                  _TogetherAnswerRow(
                    label: 'Your partner guessed',
                    answer: prompt.choices[_partnerAnswers[_round]!],
                    color: sageLeaf,
                  ),
                ],
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _step == 2
                        ? _continueRound
                        : (picked == null ? null : _continueRound),
                    style: FilledButton.styleFrom(
                      backgroundColor: ink,
                      foregroundColor: alabaster,
                      disabledBackgroundColor: sandDark,
                      padding: const EdgeInsets.symmetric(vertical: 15),
                    ),
                    child: Text(
                      _step == 0
                          ? 'Lock answer & pass phone'
                          : (_step == 1
                                ? 'Lock guess & reveal'
                                : (_round == _prompts.length - 1
                                      ? 'See our recap'
                                      : 'Next prompt')),
                    ),
                  ),
                ),
              ] else ...[
                const SizedBox(height: 20),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(22),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF9F1E8),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: const Color(0xFFEAD9CA)),
                  ),
                  child: Column(
                    children: [
                      const Icon(
                        Icons.diversity_1_rounded,
                        color: terracotta,
                        size: 34,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'You matched on $_matches of ${_prompts.length}',
                        textAlign: TextAlign.center,
                        style: serifStyle(size: 25),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'The best part is learning what support feels like for each of you. Pick one answer to try this week.',
                        textAlign: TextAlign.center,
                        style: sansStyle(
                          size: 12,
                          color: stoneMuted,
                          height: 1.5,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                for (var i = 0; i < _prompts.length; i++) ...[
                  if (i > 0) const SizedBox(height: 9),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(15),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(17),
                      border: Border.all(color: borderStone),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_prompts[i].question, style: serifStyle(size: 16)),
                        const SizedBox(height: 7),
                        Text(
                          'You: ${_prompts[i].choices[_myAnswers[i]!]}',
                          style: sansStyle(size: 12, color: terracotta),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          'Partner: ${_prompts[i].choices[_partnerAnswers[i]!]}',
                          style: sansStyle(size: 12, color: sageLeaf),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _copyTakeaway,
                    icon: const Icon(Icons.copy_rounded),
                    label: const Text('Copy our recap'),
                    style: FilledButton.styleFrom(
                      backgroundColor: ink,
                      foregroundColor: alabaster,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: _playAgain,
                    child: const Text('Play again'),
                  ),
                ),
              ],
              const SizedBox(height: 16),
              Center(
                child: Text(
                  'Just for the two of you · answers aren’t saved',
                  textAlign: TextAlign.center,
                  style: sansStyle(size: 10, color: stoneMuted),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TogetherAnswerRow extends StatelessWidget {
  final String label;
  final String answer;
  final Color color;

  const _TogetherAnswerRow({
    required this.label,
    required this.answer,
    required this.color,
  });

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(15),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: borderStone),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: sansStyle(size: 10, color: stoneMuted)),
        const SizedBox(height: 4),
        Text(
          answer,
          style: sansStyle(size: 13, weight: FontWeight.w700, color: color),
        ),
      ],
    ),
  );
}

// ---------------------------------------------------------------------------
// CYCLE HISTORY & SYMPTOM PATTERN REPORT
// ---------------------------------------------------------------------------
class CycleReportsScreen extends StatelessWidget {
  final List<DateTime> periodStarts;
  final Set<DateTime> periodDays;
  final Map<DateTime, Set<String>> symptomLogs;
  final Map<DateTime, String> moodLogs;
  final int fallbackCycleLength;
  final int fallbackPeriodLength;

  const CycleReportsScreen({
    super.key,
    required this.periodStarts,
    required this.periodDays,
    required this.symptomLogs,
    required this.moodLogs,
    required this.fallbackCycleLength,
    required this.fallbackPeriodLength,
  });

  List<int> get cycleLengths {
    final starts = periodStarts.toList()..sort();
    return [
      for (var i = 1; i < starts.length; i++)
        if (starts[i].difference(starts[i - 1]).inDays >= 18 &&
            starts[i].difference(starts[i - 1]).inDays <= 42)
          starts[i].difference(starts[i - 1]).inDays,
    ];
  }

  List<int> get periodLengths {
    final starts =
        periodDays
            .where(
              (day) =>
                  !periodDays.contains(day.subtract(const Duration(days: 1))),
            )
            .toList()
          ..sort();
    return [for (final start in starts) _periodDurationFrom(start)]
        .where((length) => length > 0 && length <= 14)
        .toList();
  }

  int _periodDurationFrom(DateTime start) {
    var length = 0;
    var day = start;
    while (periodDays.contains(day)) {
      length++;
      day = day.add(const Duration(days: 1));
    }
    return length;
  }

  int _average(List<int> values, int fallback) => values.isEmpty
      ? fallback
      : (values.reduce((a, b) => a + b) / values.length).round();

  Map<String, int> get symptomCounts {
    final counts = <String, int>{};
    for (final day in symptomLogs.values) {
      for (final symptom in day) {
        counts.update(symptom, (count) => count + 1, ifAbsent: () => 1);
      }
    }
    return counts;
  }

  Map<String, int> get moodCounts {
    final counts = <String, int>{};
    for (final mood in moodLogs.values) {
      counts.update(mood, (count) => count + 1, ifAbsent: () => 1);
    }
    return counts;
  }

  Future<void> _copyReport(BuildContext context) async {
    final lengths = cycleLengths;
    final durations = periodLengths;
    final topSymptoms = symptomCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final report = [
      'Kyvra cycle report',
      'Logged cycle starts: ${periodStarts.length}',
      'Average cycle length: ${_average(lengths, fallbackCycleLength)} days${lengths.isEmpty ? ' (setup estimate)' : ''}',
      if (lengths.isNotEmpty)
        'Logged cycle range: ${lengths.reduce((a, b) => a < b ? a : b)}–${lengths.reduce((a, b) => a > b ? a : b)} days',
      'Average period length: ${_average(durations, fallbackPeriodLength)} days${durations.isEmpty ? ' (setup estimate)' : ''}',
      if (topSymptoms.isNotEmpty)
        'Most logged signals: ${topSymptoms.take(5).map((entry) => '${entry.key} (${entry.value})').join(', ')}',
      'Cycle predictions are estimates and are not a method of birth control or a diagnosis.',
    ].join('\n');
    await Clipboard.setData(ClipboardData(text: report));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Cycle report copied to clipboard.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cycles = cycleLengths;
    final durations = periodLengths;
    final averageCycle = _average(cycles, fallbackCycleLength);
    final averagePeriod = _average(durations, fallbackPeriodLength);
    final rankedSymptoms = symptomCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final rankedMoods = moodCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final recentCycles = cycles.length <= 6
        ? cycles
        : cycles.sublist(cycles.length - 6);
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DashboardPageHeader(
                title: 'Cycle history & patterns',
                subtitle: 'A summary of the dates and signals you have logged',
                onBack: () => Navigator.of(context).pop(),
              ),
              Row(
                children: [
                  Expanded(
                    child: _ReportMetric(
                      label: 'Average cycle',
                      value: '$averageCycle days',
                      detail: cycles.isEmpty
                          ? 'Setup estimate'
                          : '${cycles.length} intervals logged',
                      color: terracotta,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _ReportMetric(
                      label: 'Average period',
                      value: '$averagePeriod days',
                      detail: durations.isEmpty
                          ? 'Setup estimate'
                          : '${durations.length} periods logged',
                      color: roseClay,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              _ReportCard(
                title: 'Recent cycle lengths',
                subtitle: recentCycles.isEmpty
                    ? 'Log another period start to begin building your history.'
                    : 'Each bar represents the days between logged period starts.',
                child: recentCycles.isEmpty
                    ? const SizedBox.shrink()
                    : Column(
                        children: [
                          for (var i = 0; i < recentCycles.length; i++) ...[
                            if (i > 0) const SizedBox(height: 12),
                            Row(
                              children: [
                                SizedBox(
                                  width: 78,
                                  child: Text(
                                    'Cycle ${cycles.length - recentCycles.length + i + 1}',
                                    style: sansStyle(
                                      color: stoneMuted,
                                      size: 11,
                                    ),
                                  ),
                                ),
                                Expanded(
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(8),
                                    child: LinearProgressIndicator(
                                      value: (recentCycles[i] / 42).clamp(
                                        0.0,
                                        1.0,
                                      ),
                                      minHeight: 8,
                                      backgroundColor: sand,
                                      color: terracotta,
                                    ),
                                  ),
                                ),
                                SizedBox(
                                  width: 48,
                                  child: Text(
                                    '${recentCycles[i]} d',
                                    textAlign: TextAlign.end,
                                    style: sansStyle(
                                      size: 11,
                                      weight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
              ),
              const SizedBox(height: 14),
              _ReportCard(
                title: 'Most logged body signals',
                subtitle:
                    'Counts are based on the days you saved on this device.',
                child: rankedSymptoms.isEmpty
                    ? const _ReportEmpty(
                        label: 'No symptoms or signals logged yet.',
                      )
                    : Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final entry in rankedSymptoms.take(8))
                            Chip(
                              label: Text('${entry.key} · ${entry.value}'),
                              backgroundColor: terracotta.withAlpha(24),
                              side: BorderSide(color: terracotta.withAlpha(70)),
                              labelStyle: sansStyle(size: 11, color: ink),
                            ),
                        ],
                      ),
              ),
              const SizedBox(height: 14),
              _ReportCard(
                title: 'Mood check-ins',
                subtitle: 'Your saved mood entries, grouped by label.',
                child: rankedMoods.isEmpty
                    ? const _ReportEmpty(label: 'No mood check-ins logged yet.')
                    : Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final entry in rankedMoods)
                            Chip(
                              label: Text('${entry.key} · ${entry.value}'),
                              backgroundColor: sageLeaf.withAlpha(22),
                              side: BorderSide(color: sageLeaf.withAlpha(70)),
                              labelStyle: sansStyle(size: 11, color: ink),
                            ),
                        ],
                      ),
              ),
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: sand,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: borderStone),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.info_outline_rounded, color: stoneMuted),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Cycle and fertile-window dates are estimates. They cannot diagnose a condition or be used as birth control.',
                        style: sansStyle(
                          size: 11,
                          color: stoneMuted,
                          height: 1.45,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => _copyReport(context),
                  icon: const Icon(Icons.copy_rounded),
                  label: const Text('Copy summary for a health visit'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: ink,
                    side: const BorderSide(color: borderStone),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReportMetric extends StatelessWidget {
  final String label;
  final String value;
  final String detail;
  final Color color;

  const _ReportMetric({
    required this.label,
    required this.value,
    required this.detail,
    required this.color,
  });

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(15),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: borderStone),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: sansStyle(size: 11, color: stoneMuted)),
        const SizedBox(height: 6),
        Text(value, style: serifStyle(size: 21, color: color)),
        const SizedBox(height: 3),
        Text(detail, style: sansStyle(size: 10, color: stoneMuted)),
      ],
    ),
  );
}

class _ReportCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final Widget child;

  const _ReportCard({
    required this.title,
    required this.subtitle,
    required this.child,
  });

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(17),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: borderStone),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: serifStyle(size: 18)),
        const SizedBox(height: 3),
        Text(subtitle, style: sansStyle(size: 11, color: stoneMuted)),
        const SizedBox(height: 14),
        child,
      ],
    ),
  );
}

class _ReportEmpty extends StatelessWidget {
  final String label;
  const _ReportEmpty({required this.label});

  @override
  Widget build(BuildContext context) =>
      Text(label, style: sansStyle(size: 12, color: stoneMuted));
}

// ---------------------------------------------------------------------------
// BLOSSOM CHAT PAGE AND EXPANDABLE CHAT PANEL
// ---------------------------------------------------------------------------
class BlossomChatPage extends StatelessWidget {
  final Map<int, Map<String, double>> scannedResults;

  const BlossomChatPage({super.key, required this.scannedResults});

  void _openChat(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => BlossomChatSheet(scannedResults: scannedResults),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Row(
        children: [
          const FlowerMark(size: 24),
          const SizedBox(width: 9),
          Text('OVA', style: serifStyle(size: 21)),
        ],
      ),
    ),
    body: SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(28, 24, 28, 100),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const FlowerMark(size: 62),
                const SizedBox(height: 22),
                Text(
                  'A little space for your questions',
                  textAlign: TextAlign.center,
                  style: serifStyle(size: 29, color: ink),
                ),
                const SizedBox(height: 10),
                Text(
                  'Explore general information about menstrual cycles and women’s health, at your own pace.',
                  textAlign: TextAlign.center,
                  style: sansStyle(size: 14, color: stoneMuted, height: 1.6),
                ),
                const SizedBox(height: 22),
                Container(
                  padding: const EdgeInsets.all(15),
                  decoration: BoxDecoration(
                    color: sand,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: borderStone),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(
                        Icons.favorite_border_rounded,
                        color: terracotta,
                        size: 19,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'OVA can share general information, but it can’t diagnose or replace a qualified health professional.',
                          style: sansStyle(size: 11, color: stoneMuted),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
    floatingActionButton: FloatingActionButton.extended(
      heroTag: 'openBlossomChat',
      onPressed: () => _openChat(context),
      backgroundColor: ink,
      foregroundColor: alabaster,
      icon: const Icon(Icons.chat_rounded),
      label: Text(
        'Start a conversation',
        style: sansStyle(color: alabaster, size: 13, weight: FontWeight.w700),
      ),
    ),
  );
}

class _BlossomChatLine {
  final String text;
  final bool fromUser;
  final bool isError;
  final bool includeInContext;

  const _BlossomChatLine(
    this.text, {
    this.fromUser = false,
    this.isError = false,
    this.includeInContext = true,
  });
}

class BlossomChatSheet extends StatefulWidget {
  final Map<int, Map<String, double>> scannedResults;

  const BlossomChatSheet({super.key, required this.scannedResults});

  @override
  State<BlossomChatSheet> createState() => _BlossomChatSheetState();
}

class _BlossomChatSheetState extends State<BlossomChatSheet> {
  final BlossomChatApi _api = BlossomChatApi();
  final TextEditingController _composer = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final List<_BlossomChatLine> _messages = [
    const _BlossomChatLine(
      'Hi, I’m OVA. I can share general menstrual-cycle and women’s health information. What would you like to talk about?',
    ),
  ];
  bool _sending = false;
  bool _awaitingAssayConfirmation = false;

  @override
  void dispose() {
    _api.close();
    _composer.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToLatest() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    });
  }

  Future<void> _send([String? suggestedText]) async {
    final text = (suggestedText ?? _composer.text).trim();
    if (text.isEmpty || _sending) return;

    _composer.clear();
    setState(() {
      _messages.add(_BlossomChatLine(text, fromUser: true));
      _sending = true;
    });
    _scrollToLatest();

    try {
      late final String answer;
      final isPeriodTimingQuestion = LocalChatResponder.isPeriodTimingQuestion(
        text,
      );
      final isAssayFlow = _awaitingAssayConfirmation || isPeriodTimingQuestion;

      if (isAssayFlow) {
        final isReviewingChart =
            _awaitingAssayConfirmation &&
            LocalChatResponder.isAffirmative(text);
        await Future<void>.delayed(
          Duration(milliseconds: isReviewingChart ? 760 : 320),
        );

        if (_awaitingAssayConfirmation && LocalChatResponder.isNegative(text)) {
          answer = LocalChatResponder.noAssayReply();
          _awaitingAssayConfirmation = false;
        } else if (isReviewingChart) {
          answer = LocalChatResponder.reviewAssayChart(widget.scannedResults);
          _awaitingAssayConfirmation = false;
        } else if (_awaitingAssayConfirmation) {
          answer = 'No rush. Just reply yes if you used the four-marker Assay Scan, or no if you haven’t. I’ll take it from there.';
        } else {
          answer = LocalChatResponder.replyTo(text);
          _awaitingAssayConfirmation = true;
        }
      } else if (_api.isConfigured) {
        final history = _messages
            .where((message) => message.includeInContext)
            .map(
              (message) => ChatApiMessage(
                role: message.fromUser ? 'user' : 'assistant',
                content: message.text,
              ),
            )
            .toList(growable: false);
        answer = await _api.sendMessage(history);
      } else {
        await Future<void>.delayed(const Duration(milliseconds: 320));
        answer = LocalChatResponder.replyTo(text);
      }
      if (!mounted) return;
      setState(() => _messages.add(_BlossomChatLine(answer)));
    } on ChatApiException catch (error) {
      if (!mounted) return;
      _excludeLastUserTurnFromContext();
      setState(
        () => _messages.add(
          _BlossomChatLine(
            error.message,
            isError: true,
            includeInContext: false,
          ),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      _excludeLastUserTurnFromContext();
      setState(
        () => _messages.add(
          const _BlossomChatLine(
            'I couldn’t reach the chat service. Please check your connection and try again.',
            isError: true,
            includeInContext: false,
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _sending = false);
        _scrollToLatest();
      }
    }
  }

  void _excludeLastUserTurnFromContext() {
    if (_messages.isEmpty || !_messages.last.fromUser) return;
    final failedTurn = _messages.last;
    _messages[_messages.length - 1] = _BlossomChatLine(
      failedTurn.text,
      fromUser: true,
      includeInContext: false,
    );
  }

  Widget _messageBubble(_BlossomChatLine message) {
    final isUser = message.fromUser;
    final background = isUser
        ? ink
        : message.isError
        ? const Color(0xFFFFEEE9)
        : Colors.white;
    final foreground = isUser
        ? alabaster
        : message.isError
        ? const Color(0xFF9A3E2E)
        : ink;

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 310),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(18),
              topRight: const Radius.circular(18),
              bottomLeft: Radius.circular(isUser ? 18 : 5),
              bottomRight: Radius.circular(isUser ? 5 : 18),
            ),
            border: Border.all(
              color: isUser
                  ? ink
                  : (message.isError ? background : borderStone),
            ),
          ),
          child: Text(
            message.text,
            style: sansStyle(size: 12, color: foreground, height: 1.5),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final keyboardHeight = media.viewInsets.bottom;
    final panelHeight = (media.size.height - keyboardHeight) * 0.94;
    final hasUserMessage = _messages.any((message) => message.fromUser);

    return Padding(
      padding: EdgeInsets.only(bottom: keyboardHeight),
      child: SizedBox(
        height: panelHeight,
        child: Container(
          decoration: const BoxDecoration(
            color: alabaster,
            borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
          ),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 12, 12, 12),
                child: Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: terracotta.withAlpha(28),
                        shape: BoxShape.circle,
                      ),
                      child: const Center(child: FlowerMark(size: 24)),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('OVA', style: serifStyle(size: 19)),
                          Text(
                            'General information • not a diagnosis',
                            style: sansStyle(size: 9, color: stoneMuted),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Close chat',
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close_rounded, color: stoneMuted),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1, color: borderStone),
              if (!_api.isConfigured)
                Container(
                  width: double.infinity,
                  margin: const EdgeInsets.fromLTRB(14, 12, 14, 0),
                  padding: const EdgeInsets.all(11),
                  decoration: BoxDecoration(
                    color: sand,
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: Text(
                    'Offline demo mode: OVA matches your keywords to prepared replies. Messages stay on your device; this isn’t an AI chat.',
                    style: sansStyle(size: 10, color: stoneMuted),
                  ),
                ),
              Expanded(
                child: ListView.separated(
                  controller: _scrollController,
                  padding: const EdgeInsets.fromLTRB(14, 16, 14, 12),
                  itemCount: _messages.length + (_sending ? 1 : 0),
                  separatorBuilder: (_, _) => const SizedBox(height: 9),
                  itemBuilder: (context, index) {
                    if (index == _messages.length) {
                      return const Align(
                        alignment: Alignment.centerLeft,
                        child: Padding(
                          padding: EdgeInsets.all(12),
                          child: SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: terracotta,
                            ),
                          ),
                        ),
                      );
                    }
                    return _messageBubble(_messages[index]);
                  },
                ),
              ),
              if (!hasUserMessage)
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
                  child: Wrap(
                    spacing: 7,
                    runSpacing: 2,
                    children:
                        [
                              'How can I track my cycle?',
                              'What can affect cycle length?',
                              'How can I understand my hormones?',
                              'My periods are not on time',
                            ]
                            .map(
                              (prompt) => ActionChip(
                                label: Text(prompt, style: sansStyle(size: 10)),
                                backgroundColor: Colors.white,
                                side: const BorderSide(color: borderStone),
                                onPressed: _sending
                                    ? null
                                    : () => _send(prompt),
                              ),
                            )
                            .toList(),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 4, 14, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _api.isConfigured
                          ? 'Messages are sent to your configured chat backend. Avoid sharing identifying details.'
                          : 'Try keywords like cycle, hormones, late or irregular periods, cramps, or PMS.',
                      style: sansStyle(size: 9, color: stoneMuted),
                    ),
                    const SizedBox(height: 7),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _composer,
                            minLines: 1,
                            maxLines: 4,
                            maxLength: 2000,
                            buildCounter: (
                              context, {
                              required currentLength,
                              required isFocused,
                              required maxLength,
                            }) => null,
                            textCapitalization: TextCapitalization.sentences,
                            textInputAction: TextInputAction.send,
                            onSubmitted: (_) => _send(),
                            decoration: InputDecoration(
                              hintText: 'Write a message…',
                              hintStyle: sansStyle(size: 12, color: stoneMuted),
                              filled: true,
                              fillColor: Colors.white,
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 12,
                              ),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(18),
                                borderSide: const BorderSide(
                                  color: borderStone,
                                ),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(18),
                                borderSide: const BorderSide(
                                  color: borderStone,
                                ),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(18),
                                borderSide: const BorderSide(color: terracotta),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        SizedBox(
                          height: 46,
                          width: 46,
                          child: IconButton.filled(
                            tooltip: 'Send message',
                            onPressed: _sending ? null : () => _send(),
                            style: IconButton.styleFrom(
                              backgroundColor: ink,
                              foregroundColor: alabaster,
                              disabledBackgroundColor: sandDark,
                            ),
                            icon: const Icon(Icons.arrow_upward_rounded),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 360° RADIAL CYCLE WHEEL PAINTER
// ---------------------------------------------------------------------------
class CycleWheelPainter extends CustomPainter {
  final double progress;
  final int cycleLength;
  final int periodLength;
  final int ovulationDay;
  final Color activeColor;

  CycleWheelPainter({
    required this.progress,
    required this.cycleLength,
    required this.periodLength,
    required this.ovulationDay,
    required this.activeColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width / 2) - 8;
    final rect = Rect.fromCircle(center: center, radius: radius);

    // Background track
    final trackPaint = Paint()
      ..color = Colors.white.withAlpha(31)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 9;
    canvas.drawCircle(center, radius, trackPaint);

    // Phase arcs
    void drawDayArc(int startDay, int endDay, Color color) {
      final startAngle =
          -math.pi / 2 + ((startDay - 1) / cycleLength) * 2 * math.pi;
      final sweepAngle = ((endDay - startDay + 1) / cycleLength) * 2 * math.pi;
      final paint = Paint()
        ..color = color.withAlpha(97)
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = 9;
      canvas.drawArc(rect, startAngle, sweepAngle, false, paint);
    }

    drawDayArc(1, periodLength, roseClay);
    drawDayArc(ovulationDay - 4, ovulationDay + 1, terracotta);

    // Active progress arc
    final activeSweep = (progress.clamp(0.0, 1.0)) * 2 * math.pi;
    final activePaint = Paint()
      ..color = activeColor
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 9;
    canvas.drawArc(rect, -math.pi / 2, activeSweep, false, activePaint);

    // Current Day Knob
    final knobAngle = -math.pi / 2 + activeSweep;
    final knobCenter = Offset(
      center.dx + radius * math.cos(knobAngle),
      center.dy + radius * math.sin(knobAngle),
    );
    canvas.drawCircle(knobCenter, 7, Paint()..color = alabaster);
    canvas.drawCircle(knobCenter, 4.5, Paint()..color = activeColor);
  }

  @override
  bool shouldRepaint(covariant CycleWheelPainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.activeColor != activeColor;
}

class _SheetHandle extends StatelessWidget {
  const _SheetHandle();
  @override
  Widget build(BuildContext context) => Container(
    width: 40,
    height: 4,
    decoration: BoxDecoration(
      color: borderStone,
      borderRadius: BorderRadius.circular(8),
    ),
  );
}

class DashboardPageHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final VoidCallback onBack;

  const DashboardPageHeader({
    super.key,
    required this.title,
    this.subtitle,
    required this.onBack,
  });

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: Row(
      children: [
        IconButton(
          tooltip: 'Back to Today',
          onPressed: onBack,
          icon: const Icon(
            Icons.arrow_back_ios_new_rounded,
            color: ink,
            size: 18,
          ),
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: serifStyle(size: 26)),
              if (subtitle != null)
                Text(subtitle!, style: sansStyle(color: stoneMuted, size: 12)),
            ],
          ),
        ),
      ],
    ),
  );
}

// ---------------------------------------------------------------------------
// CYCLE CALENDAR SCREEN (MULTI-MONTH PROJECTION)
// ---------------------------------------------------------------------------
class CycleCalendarScreen extends StatelessWidget {
  final DateTime visibleMonth;
  final DateTime selectedDate;
  final int cycleDay;
  final int cycleLength;
  final CyclePhase phase;
  final DateTime nextPeriod;
  final Set<DateTime> periodDays;
  final Set<DateTime> forecastPeriodDays;
  final bool Function(DateTime) isFertileWindow;
  final bool Function(DateTime) isOvulationEstimate;
  final VoidCallback onBack;
  final ValueChanged<DateTime> onMonthChanged;
  final ValueChanged<DateTime> onSelectDate;
  final VoidCallback onTogglePeriod;
  final VoidCallback onEditSymptoms;

  const CycleCalendarScreen({
    super.key,
    required this.visibleMonth,
    required this.selectedDate,
    required this.cycleDay,
    required this.cycleLength,
    required this.phase,
    required this.nextPeriod,
    required this.periodDays,
    required this.forecastPeriodDays,
    required this.isFertileWindow,
    required this.isOvulationEstimate,
    required this.onBack,
    required this.onMonthChanged,
    required this.onSelectDate,
    required this.onTogglePeriod,
    required this.onEditSymptoms,
  });

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    padding: const EdgeInsets.fromLTRB(18, 12, 18, 28),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DashboardPageHeader(
          title: 'Cycle Calendar',
          subtitle: 'Dynamic $cycleLength-day rhythm & fertile projections',
          onBack: onBack,
        ),
        Container(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: borderStone),
          ),
          child: Column(
            children: [
              Row(
                children: [
                  IconButton(
                    onPressed: () => onMonthChanged(
                      DateTime(visibleMonth.year, visibleMonth.month - 1),
                    ),
                    icon: const Icon(Icons.chevron_left_rounded, color: ink),
                  ),
                  Expanded(
                    child: Center(
                      child: Text(
                        '${_month(visibleMonth.month)} ${visibleMonth.year}',
                        style: serifStyle(size: 20),
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => onMonthChanged(
                      DateTime(visibleMonth.year, visibleMonth.month + 1),
                    ),
                    icon: const Icon(Icons.chevron_right_rounded, color: ink),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Row(
                children: ['M', 'T', 'W', 'T', 'F', 'S', 'S']
                    .map(
                      (label) => Expanded(
                        child: Center(
                          child: Text(
                            label,
                            style: sansStyle(
                              color: stoneMuted,
                              size: 10,
                              weight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                    )
                    .toList(),
              ),
              const SizedBox(height: 8),
              CycleDateGrid(
                month: visibleMonth,
                selected: selectedDate,
                today: dateOnly(DateTime.now()),
                periodDays: periodDays,
                forecastPeriodDays: forecastPeriodDays,
                isFertileWindow: isFertileWindow,
                isOvulationEstimate: isOvulationEstimate,
                onSelect: onSelectDate,
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Wrap(
          spacing: 16,
          runSpacing: 8,
          children: const [
            _CalendarLegend(color: roseClay, label: 'Logged flow'),
            _CalendarLegend(color: Color(0xFFF3C6CE), label: 'Forecasted flow'),
            _CalendarLegend(color: Color(0xFFF5D5C6), label: 'Fertile window'),
            _CalendarLegend(color: terracotta, label: 'Ovulation peak'),
          ],
        ),
        const SizedBox(height: 18),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: ink,
            borderRadius: BorderRadius.circular(24),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    formatDateLong(selectedDate).toUpperCase(),
                    style: sansStyle(
                      color: Colors.white60,
                      size: 10,
                      weight: FontWeight.w700,
                      letterSpacing: 1.2,
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: phase.color.withAlpha(64),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      phase.label,
                      style: sansStyle(
                        color: alabaster,
                        size: 10,
                        weight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Cycle Day $cycleDay of $cycleLength',
                style: serifStyle(color: alabaster, size: 26),
              ),
              const SizedBox(height: 6),
              Text(
                phase.tagline,
                style: sansStyle(color: Colors.white70, size: 12),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: onTogglePeriod,
                      icon: Icon(
                        periodDays.contains(dateOnly(selectedDate))
                            ? Icons.remove_circle_outline
                            : Icons.water_drop_rounded,
                        size: 17,
                      ),
                      label: Text(
                        periodDays.contains(dateOnly(selectedDate))
                            ? 'Unlog Flow'
                            : 'Log Flow Day',
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: roseClay,
                        foregroundColor: alabaster,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: onEditSymptoms,
                      icon: const Icon(Icons.bolt_rounded, size: 17),
                      label: const Text('Log Signals'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: alabaster,
                        side: const BorderSide(color: Colors.white30),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class CycleDateGrid extends StatelessWidget {
  final DateTime month;
  final DateTime selected;
  final DateTime today;
  final Set<DateTime> periodDays;
  final Set<DateTime> forecastPeriodDays;
  final bool Function(DateTime) isFertileWindow;
  final bool Function(DateTime) isOvulationEstimate;
  final ValueChanged<DateTime> onSelect;

  const CycleDateGrid({
    super.key,
    required this.month,
    required this.selected,
    required this.today,
    required this.periodDays,
    required this.forecastPeriodDays,
    required this.isFertileWindow,
    required this.isOvulationEstimate,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final offset = DateTime(month.year, month.month, 1).weekday - 1;
    final dayCount = DateTime(month.year, month.month + 1, 0).day;
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 7,
        mainAxisSpacing: 5,
        crossAxisSpacing: 4,
      ),
      itemCount: offset + dayCount,
      itemBuilder: (context, index) {
        if (index < offset) return const SizedBox();
        final date = DateTime(month.year, month.month, index - offset + 1);
        final selectedDay = sameDate(date, selected);
        final actualPeriod = periodDays.contains(date);
        final estimatedPeriod =
            forecastPeriodDays.contains(date) && !actualPeriod;
        final fertile =
            isFertileWindow(date) && !actualPeriod && !estimatedPeriod;
        final ovulation =
            isOvulationEstimate(date) && !actualPeriod && !estimatedPeriod;

        final fill = selectedDay
            ? ink
            : (actualPeriod
                  ? roseClay
                  : (estimatedPeriod
                        ? const Color(0xFFF9E2E6)
                        : (fertile ? const Color(0xFFFAF0E6) : null)));

        return InkWell(
          borderRadius: BorderRadius.circular(30),
          onTap: () => onSelect(date),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            decoration: BoxDecoration(
              color: fill,
              shape: BoxShape.circle,
              border: Border.all(
                color: selectedDay
                    ? ink
                    : (ovulation
                          ? terracotta
                          : (sameDate(date, today) ? ink : Colors.transparent)),
                width: selectedDay || ovulation || sameDate(date, today)
                    ? 1.5
                    : 0,
              ),
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                Text(
                  '${date.day}',
                  style: sansStyle(
                    color: selectedDay || actualPeriod ? alabaster : ink,
                    size: 12,
                    weight: selectedDay || actualPeriod || ovulation
                        ? FontWeight.w700
                        : FontWeight.w500,
                  ),
                ),
                if (ovulation)
                  Positioned(
                    bottom: 3,
                    child: Container(
                      width: 5,
                      height: 5,
                      decoration: BoxDecoration(
                        color: selectedDay ? alabaster : terracotta,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _CalendarLegend extends StatelessWidget {
  final Color color;
  final String label;
  const _CalendarLegend({required this.color, required this.label});

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 10,
        height: 10,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
      const SizedBox(width: 6),
      Text(label, style: sansStyle(color: stoneMuted, size: 11)),
    ],
  );
}

// ---------------------------------------------------------------------------
// HORMONE INSIGHTS & INTERACTIVE CUBIC SPLINE GRAPH
// ---------------------------------------------------------------------------
const List<String> hormoneNames = ['LH', 'E3G', 'PdG', 'FSH'];

Color hormoneColor(String hormone) {
  switch (hormone) {
    case 'LH':
      return terracotta;
    case 'E3G':
      return roseClay;
    case 'PdG':
      return lutealIndigo;
    default:
      return sageLeaf;
  }
}

String hormoneFullName(String hormone) {
  switch (hormone) {
    case 'LH':
      return 'Luteinizing Hormone';
    case 'E3G':
      return 'Estrone-3-Glucuronide (Estrogen)';
    case 'PdG':
      return 'Pregnanediol Glucuronide (Progesterone)';
    default:
      return 'Follicle-Stimulating Hormone';
  }
}

String hormoneDescription(String hormone) {
  switch (hormone) {
    case 'LH':
      return 'Surges rapidly 24–36 hours prior to egg release. Primary trigger for ovulation.';
    case 'E3G':
      return 'Urinary estrogen metabolite produced by dominant follicle; rises 3–5 days before LH peak.';
    case 'PdG':
      return 'Urinary progesterone metabolite; sustained post-ovulatory rise confirms luteal shift.';
    default:
      return 'Recruits ovarian follicles early in the cycle with a secondary mid-cycle pulse.';
  }
}

List<double> simulatedHormoneValues(
  String hormone,
  int cycleLength, {
  bool pcosAware = false,
}) {
  final safeLength = cycleLength.clamp(21, 35).toInt();
  final ovulationDay = safeLength - 14.0;
  final pcosSurgeOne = (safeLength * 0.40).clamp(9.0, 15.0);
  final pcosSurgeTwo = (safeLength * 0.67).clamp(15.0, 24.0);
  final pcosSurgeThree = (safeLength * 0.84).clamp(19.0, 30.0);
  return List<double>.generate(safeLength, (index) {
    final day = index + 1.0;
    double value;
    switch (hormone) {
      case 'LH':
        value = pcosAware
            ? 19 +
                  29 *
                      math.exp(-0.5 * math.pow((day - pcosSurgeOne) / 1.5, 2)) +
                  39 *
                      math.exp(-0.5 * math.pow((day - pcosSurgeTwo) / 1.6, 2)) +
                  25 *
                      math.exp(
                        -0.5 * math.pow((day - pcosSurgeThree) / 1.8, 2),
                      ) +
                  2.5 * math.sin(day * 0.7)
            : 11 +
                  84 *
                      math.exp(
                        -0.5 * math.pow((day - ovulationDay) / 1.15, 2),
                      ) +
                  1.5 * math.sin(day * 0.7);
        break;
      case 'FSH':
        value = pcosAware
            ? 22 +
                  26 * math.exp(-0.5 * math.pow((day - 3.0) / 2.2, 2)) +
                  7 * math.exp(-0.5 * math.pow((day - pcosSurgeTwo) / 2.1, 2)) +
                  1.2 * math.sin(day * 0.55)
            : 22 +
                  26 * math.exp(-0.5 * math.pow((day - 3.0) / 2.2, 2)) +
                  24 *
                      math.exp(-0.5 * math.pow((day - ovulationDay) / 1.5, 2)) +
                  1.2 * math.sin(day * 0.55);
        break;
      case 'E3G':
        value = pcosAware
            ? 16 +
                  43 *
                      math.exp(
                        -0.5 * math.pow((day - (pcosSurgeOne - 3)) / 3.0, 2),
                      ) +
                  37 *
                      math.exp(
                        -0.5 * math.pow((day - (pcosSurgeTwo - 1)) / 2.6, 2),
                      ) +
                  31 *
                      math.exp(
                        -0.5 * math.pow((day - (pcosSurgeThree - 2)) / 3.2, 2),
                      )
            : 16 +
                  66 *
                      math.exp(
                        -0.5 * math.pow((day - (ovulationDay - 1.5)) / 3.2, 2),
                      ) +
                  32 *
                      math.exp(
                        -0.5 * math.pow((day - (ovulationDay + 6.5)) / 3.8, 2),
                      );
        break;
      default: // PdG
        final lutealPeak = ovulationDay + 6.5;
        value = pcosAware
            ? 9 + 6 * math.exp(-0.5 * math.pow((day - pcosSurgeTwo) / 4.0, 2))
            : 9 +
                  74 *
                      math.exp(-0.5 * math.pow((day - lutealPeak) / 3.9, 2)) *
                      (day > ovulationDay - 1 ? 1.0 : 0.15);
        break;
    }
    return value.clamp(5.0, 96.0).toDouble();
  });
}

class HormoneInsightsScreen extends StatefulWidget {
  final int cycleLength;
  final int cycleDay;
  final int periodLength;
  final int ovulationDay;
  final Map<int, Map<String, double>> scannedResults;
  final Map<int, Map<String, double>> demoResults;
  final VoidCallback onOpenReports;
  final VoidCallback onBack;

  const HormoneInsightsScreen({
    super.key,
    required this.cycleLength,
    required this.cycleDay,
    required this.periodLength,
    required this.ovulationDay,
    required this.scannedResults,
    required this.demoResults,
    required this.onOpenReports,
    required this.onBack,
  });

  @override
  State<HormoneInsightsScreen> createState() => _HormoneInsightsScreenState();
}

class _HormoneInsightsScreenState extends State<HormoneInsightsScreen>
    with SingleTickerProviderStateMixin {
  String selectedHormone = 'LH';
  bool overlayAllHormones = true;
  bool pcosAware = false;
  int? confirmedOvulationDay;
  late int scrubbedDay;
  late AnimationController _chartAnim;

  @override
  void initState() {
    super.initState();
    scrubbedDay = widget.cycleDay.clamp(1, widget.cycleLength);
    _chartAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..forward();
  }

  @override
  void dispose() {
    _chartAnim.dispose();
    super.dispose();
  }

  void _selectHormone(String hormone) {
    setState(() => selectedHormone = hormone);
    _chartAnim.forward(from: 0.25);
  }

  void _updateScrubFromDx(double dx, double width) {
    const leftPad = 32.0;
    const rightPad = 12.0;
    final usable = (width - leftPad - rightPad).clamp(1.0, double.infinity);
    final rel = ((dx - leftPad) / usable).clamp(0.0, 1.0);
    final newDay = (1 + rel * (widget.cycleLength - 1)).round().clamp(
      1,
      widget.cycleLength,
    );
    if (newDay != scrubbedDay) {
      HapticFeedback.selectionClick();
      setState(() => scrubbedDay = newDay);
    }
  }

  String _fertilityStatusForDay(int d) {
    if (pcosAware && confirmedOvulationDay == null) {
      return 'Ovulation not confirmed';
    }
    final ovulationDay = pcosAware
        ? confirmedOvulationDay!
        : widget.ovulationDay;
    if (d == ovulationDay) return 'Peak Fertility';
    if (d >= ovulationDay - 4 && d <= ovulationDay + 1) {
      return 'High Fertility';
    }
    return 'Low Fertility';
  }

  Color _fertilityColorForDay(int day) {
    switch (_fertilityStatusForDay(day)) {
      case 'Peak Fertility':
        return terracotta;
      case 'High Fertility':
        return sageLeaf;
      case 'Low Fertility':
        return stoneMuted;
      default:
        return lutealIndigo;
    }
  }

  int? _dpoForDay(int day) {
    if (pcosAware && confirmedOvulationDay == null) return null;
    final ovulationDay = pcosAware
        ? confirmedOvulationDay!
        : widget.ovulationDay;
    return day > ovulationDay ? day - ovulationDay : null;
  }

  void _setPcosAware(bool enabled) {
    setState(() {
      pcosAware = enabled;
      confirmedOvulationDay = null;
    });
    _chartAnim.forward(from: 0.25);
  }

  @override
  Widget build(BuildContext context) {
    final values = simulatedHormoneValues(
      selectedHormone,
      widget.cycleLength,
      pcosAware: pcosAware,
    );
    final safeDay = scrubbedDay.clamp(1, values.length);
    final activeVal = values[safeDay - 1];
    final prevVal = safeDay > 1 ? values[safeDay - 2] : activeVal;
    final delta = activeVal - prevVal;
    final selectedDpo = _dpoForDay(safeDay);
    final color = hormoneColor(selectedHormone);

    final graphHormones = overlayAllHormones
        ? [...hormoneNames.where((h) => h != selectedHormone), selectedHormone]
        : [selectedHormone];

    final graphSeries = graphHormones
        .map(
          (h) => HormoneSeries(
            label: h,
            values: simulatedHormoneValues(
              h,
              widget.cycleLength,
              pcosAware: pcosAware,
            ),
            color: hormoneColor(h),
            highlighted: h == selectedHormone,
          ),
        )
        .toList();
    final demoResultsForChart = <int, Map<String, double>>{};
    if (widget.demoResults.isNotEmpty) {
      final demoLength = widget.cycleLength.clamp(21, 35).toInt();
      final demoCurves = {
        for (final hormone in hormoneNames)
          hormone: simulatedHormoneValues(
            hormone,
            demoLength,
            pcosAware: pcosAware,
          ),
      };
      for (var day = 1; day <= demoLength; day++) {
        demoResultsForChart[day] = {
          for (final hormone in hormoneNames)
            hormone: demoCurves[hormone]![day - 1],
        };
      }
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DashboardPageHeader(
            title: 'Hormone Curves',
            subtitle: 'Explore illustrative hormone patterns across a cycle',
            onBack: widget.onBack,
          ),
          TextButton.icon(
            onPressed: widget.onOpenReports,
            icon: const Icon(Icons.description_outlined),
            label: const Text('Tests & reports'),
          ),
          const Padding(
            padding: EdgeInsets.only(top: 10),
            child: Text(
              'These curves are simulated, not measured concentrations. Fertility labels and DPO use calendar estimates or a date you mark; they do not confirm ovulation.',
              style: TextStyle(fontSize: 13, height: 1.5, color: stoneMuted),
            ),
          ),

          // PCOS-aware view: irregular cycles should not inherit a calendar-only
          // ovulation or DPO estimate.
          Container(
            margin: const EdgeInsets.only(top: 14),
            padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: pcosAware ? lutealIndigo : borderStone),
            ),
            child: Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: lutealIndigo.withAlpha(22),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.tune_rounded,
                    color: lutealIndigo,
                    size: 19,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'PCOS / irregular cycle view',
                        style: sansStyle(size: 12, weight: FontWeight.w700),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        pcosAware
                            ? 'Example pattern; mark ovulation to start DPO.'
                            : 'Show an example with variable hormone surges.',
                        style: sansStyle(size: 10, color: stoneMuted),
                      ),
                    ],
                  ),
                ),
                Switch.adaptive(
                  value: pcosAware,
                  activeTrackColor: lutealIndigo,
                  onChanged: _setPcosAware,
                ),
              ],
            ),
          ),

          // Hormone Selector Pills + Compare Toggle
          Row(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: hormoneNames.map((hormone) {
                      final chosen = hormone == selectedHormone;
                      final hColor = hormoneColor(hormone);
                      return Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          label: Text(hormone),
                          selected: chosen,
                          onSelected: (_) => _selectHormone(hormone),
                          selectedColor: hColor,
                          backgroundColor: Colors.white,
                          labelStyle: sansStyle(
                            size: 12,
                            color: chosen ? alabaster : ink,
                            weight: FontWeight.w700,
                          ),
                          side: BorderSide(
                            color: chosen ? hColor : borderStone,
                          ),
                          shape: const StadiumBorder(),
                          showCheckmark: false,
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ),
              FilterChip(
                label: const Text('All 4'),
                selected: overlayAllHormones,
                onSelected: (v) {
                  setState(() => overlayAllHormones = v);
                  _chartAnim.forward(from: 0.3);
                },
                selectedColor: ink,
                backgroundColor: Colors.white,
                labelStyle: sansStyle(
                  size: 11,
                  color: overlayAllHormones ? alabaster : ink,
                  weight: FontWeight.w700,
                ),
                showCheckmark: false,
                shape: const StadiumBorder(),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Main Interactive Chart Card
          Container(
            padding: const EdgeInsets.fromLTRB(16, 18, 16, 16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(26),
              border: Border.all(color: borderStone),
              boxShadow: [
                BoxShadow(
                  color: ink.withAlpha(10),
                  blurRadius: 20,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (widget.demoResults.isNotEmpty) ...[
                  Container(
                    width: double.infinity,
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 11,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: goldWarm.withAlpha(30),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: goldWarm.withAlpha(110)),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.science_outlined,
                          size: 15,
                          color: ink,
                        ),
                        const SizedBox(width: 7),
                        Expanded(
                          child: Text(
                            'DEMO DATA · Sample readings, not measured results',
                            style: sansStyle(
                              size: 10,
                              color: ink,
                              weight: FontWeight.w800,
                            ),
                          ),
                        ),
                        const _DemoDataLegendMark(),
                      ],
                    ),
                  ),
                ],
                // Live Scrubber Header Callout
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: alabaster,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: borderStone),
                  ),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 9,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: color.withAlpha(38),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              'CYCLE DAY $safeDay ${safeDay == widget.cycleDay ? "• TODAY" : ""}',
                              style: sansStyle(
                                size: 10,
                                weight: FontWeight.w700,
                                color: color,
                                letterSpacing: 1.0,
                              ),
                            ),
                          ),
                          const Spacer(),
                          if (selectedDpo != null)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 5,
                              ),
                              decoration: BoxDecoration(
                                color: terracotta.withAlpha(28),
                                borderRadius: BorderRadius.circular(9),
                              ),
                              child: Text(
                                '${pcosAware ? '' : 'EST. '}$selectedDpo DPO',
                                style: sansStyle(
                                  size: 10,
                                  weight: FontWeight.w800,
                                  color: terracotta,
                                ),
                              ),
                            )
                          else
                            Text(
                              pcosAware ? 'DPO pending' : 'Pre-ovulation',
                              style: sansStyle(
                                size: 10,
                                weight: FontWeight.w700,
                                color: stoneMuted,
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 9,
                              vertical: 5,
                            ),
                            decoration: BoxDecoration(
                              color: _fertilityColorForDay(safeDay)
                                  .withAlpha(28),
                              borderRadius: BorderRadius.circular(9),
                            ),
                            child: Text(
                              _fertilityStatusForDay(safeDay),
                              style: sansStyle(
                                size: 10,
                                weight: FontWeight.w800,
                                color: _fertilityColorForDay(safeDay),
                              ),
                            ),
                          ),
                          const Spacer(),
                          Text(
                            '${delta >= 0 ? "+" : ""}${delta.toStringAsFixed(1)} vs prev day',
                            style: sansStyle(
                              size: 10,
                              weight: FontWeight.w700,
                              color: delta >= 0 ? sageLeaf : roseClay,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: hormoneNames.map((h) {
                          final hVals = simulatedHormoneValues(
                            h,
                            widget.cycleLength,
                            pcosAware: pcosAware,
                          );
                          final v = hVals[safeDay - 1];
                          final isSel = h == selectedHormone;
                          final hCol = hormoneColor(h);
                          return Expanded(
                            child: GestureDetector(
                              onTap: () => _selectHormone(h),
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 180),
                                margin: const EdgeInsets.symmetric(
                                  horizontal: 3,
                                ),
                                padding: const EdgeInsets.symmetric(
                                  vertical: 8,
                                  horizontal: 8,
                                ),
                                decoration: BoxDecoration(
                                  color: isSel
                                      ? hCol.withAlpha(31)
                                      : Colors.white,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: isSel ? hCol : borderStone,
                                    width: isSel ? 1.4 : 1,
                                  ),
                                ),
                                child: Column(
                                  children: [
                                    Text(
                                      h,
                                      style: sansStyle(
                                        size: 10,
                                        weight: FontWeight.w700,
                                        color: hCol,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      v.toStringAsFixed(0),
                                      style: serifStyle(size: 18, color: ink),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // Interactive Touch-Scrubbable Spline Canvas
                LayoutBuilder(
                  builder: (context, constraints) => GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTapDown: (d) => _updateScrubFromDx(
                      d.localPosition.dx,
                      constraints.maxWidth,
                    ),
                    onHorizontalDragUpdate: (d) => _updateScrubFromDx(
                      d.localPosition.dx,
                      constraints.maxWidth,
                    ),
                    child: AnimatedBuilder(
                      animation: _chartAnim,
                      builder: (context, _) => SizedBox(
                        height: 310,
                        width: double.infinity,
                        child: CustomPaint(
                          painter: HormoneSplineChartPainter(
                            series: graphSeries,
                            scrubbedDay: safeDay,
                            todayCycleDay: widget.cycleDay,
                            periodLength: widget.periodLength,
                            ovulationDay: pcosAware
                                ? confirmedOvulationDay
                                : widget.ovulationDay,
                            dpoEstimated: !pcosAware,
                            dpoForDay: _dpoForDay,
                            animationValue: Curves.easeOutCubic.transform(
                              _chartAnim.value,
                            ),
                            scannedResults: widget.scannedResults,
                            demoResults: demoResultsForChart,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 10),

                if (!pcosAware || confirmedOvulationDay != null)
                  Wrap(
                    spacing: 12,
                    runSpacing: 6,
                    children: const [
                      _FertilityLegendItem(
                        label: 'Peak Fertility',
                        color: terracotta,
                      ),
                      _FertilityLegendItem(
                        label: 'High Fertility',
                        color: sageLeaf,
                      ),
                      _FertilityLegendItem(
                        label: 'Low Fertility',
                        color: stoneMuted,
                      ),
                    ],
                  )
                else
                  Text(
                    'Fertility status will appear after ovulation is marked.',
                    style: sansStyle(size: 10, color: stoneMuted),
                  ),
                const SizedBox(height: 8),

                if (pcosAware)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            confirmedOvulationDay == null
                                ? 'LH patterns alone may not confirm ovulation.'
                                : 'Ovulation marked on cycle day $confirmedOvulationDay.',
                            style: sansStyle(
                              size: 10,
                              color: stoneMuted,
                              height: 1.35,
                            ),
                          ),
                        ),
                        TextButton(
                          onPressed: () =>
                              setState(() => confirmedOvulationDay = safeDay),
                          style: TextButton.styleFrom(
                            foregroundColor: lutealIndigo,
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            minimumSize: const Size(0, 36),
                          ),
                          child: Text(
                            confirmedOvulationDay == null
                                ? 'Mark day $safeDay'
                                : 'Set day $safeDay',
                            style: sansStyle(
                              size: 10,
                              weight: FontWeight.w800,
                              color: lutealIndigo,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                // Quick Day Slider
                Row(
                  children: [
                    Text(
                      'SCRUB',
                      style: sansStyle(
                        size: 9,
                        weight: FontWeight.w700,
                        color: stoneMuted,
                        letterSpacing: 1.2,
                      ),
                    ),
                    Expanded(
                      child: SliderTheme(
                        data: SliderTheme.of(context).copyWith(
                          trackHeight: 3,
                          thumbShape: const RoundSliderThumbShape(
                            enabledThumbRadius: 7,
                          ),
                        ),
                        child: Slider(
                          value: safeDay.toDouble(),
                          min: 1,
                          max: widget.cycleLength.toDouble(),
                          activeColor: color,
                          inactiveColor: sand,
                          onChanged: (v) =>
                              setState(() => scrubbedDay = v.round()),
                        ),
                      ),
                    ),
                    Text(
                      'Day $safeDay/${widget.cycleLength}',
                      style: sansStyle(
                        size: 11,
                        weight: FontWeight.w700,
                        color: ink,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Selected Biomarker Deep-Dive Card
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: borderStone),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        color: color,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        hormoneFullName(selectedHormone),
                        style: serifStyle(size: 18),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  hormoneDescription(selectedHormone),
                  style: sansStyle(color: stoneMuted, size: 13, height: 1.5),
                ),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const HormoneGuideScreen(),
                      ),
                    ),
                    icon: const Icon(Icons.menu_book_outlined, size: 17),
                    label: const Text(
                      'Clinical reference guide for all 4 markers',
                    ),
                    style: TextButton.styleFrom(
                      foregroundColor: terracotta,
                      padding: EdgeInsets.zero,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FertilityLegendItem extends StatelessWidget {
  final String label;
  final Color color;

  const _FertilityLegendItem({required this.label, required this.color});

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
      const SizedBox(width: 5),
      Text(
        label,
        style: sansStyle(size: 9, weight: FontWeight.w700, color: color),
      ),
    ],
  );
}

class HormoneSeries {
  final String label;
  final List<double> values;
  final Color color;
  final bool highlighted;

  const HormoneSeries({
    required this.label,
    required this.values,
    required this.color,
    this.highlighted = false,
  });
}

// ---------------------------------------------------------------------------
// SMOOTH CATMULL-ROM / CUBIC BEZIER SPLINE CHART PAINTER
// ---------------------------------------------------------------------------
class HormoneSplineChartPainter extends CustomPainter {
  final List<HormoneSeries> series;
  final int scrubbedDay;
  final int todayCycleDay;
  final int periodLength;
  final int? ovulationDay;
  final bool dpoEstimated;
  final int? Function(int day) dpoForDay;
  final double animationValue;
  final Map<int, Map<String, double>> scannedResults;
  final Map<int, Map<String, double>> demoResults;

  HormoneSplineChartPainter({
    required this.series,
    required this.scrubbedDay,
    required this.todayCycleDay,
    required this.periodLength,
    required this.ovulationDay,
    required this.dpoEstimated,
    required this.dpoForDay,
    required this.animationValue,
    required this.scannedResults,
    required this.demoResults,
  });

  Path _buildSmoothSpline(List<Offset> pts, {required double plotBottom}) {
    final path = Path();
    if (pts.isEmpty) return path;
    path.moveTo(pts.first.dx, pts.first.dy);
    if (pts.length == 1) return path;

    for (int i = 0; i < pts.length - 1; i++) {
      final p0 = i > 0 ? pts[i - 1] : pts[i];
      final p1 = pts[i];
      final p2 = pts[i + 1];
      final p3 = i + 2 < pts.length ? pts[i + 2] : p2;

      final cp1x = p1.dx + (p2.dx - p0.dx) / 6.0;
      final cp1y = (p1.dy + (p2.dy - p0.dy) / 6.0).clamp(8.0, plotBottom);
      final cp2x = p2.dx - (p3.dx - p1.dx) / 6.0;
      final cp2y = (p2.dy - (p3.dy - p1.dy) / 6.0).clamp(8.0, plotBottom);

      path.cubicTo(cp1x, cp1y, cp2x, cp2y, p2.dx, p2.dy);
    }
    return path;
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (series.isEmpty || series.first.values.isEmpty) return;

    const left = 32.0;
    const right = 12.0;
    const top = 24.0;
    const bottom = 58.0;
    final chartWidth = size.width - left - right;
    final chartHeight = size.height - top - bottom;
    if (chartWidth <= 0 || chartHeight <= 0) return;

    final dayCount = series.first.values.length;
    double yFor(double value) =>
        top + chartHeight * (1 - (value * animationValue) / 100);
    double xFor(int index) =>
        left + (dayCount <= 1 ? 0.0 : index / (dayCount - 1)) * chartWidth;

    // 1. Draw phase bands. In PCOS-aware mode the fertile/luteal bands are
    // omitted until the user marks an ovulation day.
    void drawPhaseBand(int startDay, int endDay, Color color, String label) {
      final x1 = xFor((startDay - 1).clamp(0, dayCount - 1));
      final x2 = xFor((endDay - 1).clamp(0, dayCount - 1));
      final rect = Rect.fromLTRB(x1, top, x2, top + chartHeight);
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(8)),
        Paint()..color = color.withAlpha(17),
      );
      final tp = TextPainter(
        text: TextSpan(
          text: label,
          style: sansStyle(
            color: color.withAlpha(191),
            size: 8.5,
            weight: FontWeight.w700,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      if (rect.width > tp.width + 6) {
        tp.paint(canvas, Offset(x1 + 5, top + 4));
      }
    }

    drawPhaseBand(1, periodLength, roseClay, 'MENSTRUAL');
    if (ovulationDay != null) {
      drawPhaseBand(
        ovulationDay! - 4,
        ovulationDay! + 1,
        sageLeaf,
        'HIGH FERTILITY',
      );
      final peakX = xFor(ovulationDay! - 1);
      final dayWidth = chartWidth / (dayCount - 1);
      canvas.drawRect(
        Rect.fromLTRB(
          peakX - dayWidth / 2,
          top,
          peakX + dayWidth / 2,
          top + chartHeight,
        ),
        Paint()..color = terracotta.withAlpha(28),
      );
      drawPhaseBand(ovulationDay! + 2, dayCount, stoneMuted, 'LOW FERTILITY');
    }

    // 2. Horizontal Grid Lines & Y-Axis Labels
    final gridPaint = Paint()
      ..color = borderStone
      ..strokeWidth = 1.1;

    for (final level in [0, 25, 50, 75, 100]) {
      final y = top + chartHeight * (1 - level / 100);
      canvas.drawLine(
        Offset(left, y),
        Offset(size.width - right, y),
        gridPaint,
      );
      final label = TextPainter(
        text: TextSpan(
          text: '$level',
          style: sansStyle(color: stoneMuted, size: 10),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      label.paint(canvas, Offset(0, y - label.height / 2));
    }

    // 3. Draw Smooth Splines + Area Fills
    for (final graph in series) {
      final points = [
        for (var i = 0; i < graph.values.length; i++)
          Offset(xFor(i), yFor(graph.values[i])),
      ];
      final splinePath = _buildSmoothSpline(
        points,
        plotBottom: top + chartHeight,
      );

      if (graph.highlighted) {
        final area = Path.from(splinePath)
          ..lineTo(xFor(graph.values.length - 1), top + chartHeight)
          ..lineTo(xFor(0), top + chartHeight)
          ..close();
        canvas.drawPath(
          area,
          Paint()
            ..shader = LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [graph.color.withAlpha(50), graph.color.withAlpha(3)],
            ).createShader(Rect.fromLTWH(left, top, chartWidth, chartHeight)),
        );
      }

      canvas.drawPath(
        splinePath,
        Paint()
          ..color = graph.highlighted ? graph.color : graph.color.withAlpha(205)
          ..style = PaintingStyle.stroke
          ..strokeWidth = graph.highlighted ? 4.0 : 2.5
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round,
      );

      // Persistent measurement dots make each day's reading easier to follow.
      for (final point in points) {
        canvas.drawCircle(
          point,
          graph.highlighted ? 5.3 : 4.2,
          Paint()..color = Colors.white,
        );
        canvas.drawCircle(
          point,
          graph.highlighted ? 3.6 : 2.8,
          Paint()..color = graph.color,
        );
      }
    }

    // 4. Vertical Scrubber Guide Line
    final scrubIdx = (scrubbedDay - 1).clamp(0, dayCount - 1);
    final scrubX = xFor(scrubIdx);
    canvas.drawLine(
      Offset(scrubX, top),
      Offset(scrubX, top + chartHeight),
      Paint()
        ..color = ink.withAlpha(89)
        ..strokeWidth = 1.4,
    );

    // Selected DPO callout, modeled after the reference chart's date bubble.
    final selectedDpo = dpoForDay(scrubbedDay);
    if (selectedDpo != null) {
      final dpoText = TextPainter(
        text: TextSpan(
          text: '${dpoEstimated ? 'EST. ' : ''}$selectedDpo DPO',
          style: sansStyle(
            color: Colors.white,
            size: 11,
            weight: FontWeight.w800,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      const bubblePaddingX = 10.0;
      const bubblePaddingY = 6.0;
      final bubbleWidth = dpoText.width + bubblePaddingX * 2;
      final bubbleHeight = dpoText.height + bubblePaddingY * 2;
      final bubbleLeft = (scrubX - bubbleWidth / 2)
          .clamp(left, size.width - right - bubbleWidth)
          .toDouble();
      final bubbleRect = Rect.fromLTWH(
        bubbleLeft,
        1,
        bubbleWidth,
        bubbleHeight,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(bubbleRect, const Radius.circular(10)),
        Paint()..color = terracotta,
      );
      dpoText.paint(
        canvas,
        Offset(bubbleLeft + bubblePaddingX, bubblePaddingY),
      );
    }

    // 5. Draw Active Scrubber Nodes on Curves
    for (final graph in series) {
      final pt = Offset(scrubX, yFor(graph.values[scrubIdx]));
      if (graph.highlighted) {
        canvas.drawCircle(pt, 10, Paint()..color = graph.color.withAlpha(51));
      }
      canvas.drawCircle(
        pt,
        graph.highlighted ? 6.0 : 4.2,
        Paint()..color = Colors.white,
      );
      canvas.drawCircle(
        pt,
        graph.highlighted ? 4.0 : 2.6,
        Paint()..color = graph.color,
      );
    }

    // 6. Plot any Scanned Assay Points
    scannedResults.forEach((day, map) {
      if (day >= 1 && day <= dayCount) {
        for (final graph in series) {
          if (graph.highlighted && map.containsKey(graph.label)) {
            final pt = Offset(xFor(day - 1), yFor(map[graph.label]!));
            canvas.drawCircle(pt, 6, Paint()..color = ink);
            canvas.drawCircle(pt, 3, Paint()..color = goldWarm);
          }
        }
      }
    });

    // Demo values use a gold diamond so they remain visually distinct from
    // the model curve and any real reader measurements.
    demoResults.forEach((day, map) {
      if (day >= 1 && day <= dayCount) {
        for (final graph in series) {
          if (graph.highlighted && map.containsKey(graph.label)) {
            final center = Offset(xFor(day - 1), yFor(map[graph.label]!));
            final rect = Rect.fromCenter(center: center, width: 10, height: 10);
            final path = Path()
              ..moveTo(center.dx, rect.top)
              ..lineTo(rect.right, center.dy)
              ..lineTo(center.dx, rect.bottom)
              ..lineTo(rect.left, center.dy)
              ..close();
            canvas.drawPath(path, Paint()..color = Colors.white);
            canvas.drawPath(path, Paint()..color = goldWarm);
          }
        }
      }
    });

    // 7. X-Axis Day Ticks
    final cycleTicks = <int>{1, 7, 14, 21, dayCount, scrubbedDay};
    if (ovulationDay != null) cycleTicks.add(ovulationDay!);
    for (final day in cycleTicks) {
      if (day < 1 || day > dayCount) continue;
      final x = xFor(day - 1);
      final isOv = day == ovulationDay;
      final isToday = day == todayCycleDay;
      final label = TextPainter(
        text: TextSpan(
          text: isOv ? 'D$day★' : 'D$day',
          style: sansStyle(
            color: isOv ? terracotta : (isToday ? ink : stoneMuted),
            size: 10,
            weight: isOv || isToday ? FontWeight.w800 : FontWeight.w600,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      label.paint(canvas, Offset(x - label.width / 2, top + chartHeight + 4));
    }

    // Sparse DPO axis labels keep the lower edge readable on small phones.
    final dpoMilestones = <int>{1, 7, 14};
    for (var day = 1; day <= dayCount; day++) {
      final dpo = dpoForDay(day);
      if (dpo == null || !dpoMilestones.contains(dpo)) {
        continue;
      }
      final x = xFor(day - 1);
      final labelText = '$dpo DPO';
      final label = TextPainter(
        text: TextSpan(
          text: labelText,
          style: sansStyle(
            color: day == scrubbedDay ? terracotta : stoneMuted,
            size: 8,
            weight: day == scrubbedDay ? FontWeight.w800 : FontWeight.w600,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      label.paint(canvas, Offset(x - label.width / 2, top + chartHeight + 24));
    }
  }

  @override
  bool shouldRepaint(covariant HormoneSplineChartPainter oldDelegate) =>
      oldDelegate.series != series ||
      oldDelegate.scrubbedDay != scrubbedDay ||
      oldDelegate.todayCycleDay != todayCycleDay ||
      oldDelegate.ovulationDay != ovulationDay ||
      oldDelegate.animationValue != animationValue ||
      oldDelegate.scannedResults != scannedResults ||
      oldDelegate.demoResults != demoResults;
}

class _DemoDataLegendMark extends StatelessWidget {
  const _DemoDataLegendMark();

  @override
  Widget build(BuildContext context) => Transform.rotate(
    angle: math.pi / 4,
    child: Container(
      width: 9,
      height: 9,
      decoration: BoxDecoration(
        color: goldWarm,
        border: Border.all(color: Colors.white, width: 1.5),
        borderRadius: BorderRadius.circular(2),
      ),
    ),
  );
}

// ---------------------------------------------------------------------------
// HORMONE GUIDE SCREEN
// ---------------------------------------------------------------------------
class HormoneGuideScreen extends StatelessWidget {
  const HormoneGuideScreen({super.key});

  static const hormones =
      <({String acronym, String name, String role, String meaning})>[
        (
          acronym: 'LH',
          name: 'Luteinizing Hormone',
          role: 'Triggers dominant follicle rupture and egg release.',
          meaning: 'A sharp mid-cycle surge precedes ovulation by 24–36 hours. Useful for pinpointing peak fertility.',
        ),
        (
          acronym: 'E3G',
          name: 'Estrone-3-Glucuronide',
          role: 'Primary urinary metabolite of estradiol (E2).',
          meaning: 'Rises progressively as ovarian follicles mature, opening the fertile window several days before the LH surge.',
        ),
        (
          acronym: 'PdG',
          name: 'Pregnanediol-3-Glucuronide',
          role: 'Major urinary metabolite of progesterone.',
          meaning: 'Elevated levels across multiple days following the LH peak help confirm that ovulation successfully occurred.',
        ),
        (
          acronym: 'FSH',
          name: 'Follicle-Stimulating Hormone',
          role: 'Stimulates early ovarian follicle recruitment.',
          meaning: 'Peaks early in the follicular phase to select the dominant follicle, with a secondary pulse alongside LH.',
        ),
      ];

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            DashboardPageHeader(
              title: 'Biomarker Reference',
              subtitle: 'How multiplex urinary hormone panels map the cycle',
              onBack: () => Navigator.of(context).pop(),
            ),
            for (final hormone in hormones)
              Container(
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: borderStone),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 44,
                          height: 44,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: hormoneColor(hormone.acronym).withAlpha(36),
                            borderRadius: BorderRadius.circular(13),
                          ),
                          child: Text(
                            hormone.acronym,
                            style: sansStyle(
                              color: hormoneColor(hormone.acronym),
                              weight: FontWeight.w700,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            hormone.name,
                            style: serifStyle(size: 18),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      hormone.role,
                      style: sansStyle(weight: FontWeight.w700, size: 13),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      hormone.meaning,
                      style: sansStyle(
                        color: stoneMuted,
                        size: 12,
                        height: 1.5,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    ),
  );
}

// ---------------------------------------------------------------------------
// OFFLINE BLE LFA READER
// ---------------------------------------------------------------------------
class LfaTestScreen extends StatefulWidget {
  final VoidCallback onBack;
  final VoidCallback onViewChart;
  final int cycleLength;
  final int cycleDay;
  final ValueChanged<Map<int, Map<String, double>>> onShowDemoData;
  final Future<bool> Function(TestRecord) onRecordTest;
  final VoidCallback onOpenReports;
  final String patientName;
  final int patientAge;
  final int captureCycleDay;

  const LfaTestScreen({
    super.key,
    required this.onBack,
    required this.onViewChart,
    required this.cycleLength,
    required this.cycleDay,
    required this.onShowDemoData,
    required this.onRecordTest,
    required this.onOpenReports,
    required this.patientName,
    required this.patientAge,
    required this.captureCycleDay,
  });

  @override
  State<LfaTestScreen> createState() => _LfaTestScreenState();
}

class _LfaTestScreenState extends State<LfaTestScreen>
    with SingleTickerProviderStateMixin {
  final LfaBleReader _reader = LfaBleReader();
  bool scanning = false;
  bool pairing = false;
  bool demoDataShown = false;
  String status =
      'Pair your reader once. Kyvra will remember it on this phone.';
  LfaSavedReader? savedReader;
  LfaChannelSelection? selection;
  TestRecord? latestRecord;
  late final AnimationController _activityController;

  @override
  void initState() {
    super.initState();
    _activityController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _loadSavedReader();
  }

  Future<void> _loadSavedReader() async {
    try {
      final reader = await LfaReaderStore.load();
      if (!mounted) return;
      setState(() {
        savedReader = reader;
        if (reader != null) status = '${reader.name} is saved on this phone.';
      });
    } catch (_) {
      // BLE pairing can still be used if platform storage is unavailable.
    }
  }

  @override
  void dispose() {
    _activityController.dispose();
    unawaited(_reader.dispose());
    super.dispose();
  }

  Future<void> _pairReader() async {
    if (pairing || scanning) return;
    setState(() {
      pairing = true;
      selection = null;
      status = 'Looking for your reader…';
    });
    _activityController.repeat();
    try {
      final devices = await _reader.discoverReaders(
        onProgress: (message) {
          if (mounted) setState(() => status = message);
        },
      );
      if (!mounted) return;
      if (devices.isEmpty) {
        setState(
          () => status =
              'No reader found. Turn it on and keep it nearby, then try again.',
        );
        return;
      }
      LfaNearbyReader? chosen;
      if (devices.length == 1) {
        chosen = devices.first;
      } else {
        chosen = await showModalBottomSheet<LfaNearbyReader>(
          context: context,
          showDragHandle: true,
          builder: (context) => SafeArea(
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 4, 8, 12),
                  child: Text(
                    'Choose your reader',
                    style: serifStyle(size: 21),
                  ),
                ),
                for (final device in devices)
                  ListTile(
                    leading: const Icon(
                      Icons.bluetooth_rounded,
                      color: lutealIndigo,
                    ),
                    title: Text(device.name),
                    subtitle: Text('Signal ${device.rssi} dBm'),
                    onTap: () => Navigator.of(context).pop(device),
                  ),
              ],
            ),
          ),
        );
      }
      if (chosen == null || !mounted) return;
      final readerToPair = chosen;
      setState(() => status = 'Connecting to ${readerToPair.name}…');
      await _reader.checkReader(readerToPair.id);
      await LfaReaderStore.save(readerToPair);
      if (!mounted) return;
      setState(() {
        savedReader = LfaSavedReader(
          id: readerToPair.id,
          name: readerToPair.name,
        );
        status =
            'Connected and saved. You can use this reader for future tests.';
      });
    } catch (error) {
      if (mounted) setState(() => status = error.toString());
    } finally {
      if (mounted) {
        _activityController.stop();
        setState(() => pairing = false);
      }
    }
  }

  Future<void> _forgetReader() async {
    try {
      await LfaReaderStore.forget();
      if (!mounted) return;
      setState(() {
        savedReader = null;
        selection = null;
        status = 'Reader forgotten. Pair it again when you are ready.';
      });
    } catch (error) {
      if (mounted) setState(() => status = error.toString());
    }
  }

  Future<void> _runScan() async {
    final reader = savedReader;
    if (reader == null) {
      setState(
        () => status = 'Choose “Pair a device” once before starting a test.',
      );
      return;
    }
    final startedAt = DateTime.now();
    final captureDay = widget.captureCycleDay;
    setState(() {
      scanning = true;
      selection = null;
      latestRecord = null;
      status = 'Connecting to ${reader.name}…';
    });
    _activityController.repeat();
    try {
      final session = await _reader.captureSession(
        deviceId: reader.id,
        onProgress: (message) {
          if (mounted) setState(() => status = message);
        },
      );
      if (!mounted) return;
      setState(() => status = 'Comparing the four LED images…');
      final bestImage = await LfaImageSelector.choose(session);
      if (!mounted) return;
      final record = TestRecord(
        id: 'KVL-${startedAt.microsecondsSinceEpoch.toRadixString(36).toUpperCase()}',
        capturedAt: startedAt,
        cycleDay: captureDay,
        isDemo: false,
        readerName: reader.name,
        selectedChannel: _ledLabel(bestImage.led),
        image: bestImage.image,
      );
      final saved = await widget.onRecordTest(record);
      if (!mounted) return;
      setState(() {
        selection = bestImage;
        latestRecord = record;
        status = saved
            ? 'Image capture saved. Open your report to review what is available.'
            : 'Image capture complete. Export a report to keep a copy of this session.';
        scanning = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        status = error.toString();
        scanning = false;
      });
    } finally {
      if (mounted) {
        _activityController.stop();
        setState(() => scanning = false);
      }
    }
  }

  Future<void> _showDemoData() async {
    final safeLength = widget.cycleLength.clamp(21, 35).toInt();
    final curves = {
      for (final hormone in hormoneNames)
        hormone: simulatedHormoneValues(hormone, safeLength),
    };
    final byDay = <int, Map<String, double>>{};
    for (var day = 1; day <= safeLength; day++) {
      byDay[day] = {
        for (final hormone in hormoneNames) hormone: curves[hormone]![day - 1],
      };
    }
    widget.onShowDemoData(byDay);
    final now = DateTime.now();
    final day = widget.cycleDay.clamp(1, safeLength);
    final record = TestRecord(
      id: 'DEMO-${now.microsecondsSinceEpoch.toRadixString(36).toUpperCase()}',
      capturedAt: now,
      cycleDay: day,
      isDemo: true,
      demoValues: byDay[day]!,
    );
    setState(() {
      demoDataShown = true;
      latestRecord = record;
      selection = null;
    });
    await widget.onRecordTest(record);
  }

  void _openLatestReport() {
    final record = latestRecord;
    if (record == null) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => TestReportDetailScreen(
          record: record,
          patientName: widget.patientName,
          patientAge: widget.patientAge,
        ),
      ),
    );
  }

  String _ledLabel(String led) => switch (led) {
    'G' => 'Green',
    'W' => 'White',
    'R' => 'Red',
    'B' => 'Blue',
    _ => led,
  };

  @override
  Widget build(BuildContext context) {
    final selected = selection;
    final busy = scanning || pairing;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DashboardPageHeader(
            title: 'Hormone test',
            subtitle: 'The reader checks all four LED channels automatically',
            onBack: widget.onBack,
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: widget.onOpenReports,
              icon: const Icon(Icons.description_outlined),
              label: const Text('Tests & reports - understand your results'),
            ),
          ),
          const SizedBox(height: 18),
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: borderStone),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  busy
                      ? Icons.bluetooth_searching_rounded
                      : Icons.bluetooth_rounded,
                  color: busy ? terracotta : lutealIndigo,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        busy
                            ? (pairing ? 'Connecting reader' : 'Reading strip')
                            : 'Reader connection',
                        style: sansStyle(size: 13, weight: FontWeight.w700),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        status,
                        style: sansStyle(
                          size: 12,
                          color: stoneMuted,
                          height: 1.45,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(17),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: borderStone),
            ),
            child: savedReader == null
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Have a reader?', style: serifStyle(size: 19)),
                      const SizedBox(height: 4),
                      Text(
                        'Pair it once. The app remembers it for future tests.',
                        style: sansStyle(
                          size: 12,
                          color: stoneMuted,
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: busy ? null : _pairReader,
                          icon: const Icon(Icons.bluetooth_searching_rounded),
                          label: Text(
                            pairing ? 'Connecting…' : 'Pair a device',
                          ),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: ink,
                            side: const BorderSide(color: borderStone),
                            shape: const StadiumBorder(),
                            padding: const EdgeInsets.symmetric(vertical: 13),
                          ),
                        ),
                      ),
                    ],
                  )
                : Row(
                    children: [
                      const Icon(
                        Icons.bluetooth_connected_rounded,
                        color: sageLeaf,
                      ),
                      const SizedBox(width: 11),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              savedReader!.name,
                              style: sansStyle(
                                size: 13,
                                weight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              'Paired on this phone',
                              style: sansStyle(size: 11, color: stoneMuted),
                            ),
                          ],
                        ),
                      ),
                      TextButton(
                        onPressed: busy ? null : _forgetReader,
                        child: Text(
                          'Forget device',
                          style: sansStyle(
                            size: 11,
                            weight: FontWeight.w700,
                            color: terracotta,
                          ),
                        ),
                      ),
                    ],
                  ),
          ),
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: ink,
              borderRadius: BorderRadius.circular(26),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'OFFLINE READER',
                  style: sansStyle(
                    size: 10,
                    weight: FontWeight.w700,
                    color: Colors.white60,
                    letterSpacing: 1.4,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'Place the test strip in the reader, then start the scan. The reader checks it automatically and the app chooses the clearest image for you.',
                  style: sansStyle(size: 13, color: Colors.white, height: 1.5),
                ),
                const SizedBox(height: 18),
                if (scanning) ...[
                  LfaCaptureAnimation(
                    controller: _activityController,
                    caption: 'Reading test strip…',
                  ),
                  const SizedBox(height: 14),
                ] else if (pairing) ...[
                  LfaCaptureAnimation(
                    controller: _activityController,
                    caption: 'Pairing your reader',
                    pairing: true,
                  ),
                  const SizedBox(height: 14),
                ],
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton.icon(
                    onPressed: busy || savedReader == null ? null : _runScan,
                    icon: Icon(
                      scanning
                          ? Icons.radar_rounded
                          : Icons.document_scanner_rounded,
                    ),
                    label: Text(
                      scanning
                          ? 'Reading strip…'
                          : savedReader == null
                          ? 'Pair a device first'
                          : 'Start test',
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: terracotta,
                      foregroundColor: alabaster,
                      shape: const StadiumBorder(),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: alabaster,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: borderStone),
            ),
            child: Row(
              children: [
                const Icon(Icons.science_outlined, color: lutealIndigo),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Explore with sample readings',
                        style: sansStyle(size: 12, weight: FontWeight.w800),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        'Clearly marked demo values can be added to the chart.',
                        style: sansStyle(
                          size: 11,
                          color: stoneMuted,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ),
                ),
                TextButton(
                  onPressed: busy ? null : _showDemoData,
                  child: Text(
                    demoDataShown ? 'Shown' : 'Show demo data',
                    style: sansStyle(
                      size: 11,
                      weight: FontWeight.w800,
                      color: terracotta,
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (demoDataShown && latestRecord?.isDemo == true)
            Padding(
              padding: const EdgeInsets.only(top: 9),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Sample cycle readings, including cycle day ${widget.cycleDay}, were added to the chart and are labeled DEMO DATA.',
                    style: sansStyle(size: 11, color: stoneMuted, height: 1.4),
                  ),
                  const SizedBox(height: 10),
                  PrimaryButton(
                    label: 'View demo chart',
                    onTap: widget.onViewChart,
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: _openLatestReport,
                    icon: const Icon(Icons.picture_as_pdf_outlined),
                    label: const Text('View test report / create PDF'),
                  ),
                ],
              ),
            ),
          if (selected != null) ...[
            const SizedBox(height: 18),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: borderStone),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${_ledLabel(selected.led)} LED selected automatically',
                    style: serifStyle(size: 20),
                  ),
                  const SizedBox(height: 10),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: Container(
                      width: double.infinity,
                      constraints: const BoxConstraints(maxHeight: 340),
                      color: const Color(0xFFF3F2F5),
                      child: Image.memory(
                        selected.image,
                        fit: BoxFit.contain,
                        gaplessPlayback: true,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'All four channels were checked on this phone. Hormone values are not added to your chart until the strip calibration is configured.',
                    style: sansStyle(size: 12, color: stoneMuted, height: 1.5),
                  ),
                  const SizedBox(height: 14),
                  PrimaryButton(
                    label: 'View test report / create PDF',
                    onTap: _openLatestReport,
                  ),
                  const SizedBox(height: 10),
                  PrimaryButton(
                    label: 'View hormone chart',
                    onTap: widget.onViewChart,
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class LfaCaptureAnimation extends StatelessWidget {
  final Animation<double> controller;
  final String caption;
  final bool pairing;

  const LfaCaptureAnimation({
    super.key,
    required this.controller,
    required this.caption,
    this.pairing = false,
  });

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (context, _) => Row(
      children: [
        pairing ? _bluetoothPulse() : _stripEnteringReader(),
        const SizedBox(width: 11),
        Expanded(
          child: Text(
            caption,
            style: sansStyle(
              size: 11,
              color: Colors.white70,
              weight: FontWeight.w600,
            ),
          ),
        ),
      ],
    ),
  );

  Widget _bluetoothPulse() {
    final pulse = (math.sin(controller.value * math.pi * 2) + 1) / 2;
    return SizedBox(
      width: 52,
      height: 42,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: 27 + pulse * 14,
            height: 27 + pulse * 14,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: roseClay.withAlpha((100 * (1 - pulse)).round()),
              ),
            ),
          ),
          const Icon(
            Icons.bluetooth_searching_rounded,
            color: roseClay,
            size: 25,
          ),
        ],
      ),
    );
  }

  Widget _stripEnteringReader() {
    final phase = controller.value;
    final insertion = phase < 0.42 ? phase / 0.42 : 1.0;
    final stripLeft = -5 + insertion * 23;
    final scanPulse =
        (math.sin((phase - 0.42).clamp(0.0, 1.0) * math.pi * 3) + 1) / 2;
    return SizedBox(
      width: 64,
      height: 42,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: 11,
            top: 5,
            child: Container(
              width: 50,
              height: 32,
              decoration: BoxDecoration(
                color: Colors.white.withAlpha(18),
                border: Border.all(color: Colors.white60, width: 1.2),
                borderRadius: BorderRadius.circular(9),
              ),
            ),
          ),
          Positioned(
            left: 12,
            top: 15,
            child: Container(
              width: 5,
              height: 9,
              decoration: BoxDecoration(
                color: ink,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Positioned(
            left: stripLeft,
            top: 17,
            child: Container(
              width: 33,
              height: 5,
              decoration: BoxDecoration(
                color: roseClay,
                borderRadius: BorderRadius.circular(3),
                boxShadow: [
                  BoxShadow(color: roseClay.withAlpha(70), blurRadius: 6),
                ],
              ),
            ),
          ),
          Positioned(
            right: 5,
            top: 10,
            child: Container(
              width: 2,
              height: 22,
              decoration: BoxDecoration(
                color: Colors.white.withAlpha((60 + scanPulse * 130).round()),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// PROFILE SCREEN
// ---------------------------------------------------------------------------
class ProfileScreen extends StatelessWidget {
  final String name;
  final int age;
  final int cycleLength;
  final int periodLength;
  final int loggedPeriodsCount;
  final List<String> goals;
  final VoidCallback onBack;

  const ProfileScreen({
    super.key,
    required this.name,
    required this.age,
    required this.cycleLength,
    required this.periodLength,
    required this.loggedPeriodsCount,
    required this.goals,
    required this.onBack,
  });

  void _logOut(BuildContext context) {
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute<void>(builder: (_) => const WelcomeScreen()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DashboardPageHeader(
          title: 'Profile & Cycle Setup',
          subtitle: 'Your cycle parameters and active focus areas',
          onBack: onBack,
        ),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: borderStone),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 26,
                    backgroundColor: terracotta.withAlpha(38),
                    child: Text(
                      (name.isEmpty ? 'A' : name[0]).toUpperCase(),
                      style: serifStyle(size: 22, color: terracotta),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name.isEmpty ? 'Blossom Member' : name,
                          style: serifStyle(size: 22),
                        ),
                        Text(
                          '$age years • $loggedPeriodsCount cycles logged',
                          style: sansStyle(color: stoneMuted, size: 12),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              const Divider(color: borderStone),
              const SizedBox(height: 12),
              _ProfileDetail(
                label: 'Dynamic cycle length',
                value: '$cycleLength days',
              ),
              const SizedBox(height: 12),
              _ProfileDetail(
                label: 'Typical bleed duration',
                value: '$periodLength days',
              ),
              const SizedBox(height: 12),
              _ProfileDetail(
                label: 'Active tracking goals',
                value: goals.isEmpty
                    ? 'General cycle awareness'
                    : goals.join(' • '),
              ),
            ],
          ),
        ),
        const SizedBox(height: 22),
        SizedBox(
          width: double.infinity,
          height: 52,
          child: OutlinedButton.icon(
            onPressed: () => _logOut(context),
            icon: const Icon(Icons.logout_rounded, size: 18),
            label: const Text('Reset Session & Log Out'),
            style: OutlinedButton.styleFrom(
              foregroundColor: roseClay,
              side: const BorderSide(color: roseClay),
              shape: const StadiumBorder(),
            ),
          ),
        ),
      ],
    ),
  );
}

class _ProfileDetail extends StatelessWidget {
  final String label;
  final String value;
  const _ProfileDetail({required this.label, required this.value});

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: sansStyle(color: stoneMuted, size: 11)),
      const SizedBox(height: 3),
      Text(
        value,
        style: sansStyle(color: ink, size: 14, weight: FontWeight.w700),
      ),
    ],
  );
}
