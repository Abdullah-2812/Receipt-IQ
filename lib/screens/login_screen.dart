import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../utils/constants.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _loginFormKey = GlobalKey<FormState>();
  final _signUpFormKey = GlobalKey<FormState>();

  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _nameController = TextEditingController();

  bool _obscurePassword = true;
  bool _obscureConfirm = true;
  bool _isLoading = false;

  final _auth = FirebaseAuth.instance;

  static final _emailRegex = RegExp(r'^[\w.-]+@[\w.-]+\.[a-z]{2,}$');

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  void _showSnack(String message, {bool isError = true}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? AppColors.error : Colors.green.shade600,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.all(12),
      ),
    );
  }

  Future<void> _onLogin() async {
    if (!(_loginFormKey.currentState?.validate() ?? false)) return;
    setState(() => _isLoading = true);
    try {
      await _auth.signInWithEmailAndPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text,
      );
      // Tell the OS to prompt "Save password?" so the next login can autofill.
      TextInput.finishAutofillContext();
    } on FirebaseAuthException catch (e) {
      _showSnack(_authErrorMessage(e.code));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _onSignUp() async {
    if (!(_signUpFormKey.currentState?.validate() ?? false)) return;
    setState(() => _isLoading = true);
    try {
      final credential = await _auth.createUserWithEmailAndPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text,
      );
      await credential.user?.updateDisplayName(_nameController.text.trim());
      await credential.user?.sendEmailVerification();
      TextInput.finishAutofillContext();
      _showSnack(
        'Account created! Verification email sent to ${_emailController.text.trim()}',
        isError: false,
      );
    } on FirebaseAuthException catch (e) {
      _showSnack(_authErrorMessage(e.code));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _onForgotPassword() async {
    final email = _emailController.text.trim();
    if (email.isEmpty || !_emailRegex.hasMatch(email)) {
      _showSnack('Enter a valid email above first');
      return;
    }
    try {
      await _auth.sendPasswordResetEmail(email: email);
      _showSnack('Password reset email sent to $email', isError: false);
    } on FirebaseAuthException catch (e) {
      _showSnack(_authErrorMessage(e.code));
    }
  }

  String _authErrorMessage(String code) {
    switch (code) {
      case 'user-not-found':
        return 'No account found with this email';
      case 'wrong-password':
        return 'Incorrect password';
      case 'invalid-credential':
      case 'INVALID_LOGIN_CREDENTIALS':
        return 'Invalid email or password';
      case 'email-already-in-use':
        return 'An account already exists with this email';
      case 'invalid-email':
        return 'Invalid email address';
      case 'weak-password':
        return 'Password is too weak';
      case 'user-disabled':
        return 'This account has been disabled';
      case 'operation-not-allowed':
        return 'Email/password sign-in is not enabled in Firebase';
      case 'too-many-requests':
        return 'Too many attempts. Try again later';
      case 'network-request-failed':
        return 'No internet connection';
      default:
        return 'Something went wrong. Please try again';
    }
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final topPadding = MediaQuery.of(context).padding.top;

    return Scaffold(
      backgroundColor: AppColors.primary,
      body: Column(
        children: [
          // Colored header with branding
          Padding(
            padding: EdgeInsets.fromLTRB(24, topPadding + 28, 24, 28),
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.receipt_long,
                      size: 36, color: Colors.white),
                ),
                const SizedBox(height: 12),
                Text(
                  AppConstants.appName,
                  style: GoogleFonts.poppins(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Track expenses from your receipts',
                  style: GoogleFonts.poppins(
                    fontSize: 13,
                    color: Colors.white.withOpacity(0.8),
                  ),
                ),
              ],
            ),
          ),

          // White card — takes all remaining space so keyboard resizes it
          Expanded(
            child: Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(28),
                  topRight: Radius.circular(28),
                ),
              ),
              child: Column(
                children: [
                  // Tab switcher
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
                    child: Container(
                      decoration: BoxDecoration(
                        color: AppColors.background,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: TabBar(
                        controller: _tabController,
                        indicator: BoxDecoration(
                          color: AppColors.primary,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        indicatorSize: TabBarIndicatorSize.tab,
                        labelColor: Colors.white,
                        unselectedLabelColor: AppColors.textSecondary,
                        labelStyle: GoogleFonts.poppins(
                            fontWeight: FontWeight.w600, fontSize: 14),
                        unselectedLabelStyle:
                            GoogleFonts.poppins(fontSize: 14),
                        dividerColor: Colors.transparent,
                        tabs: const [
                          Tab(text: 'Login'),
                          Tab(text: 'Sign Up'),
                        ],
                      ),
                    ),
                  ),

                  // Forms — each scrolls independently, keyboard never hides fields
                  Expanded(
                    child: TabBarView(
                      controller: _tabController,
                      children: [
                        _buildLoginTab(),
                        _buildSignUpTab(),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Login tab ──────────────────────────────────────────────────────────────

  Widget _buildLoginTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
      child: Form(
        key: _loginFormKey,
        child: AutofillGroup(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _inputField(
                controller: _emailController,
              label: 'Email',
              hint: 'Enter your email',
              icon: Icons.email_outlined,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.next,
              autofillHints: const [
                AutofillHints.username,
                AutofillHints.email,
              ],
              validator: (v) {
                if (v == null || v.trim().isEmpty) return 'Enter your email';
                if (!_emailRegex.hasMatch(v.trim()))
                  return 'Enter a valid email';
                return null;
              },
            ),
            const SizedBox(height: 16),
            _passwordField(
              controller: _passwordController,
              label: 'Password',
              hint: 'Enter your password',
              obscure: _obscurePassword,
              onToggle: () =>
                  setState(() => _obscurePassword = !_obscurePassword),
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _onLogin(),
              autofillHints: const [AutofillHints.password],
              validator: (v) {
                if (v == null || v.isEmpty) return 'Enter your password';
                if (v.length < 6)
                  return 'Password must be at least 6 characters';
                return null;
              },
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: _onForgotPassword,
                style:
                    TextButton.styleFrom(foregroundColor: AppColors.primary),
                child: const Text('Forgot Password?'),
              ),
            ),
            const SizedBox(height: 4),
            _actionButton(
                label: 'Login',
                color: AppColors.primary,
                onPressed: _onLogin),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  "Don't have an account?",
                  style: GoogleFonts.poppins(
                      fontSize: 13, color: AppColors.textSecondary),
                ),
                TextButton(
                  onPressed: () => _tabController.animateTo(1),
                  style:
                      TextButton.styleFrom(foregroundColor: AppColors.accent),
                  child: Text('Sign Up',
                      style: GoogleFonts.poppins(
                          fontWeight: FontWeight.w600, fontSize: 13)),
                ),
              ],
            ),
          ],
        ),
        ),
      ),
    );
  }

  // ── Sign-up tab ────────────────────────────────────────────────────────────

  Widget _buildSignUpTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
      child: Form(
        key: _signUpFormKey,
        child: AutofillGroup(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _inputField(
                controller: _nameController,
              label: 'Full Name',
              hint: 'Enter your name',
              icon: Icons.person_outline,
              textInputAction: TextInputAction.next,
              autofillHints: const [AutofillHints.name],
              validator: (v) {
                if (v == null || v.trim().isEmpty) return 'Enter your name';
                if (v.trim().length < 2)
                  return 'Name must be at least 2 characters';
                return null;
              },
            ),
            const SizedBox(height: 16),
            _inputField(
              controller: _emailController,
              label: 'Email',
              hint: 'Enter your email',
              icon: Icons.email_outlined,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.next,
              autofillHints: const [
                AutofillHints.newUsername,
                AutofillHints.email,
              ],
              validator: (v) {
                if (v == null || v.trim().isEmpty) return 'Enter your email';
                if (!_emailRegex.hasMatch(v.trim()))
                  return 'Enter a valid email';
                return null;
              },
            ),
            const SizedBox(height: 16),
            _passwordField(
              controller: _passwordController,
              label: 'Password',
              hint: 'Min 6 characters',
              obscure: _obscurePassword,
              onToggle: () =>
                  setState(() => _obscurePassword = !_obscurePassword),
              textInputAction: TextInputAction.next,
              autofillHints: const [AutofillHints.newPassword],
              validator: (v) {
                if (v == null || v.isEmpty) return 'Enter a password';
                if (v.length < 6)
                  return 'Password must be at least 6 characters';
                return null;
              },
            ),
            const SizedBox(height: 16),
            _passwordField(
              controller: _confirmPasswordController,
              label: 'Confirm Password',
              hint: 'Re-enter your password',
              obscure: _obscureConfirm,
              onToggle: () =>
                  setState(() => _obscureConfirm = !_obscureConfirm),
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _onSignUp(),
              validator: (v) {
                if (v == null || v.isEmpty) return 'Confirm your password';
                if (v != _passwordController.text)
                  return 'Passwords do not match';
                return null;
              },
            ),
            const SizedBox(height: 24),
            _actionButton(
                label: 'Create Account',
                color: AppColors.accent,
                onPressed: _onSignUp),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'Already have an account?',
                  style: GoogleFonts.poppins(
                      fontSize: 13, color: AppColors.textSecondary),
                ),
                TextButton(
                  onPressed: () => _tabController.animateTo(0),
                  style:
                      TextButton.styleFrom(foregroundColor: AppColors.primary),
                  child: Text('Login',
                      style: GoogleFonts.poppins(
                          fontWeight: FontWeight.w600, fontSize: 13)),
                ),
              ],
            ),
          ],
        ),
        ),
      ),
    );
  }

  // ── Reusable field helpers ─────────────────────────────────────────────────

  Widget _inputField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    TextInputType keyboardType = TextInputType.text,
    TextInputAction textInputAction = TextInputAction.next,
    String? Function(String?)? validator,
    List<String>? autofillHints,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      textInputAction: textInputAction,
      autofillHints: autofillHints,
      decoration: _decoration(label, hint, Icon(icon, size: 20)),
      validator: validator,
    );
  }

  Widget _passwordField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required bool obscure,
    required VoidCallback onToggle,
    TextInputAction textInputAction = TextInputAction.next,
    void Function(String)? onSubmitted,
    String? Function(String?)? validator,
    List<String>? autofillHints,
  }) {
    return TextFormField(
      controller: controller,
      obscureText: obscure,
      textInputAction: textInputAction,
      onFieldSubmitted: onSubmitted,
      autofillHints: autofillHints,
      decoration: _decoration(
        label,
        hint,
        const Icon(Icons.lock_outline, size: 20),
        suffix: IconButton(
          icon: Icon(
            obscure
                ? Icons.visibility_off_outlined
                : Icons.visibility_outlined,
            size: 20,
            color: AppColors.textSecondary,
          ),
          onPressed: onToggle,
        ),
      ),
      validator: validator,
    );
  }

  InputDecoration _decoration(String label, String hint, Widget prefix,
      {Widget? suffix}) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      prefixIcon: prefix,
      suffixIcon: suffix,
      filled: true,
      fillColor: AppColors.background,
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.grey.shade200),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: AppColors.primary, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: AppColors.error),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: AppColors.error, width: 1.5),
      ),
    );
  }

  Widget _actionButton({
    required String label,
    required Color color,
    required VoidCallback onPressed,
  }) {
    return SizedBox(
      height: 52,
      child: FilledButton(
        onPressed: _isLoading ? null : onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: color,
          foregroundColor: Colors.white,
          disabledBackgroundColor: color.withOpacity(0.6),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        child: _isLoading
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                    strokeWidth: 2.5, color: Colors.white),
              )
            : Text(
                label,
                style: GoogleFonts.poppins(
                    fontSize: 15, fontWeight: FontWeight.w600),
              ),
      ),
    );
  }
}
