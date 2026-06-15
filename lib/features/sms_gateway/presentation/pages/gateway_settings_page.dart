import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../../core/storage/local_storage_service.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../shared/widgets/app_button.dart';
import '../../../../shared/widgets/section_card.dart';
import '../controllers/gateway_settings_controller.dart';
import '../controllers/sms_gateway_controller.dart';

class GatewaySettingsPage extends StatefulWidget {
  const GatewaySettingsPage({super.key});

  @override
  State<GatewaySettingsPage> createState() => _GatewaySettingsPageState();
}

class _GatewaySettingsPageState extends State<GatewaySettingsPage> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _backendUrlCtrl;
  late TextEditingController _tokenCtrl;
  late TextEditingController _deviceCodeCtrl;
  late TextEditingController _intervalCtrl;
  bool _autoStart = false;
  bool _obscureToken = true;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    final config = context.read<GatewaySettingsController>().config;
    _backendUrlCtrl = TextEditingController(text: config.backendUrl);
    _tokenCtrl = TextEditingController(text: config.gatewayToken);
    _deviceCodeCtrl = TextEditingController(text: config.deviceCode);
    _intervalCtrl =
        TextEditingController(text: config.pollingIntervalSeconds.toString());
    _autoStart = config.autoStart;
  }

  @override
  void dispose() {
    _backendUrlCtrl.dispose();
    _tokenCtrl.dispose();
    _deviceCodeCtrl.dispose();
    _intervalCtrl.dispose();
    super.dispose();
  }

  Future<void> _onSave() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSaving = true);

    final url = _backendUrlCtrl.text.trim().replaceAll(RegExp(r'/+$'), '');
    final newConfig = GatewayConfig(
      backendUrl: url,
      gatewayToken: _tokenCtrl.text.trim(),
      deviceCode: _deviceCodeCtrl.text.trim(),
      autoStart: _autoStart,
      pollingIntervalSeconds: int.tryParse(_intervalCtrl.text.trim()) ?? 10,
    );
    // Snapshot mọi thứ phụ thuộc `context` TRƯỚC khi await — tránh
    // "Looking up a deactivated widget's ancestor" nếu widget unmount khi
    // save trả về.
    final gatewayWasRunning =
        context.read<SmsGatewayController>().isRunning;
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

    await context.read<GatewaySettingsController>().save(newConfig);
    if (!mounted) return;
    setState(() => _isSaving = false);

    if (gatewayWasRunning) {
      messenger.showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 6),
          backgroundColor: AppTheme.logWarning,
          content: const Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Colors.white, size: 18),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Saved. Restart the gateway to apply the new settings.',
                ),
              ),
            ],
          ),
        ),
      );
    } else {
      messenger.showSnackBar(
        const SnackBar(
          content: Row(
            children: [
              Icon(Icons.check_circle, color: Colors.white, size: 18),
              SizedBox(width: 10),
              Text('Settings saved'),
            ],
          ),
        ),
      );
    }
    navigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text('Settings'),
      ),
      body: Form(
        key: _formKey,
        autovalidateMode: AutovalidateMode.onUserInteraction,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            AppTheme.s16, AppTheme.s8, AppTheme.s16, AppTheme.s24,
          ),
          children: [
            SectionCard(
              icon: Icons.cloud_outlined,
              title: 'Backend',
              subtitle: 'Where this gateway pulls SMS from',
              children: [
                _Field(
                  controller: _backendUrlCtrl,
                  label: 'Backend URL',
                  hint: 'https://api.example.com',
                  icon: Icons.link_rounded,
                  keyboardType: TextInputType.url,
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) return 'Required';
                    final trimmed = v.trim().replaceAll(RegExp(r'/+$'), '');
                    final uri = Uri.tryParse(trimmed);
                    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
                      return 'Invalid URL';
                    }
                    if (uri.scheme != 'http' && uri.scheme != 'https') {
                      return 'Must start with http:// or https://';
                    }
                    if (uri.path.isNotEmpty && uri.path != '/') {
                      return 'Remove path — enter root URL only';
                    }
                    if (uri.hasQuery || uri.hasFragment) {
                      return 'Remove ? and # — enter root URL only';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: AppTheme.s16),
                _Field(
                  controller: _tokenCtrl,
                  label: 'Gateway token',
                  hint: 'Provided by your admin',
                  icon: Icons.key_rounded,
                  obscure: _obscureToken,
                  suffix: IconButton(
                    icon: Icon(_obscureToken
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined),
                    onPressed: () =>
                        setState(() => _obscureToken = !_obscureToken),
                  ),
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Required' : null,
                ),
              ],
            ),
            const SizedBox(height: AppTheme.s16),
            SectionCard(
              icon: Icons.smartphone_outlined,
              title: 'Device',
              subtitle: 'Identifies this phone on the backend',
              children: [
                _Field(
                  controller: _deviceCodeCtrl,
                  label: 'Device code',
                  hint: 'android-gateway-001',
                  icon: Icons.qr_code_rounded,
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Required' : null,
                ),
              ],
            ),
            const SizedBox(height: AppTheme.s16),
            SectionCard(
              icon: Icons.tune_rounded,
              title: 'Behavior',
              subtitle: 'Polling cadence and startup',
              children: [
                _Field(
                  controller: _intervalCtrl,
                  label: 'Polling interval (seconds)',
                  hint: '5 – 600',
                  icon: Icons.timer_outlined,
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(4),
                  ],
                  validator: (v) {
                    final n = int.tryParse(v ?? '');
                    if (n == null || n < 5 || n > 600) {
                      return 'Must be between 5 and 600';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: AppTheme.s8),
                _SwitchTile(
                  icon: Icons.bolt_rounded,
                  title: 'Auto start on app launch',
                  subtitle:
                      'Automatically begin polling when the app opens',
                  value: _autoStart,
                  onChanged: (v) => setState(() => _autoStart = v),
                ),
              ],
            ),
            const SizedBox(height: AppTheme.s12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppTheme.s8),
              child: Row(
                children: [
                  Icon(
                    Icons.info_outline_rounded,
                    size: 14,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Connect to ApiGateway (not SmsService directly). '
                      'On LAN: http://192.168.x.x:5003 or https://192.168.x.x:5001.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color:
                            theme.colorScheme.onSurface.withValues(alpha: 0.55),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppTheme.s24),
            AppButton(
              label: 'Save settings',
              icon: Icons.check_rounded,
              loading: _isSaving,
              onPressed: _onSave,
            ),
          ],
        ),
      ),
    );
  }
}

class _Field extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String? hint;
  final IconData icon;
  final bool obscure;
  final Widget? suffix;
  final TextInputType? keyboardType;
  final FormFieldValidator<String>? validator;
  final List<TextInputFormatter>? inputFormatters;

  const _Field({
    required this.controller,
    required this.label,
    required this.icon,
    this.hint,
    this.obscure = false,
    this.suffix,
    this.keyboardType,
    this.validator,
    this.inputFormatters,
  });

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      obscureText: obscure,
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
      validator: validator,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: Icon(icon, size: 20),
        suffixIcon: suffix,
      ),
    );
  }
}

class _SwitchTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _SwitchTile({
    required this.icon,
    required this.title,
    required this.value,
    required this.onChanged,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: () => onChanged(!value),
      borderRadius: BorderRadius.circular(AppTheme.rMd),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppTheme.s4,
          vertical: AppTheme.s8,
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: theme.colorScheme.primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(AppTheme.rSm),
              ),
              child: Icon(icon, size: 18, color: theme.colorScheme.primary),
            ),
            const SizedBox(width: AppTheme.s12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(fontWeight: FontWeight.w600)),
                  if (subtitle != null)
                    Text(subtitle!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color:
                              theme.colorScheme.onSurface.withValues(alpha: 0.6),
                        )),
                ],
              ),
            ),
            Switch(value: value, onChanged: onChanged),
          ],
        ),
      ),
    );
  }
}
