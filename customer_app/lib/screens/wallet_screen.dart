import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/api_client.dart';
import '../providers/auth_provider.dart';
import '../widgets/app_gradients.dart';

String _ghs(int? pesewas) {
  if (pesewas == null || pesewas < 0) return 'GHS 0.00';
  return 'GHS ${(pesewas / 100).toStringAsFixed(2)}';
}

class CustomerWalletScreen extends ConsumerStatefulWidget {
  const CustomerWalletScreen({super.key});

  @override
  ConsumerState<CustomerWalletScreen> createState() => _CustomerWalletScreenState();
}

class _CustomerWalletScreenState extends ConsumerState<CustomerWalletScreen> {
  Map<String, dynamic>? _data;
  String? _error;
  bool _loading = true;
  bool _toppingUp = false;
  final _topUpGhs = TextEditingController(text: '50');

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _topUpGhs.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final d = await ref.read(apiClientProvider).getWallet();
      if (!mounted) return;
      setState(() {
        _data = d;
        _loading = false;
      });
    } on DioException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = messageFromDio(e);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _topUp() async {
    final ghs = double.tryParse(_topUpGhs.text.trim());
    if (ghs == null || ghs < 10) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter at least GHS 10.')),
      );
      return;
    }
    final pesewas = (ghs * 100).round();
    setState(() => _toppingUp = true);
    try {
      await ref.read(apiClientProvider).topUpWallet(pesewas);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Added ${_ghs(pesewas)} (simulated) — use Profile → navigate away and back if needed')),
      );
      await _load();
    } on DioException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(messageFromDio(e))),
      );
    } finally {
      if (mounted) setState(() => _toppingUp = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bal = _data?['balancePesewas'] as int?;
    final esc = _data?['inEscrowPesewas'] as int?;
    final recent = _data?['recent'];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Wallet'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => context.pop(),
        ),
        actions: [IconButton(onPressed: _loading ? null : _load, icon: const Icon(Icons.refresh_rounded))],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(_error!, textAlign: TextAlign.center),
                        FilledButton(onPressed: _load, child: const Text('Retry')),
                      ],
                    ),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(20),
                        gradient: AppGradients.hero,
                        boxShadow: [
                          BoxShadow(
                            color: cs.primary.withValues(alpha: 0.3),
                            blurRadius: 18,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Available', style: TextStyle(color: Colors.white.withValues(alpha: 0.9))),
                          const SizedBox(height: 6),
                          Text(
                            _ghs(bal),
                            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w800,
                                ),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'In escrow (jobs): ${_ghs(esc)}',
                            style: TextStyle(color: Colors.white.withValues(alpha: 0.88), fontSize: 14),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text('Test top-up (dev)', style: Theme.of(context).textTheme.titleSmall),
                    const SizedBox(height: 8),
                    Text(
                      'Requires DEV_SIMULATE_ESCROW or DEV_SIMULATE_WALLET_TOPUP on the server. For arbitrary amounts use Admin → Wallet credit.',
                      style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _topUpGhs,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            decoration: const InputDecoration(
                              labelText: 'Amount (GHS)',
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        FilledButton(
                          onPressed: _toppingUp ? null : _topUp,
                          child: _toppingUp
                              ? const SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Text('Add'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    Text('Recent', style: Theme.of(context).textTheme.titleSmall),
                    const SizedBox(height: 8),
                    if (recent is! List || recent.isEmpty)
                      Text('No movements yet', style: TextStyle(color: cs.onSurfaceVariant))
                    else
                      ...(recent as List)
                          .map<Widget>((row) {
                            final m = row as Map<String, dynamic>;
                            final amt = m['amountPesewas'] as int? ?? 0;
                            final dir = m['direction'] as String? ?? '';
                            final desc = m['description'] as String? ?? m['type'] as String? ?? '';
                            final isCredit = dir == 'CREDIT';
                            return ListTile(
                              dense: true,
                              title: Text(desc, maxLines: 2, overflow: TextOverflow.ellipsis),
                              trailing: Text(
                                '${isCredit ? '+' : '-'}${_ghs(amt)}',
                                style: TextStyle(
                                  color: isCredit ? Colors.green : Colors.red,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            );
                          })
                          .toList(),
                  ],
                ),
    );
  }
}
