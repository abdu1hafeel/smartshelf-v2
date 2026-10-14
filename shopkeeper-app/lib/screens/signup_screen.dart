// ==============================================================================
// SmartShelf V2 - Shopkeeper Mobile Sign-Up Screen
// ==============================================================================

import 'package:flutter/material.dart';
import '../services/auth_service.dart';

class SignupScreen extends StatefulWidget {
  final AuthService authService;

  const SignupScreen({super.key, required this.authService});

  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> {
  final _fullNameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  bool _requiresVerification = false;
  String? _successBannerMessage;
  bool _isResending = false;

  final RegExp _emailRegex = RegExp(
    r'^[a-zA-Z0-9.!#$%&’*+/=?^_`{|}~-]+@[a-zA-Z0-9-]+(?:\.[a-zA-Z0-9-]+)+$',
  );

  @override
  void dispose() {
    _fullNameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _handleSignUp() async {
    if (!_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();

    setState(() {
      _successBannerMessage = null;
      _requiresVerification = false;
    });

    final res = await widget.authService.signUp(
      email: _emailController.text,
      password: _passwordController.text,
      fullName: _fullNameController.text,
    );

    if (!mounted) return;

    if (res.success) {
      if (res.requiresEmailConfirmation) {
        setState(() {
          _requiresVerification = true;
          _successBannerMessage = res.message;
        });
      } else {
        // Automatically signed in! If this screen was pushed onto navigator, pop back.
        if (Navigator.canPop(context)) {
          Navigator.pop(context);
        }
      }
    }
  }

  Future<void> _handleResendVerification() async {
    final email = _emailController.text.trim();
    if (email.isEmpty) return;

    setState(() => _isResending = true);
    final sent = await widget.authService.resendVerificationEmail(email);
    if (!mounted) return;
    setState(() => _isResending = false);

    if (sent) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Verification link re-sent to $email'),
          backgroundColor: const Color(0xFF10B981),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(widget.authService.errorMessage ?? 'Failed to resend verification email'),
          backgroundColor: const Color(0xFFEF4444),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: Color(0xFF0F172A)),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // App Brand Logo & Title
                  Center(
                    child: Container(
                      width: 58,
                      height: 58,
                      decoration: BoxDecoration(
                        color: const Color(0xFF4F46E5),
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF4F46E5).withValues(alpha: 0.28),
                            blurRadius: 14,
                            offset: const Offset(0, 5),
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.person_add_alt_1_rounded,
                        color: Colors.white,
                        size: 30,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Create Account',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF0F172A),
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Join your store team or register a new retail branch',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w500,
                      color: Colors.grey.shade600,
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Error Banner
                  if (widget.authService.errorMessage != null) ...[
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFF1F2),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFFECDD3)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.error_outline, color: Color(0xFFBE123C), size: 20),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              widget.authService.errorMessage!,
                              style: const TextStyle(
                                color: Color(0xFFBE123C),
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],

                  // Email Verification Notice Banner
                  if (_requiresVerification && _successBannerMessage != null) ...[
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: const Color(0xFFECFDF5),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFA7F3D0)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.mark_email_read_rounded,
                                  color: Color(0xFF059669), size: 20),
                              const SizedBox(width: 8),
                              const Text(
                                'Verification Link Sent',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF065F46),
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _successBannerMessage!,
                            style: const TextStyle(
                              color: Color(0xFF047857),
                              fontSize: 12,
                              height: 1.4,
                            ),
                          ),
                          const SizedBox(height: 10),
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              onPressed: _isResending ? null : _handleResendVerification,
                              style: OutlinedButton.styleFrom(
                                side: const BorderSide(color: Color(0xFF059669)),
                                foregroundColor: const Color(0xFF059669),
                                padding: const EdgeInsets.symmetric(vertical: 8),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                              icon: _isResending
                                  ? const SizedBox(
                                      width: 14,
                                      height: 14,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF059669)),
                                      ),
                                    )
                                  : const Icon(Icons.refresh, size: 16),
                              label: const Text(
                                'Resend Verification Email',
                                style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],

                  // Sign-Up Form Card
                  Container(
                    padding: const EdgeInsets.all(22),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.grey.shade200),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.03),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // Full Name Field
                          TextFormField(
                            controller: _fullNameController,
                            textCapitalization: TextCapitalization.words,
                            textInputAction: TextInputAction.next,
                            decoration: InputDecoration(
                              labelText: 'Full Name',
                              hintText: 'e.g. Rahul Sharma',
                              prefixIcon: const Icon(Icons.person_outline_rounded, size: 20),
                              filled: true,
                              fillColor: const Color(0xFFF8FAFC),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide(color: Colors.grey.shade300),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide(color: Colors.grey.shade200),
                              ),
                              contentPadding:
                                  const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                            ),
                            validator: (val) {
                              if (val == null || val.trim().isEmpty) {
                                return 'Please enter your full name';
                              }
                              if (val.trim().length < 2) {
                                return 'Name must be at least 2 characters';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 14),

                          // Email Field
                          TextFormField(
                            controller: _emailController,
                            keyboardType: TextInputType.emailAddress,
                            textInputAction: TextInputAction.next,
                            decoration: InputDecoration(
                              labelText: 'Email Address',
                              hintText: 'e.g. rahul@store.com',
                              prefixIcon: const Icon(Icons.email_outlined, size: 20),
                              filled: true,
                              fillColor: const Color(0xFFF8FAFC),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide(color: Colors.grey.shade300),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide(color: Colors.grey.shade200),
                              ),
                              contentPadding:
                                  const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                            ),
                            validator: (val) {
                              if (val == null || val.trim().isEmpty) {
                                return 'Please enter your email';
                              }
                              if (!_emailRegex.hasMatch(val.trim())) {
                                return 'Please enter a valid email address';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 14),

                          // Password Field
                          TextFormField(
                            controller: _passwordController,
                            obscureText: _obscurePassword,
                            textInputAction: TextInputAction.next,
                            decoration: InputDecoration(
                              labelText: 'Password',
                              hintText: 'At least 6 characters',
                              prefixIcon: const Icon(Icons.lock_outline, size: 20),
                              suffixIcon: IconButton(
                                icon: Icon(
                                  _obscurePassword ? Icons.visibility_off : Icons.visibility,
                                  size: 20,
                                ),
                                onPressed: () {
                                  setState(() {
                                    _obscurePassword = !_obscurePassword;
                                  });
                                },
                              ),
                              filled: true,
                              fillColor: const Color(0xFFF8FAFC),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide(color: Colors.grey.shade300),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide(color: Colors.grey.shade200),
                              ),
                              contentPadding:
                                  const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                            ),
                            validator: (val) {
                              if (val == null || val.isEmpty) {
                                return 'Please enter a password';
                              }
                              if (val.length < 6) {
                                return 'Password must be at least 6 characters';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 14),

                          // Confirm Password Field
                          TextFormField(
                            controller: _confirmPasswordController,
                            obscureText: _obscureConfirmPassword,
                            textInputAction: TextInputAction.done,
                            onFieldSubmitted: (_) => _handleSignUp(),
                            decoration: InputDecoration(
                              labelText: 'Confirm Password',
                              hintText: 'Re-enter your password',
                              prefixIcon: const Icon(Icons.lock_reset_rounded, size: 20),
                              suffixIcon: IconButton(
                                icon: Icon(
                                  _obscureConfirmPassword ? Icons.visibility_off : Icons.visibility,
                                  size: 20,
                                ),
                                onPressed: () {
                                  setState(() {
                                    _obscureConfirmPassword = !_obscureConfirmPassword;
                                  });
                                },
                              ),
                              filled: true,
                              fillColor: const Color(0xFFF8FAFC),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide(color: Colors.grey.shade300),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide(color: Colors.grey.shade200),
                              ),
                              contentPadding:
                                  const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                            ),
                            validator: (val) {
                              if (val == null || val.isEmpty) {
                                return 'Please confirm your password';
                              }
                              if (val != _passwordController.text) {
                                return 'Passwords do not match';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 22),

                          // Sign-Up Submit Button
                          ElevatedButton(
                            onPressed: widget.authService.isLoading ? null : _handleSignUp,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF4F46E5),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              elevation: 0,
                            ),
                            child: widget.authService.isLoading
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                    ),
                                  )
                                : const Text(
                                    'Create Account',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14,
                                    ),
                                  ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 20),

                  // Link to Sign In
                  Wrap(
                    alignment: WrapAlignment.center,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        'Already have an account?',
                        style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                      ),
                      TextButton(
                        onPressed: () {
                          if (Navigator.canPop(context)) {
                            Navigator.pop(context);
                          }
                        },
                        child: const Text(
                          'Sign In',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF4F46E5),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
