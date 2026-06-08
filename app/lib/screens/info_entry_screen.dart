import 'package:flutter/material.dart';

import '../flow/flow_controller.dart';
import '../theme.dart';

class InfoEntryScreen extends StatefulWidget {
  const InfoEntryScreen({super.key, required this.flow});
  final FlowController flow;

  @override
  State<InfoEntryScreen> createState() => _InfoEntryScreenState();
}

class _InfoEntryScreenState extends State<InfoEntryScreen> {
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  // Name is required; email is optional (final video is delivered via the QR).
  bool get _valid => _name.text.trim().isNotEmpty;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32),
          child: Form(
            key: _formKey,
            onChanged: () => setState(() {}),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('Let’s get you set up',
                    style: TextStyle(fontSize: 34, fontWeight: FontWeight.w800)),
                const SizedBox(height: 8),
                const Text("We’ll send your video here when it’s ready.",
                    style: TextStyle(fontSize: 16, color: Colors.white60)),
                const SizedBox(height: 32),
                _field(_name, 'First name', Icons.person_outline,
                    cap: TextCapitalization.words),
                const SizedBox(height: 16),
                _field(_email, 'Email', Icons.mail_outline,
                    keyboard: TextInputType.emailAddress),
                const SizedBox(height: 36),
                GradientButton(
                  label: 'CONTINUE',
                  icon: Icons.arrow_forward,
                  expand: true,
                  onPressed: _valid
                      ? () {
                          widget.flow.setGuest(
                              name: _name.text.trim(),
                              email: _email.text.trim());
                          widget.flow.go(AppPhase.preview);
                        }
                      : null,
                ),
                const SizedBox(height: 10),
                if (!_valid)
                  const Center(
                    child: Text('Enter your name to continue',
                        style: TextStyle(color: Colors.white38, fontSize: 13)),
                  ),
                const SizedBox(height: 4),
                Center(
                  child: TextButton(
                    onPressed: () => widget.flow.go(AppPhase.attract),
                    child: const Text('Back',
                        style: TextStyle(color: Colors.white54)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _field(TextEditingController c, String label, IconData icon,
      {TextInputType? keyboard, TextCapitalization cap = TextCapitalization.none}) {
    return TextFormField(
      controller: c,
      keyboardType: keyboard,
      textCapitalization: cap,
      style: const TextStyle(fontSize: 20),
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon),
        filled: true,
        fillColor: Brand.surface,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 20, vertical: 22),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: Brand.redBright, width: 2),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    super.dispose();
  }
}
