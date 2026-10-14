import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/auth_service.dart';
import '../main.dart';

class EmailVerificationScreen extends StatefulWidget {
  final String email;
  
  const EmailVerificationScreen({
    super.key,
    required this.email,
  });

  @override
  State<EmailVerificationScreen> createState() => _EmailVerificationScreenState();
}

class _EmailVerificationScreenState extends State<EmailVerificationScreen> {
  final List<TextEditingController> _otpControllers = List.generate(
    6,
    (index) => TextEditingController(),
  );
  final List<FocusNode> _focusNodes = List.generate(
    6,
    (index) => FocusNode(),
  );
  
  bool _isVerifying = false;
  bool _isResending = false;
  int _cooldownSeconds = 0;
  Timer? _cooldownTimer;

  @override
  void initState() {
    super.initState();
    // Auto-focus first field
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNodes[0].requestFocus();
    });
  }

  @override
  void dispose() {
    for (var controller in _otpControllers) {
      controller.dispose();
    }
    for (var node in _focusNodes) {
      node.dispose();
    }
    _cooldownTimer?.cancel();
    super.dispose();
  }

  String _getOtpCode() {
    return _otpControllers.map((c) => c.text).join();
  }

  bool _isOtpComplete() {
    return _getOtpCode().length == 6;
  }

  Future<void> _verifyOtp() async {
    if (!_isOtpComplete()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Silakan masukkan kode 6-digit'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() => _isVerifying = true);

    try {
      final otpCode = _getOtpCode();
      
      await Supabase.instance.client.auth.verifyOTP(
        email: widget.email,
        token: otpCode,
        type: OtpType.signup,
      );

      if (mounted) {
        // Success - navigate to home
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(
            builder: (context) => const MainNavigator(),
          ),
          (route) => false, // Remove all previous routes
        );
      }
    } on AuthException catch (e) {
      if (mounted) {
        String message = 'Kode verifikasi salah atau sudah kadaluarsa';
        if (e.message.contains('expired')) {
          message = 'Kode sudah kadaluarsa. Silakan kirim ulang.';
        }
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            backgroundColor: Colors.red,
          ),
        );
        
        // Clear OTP fields
        for (var controller in _otpControllers) {
          controller.clear();
        }
        _focusNodes[0].requestFocus();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isVerifying = false);
    }
  }


  Future<void> _resendVerification() async {
    if (_cooldownSeconds > 0) return;
    
    setState(() => _isResending = true);

    try {
      await AuthService.resendVerificationEmail(widget.email);
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Kode baru telah dikirim ke email Anda'),
            backgroundColor: Colors.green,
          ),
        );
        
        // Clear old OTP
        for (var controller in _otpControllers) {
          controller.clear();
        }
        _focusNodes[0].requestFocus();
        
        // Start cooldown
        setState(() => _cooldownSeconds = 60);
        _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
          setState(() => _cooldownSeconds--);
          if (_cooldownSeconds <= 0) {
            timer.cancel();
          }
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Gagal mengirim kode: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isResending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: true,
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              const Color(0xFF8B5CF6),
              const Color(0xFFF472B6),
            ],
          ),
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 20.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.start,
              children: [
                  const SizedBox(height: 20),
                  
                  // Email Icon
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.2),
                          blurRadius: 20,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.mark_email_unread,
                      size: 50,
                      color: Color(0xFF8B5CF6),
                    ),
                  ),
                  const SizedBox(height: 24),
                  
                  // Title
                  const Text(
                    'Verifikasi Email',
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 12),
                  
                  // Message
                  Text(
                    'Masukkan kode 6-digit yang dikirim ke:',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.white.withOpacity(0.9),
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    widget.email,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 28),
                  
                  // OTP Input Container
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E293B),
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.3),
                          blurRadius: 20,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        // OTP Input Fields
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: List.generate(6, (index) {
                            return SizedBox(
                              width: 44,
                              height: 52,
                              child: TextField(
                                controller: _otpControllers[index],
                                focusNode: _focusNodes[index],
                                textAlign: TextAlign.center,
                                textAlignVertical: TextAlignVertical.center,
                                keyboardType: TextInputType.number,
                                maxLength: 1,
                                style: const TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                  height: 1.2,
                                ),
                                decoration: InputDecoration(
                                  counterText: '',
                                  filled: true,
                                  fillColor: const Color(0xFF0F172A),
                                  contentPadding: const EdgeInsets.symmetric(vertical: 14, horizontal: 0),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: BorderSide.none,
                                  ),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: BorderSide(
                                      color: Colors.grey.withOpacity(0.3),
                                      width: 2,
                                    ),
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: const BorderSide(
                                      color: Color(0xFF8B5CF6),
                                      width: 2,
                                    ),
                                  ),
                                ),
                                inputFormatters: [
                                  FilteringTextInputFormatter.digitsOnly,
                                ],
                                onChanged: (value) {
                                  if (value.isNotEmpty && index < 5) {
                                    // Move to next field
                                    _focusNodes[index + 1].requestFocus();
                                  } else if (value.isEmpty && index > 0) {
                                    // Move to previous field on backspace
                                    _focusNodes[index - 1].requestFocus();
                                  }
                                  
                                  // Auto-verify when all fields filled
                                  if (index == 5 && value.isNotEmpty) {
                                    _verifyOtp();
                                  }
                                },
                              ),
                            );
                          }),
                        ),
                        const SizedBox(height: 20),
                        
                        // Verify Button
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: (_isVerifying || !_isOtpComplete()) 
                                ? null 
                                : _verifyOtp,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF8B5CF6),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              elevation: 4,
                              disabledBackgroundColor: Colors.grey[800],
                            ),
                            child: _isVerifying
                                ? const SizedBox(
                                    height: 20,
                                    width: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                    ),
                                  )
                                : const Text(
                                    'Verifikasi',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  
                  // Resend and Back buttons
                  Column(
                    children: [
                      TextButton.icon(
                        onPressed: (_isResending || _cooldownSeconds > 0) ? null : _resendVerification,
                        icon: _isResending
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                ),
                              )
                            : const Icon(Icons.refresh, color: Colors.white),
                        label: Text(
                          _cooldownSeconds > 0
                              ? 'Kirim Ulang ($_cooldownSeconds)'
                              : 'Kirim Ulang Kode',
                          style: TextStyle(
                            color: Colors.white.withOpacity(_cooldownSeconds > 0 ? 0.5 : 1.0),
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: () {
                          AuthService.signOut();
                          Navigator.of(context).popUntil((route) => route.isFirst);
                        },
                        child: Text(
                          'Kembali ke Login',
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.8),
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: MediaQuery.of(context).viewInsets.bottom > 0 ? 20 : 0),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
