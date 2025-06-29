// lib/screens/login_screen.dart

import 'package:flutter/material.dart';
import 'package:prestinv/config/app_colors.dart';
import 'package:prestinv/config/app_config.dart';
import 'package:prestinv/providers/auth_provider.dart';
import 'package:prestinv/screens/config_screen.dart';
import 'package:prestinv/screens/home_screen.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _loginController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isPasswordVisible = false;

  @override
  void initState() {
    super.initState();
    _loadCredentials();
  }

  /// Charge les identifiants depuis le stockage si "Rester connecté" était coché.
  Future<void> _loadCredentials() async {
    final prefs = await SharedPreferences.getInstance();
    // On utilise `mounted` pour s'assurer que le widget existe toujours
    if (!mounted) return;
    final authProvider = Provider.of<AuthProvider>(context, listen: false);

    if (authProvider.rememberMe) {
      _loginController.text = prefs.getString('savedLogin') ?? '';
      _passwordController.text = prefs.getString('savedPassword') ?? '';
    }
  }

  @override
  void dispose() {
    _loginController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  /// Gère la logique de connexion lors du clic sur le bouton.
  void _handleLogin() async {
    // On vérifie que le widget est toujours monté avant d'utiliser son context
    if (!mounted) return;
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final appConfig = Provider.of<AppConfig>(context, listen: false);

    bool success = await authProvider.login(
      _loginController.text.trim(),
      _passwordController.text.trim(),
      appConfig,
    );

    if (!mounted) return;

    if (success) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const HomeScreen()),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(authProvider.errorMessage ?? 'Une erreur est survenue.'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        // Fond d'écran avec la nouvelle couleur primaire
        decoration: const BoxDecoration(
          color: AppColors.primary,
        ),
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(32.0),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Card(
                // Le CardTheme du main.dart s'applique ici
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 32.0),
                  child: Consumer<AuthProvider>(
                    builder: (context, auth, child) {
                      return Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.inventory_2_outlined, size: 64, color: AppColors.accent),
                          const SizedBox(height: 16),
                          const Text(
                            'Prestige Inv',
                            style: TextStyle(fontSize: 36, fontWeight: FontWeight.bold, color: AppColors.primary),
                          ),
                          const SizedBox(height: 32),
                          TextField(
                            controller: _loginController,
                            decoration: const InputDecoration(
                              labelText: 'Identifiant',
                              prefixIcon: Icon(Icons.person_outline),
                            ),
                            onSubmitted: (_) => _handleLogin(),
                          ),
                          const SizedBox(height: 16),
                          TextField(
                            controller: _passwordController,
                            obscureText: !_isPasswordVisible,
                            decoration: InputDecoration(
                              labelText: 'Mot de passe',
                              prefixIcon: const Icon(Icons.lock_outline),
                              suffixIcon: IconButton(
                                icon: Icon(_isPasswordVisible ? Icons.visibility_off : Icons.visibility),
                                onPressed: () => setState(() => _isPasswordVisible = !_isPasswordVisible),
                              ),
                            ),
                            onSubmitted: (_) => _handleLogin(),
                          ),
                          CheckboxListTile(
                            title: const Text('Rester connecté'),
                            value: auth.rememberMe,
                            onChanged: (bool? value) => auth.setRememberMe(value ?? false),
                            controlAffinity: ListTileControlAffinity.leading,
                            contentPadding: EdgeInsets.zero,
                          ),
                          const SizedBox(height: 24),
                          auth.isLoading
                              ? const CircularProgressIndicator()
                              : SizedBox(
                            width: double.infinity,
                            child: ElevatedButton(
                              // Le style vient du ElevatedButtonTheme dans main.dart
                              onPressed: _handleLogin,
                              child: const Text('CONNEXION'),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ConfigScreen()));
        },
        tooltip: 'Configuration',
        mini: true,
        child: const Icon(Icons.settings),
      ),
    );
  }
}