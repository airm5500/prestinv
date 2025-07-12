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

  Future<void> _loadCredentials() async {
    final prefs = await SharedPreferences.getInstance();
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

  void _handleLogin() async {
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
      backgroundColor: AppColors.background,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.inventory_2_outlined, size: 80, color: AppColors.primary),
                const SizedBox(height: 20),
                const Text('Prestinv', style: TextStyle(fontSize: 36, fontWeight: FontWeight.bold, color: AppColors.primary)),
                const SizedBox(height: 40),

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

                Consumer<AuthProvider>(
                  builder: (context, auth, child) {
                    return CheckboxListTile(
                      title: const Text('Rester connecté'),
                      value: auth.rememberMe,
                      onChanged: (bool? value) => auth.setRememberMe(value ?? false),
                      controlAffinity: ListTileControlAffinity.leading,
                      contentPadding: EdgeInsets.zero,
                    );
                  },
                ),
                const SizedBox(height: 16),

                // NOUVEAU : Le sélecteur de mode de connexion est maintenant ici
                Consumer<AppConfig>(
                  builder: (context, appConfig, child) {
                    return Card(
                      elevation: 1,
                      color: Colors.white,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('Mode de connexion :'),
                            Row(
                              children: [
                                Text(
                                  appConfig.apiMode == ApiMode.local ? 'Local' : 'Distant',
                                  style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.primary),
                                ),
                                Switch(
                                  activeColor: AppColors.accent,
                                  value: appConfig.apiMode == ApiMode.local,
                                  onChanged: (value) {
                                    appConfig.setApiMode(value ? ApiMode.local : ApiMode.distant);
                                  },
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),

                const SizedBox(height: 24),

                Consumer<AuthProvider>(
                    builder: (context, auth, child) {
                      return auth.isLoading
                          ? const CircularProgressIndicator()
                          : SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: _handleLogin,
                          child: const Text('CONNEXION'),
                        ),
                      );
                    }
                ),
              ],
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
