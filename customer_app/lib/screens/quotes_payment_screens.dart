import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/api_client.dart';
import '../providers/auth_provider.dart';
import '../providers/realtime_provider.dart';
import '../widgets/app_gradients.dart';

String _ghsFromPesewas(int pesewas) {
  return 'GHS ${(pesewas / 100).toStringAsFixed(2)}';
}

int? _pesewasInt(dynamic v) {
  if (v == null) return null;
  if (v is int) return v;
  if (v is double) return v.round();
  return int.tryParse(v.toString());
}

/// Backend stores optional labour / parts / transport in pesewas (same as total).
/// When present, we show all three lines so parts & transport are never hidden.
Map<String, int>? _breakdownMap(dynamic raw) {
  if (raw == null) return null;
  if (raw is! Map) return null;
  return {
    'labour': _pesewasInt(raw['labour']) ?? 0,
    'parts': _pesewasInt(raw['parts']) ?? 0,
    'transport': _pesewasInt(raw['transport']) ?? 0,
  };
}

String _prettyTier(String? t) {
  if (t == null || t.isEmpty) return '';
  final lower = t.replaceAll('_', ' ').toLowerCase().split(' ');
  return lower.map((w) => w.isEmpty ? '' : '${w[0].toUpperCase()}${w.substring(1)}').join(' ');
}

String? _formatExpires(dynamic raw) {
  if (raw is! String || raw.isEmpty) return null;
  try {
    final local = DateTime.parse(raw).toLocal();
    return DateFormat('d MMM yyyy · HH:mm').format(local);
  } catch (_) {
    return null;
  }
}

class QuotesListScreen extends ConsumerStatefulWidget {
  const QuotesListScreen({required this.jobId, super.key});
  final String jobId;

  @override
  ConsumerState<QuotesListScreen> createState() => _QuotesListScreenState();
}

class _QuotesListScreenState extends ConsumerState<QuotesListScreen> {
  List<dynamic> _quotes = [];
  String? _error;
  bool _loading = true;
  String? _acceptingQuoteId;
  String? _rejectingQuoteId;
  StreamSubscription<Map<String, dynamic>>? _jobEvSub;

  @override
  void initState() {
    super.initState();
    _load();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final rt = ref.read(realtimeClientProvider);
      rt.joinJob(widget.jobId);
      _jobEvSub = rt.onJobEvent.listen((data) {
        final id = data['jobId'] as String?;
        if (id == widget.jobId && mounted) _load();
      });
    });
  }

  @override
  void dispose() {
    _jobEvSub?.cancel();
    ref.read(realtimeClientProvider).leaveJob(widget.jobId);
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final api = ref.read(apiClientProvider);
    try {
      final list = await api.listJobQuotes(widget.jobId);
      if (!mounted) return;
      setState(() {
        _quotes = list;
        _loading = false;
      });
    } on DioException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = messageFromDio(e);
        _loading = false;
      });
    }
  }

  Future<void> _accept(String quoteId) async {
    setState(() => _acceptingQuoteId = quoteId);
    final api = ref.read(apiClientProvider);
    try {
      await api.acceptQuote(quoteId);
      if (!mounted) return;
      context.push('/jobs/${widget.jobId}/quote-accepted');
    } on DioException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(messageFromDio(e))),
      );
    } finally {
      if (mounted) setState(() => _acceptingQuoteId = null);
    }
  }

  Future<void> _reject(String quoteId) async {
    setState(() => _rejectingQuoteId = quoteId);
    final api = ref.read(apiClientProvider);
    try {
      await api.rejectQuote(quoteId);
      if (!mounted) return;
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Quote rejected.')),
      );
    } on DioException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(messageFromDio(e))),
      );
    } finally {
      if (mounted) setState(() => _rejectingQuoteId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Quotes'),
        actions: [
          IconButton(
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Refresh',
          ),
        ],
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
                        const SizedBox(height: 16),
                        FilledButton(onPressed: _load, child: const Text('Retry')),
                      ],
                    ),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: _quotes.isEmpty
                      ? ListView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          children: [
                            SizedBox(
                              height: MediaQuery.sizeOf(context).height * 0.35,
                            ),
                            Center(
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 32),
                                child: Text(
                                  'No quotes yet. Pull to refresh after a worker sends a price.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                                ),
                              ),
                            ),
                          ],
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.all(16),
                          itemCount: _quotes.length,
                          itemBuilder: (context, i) {
                            final q = _quotes[i] as Map<String, dynamic>;
                            final id = q['id'] as String? ?? '';
                            final actionable = (q['status'] as String? ?? '') == 'PENDING' ||
                                (q['status'] as String? ?? '') == 'COUNTERED';
                            return _CustomerQuoteCard(
                              quote: q,
                              actionable: actionable,
                              accepting: _acceptingQuoteId == id,
                              rejecting: _rejectingQuoteId == id,
                              onAccept: () => _accept(id),
                              onReject: () => _reject(id),
                            );
                          },
                        ),
                ),
    );
  }
}

Widget _breakdownLine(BuildContext context, String label, int pesewas) {
  final tt = Theme.of(context).textTheme;
  final cs = Theme.of(context).colorScheme;
  return Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Row(
      children: [
        Expanded(child: Text(label, style: tt.bodyMedium)),
        Text(
          _ghsFromPesewas(pesewas),
          style: tt.bodyMedium?.copyWith(fontWeight: FontWeight.w500, color: cs.onSurface),
        ),
      ],
    ),
  );
}

class _CustomerQuoteCard extends StatelessWidget {
  const _CustomerQuoteCard({
    required this.quote,
    required this.actionable,
    required this.accepting,
    required this.rejecting,
    required this.onAccept,
    required this.onReject,
  });

  final Map<String, dynamic> quote;
  final bool actionable;
  final bool accepting;
  final bool rejecting;
  final VoidCallback onAccept;
  final VoidCallback onReject;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    final pesewas = quote['amountPesewas'];
    final amount = pesewas is int ? pesewas : int.tryParse('$pesewas') ?? 0;
    final status = quote['status'] as String? ?? '';
    final msg = quote['message'] as String?;
    final counterRaw = quote['counterAmountPesewas'];
    final counterPesewas = counterRaw != null
        ? (counterRaw is int ? counterRaw : int.tryParse('$counterRaw'))
        : null;
    final breakdown = _breakdownMap(quote['breakdown']);
    final worker = quote['worker'] as Map<String, dynamic>?;
    final name = worker?['name'] as String? ?? 'Worker';
    final tier = worker?['tier'] as String?;
    final tierLabel = _prettyTier(tier);
    final rating = worker?['rating'];
    final jobsDone = worker?['totalJobsCompleted'];
    final jobsDoneInt = jobsDone is int ? jobsDone : (jobsDone is num ? jobsDone.toInt() : 0);
    final ratingStr = rating is num
        ? (jobsDoneInt == 0 && rating == 0 ? 'New' : rating.toStringAsFixed(1))
        : '—';
    final jobsStr = jobsDoneInt > 0 ? '$jobsDoneInt' : '0';
    final bio = worker?['bio'] as String?;
    final expires = _formatExpires(quote['expiresAt']);

    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    'Offer',
                    style: tt.labelMedium?.copyWith(color: cs.onSurfaceVariant),
                  ),
                ),
                Chip(
                  label: Text(status, style: const TextStyle(fontSize: 12)),
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text('Worker', style: tt.labelMedium?.copyWith(color: cs.onSurfaceVariant)),
            const SizedBox(height: 4),
            Text(
              name,
              style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 10,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (tierLabel.isNotEmpty)
                  Chip(
                    label: Text('Tier: $tierLabel'),
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                  ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.star_rounded, size: 18, color: Colors.amber.shade700),
                    const SizedBox(width: 4),
                    Text(
                      ratingStr == 'New' ? 'New to RidDev' : '$ratingStr avg. rating',
                      style: tt.bodySmall,
                    ),
                  ],
                ),
                Text('$jobsStr jobs completed', style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
              ],
            ),
            if (bio != null && bio.trim().isNotEmpty) ...[
              const SizedBox(height: 12),
              Text('About this tradesperson', style: tt.labelMedium?.copyWith(color: cs.onSurfaceVariant)),
              const SizedBox(height: 4),
              Text(
                bio.trim(),
                style: tt.bodyMedium?.copyWith(height: 1.4),
              ),
            ],
            const SizedBox(height: 16),
            Text('Price details', style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            if (breakdown != null) ...[
              _breakdownLine(context, 'Labour', breakdown['labour'] ?? 0),
              _breakdownLine(context, 'Parts & materials', breakdown['parts'] ?? 0),
              _breakdownLine(context, 'Transportation', breakdown['transport'] ?? 0),
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Divider(height: 1),
              ),
            ] else
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  'The worker did not add a labour / parts / transport breakdown — only a total is shown below.',
                  style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant, fontStyle: FontStyle.italic, height: 1.35),
                ),
              ),
            if (status == 'COUNTERED' && counterPesewas != null && counterPesewas > 0) ...[
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Expanded(
                    child: Text('Original quote', style: tt.bodyMedium),
                  ),
                  Text(_ghsFromPesewas(amount), style: tt.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Expanded(
                    child: Text('Counter-offer (current)', style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
                  ),
                  Text(
                    _ghsFromPesewas(counterPesewas),
                    style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w800, color: cs.primary),
                  ),
                ],
              ),
            ] else
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Expanded(
                    child: Text('Total quoted', style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
                  ),
                  Text(
                    _ghsFromPesewas(amount),
                    style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w800, color: cs.primary),
                  ),
                ],
              ),
            if (breakdown != null) ...[
              const SizedBox(height: 6),
              Text(
                'If line items do not add up to the total, the worker may have rounded the package price.',
                style: tt.labelSmall?.copyWith(color: cs.onSurfaceVariant, height: 1.3),
              ),
            ],
            if (expires != null) ...[
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.timer_outlined, size: 18, color: cs.onSurfaceVariant),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Quote expires: $expires',
                      style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant, height: 1.35),
                    ),
                  ),
                ],
              ),
            ],
            if (msg != null && msg.trim().isNotEmpty) ...[
              const SizedBox(height: 14),
              Text('Message from worker', style: tt.labelMedium?.copyWith(color: cs.onSurfaceVariant)),
              const SizedBox(height: 6),
              DecoratedBox(
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHighest.withValues(alpha: 0.65),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(msg.trim(), style: tt.bodyMedium?.copyWith(height: 1.45)),
                ),
              ),
            ],
            if (actionable) ...[
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: (accepting || rejecting) ? null : onReject,
                    child: rejecting
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Reject'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: (accepting || rejecting) ? null : onAccept,
                    child: accepting
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Accept'),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class NegotiationScreen extends StatelessWidget {
  const NegotiationScreen({required this.jobId, super.key});
  final String jobId;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Negotiation')),
      body: const Center(child: Text('Counter-offer thread')),
    );
  }
}

class QuoteAcceptedScreen extends StatelessWidget {
  const QuoteAcceptedScreen({required this.jobId, super.key});
  final String jobId;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Quote accepted')),
      body: Center(
        child: FilledButton(
          onPressed: () => context.push('/payment/$jobId'),
          child: const Text('Proceed to payment'),
        ),
      ),
    );
  }
}

class _PaymentSummaryCard extends StatelessWidget {
  const _PaymentSummaryCard({
    required this.agreedPesewas,
    required this.trustPesewas,
    required this.totalPesewas,
  });

  final int agreedPesewas;
  final int trustPesewas;
  final int totalPesewas;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Material(
      color: cs.surface,
      elevation: 2,
      shadowColor: cs.shadow.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(18),
      child: Ink(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.4)),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              cs.surface,
              cs.surfaceContainerHighest.withValues(alpha: 0.35),
            ],
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(Icons.receipt_long_rounded, color: cs.primary, size: 22),
                  const SizedBox(width: 10),
                  Text(
                    'Order summary',
                    style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w800),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _PaymentLine(
                label: 'Agreed job price',
                value: _ghsFromPesewas(agreedPesewas),
                tt: tt,
                cs: cs,
              ),
              const SizedBox(height: 10),
              _PaymentLine(
                label: 'Trust & support (5%)',
                value: _ghsFromPesewas(trustPesewas),
                tt: tt,
                cs: cs,
              ),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 14),
                child: Divider(height: 1, color: cs.outlineVariant.withValues(alpha: 0.6)),
              ),
              _PaymentLine(
                label: 'Total due today',
                value: _ghsFromPesewas(totalPesewas),
                tt: tt,
                cs: cs,
                emphasize: true,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PaymentLine extends StatelessWidget {
  const _PaymentLine({
    required this.label,
    required this.value,
    required this.tt,
    required this.cs,
    this.emphasize = false,
  });

  final String label;
  final String value;
  final TextTheme tt;
  final ColorScheme cs;
  final bool emphasize;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          child: Text(
            label,
            style: emphasize
                ? tt.titleSmall?.copyWith(fontWeight: FontWeight.w700, color: cs.onSurface)
                : tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
          ),
        ),
        Text(
          value,
          style: emphasize
              ? tt.titleLarge?.copyWith(fontWeight: FontWeight.w900, color: cs.primary, letterSpacing: -0.3)
              : tt.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
        ),
      ],
    );
  }
}

class _PaymentFundingOptionTile extends StatelessWidget {
  const _PaymentFundingOptionTile({
    required this.selected,
    required this.title,
    required this.subtitle,
    required this.icon,
    this.onTap,
  });

  final bool selected;
  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: cs.surface,
        elevation: selected ? 2 : 0.5,
        shadowColor: cs.shadow.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Ink(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: selected ? cs.primary : cs.outlineVariant.withValues(alpha: 0.45),
                width: selected ? 2 : 1,
              ),
              color: selected ? cs.primaryContainer.withValues(alpha: 0.22) : cs.surface,
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: selected ? cs.primary.withValues(alpha: 0.18) : cs.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(icon, color: selected ? cs.primary : cs.onSurfaceVariant, size: 24),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          subtitle,
                          style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant, height: 1.35),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    selected ? Icons.check_circle_rounded : Icons.circle_outlined,
                    color: selected ? cs.primary : cs.outline,
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

class PaymentScreen extends ConsumerStatefulWidget {
  const PaymentScreen({required this.jobId, super.key});
  final String jobId;

  @override
  ConsumerState<PaymentScreen> createState() => _PaymentScreenState();
}

class _PaymentScreenState extends ConsumerState<PaymentScreen> {
  bool _paying = false;
  bool _loading = true;
  String? _loadError;
  Map<String, dynamic>? _job;
  int? _balancePesewas;
  bool _walletLocked = false;
  String _fundingSource = 'PAYSTACK';
  int _externalPayChoice = 0;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  int _customerTotalPesewas(Map<String, dynamic> job) {
    final agreed = _pesewasInt(job['agreedPricePesewas']) ?? 0;
    if (agreed <= 0) return 0;
    final trustStored = _pesewasInt(job['trustFeePesewas']);
    final trust = trustStored ?? ((agreed * 500) / 10000).round();
    return agreed + trust;
  }

  Future<void> _loadData() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final api = ref.read(apiClientProvider);
      final job = await api.getJob(widget.jobId);
      final w = await api.getWallet();
      if (!mounted) return;
      setState(() {
        _job = job;
        _balancePesewas = w['balancePesewas'] as int?;
        _walletLocked = w['isLocked'] == true;
        _loading = false;
      });
    } on DioException catch (e) {
      if (!mounted) return;
      setState(() {
        _loadError = messageFromDio(e);
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loadError = 'Could not load payment details.';
        _loading = false;
      });
    }
  }

  Future<void> _refreshWalletOnly() async {
    try {
      final w = await ref.read(apiClientProvider).getWallet();
      if (!mounted) return;
      setState(() {
        _balancePesewas = w['balancePesewas'] as int?;
        _walletLocked = w['isLocked'] == true;
      });
    } catch (_) {
      /* keep previous */
    }
  }

  Future<void> _onPay() async {
    setState(() => _paying = true);
    try {
      final data = await ref.read(apiClientProvider).initiatePayment(
        jobId: widget.jobId,
        fundingSource: _fundingSource,
      );
      if (!mounted) return;
      final simulated = data['devSimulatedEscrow'] == true;
      final fromWallet = data['fundedByWallet'] == true;
      final authUrl = data['authorizationUrl'];
      final urlStr = authUrl is String ? authUrl.trim() : '';

      if (simulated || fromWallet) {
        context.go('/payment/${widget.jobId}/success');
        return;
      }
      if (urlStr.isNotEmpty) {
        final uri = Uri.tryParse(urlStr);
        if (uri != null && await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        }
        if (mounted) {
          context.push('/payment/${widget.jobId}/processing');
        }
        return;
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No payment URL returned. Check backend configuration.')),
        );
      }
    } on DioException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(messageFromDio(e))),
      );
    } finally {
      if (mounted) setState(() => _paying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Scaffold(
      backgroundColor: cs.surfaceContainerLowest,
      appBar: AppBar(
        title: const Text('Checkout'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => context.pop(),
          tooltip: 'Back',
        ),
        actions: [
          if (!_loading && _loadError == null)
            IconButton(
              onPressed: _paying ? null : () async => _loadData(),
              icon: const Icon(Icons.refresh_rounded),
              tooltip: 'Refresh',
            ),
        ],
      ),
      body: _loading
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 20),
                  Text(
                    'Loading checkout…',
                    style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
                  ),
                ],
              ),
            )
          : _loadError != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.cloud_off_rounded, size: 56, color: cs.outline),
                        const SizedBox(height: 16),
                        Text(_loadError!, textAlign: TextAlign.center, style: tt.bodyLarge),
                        const SizedBox(height: 20),
                        FilledButton(onPressed: _loadData, child: const Text('Retry')),
                      ],
                    ),
                  ),
                )
              : _buildBody(context, cs, tt),
    );
  }

  Widget _buildBody(BuildContext context, ColorScheme cs, TextTheme tt) {
    final job = _job!;
    final jobTitle = job['title'] as String? ?? 'Job';
    final agreed = _pesewasInt(job['agreedPricePesewas']) ?? 0;
    final trustStored = _pesewasInt(job['trustFeePesewas']);
    final trust = agreed > 0 ? (trustStored ?? ((agreed * 500) / 10000).round()) : 0;
    final totalPesewas = _customerTotalPesewas(job);
    final bal = _balancePesewas ?? 0;
    final canPayFromWallet =
        totalPesewas > 0 && bal >= totalPesewas && !_walletLocked;

    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 32),
      children: [
        if (agreed <= 0)
          Material(
            color: cs.errorContainer.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.error_outline_rounded, color: cs.error),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Could not read the agreed price. Go back and open checkout from the accepted quote again.',
                      style: tt.bodyMedium?.copyWith(color: cs.onErrorContainer, height: 1.35),
                    ),
                  ),
                ],
              ),
            ),
          )
        else ...[
          Material(
            color: Colors.transparent,
            elevation: 6,
            shadowColor: cs.primary.withValues(alpha: 0.28),
            borderRadius: BorderRadius.circular(20),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: Stack(
                children: [
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: const BoxDecoration(gradient: AppGradients.hero),
                    ),
                  ),
                  Positioned(
                    right: -20,
                    top: -20,
                    child: Icon(Icons.blur_on_rounded, size: 100, color: Colors.white.withValues(alpha: 0.1)),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(18, 20, 18, 20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Secure escrow',
                          style: tt.labelLarge?.copyWith(
                            color: Colors.white.withValues(alpha: 0.88),
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.4,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          jobTitle,
                          style: tt.titleLarge?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            height: 1.2,
                            letterSpacing: -0.3,
                          ),
                        ),
                        const SizedBox(height: 18),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: Colors.white24),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Total due',
                                    style: tt.bodySmall?.copyWith(color: Colors.white70),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Held until work is complete',
                                    style: tt.labelSmall?.copyWith(color: Colors.white54),
                                  ),
                                ],
                              ),
                              Text(
                                _ghsFromPesewas(totalPesewas),
                                style: tt.headlineSmall?.copyWith(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: -0.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          _PaymentSummaryCard(
            agreedPesewas: agreed,
            trustPesewas: trust,
            totalPesewas: totalPesewas,
          ),
          const SizedBox(height: 22),
          Row(
            children: [
              Icon(Icons.account_balance_wallet_rounded, color: cs.primary, size: 22),
              const SizedBox(width: 10),
              Text(
                'Choose how to pay',
                style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w800),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _PaymentFundingOptionTile(
            selected: _fundingSource == 'PAYSTACK',
            title: 'Paystack / MoMo',
            subtitle: 'Card or mobile money — opens secure Paystack checkout.',
            icon: Icons.credit_card_rounded,
            onTap: _paying ? null : () => setState(() => _fundingSource = 'PAYSTACK'),
          ),
          _PaymentFundingOptionTile(
            selected: _fundingSource == 'WALLET',
            title: 'RidDev wallet',
            subtitle: totalPesewas > 0
                ? 'Pay ${_ghsFromPesewas(totalPesewas)} from your in-app balance.'
                : 'Pay from balance when the total is ready.',
            icon: Icons.savings_rounded,
            onTap: _paying
                ? null
                : () {
                    setState(() => _fundingSource = 'WALLET');
                    _refreshWalletOnly();
                  },
          ),
          const SizedBox(height: 8),
          if (_fundingSource == 'PAYSTACK') ...[
            Material(
              color: cs.surface,
              elevation: 1,
              borderRadius: BorderRadius.circular(16),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Method',
                      style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 10),
                    SegmentedButton<int>(
                      segments: const [
                        ButtonSegment(value: 0, label: Text('MTN MoMo')),
                        ButtonSegment(value: 1, label: Text('Telecel')),
                        ButtonSegment(value: 2, label: Text('Card')),
                      ],
                      selected: {_externalPayChoice},
                      onSelectionChanged: _paying
                          ? null
                          : (Set<int> s) {
                              if (s.isEmpty) return;
                              setState(() => _externalPayChoice = s.first);
                            },
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      decoration: InputDecoration(
                        labelText: 'MoMo number (if using MoMo)',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        filled: true,
                        fillColor: cs.surfaceContainerHighest.withValues(alpha: 0.5),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Wallet for reference: ${_ghsFromPesewas(bal)} — switch to RidDev wallet above to pay from balance.',
                      style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant, height: 1.35),
                    ),
                  ],
                ),
              ),
            ),
          ] else ...[
            Material(
              color: cs.surface,
              elevation: 2,
              shadowColor: cs.shadow.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(18),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Wallet balance', style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
                        IconButton(
                          onPressed: _paying ? null : _refreshWalletOnly,
                          icon: const Icon(Icons.refresh_rounded),
                          tooltip: 'Refresh',
                        ),
                      ],
                    ),
                    Text(
                      _ghsFromPesewas(bal),
                      style: tt.headlineMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                        color: cs.primary,
                        letterSpacing: -0.5,
                      ),
                    ),
                    if (_walletLocked) ...[
                      const SizedBox(height: 12),
                      Text(
                        'Wallet is temporarily locked. Use Paystack or contact support.',
                        style: tt.bodySmall?.copyWith(color: cs.error),
                      ),
                    ] else ...[
                      const SizedBox(height: 12),
                      Text(
                        'Due now: ${_ghsFromPesewas(totalPesewas)}',
                        style: tt.bodyMedium,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        canPayFromWallet
                            ? 'Enough balance — you can pay in one tap below.'
                            : (bal < totalPesewas
                                ? 'Top up under Profile → Wallet to cover this amount.'
                                : ''),
                        style: tt.bodySmall?.copyWith(
                          color: canPayFromWallet ? cs.primary : cs.onSurfaceVariant,
                          fontWeight: canPayFromWallet ? FontWeight.w700 : null,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(height: 24),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
            onPressed: _paying || (agreed <= 0)
                ? null
                : (_fundingSource == 'WALLET' && !canPayFromWallet)
                    ? null
                    : _onPay,
            icon: _paying
                ? const SizedBox(
                    height: 22,
                    width: 22,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : Icon(_fundingSource == 'WALLET' ? Icons.lock_open_rounded : Icons.arrow_forward_rounded),
            label: _paying
                ? const Text('Processing…')
                : Text(_fundingSource == 'WALLET' ? 'Pay from wallet' : 'Continue to secure checkout'),
          ),
          const SizedBox(height: 14),
          Text(
            _fundingSource == 'PAYSTACK'
                ? 'You may complete payment in Paystack. Funds are held in escrow until you confirm the work.'
                : 'Funds move from your RidDev wallet into escrow for this job when you confirm.',
            textAlign: TextAlign.center,
            style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant, height: 1.4),
          ),
        ],
      ],
    );
  }
}

class PaymentProcessingScreen extends StatelessWidget {
  const PaymentProcessingScreen({required this.jobId, super.key});
  final String jobId;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Scaffold(
      backgroundColor: cs.surfaceContainerLowest,
      appBar: AppBar(
        title: const Text('Completing payment'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => context.pop(),
          tooltip: 'Back',
        ),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: cs.primaryContainer.withValues(alpha: 0.5),
                ),
                child: Icon(Icons.hourglass_top_rounded, size: 48, color: cs.primary),
              ),
              const SizedBox(height: 24),
              Text(
                'Finish in your browser',
                textAlign: TextAlign.center,
                style: tt.titleLarge?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 10),
              Text(
                'After Paystack confirms, return here — we’ll update escrow automatically.',
                textAlign: TextAlign.center,
                style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant, height: 1.45),
              ),
              const SizedBox(height: 28),
              const CircularProgressIndicator(),
              const SizedBox(height: 32),
              FilledButton.tonal(
                onPressed: () => context.go('/payment/$jobId/success'),
                child: const Text('Simulate success (dev)'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class PaymentSuccessScreen extends StatelessWidget {
  const PaymentSuccessScreen({required this.jobId, super.key});
  final String jobId;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Scaffold(
      backgroundColor: cs.surfaceContainerLowest,
      appBar: AppBar(
        title: const Text('Payment successful'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => context.go('/history'),
          tooltip: 'Job history',
        ),
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(22),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: AppGradients.cardSoft,
                  boxShadow: [
                    BoxShadow(
                      color: cs.primary.withValues(alpha: 0.15),
                      blurRadius: 24,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Icon(Icons.verified_rounded, size: 52, color: cs.primary),
              ),
              const SizedBox(height: 24),
              Text(
                'Funds are in escrow',
                textAlign: TextAlign.center,
                style: tt.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 10),
              Text(
                'You can message your worker and track the job. Payment is released when you confirm the work is done.',
                textAlign: TextAlign.center,
                style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant, height: 1.45),
              ),
              const SizedBox(height: 32),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 24),
                  minimumSize: const Size.fromHeight(52),
                ),
                onPressed: () => context.go('/active-job/$jobId?from=payment'),
                icon: const Icon(Icons.construction_rounded),
                label: const Text('Go to active job'),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: () => context.go('/history?filter=active'),
                child: const Text('View in job history'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
