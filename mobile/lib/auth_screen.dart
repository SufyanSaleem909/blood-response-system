import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

const String baseUrl = "http://192.168.100.53:8000"; // match main.dart

class AuthScreen extends StatefulWidget {
  final Widget Function(String token, String? userId, String phone)
  onAuthenticated;
  const AuthScreen({super.key, required this.onAuthenticated});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final phoneCtrl = TextEditingController();
  final codeCtrl = TextEditingController();
  bool otpSent = false;
  bool isLoading = false;

  Future<void> _requestOtp() async {
    if (phoneCtrl.text.trim().isEmpty) return;
    setState(() => isLoading = true);
    try {
      final res = await http.post(
        Uri.parse("$baseUrl/auth/request-otp"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({"phone_number": phoneCtrl.text.trim()}),
      );
      if (res.statusCode == 200) {
        setState(() => otpSent = true);
        _showSnack("OTP sent — check backend console (dev mode).");
      } else {
        _showSnack("Failed to request OTP: ${res.body}");
      }
    } catch (e) {
      _showSnack("Connection error: $e");
    } finally {
      setState(() => isLoading = false);
    }
  }

  Future<void> _verifyOtp() async {
    if (codeCtrl.text.trim().isEmpty) return;
    setState(() => isLoading = true);
    try {
      final res = await http.post(
        Uri.parse("$baseUrl/auth/verify-otp"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "phone_number": phoneCtrl.text.trim(),
          "code": codeCtrl.text.trim(),
        }),
      );
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString("access_token", data["access_token"]);
        if (data["user_id"] != null) {
          await prefs.setString("user_id", data["user_id"]);
        }
        await prefs.setString("phone_number", phoneCtrl.text.trim());

        if (!mounted) return;
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => widget.onAuthenticated(
              data["access_token"],
              data["user_id"],
              phoneCtrl.text.trim(),
            ),
          ),
        );
      } else {
        _showSnack("Invalid code: ${res.body}");
      }
    } catch (e) {
      _showSnack("Connection error: $e");
    } finally {
      setState(() => isLoading = false);
    }
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Sign in")),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 20),
            TextField(
              controller: phoneCtrl,
              enabled: !otpSent,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                labelText: "Phone number",
                hintText: "+92 3XX XXXXXXX",
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            if (otpSent)
              TextField(
                controller: codeCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: "6-digit code",
                  border: OutlineInputBorder(),
                ),
              ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: isLoading
                  ? null
                  : (otpSent ? _verifyOtp : _requestOtp),
              child: isLoading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(otpSent ? "Verify code" : "Send code"),
            ),
          ],
        ),
      ),
    );
  }
}
