import 'package:flutter/material.dart';

import '../config/api_config.dart';
import '../services/api_exception.dart';
import '../services/app_services.dart';
import '../utils/format.dart';
import '../widgets/state_views.dart';

/// Lets the user switch between the online (Supabase) and local (XAMPP) API.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final _url = TextEditingController(text: ApiConfig.baseUrl.value);
  bool _testing = false;
  bool? _testOk;
  String? _testMessage;

  static final _presets = {
    'Supabase (online)': ApiConfig.hostedBaseUrl,
    'XAMPP (this device)': ApiConfig.localBaseUrl,
    'PHP dev server (emulator)': 'http://10.0.2.2:8000/api',
  };

  @override
  void dispose() {
    _url.dispose();
    super.dispose();
  }

  String? _validate(String value) {
    final uri = Uri.tryParse(ApiConfig.normalize(value));
    if (value.trim().isEmpty || uri == null || uri.host.isEmpty) {
      return 'Enter a URL such as http://192.168.1.10/techstore_api/api';
    }
    return null;
  }

  Future<void> _test() async {
    final error = _validate(_url.text);
    if (error != null) {
      setState(() {
        _testOk = false;
        _testMessage = error;
      });
      return;
    }
    setState(() {
      _testing = true;
      _testMessage = null;
    });
    try {
      final health = await AppServices.productStore.api.checkHealth(
        baseUrl: _url.text,
      );
      _testOk = true;
      _testMessage =
          '${health.message} ${pluralize(health.productCount, 'product')} in the database.';
    } on ApiException catch (e) {
      _testOk = false;
      _testMessage = e.message;
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  Future<void> _save() async {
    final error = _validate(_url.text);
    if (error != null) {
      showAppSnackBar(context, error, isError: true);
      return;
    }
    final unchanged = ApiConfig.normalize(_url.text) == ApiConfig.baseUrl.value;
    await ApiConfig.save(_url.text);
    // An unchanged URL does not notify HomeShell, so reload here.
    if (unchanged) AppServices.productStore.load();
    if (!mounted) return;
    _url.text = ApiConfig.baseUrl.value;
    showAppSnackBar(context, 'Server URL saved. Reloading products…');
  }

  Future<void> _reset() async {
    await ApiConfig.reset();
    if (!mounted) return;
    setState(() {
      _url.text = ApiConfig.baseUrl.value;
      _testMessage = null;
    });
    showAppSnackBar(context, 'Restored the default server URL.');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Server Settings')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text('Custom REST API', style: theme.textTheme.titleMedium),
              const SizedBox(height: 4),
              Text(
                'Where the app sends GET/POST/PUT/DELETE requests: the Supabase Edge Function '
                '(online) or the "api" folder of the PHP backend on XAMPP.',
                style: muted,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _url,
                keyboardType: TextInputType.url,
                autocorrect: false,
                decoration: const InputDecoration(
                  labelText: 'API base URL',
                  prefixIcon: Icon(Icons.dns_outlined),
                ),
                onSubmitted: (_) => _test(),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  for (final preset in _presets.entries)
                    ActionChip(
                      label: Text(preset.key),
                      onPressed: () => setState(() => _url.text = preset.value),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _testing ? null : _test,
                      icon: _testing
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.network_check),
                      label: const Text('Test connection'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _save,
                      icon: const Icon(Icons.save_outlined),
                      label: const Text('Save'),
                    ),
                  ),
                ],
              ),
              if (_testMessage != null) ...[
                const SizedBox(height: 12),
                Card(
                  color: _testOk == true
                      ? theme.colorScheme.secondaryContainer
                      : theme.colorScheme.errorContainer,
                  child: ListTile(
                    leading: Icon(
                      _testOk == true
                          ? Icons.check_circle
                          : Icons.error_outline,
                    ),
                    title: Text(
                      _testOk == true ? 'Connected' : 'Connection failed',
                    ),
                    subtitle: Text(_testMessage!),
                  ),
                ),
              ],
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: _reset,
                  icon: const Icon(Icons.restart_alt),
                  label: Text('Reset to default (${ApiConfig.defaultBaseUrl})'),
                ),
              ),
              const SizedBox(height: 8),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Using XAMPP from a physical phone?',
                        style: theme.textTheme.titleSmall,
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        '1. Connect the phone and PC to the same Wi-Fi.\n'
                        '2. On the PC run "ipconfig" and copy the IPv4 address.\n'
                        '3. Enter http://<that-IP>/techstore_api/api above.\n'
                        '4. Allow Apache through Windows Firewall if the test fails.',
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Text('APIs used by this app', style: theme.textTheme.titleMedium),
              const SizedBox(height: 8),
              Card(
                child: Column(
                  children: [
                    ValueListenableBuilder<String>(
                      valueListenable: ApiConfig.baseUrl,
                      builder: (context, url, _) => ListTile(
                        leading: const Icon(Icons.storage),
                        title: const Text('TechStore REST API (custom)'),
                        subtitle: Text('$url/products.php'),
                      ),
                    ),
                    const Divider(height: 1),
                    const ListTile(
                      leading: Icon(Icons.public),
                      title: Text('DummyJSON Products API (third-party)'),
                      subtitle: Text(
                        '${ApiConfig.dummyJsonBaseUrl}/products  ·  https://dummyjson.com/docs/products',
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
}
