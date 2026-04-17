import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../core/api_client.dart';
import '../core/api_url.dart';
import '../core/notification_utils.dart';
import '../providers/auth_provider.dart';
import '../providers/post_job_provider.dart';
import '../providers/realtime_provider.dart';
import '../widgets/app_gradients.dart';

String _ghsFromPesewasNum(dynamic ag) {
  int? p;
  if (ag is int) {
    p = ag;
  } else if (ag != null) {
    p = int.tryParse('$ag');
  }
  if (p == null || p <= 0) {
    return '';
  }
  return 'GHS ${(p / 100).toStringAsFixed(2)}';
}

String _profileInitials(String? name) {
  if (name == null || name.trim().isEmpty) return '?';
  final parts = name.trim().split(RegExp(r'\s+'));
  if (parts.length >= 2) {
    final a = parts[0].isNotEmpty ? parts[0][0] : '';
    final b = parts[1].isNotEmpty ? parts[1][0] : '';
    return ('$a$b').toUpperCase();
  }
  final s = parts[0];
  return (s.length >= 2 ? s.substring(0, 2) : s).toUpperCase();
}

int? _pesewasInt(dynamic v) {
  if (v == null) return null;
  if (v is int) return v;
  if (v is double) return v.round();
  return int.tryParse(v.toString());
}

/// Same shape as worker quote breakdown (pesewas per line).
Map<String, int>? _quoteBreakdownMap(dynamic raw) {
  if (raw == null) return null;
  if (raw is! Map) return null;
  return {
    'labour': _pesewasInt(raw['labour']) ?? 0,
    'parts': _pesewasInt(raw['parts']) ?? 0,
    'transport': _pesewasInt(raw['transport']) ?? 0,
  };
}

class _JobBreakdownRow extends StatelessWidget {
  const _JobBreakdownRow({
    required this.label,
    required this.pesewas,
    required this.tt,
    required this.cs,
  });

  final String label;
  final int pesewas;
  final TextTheme tt;
  final ColorScheme cs;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Expanded(child: Text(label, style: tt.bodyMedium)),
          Text(
            'GHS ${(pesewas / 100).toStringAsFixed(2)}',
            style: tt.bodyMedium?.copyWith(fontWeight: FontWeight.w600, color: cs.onSurface),
          ),
        ],
      ),
    );
  }
}

bool _jobNeedsPayment(Map<String, dynamic> j) {
  final status = j['status'] as String? ?? '';
  if (status != 'ACCEPTED' && status != 'IN_PROGRESS') return false;
  return j['escrowHeld'] != true;
}

String _jobHistorySubtitle(Map<String, dynamic> j) {
  if (_jobNeedsPayment(j)) {
    return 'Pending payment · pay to unlock chat and start work';
  }
  final status = j['status'] as String? ?? '';
  final worker = j['worker'] as Map<String, dynamic>?;
  final name = worker?['name'] as String?;
  final ghs = _ghsFromPesewasNum(j['agreedPricePesewas']);
  final statusLabel = status.replaceAll('_', ' ');
  switch (status) {
    case 'OPEN':
    case 'QUOTED':
      return '$statusLabel · tap for quotes';
    case 'ACCEPTED':
    case 'IN_PROGRESS':
    case 'COMPLETED':
    case 'DISPUTED':
      final parts = <String>[statusLabel];
      if (name != null && name.isNotEmpty) parts.add(name);
      if (ghs.isNotEmpty) parts.add(ghs);
      return parts.join(' · ');
    default:
      return statusLabel;
  }
}

/// Hero summary on [JobHistoryScreen] when `filter=active`.
class _ActiveJobsPanelHeader extends StatelessWidget {
  const _ActiveJobsPanelHeader({
    required this.jobCount,
    required this.awaitingPaymentCount,
  });

  final int jobCount;
  final int awaitingPaymentCount;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: AppGradients.hero,
        boxShadow: [
          BoxShadow(
            color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.28),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(Icons.flash_on_rounded, color: Colors.white, size: 28),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  jobCount == 1 ? '1 active job' : '$jobCount active jobs',
                  style: tt.titleLarge?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.4,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Accepted & in progress — open a job to chat, pay, or mark complete.',
                  style: tt.bodySmall?.copyWith(
                    color: Colors.white.withValues(alpha: 0.88),
                    height: 1.4,
                  ),
                ),
                if (awaitingPaymentCount > 0) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.amber.shade100.withValues(alpha: 0.25),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.amber.shade200.withValues(alpha: 0.6)),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.priority_high_rounded, size: 20, color: Colors.amber.shade200),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            awaitingPaymentCount == 1
                                ? '1 job needs payment before chat unlocks'
                                : '$awaitingPaymentCount jobs need payment',
                            style: tt.labelLarge?.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ActiveJobsPaymentRow extends StatelessWidget {
  const _ActiveJobsPaymentRow({required this.pendingCount});

  final int pendingCount;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Material(
      color: cs.errorContainer.withValues(alpha: 0.45),
      borderRadius: BorderRadius.circular(16),
      elevation: 2,
      shadowColor: cs.error.withValues(alpha: 0.15),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              backgroundColor: cs.error.withValues(alpha: 0.18),
              child: Icon(Icons.lock_clock_rounded, color: cs.error),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Checkout required',
                    style: tt.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: cs.onErrorContainer,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    pendingCount == 1
                        ? '1 job is waiting for payment. Pay in the job screen to message your worker.'
                        : '$pendingCount jobs are waiting for payment. Complete checkout to unlock chat.',
                    style: tt.bodySmall?.copyWith(
                      color: cs.onErrorContainer.withValues(alpha: 0.92),
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ActiveJobPanelCard extends StatelessWidget {
  const _ActiveJobPanelCard({
    required this.job,
    required this.onTap,
  });

  final Map<String, dynamic> job;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final title = job['title'] as String? ?? 'Job';
    final pendingPay = _jobNeedsPayment(job);
    final worker = job['worker'] as Map<String, dynamic>?;
    final workerName = worker?['name'] as String?;
    final status = (job['status'] as String? ?? '').replaceAll('_', ' ');
    final ghs = _ghsFromPesewasNum(job['agreedPricePesewas']);

    return Material(
      color: cs.surface,
      elevation: 2,
      shadowColor: cs.shadow.withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: pendingPay ? cs.error.withValues(alpha: 0.45) : cs.outlineVariant.withValues(alpha: 0.42),
              width: pendingPay ? 1.5 : 1,
            ),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                cs.surface,
                pendingPay ? cs.errorContainer.withValues(alpha: 0.12) : cs.surfaceContainerHighest.withValues(alpha: 0.35),
              ],
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: pendingPay
                          ? [
                              cs.errorContainer.withValues(alpha: 0.85),
                              cs.errorContainer.withValues(alpha: 0.35),
                            ]
                          : [
                              cs.primaryContainer.withValues(alpha: 0.95),
                              cs.primaryContainer.withValues(alpha: 0.45),
                            ],
                    ),
                  ),
                  child: Icon(
                    pendingPay ? Icons.payment_rounded : Icons.construction_rounded,
                    color: pendingPay ? cs.error : cs.onPrimaryContainer,
                    size: 26,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.2),
                      ),
                      if (workerName != null && workerName.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Icon(Icons.person_outline_rounded, size: 14, color: cs.primary),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                workerName,
                                style: tt.bodySmall?.copyWith(
                                  color: cs.primary,
                                  fontWeight: FontWeight.w600,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ],
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: cs.secondaryContainer.withValues(alpha: 0.8),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              status,
                              style: tt.labelMedium?.copyWith(
                                color: cs.onSecondaryContainer,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          if (ghs.isNotEmpty)
                            Text(ghs, style: tt.labelLarge?.copyWith(fontWeight: FontWeight.w700)),
                          if (pendingPay)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: cs.error.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.warning_amber_rounded, size: 14, color: cs.error),
                                  const SizedBox(width: 4),
                                  Text(
                                    'Pay to unlock chat',
                                    style: tt.labelMedium?.copyWith(
                                      color: cs.error,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right_rounded, color: cs.outline),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ActiveJobsEmptyPanel extends ConsumerWidget {
  const _ActiveJobsEmptyPanel();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Center(
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
                    color: cs.primary.withValues(alpha: 0.12),
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Icon(Icons.work_history_rounded, size: 48, color: cs.primary),
            ),
            const SizedBox(height: 24),
            Text(
              'No active jobs yet',
              textAlign: TextAlign.center,
              style: tt.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 12),
            Text(
              'When you accept a quote and complete payment, your job moves here so you can chat with your worker and track the work.',
              textAlign: TextAlign.center,
              style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant, height: 1.45),
            ),
            const SizedBox(height: 28),
            FilledButton.icon(
              onPressed: () {
                ref.read(postJobProvider.notifier).reset();
                context.push('/post/category');
              },
              icon: const Icon(Icons.add_rounded),
              label: const Text('Post a job'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Summary header when [JobHistoryScreen] shows completed jobs only.
class _CompletedJobsPanelHeader extends StatelessWidget {
  const _CompletedJobsPanelHeader({required this.jobCount});

  final int jobCount;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF1B5E20),
            Color(0xFF2E7D32),
            Color(0xFF43A047),
          ],
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF2E7D32).withValues(alpha: 0.28),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.22),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(Icons.workspace_premium_rounded, color: Colors.white, size: 28),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  jobCount == 1 ? '1 job wrapped up' : '$jobCount jobs completed',
                  style: tt.titleLarge?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.3,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Tap a job for details, your agreed price, and to rate the worker.',
                  style: tt.bodySmall?.copyWith(
                    color: Colors.white.withValues(alpha: 0.9),
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CompletedJobPanelCard extends StatelessWidget {
  const _CompletedJobPanelCard({
    required this.job,
    required this.onTap,
  });

  final Map<String, dynamic> job;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final title = job['title'] as String? ?? 'Job';
    final worker = job['worker'] as Map<String, dynamic>?;
    final workerName = worker?['name'] as String?;
    final ghs = _ghsFromPesewasNum(job['agreedPricePesewas']);
    String? completedLabel;
    final rawCompleted = job['completedAt'];
    if (rawCompleted is String && rawCompleted.isNotEmpty) {
      try {
        completedLabel = DateFormat('d MMM yyyy').format(DateTime.parse(rawCompleted).toLocal());
      } catch (_) {}
    }

    return Material(
      color: cs.surface,
      elevation: 2,
      shadowColor: cs.shadow.withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
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
                cs.secondaryContainer.withValues(alpha: 0.22),
              ],
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        cs.secondary.withValues(alpha: 0.35),
                        cs.secondary.withValues(alpha: 0.12),
                      ],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: cs.secondary.withValues(alpha: 0.2),
                        blurRadius: 8,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: Icon(Icons.task_alt_rounded, color: cs.secondary, size: 26),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.2),
                      ),
                      if (workerName != null && workerName.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Icon(Icons.handyman_rounded, size: 15, color: cs.primary),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                workerName,
                                style: tt.bodySmall?.copyWith(
                                  color: cs.primary,
                                  fontWeight: FontWeight.w600,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ],
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: cs.secondaryContainer.withValues(alpha: 0.9),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              'Completed',
                              style: tt.labelMedium?.copyWith(
                                color: cs.onSecondaryContainer,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          if (ghs.isNotEmpty)
                            Text(ghs, style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                          if (completedLabel != null)
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.event_available_rounded, size: 15, color: cs.onSurfaceVariant),
                                const SizedBox(width: 4),
                                Text(
                                  completedLabel,
                                  style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                                ),
                              ],
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right_rounded, color: cs.outline),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CompletedJobsEmptyPanel extends ConsumerWidget {
  const _CompletedJobsEmptyPanel();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    cs.secondaryContainer.withValues(alpha: 0.95),
                    cs.surfaceContainerHighest,
                  ],
                ),
                boxShadow: [
                  BoxShadow(
                    color: cs.secondary.withValues(alpha: 0.2),
                    blurRadius: 22,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Icon(Icons.emoji_events_rounded, size: 48, color: cs.secondary),
            ),
            const SizedBox(height: 24),
            Text(
              'No completed jobs yet',
              textAlign: TextAlign.center,
              style: tt.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 12),
            Text(
              'When a job is finished and you confirm, it will show up here with the worker and amount — and you can leave a review.',
              textAlign: TextAlign.center,
              style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant, height: 1.45),
            ),
            const SizedBox(height: 28),
            FilledButton.icon(
              onPressed: () {
                ref.read(postJobProvider.notifier).reset();
                context.push('/post/category');
              },
              icon: const Icon(Icons.add_rounded),
              label: const Text('Post a job'),
            ),
          ],
        ),
      ),
    );
  }
}

class HomeNotificationIcon extends ConsumerStatefulWidget {
  const HomeNotificationIcon({super.key});

  @override
  ConsumerState<HomeNotificationIcon> createState() => _HomeNotificationIconState();
}

class _HomeNotificationIconState extends ConsumerState<HomeNotificationIcon> {
  int _unread = 0;
  StreamSubscription<void>? _notifSocketSub;

  @override
  void initState() {
    super.initState();
    _notifSocketSub = ref.read(realtimeClientProvider).onNotificationsUpdated.listen((_) {
      if (mounted) _refresh();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await ref.read(realtimeClientProvider).connect();
      if (mounted) await _refresh();
    });
  }

  @override
  void dispose() {
    _notifSocketSub?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    try {
      final list = await ref.read(apiClientProvider).listNotifications();
      if (!mounted) return;
      final n = list.where((x) => x['isRead'] != true).length;
      setState(() => _unread = n);
    } catch (_) {
      /* ignore */
    }
  }

  @override
  Widget build(BuildContext context) {
    final icon = _unread > 0
        ? Badge(
            label: Text(_unread > 9 ? '9+' : '$_unread'),
            backgroundColor: Theme.of(context).colorScheme.error,
            child: const Icon(Icons.notifications_outlined),
          )
        : const Icon(Icons.notifications_outlined);
    return IconButton(
      onPressed: () async {
        await context.push('/notifications');
        if (mounted) await _refresh();
      },
      icon: icon,
      tooltip: 'Notifications',
    );
  }
}

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  int _activeCount = 0;
  int _completedCount = 0;
  int _pendingPayCount = 0;
  bool _loadingCounts = true;
  StreamSubscription<void>? _rtJobs;

  @override
  void initState() {
    super.initState();
    _loadCounts();
    _rtJobs = ref.read(realtimeClientProvider).onMyJobsChanged.listen((_) {
      if (mounted) _loadCounts();
    });
  }

  @override
  void dispose() {
    _rtJobs?.cancel();
    super.dispose();
  }

  Future<void> _loadCounts() async {
    setState(() => _loadingCounts = true);
    try {
      final jobs = await ref.read(apiClientProvider).listMyJobs();
      if (!mounted) return;
      var active = 0, completed = 0, pay = 0;
      for (final e in jobs) {
        final j = e as Map<String, dynamic>;
        final s = j['status'] as String? ?? '';
        if (s == 'ACCEPTED' || s == 'IN_PROGRESS') {
          active++;
          if (_jobNeedsPayment(j)) pay++;
        }
        if (s == 'COMPLETED') completed++;
      }
      setState(() {
        _activeCount = active;
        _completedCount = completed;
        _pendingPayCount = pay;
        _loadingCounts = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() => _loadingCounts = false);
      }
    }
  }

  String _activeSubtitle() {
    if (_loadingCounts) return 'Loading…';
    if (_activeCount == 0) {
      return 'No accepted jobs yet — post or open quotes from job history.';
    }
    if (_pendingPayCount > 0) {
      return _pendingPayCount == 1
          ? '1 job needs payment to unlock chat · $_activeCount active total'
          : '$_pendingPayCount jobs need payment · $_activeCount active total';
    }
    return 'Accepted & in progress — chat and mark complete';
  }

  String _completedSubtitle() {
    if (_loadingCounts) return 'Loading…';
    if (_completedCount == 0) return 'None yet — finished work shows here';
    if (_completedCount == 1) return '1 job in your history';
    return '$_completedCount jobs finished';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Scaffold(
      backgroundColor: cs.surfaceContainerLowest,
      body: CustomScrollView(
        slivers: [
          SliverAppBar.large(
            pinned: true,
            title: const Text('RidDev'),
            actions: [
              const HomeNotificationIcon(),
              IconButton(
                onPressed: () => context.push('/profile'),
                icon: const Icon(Icons.person_rounded),
              ),
            ],
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Material(
                color: Colors.transparent,
                elevation: 8,
                shadowColor: cs.primary.withValues(alpha: 0.32),
                borderRadius: BorderRadius.circular(22),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(22),
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Positioned.fill(
                        child: DecoratedBox(
                          decoration: const BoxDecoration(gradient: AppGradients.hero),
                        ),
                      ),
                      Positioned(
                        right: -32,
                        top: -28,
                        child: Icon(Icons.blur_on_rounded, size: 140, color: Colors.white.withValues(alpha: 0.1)),
                      ),
                      Positioned(
                        left: -20,
                        bottom: -24,
                        child: Icon(Icons.blur_circular_rounded, size: 96, color: Colors.white.withValues(alpha: 0.08)),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 22, 20, 20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'What do you need done?',
                                        style: tt.headlineSmall?.copyWith(
                                          color: Colors.white,
                                          fontWeight: FontWeight.w800,
                                          letterSpacing: -0.4,
                                        ),
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        'Accra & nearby · Trusted workers · GHS',
                                        style: tt.bodyMedium?.copyWith(
                                          color: Colors.white.withValues(alpha: 0.9),
                                          height: 1.35,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                if (!_loadingCounts && _pendingPayCount > 0)
                                  Container(
                                    margin: const EdgeInsets.only(left: 8),
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                    decoration: BoxDecoration(
                                      color: Colors.black.withValues(alpha: 0.22),
                                      borderRadius: BorderRadius.circular(20),
                                      border: Border.all(color: Colors.white24),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(Icons.payments_rounded, size: 16, color: Colors.amber.shade200),
                                        const SizedBox(width: 6),
                                        Text(
                                          '$_pendingPayCount pay',
                                          style: tt.labelLarge?.copyWith(
                                            color: Colors.white,
                                            fontWeight: FontWeight.w800,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 18),
                            Material(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(16),
                              elevation: 4,
                              shadowColor: Colors.black26,
                              child: InkWell(
                                borderRadius: BorderRadius.circular(16),
                                onTap: () {
                                  ref.read(postJobProvider.notifier).reset();
                                  context.push('/post/category');
                                },
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                                  child: Row(
                                    children: [
                                      Icon(Icons.search_rounded, color: cs.primary, size: 26),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Text(
                                          'Browse categories — post a job in a tap',
                                          style: tt.bodyMedium?.copyWith(
                                            color: cs.onSurfaceVariant,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ),
                                      Icon(Icons.arrow_forward_rounded, color: cs.primary),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            sliver: SliverToBoxAdapter(
              child: _CustomerSectionLabel(icon: Icons.insights_rounded, title: 'At a glance'),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
            sliver: SliverToBoxAdapter(
              child: Row(
                children: [
                  Expanded(
                    child: _CustomerMetricCard(
                      icon: Icons.play_circle_outline_rounded,
                      label: 'Active work',
                      value: _loadingCounts ? '…' : '$_activeCount',
                      color: cs.primary,
                      lightAccent: const Color(0xFFE3F2FD),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _CustomerMetricCard(
                      icon: Icons.task_alt_rounded,
                      label: 'Completed',
                      value: _loadingCounts ? '…' : '$_completedCount',
                      color: cs.secondary,
                      lightAccent: const Color(0xFFE8F5E9),
                    ),
                  ),
                ],
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 18, 16, 0),
            sliver: SliverToBoxAdapter(
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: cs.primaryContainer.withValues(alpha: 0.65),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(Icons.grid_view_rounded, size: 20, color: cs.onPrimaryContainer),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Categories',
                      style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.3),
                    ),
                  ),
                  Text(
                    'Near Accra',
                    style: tt.labelLarge?.copyWith(color: cs.primary, fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
            sliver: SliverGrid(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                // Slightly shorter ratio = taller cells; avoids ~1px bottom overflow from 2-line labels + font metrics.
                childAspectRatio: 0.86,
              ),
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  final g = jobCategoryGroups[index];
                  return Material(
                    color: cs.surface,
                    elevation: 2,
                    shadowColor: cs.shadow.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(16),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(16),
                      onTap: () {
                        ref.read(postJobProvider.notifier).reset();
                        context.push('/post/category?group=${g.id}');
                      },
                      child: Padding(
                        padding: const EdgeInsets.all(10),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: g.accentColor.withValues(alpha: 0.14),
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: Icon(g.icon, color: g.accentColor, size: 26),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              g.title,
                              textAlign: TextAlign.center,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: tt.labelLarge?.copyWith(
                                fontWeight: FontWeight.w600,
                                fontSize: 12,
                                height: 1.15,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
                childCount: jobCategoryGroups.length,
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
            sliver: SliverToBoxAdapter(
              child: _CustomerSectionLabel(icon: Icons.folder_open_rounded, title: 'Your jobs'),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
            sliver: SliverToBoxAdapter(
              child: Column(
                children: [
                  _CustomerHomeActionCard(
                    title: 'Active jobs',
                    subtitle: _activeSubtitle(),
                    icon: Icons.work_history_rounded,
                    accent: cs.primary,
                    badge: (!_loadingCounts && _activeCount > 0) ? _activeCount : null,
                    onTap: () => context.push('/history?filter=active'),
                  ),
                  _CustomerHomeActionCard(
                    title: 'Completed jobs',
                    subtitle: _completedSubtitle(),
                    icon: Icons.task_alt_rounded,
                    accent: cs.secondary,
                    badge: (!_loadingCounts && _completedCount > 0) ? _completedCount : null,
                    onTap: () => context.push('/history?filter=completed'),
                  ),
                  _CustomerHomeActionCard(
                    title: 'Saved workers',
                    subtitle: 'Tradespeople you bookmarked',
                    icon: Icons.favorite_rounded,
                    accent: cs.tertiary,
                    onTap: () => context.push('/saved-workers'),
                  ),
                ],
              ),
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 88)),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          ref.read(postJobProvider.notifier).reset();
          context.push('/post/category');
        },
        icon: const Icon(Icons.add_rounded),
        label: const Text('Post a job'),
      ),
    );
  }
}

/// Section header (customer home).
class _CustomerSectionLabel extends StatelessWidget {
  const _CustomerSectionLabel({required this.icon, required this.title});

  final IconData icon;
  final String title;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12, top: 4),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: cs.primaryContainer.withValues(alpha: 0.65),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, size: 20, color: cs.onPrimaryContainer),
          ),
          const SizedBox(width: 12),
          Text(
            title,
            style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.3),
          ),
        ],
      ),
    );
  }
}

class _CustomerMetricCard extends StatelessWidget {
  const _CustomerMetricCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
    required this.lightAccent,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color color;
  final Color lightAccent;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Material(
      color: cs.surface,
      elevation: 2,
      shadowColor: cs.shadow.withValues(alpha: 0.14),
      borderRadius: BorderRadius.circular(18),
      child: Ink(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.35)),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              lightAccent.withValues(alpha: 0.5),
              cs.surface,
            ],
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(icon, color: color, size: 22),
              ),
              const SizedBox(height: 10),
              Text(
                label,
                style: tt.labelMedium?.copyWith(
                  color: cs.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                value,
                style: tt.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CustomerHomeActionCard extends StatelessWidget {
  const _CustomerHomeActionCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.accent,
    required this.onTap,
    this.badge,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Color accent;
  final VoidCallback onTap;
  final int? badge;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: cs.surface,
        elevation: 1.5,
        shadowColor: cs.shadow.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(18),
          child: Ink(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.45)),
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
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              child: Row(
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          accent.withValues(alpha: 0.32),
                          accent.withValues(alpha: 0.1),
                        ],
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: accent.withValues(alpha: 0.22),
                          blurRadius: 8,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: Icon(icon, color: accent, size: 26),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.2),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          subtitle,
                          style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant, height: 1.35),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  if (badge != null && badge! > 0)
                    Container(
                      margin: const EdgeInsets.only(right: 6),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: accent.withValues(alpha: 0.22),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        '${badge!}',
                        style: tt.labelLarge?.copyWith(
                          color: cs.onSurface,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  Icon(Icons.chevron_right_rounded, color: cs.outline),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  Map<String, dynamic>? _user;
  String? _error;
  bool _loading = true;
  int _unreadNotifications = 0;
  int _unreadDisputeMessages = 0;
  StreamSubscription<void>? _notifSocketSub;

  @override
  void initState() {
    super.initState();
    _notifSocketSub = ref.read(realtimeClientProvider).onNotificationsUpdated.listen((_) {
      if (mounted) _load();
    });
    _load();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await ref.read(realtimeClientProvider).connect();
    });
  }

  @override
  void dispose() {
    _notifSocketSub?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final api = ref.read(apiClientProvider);
    try {
      final data = await api.getCurrentUser();
      var unreadN = 0;
      var unreadD = 0;
      try {
        final notifs = await api.listNotifications();
        unreadN = unreadNotificationCount(notifs);
        unreadD = totalUnreadDisputeMessages(notifs);
      } catch (_) {}
      if (!mounted) return;
      setState(() {
        _user = data;
        _unreadNotifications = unreadN;
        _unreadDisputeMessages = unreadD;
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

  Future<void> _logout() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Log out'),
        content: const Text('You will need to sign in again.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Log out')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await ref.read(apiClientProvider).clearToken();
    ref.read(realtimeClientProvider).disconnect();
    if (!mounted) return;
    context.go('/login');
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final name = _user?['name'] as String? ?? '—';
    final phone = _user?['phone'] as String? ?? '—';
    final email = _user?['email'] as String? ?? '—';
    final role = _user?['role'] as String? ?? 'CUSTOMER';
    final roleLabel = role == 'CUSTOMER' ? 'Customer' : role;
    final photo = _user?['profilePhoto'] as String?;

    return Scaffold(
      backgroundColor: cs.surfaceContainerLowest,
      appBar: AppBar(
        title: const Text('Profile'),
        actions: [
          IconButton(
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: _loading
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 18),
                  Text('Loading profile…', style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
                ],
              ),
            )
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.cloud_off_rounded, size: 52, color: cs.outline),
                        const SizedBox(height: 16),
                        Text(_error!, textAlign: TextAlign.center),
                        const SizedBox(height: 16),
                        FilledButton(onPressed: _load, child: const Text('Retry')),
                        const SizedBox(height: 12),
                        TextButton(onPressed: _logout, child: const Text('Log out')),
                      ],
                    ),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
                    children: [
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.fromLTRB(22, 26, 22, 26),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(24),
                          gradient: AppGradients.hero,
                          boxShadow: [
                            BoxShadow(
                              color: cs.primary.withValues(alpha: 0.28),
                              blurRadius: 18,
                              offset: const Offset(0, 10),
                            ),
                          ],
                        ),
                        child: Column(
                          children: [
                            CircleAvatar(
                              radius: 52,
                              backgroundColor: Colors.white.withValues(alpha: 0.25),
                              child: CircleAvatar(
                                radius: 46,
                                backgroundColor: Colors.white,
                                backgroundImage:
                                    (photo != null && photo.isNotEmpty) ? NetworkImage(photo) : null,
                                child: (photo == null || photo.isEmpty)
                                    ? Text(
                                        _profileInitials(name == '—' ? null : name),
                                        style: tt.headlineMedium?.copyWith(
                                          color: cs.primary,
                                          fontWeight: FontWeight.w800,
                                        ),
                                      )
                                    : null,
                              ),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              name,
                              textAlign: TextAlign.center,
                              style: tt.headlineSmall?.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.3,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                roleLabel,
                                style: tt.labelLarge?.copyWith(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'Your account info and app shortcuts',
                              textAlign: TextAlign.center,
                              style: tt.bodySmall?.copyWith(
                                color: Colors.white.withValues(alpha: 0.9),
                                height: 1.35,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                      Text(
                        'Contact',
                        style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 10),
                      _CustomerProfileInfoCard(
                        rows: [
                          _CustomerProfileInfoRow(
                            icon: Icons.badge_outlined,
                            label: 'Name',
                            value: name,
                          ),
                          _CustomerProfileInfoRow(
                            icon: Icons.email_outlined,
                            label: 'Email',
                            value: email,
                          ),
                          _CustomerProfileInfoRow(
                            icon: Icons.phone_outlined,
                            label: 'Phone',
                            value: phone,
                          ),
                        ],
                      ),
                      const SizedBox(height: 22),
                      Text(
                        'Shortcuts',
                        style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 10),
                      _CustomerProfileLinkTile(
                        icon: Icons.account_balance_wallet_outlined,
                        iconBg: cs.primaryContainer,
                        iconFg: cs.primary,
                        title: 'Wallet',
                        subtitle: 'Balance, top-up, escrow',
                        onTap: () => context.push('/wallet'),
                      ),
                      const SizedBox(height: 10),
                      _CustomerProfileLinkTile(
                        icon: Icons.notifications_outlined,
                        iconBg: cs.secondaryContainer,
                        iconFg: cs.secondary,
                        title: 'Notifications',
                        subtitle: 'Alerts & updates',
                        badgeCount: _unreadNotifications,
                        onTap: () async {
                          await context.push('/notifications');
                          if (mounted) await _load();
                        },
                      ),
                      const SizedBox(height: 10),
                      _CustomerProfileLinkTile(
                        icon: Icons.gavel_rounded,
                        iconBg: cs.tertiaryContainer,
                        iconFg: cs.tertiary,
                        title: 'Disputes',
                        subtitle: 'List, chat with support & open threads',
                        badgeCount: _unreadDisputeMessages,
                        onTap: () async {
                          await context.push('/disputes');
                          if (mounted) await _load();
                        },
                      ),
                      const SizedBox(height: 10),
                      _CustomerProfileLinkTile(
                        icon: Icons.settings_outlined,
                        iconBg: cs.surfaceContainerHighest,
                        iconFg: cs.onSurfaceVariant,
                        title: 'Settings',
                        subtitle: 'App preferences',
                        onTap: () => context.push('/settings'),
                      ),
                      const SizedBox(height: 20),
                      Material(
                        color: cs.errorContainer.withValues(alpha: 0.45),
                        borderRadius: BorderRadius.circular(16),
                        child: InkWell(
                          onTap: _logout,
                          borderRadius: BorderRadius.circular(16),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
                            child: Row(
                              children: [
                                Icon(Icons.logout_rounded, color: cs.error),
                                const SizedBox(width: 14),
                                Text(
                                  'Log out',
                                  style: tt.titleSmall?.copyWith(
                                    color: cs.error,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                const Spacer(),
                                Icon(Icons.chevron_right_rounded, color: cs.error.withValues(alpha: 0.7)),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
    );
  }
}

class _CustomerProfileInfoRow {
  const _CustomerProfileInfoRow({
    required this.icon,
    required this.label,
    required this.value,
  });
  final IconData icon;
  final String label;
  final String value;
}

class _CustomerProfileInfoCard extends StatelessWidget {
  const _CustomerProfileInfoCard({required this.rows});

  final List<_CustomerProfileInfoRow> rows;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Material(
      color: cs.surface,
      elevation: 2,
      shadowColor: cs.shadow.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(18),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Column(
          children: [
            for (var i = 0; i < rows.length; i++) ...[
              if (i > 0) Divider(height: 1, indent: 56, color: cs.outlineVariant.withValues(alpha: 0.6)),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(rows[i].icon, color: cs.primary, size: 22),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            rows[i].label,
                            style: tt.labelMedium?.copyWith(color: cs.onSurfaceVariant),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            rows[i].value,
                            style: tt.bodyLarge?.copyWith(fontWeight: FontWeight.w600, height: 1.25),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _CustomerProfileLinkTile extends StatelessWidget {
  const _CustomerProfileLinkTile({
    required this.icon,
    required this.iconBg,
    required this.iconFg,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.badgeCount,
  });

  final IconData icon;
  final Color iconBg;
  final Color iconFg;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  /// In-app unread count (e.g. notifications or dispute messages).
  final int? badgeCount;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Material(
      color: cs.surface,
      elevation: 1,
      shadowColor: cs.shadow.withValues(alpha: 0.06),
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(11),
                decoration: BoxDecoration(
                  color: iconBg.withValues(alpha: 0.95),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: iconFg, size: 24),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant, height: 1.3),
                    ),
                  ],
                ),
              ),
              if (badgeCount != null && badgeCount! > 0)
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: Badge(
                    label: Text(badgeCount! > 9 ? '9+' : '${badgeCount!}'),
                    backgroundColor: cs.error,
                  ),
                ),
              Icon(Icons.chevron_right_rounded, color: cs.outline),
            ],
          ),
        ),
      ),
    );
  }
}

class SavedWorkersScreen extends StatelessWidget {
  const SavedWorkersScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Saved workers')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.favorite_border_rounded, size: 64, color: Theme.of(context).colorScheme.outline),
              const SizedBox(height: 16),
              Text('No saved workers yet', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              Text(
                'Favourite great workers after a job to find them faster next time.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class NotificationsScreen extends ConsumerStatefulWidget {
  const NotificationsScreen({super.key});

  @override
  ConsumerState<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends ConsumerState<NotificationsScreen> {
  List<Map<String, dynamic>> _items = [];
  bool _loading = true;
  String? _error;
  StreamSubscription<void>? _notifSocketSub;

  @override
  void initState() {
    super.initState();
    _notifSocketSub = ref.read(realtimeClientProvider).onNotificationsUpdated.listen((_) {
      if (mounted) _load(showLoading: false);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await ref.read(realtimeClientProvider).connect();
    });
    _load();
  }

  @override
  void dispose() {
    _notifSocketSub?.cancel();
    super.dispose();
  }

  Future<void> _load({bool showLoading = true}) async {
    if (showLoading) {
      setState(() {
        _loading = true;
        _error = null;
      });
    } else if (mounted) {
      setState(() => _error = null);
    }
    try {
      final list = await ref.read(apiClientProvider).listNotifications();
      if (!mounted) return;
      setState(() {
        _items = list;
        _loading = false;
      });
      try {
        await ref.read(apiClientProvider).markNotificationsRead();
      } catch (_) {}
    } on DioException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = messageFromDio(e);
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications'),
        actions: [
          IconButton(onPressed: _loading ? null : _load, icon: const Icon(Icons.refresh_rounded)),
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
                        FilledButton(onPressed: _load, child: const Text('Retry')),
                      ],
                    ),
                  ),
                )
              : _items.isEmpty
                  ? Center(
                      child: Text(
                        'No notifications',
                        style: TextStyle(color: cs.onSurfaceVariant),
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.all(16),
                      itemCount: _items.length,
                      separatorBuilder: (context, i) => const Divider(height: 1),
                      itemBuilder: (context, i) {
                        final n = _items[i];
                        final title = n['title'] as String? ?? 'Notice';
                        final body = n['body'] as String? ?? '';
                        final read = n['isRead'] == true;
                        final data = n['data'];
                        String? disputeId;
                        String? jobId;
                        if (data is Map) {
                          if (data['disputeId'] is String) disputeId = data['disputeId'] as String;
                          if (data['jobId'] is String) jobId = data['jobId'] as String;
                        }
                        final tappable = disputeId != null || jobId != null;
                        return ListTile(
                          title: Text(title, style: TextStyle(fontWeight: read ? FontWeight.normal : FontWeight.w600)),
                          subtitle: Text(body),
                          trailing: tappable ? const Icon(Icons.chevron_right_rounded) : null,
                          onTap: !tappable
                              ? null
                              : () {
                                  if (disputeId != null) {
                                    context.push('/dispute-thread/$disputeId');
                                  } else if (jobId != null) {
                                    context.push('/history/$jobId');
                                  }
                                },
                        );
                      },
                    ),
    );
  }
}

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  final _apiUrl = TextEditingController();
  bool _loadingPrefs = true;

  @override
  void initState() {
    super.initState();
    _loadApiOverride();
  }

  Future<void> _loadApiOverride() async {
    final v = await getCustomerApiBaseUrlOverride();
    if (!mounted) return;
    if (v != null && v.isNotEmpty) _apiUrl.text = v;
    setState(() => _loadingPrefs = false);
  }

  @override
  void dispose() {
    _apiUrl.dispose();
    super.dispose();
  }

  Future<void> _saveApiUrl() async {
    setState(() => _loadingPrefs = true);
    final raw = _apiUrl.text.trim();
    await saveCustomerApiBaseUrlOverride(raw.isEmpty ? null : raw);
    await ref.read(realtimeClientProvider).reconnect();
    if (!mounted) return;
    setState(() => _loadingPrefs = false);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('API address saved. Pull to refresh on job lists.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('API server', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Text(
            'If Active jobs or lists show “Cannot reach the API”, your phone cannot reach the backend. '
            'On a real device, enter your computer\'s LAN address (same Wi‑Fi), e.g. http://192.168.1.50:4000. '
            'Leave blank to use the app default (Android emulator: http://10.0.2.2:4000).',
            style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13, height: 1.35),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _apiUrl,
            enabled: !_loadingPrefs,
            keyboardType: TextInputType.url,
            autocorrect: false,
            decoration: const InputDecoration(
              labelText: 'API server URL',
              hintText: 'http://192.168.1.50:4000',
              border: OutlineInputBorder(),
              helperText: 'No trailing /api',
            ),
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: _loadingPrefs ? null : _saveApiUrl,
            child: const Text('Save API address'),
          ),
          const SizedBox(height: 24),
          ListTile(
            leading: const Icon(Icons.language),
            title: const Text('Language'),
            subtitle: const Text('English'),
          ),
          ListTile(
            leading: const Icon(Icons.schedule),
            title: const Text('Time zone'),
            subtitle: const Text('Africa/Accra (GMT+0)'),
          ),
        ],
      ),
    );
  }
}

class JobHistoryScreen extends ConsumerStatefulWidget {
  const JobHistoryScreen({
    super.key,
    this.activeOnly = false,
    this.completedOnly = false,
  });

  /// When true (home → Active jobs), list only accepted / in-progress jobs.
  final bool activeOnly;

  /// When true (home → Completed jobs), list only jobs with status COMPLETED.
  final bool completedOnly;

  @override
  ConsumerState<JobHistoryScreen> createState() => _JobHistoryScreenState();
}

class _JobHistoryScreenState extends ConsumerState<JobHistoryScreen> {
  List<dynamic> _jobs = [];
  String? _error;
  bool _loading = true;
  bool _pendingSnackShown = false;
  StreamSubscription<void>? _rtSub;

  @override
  void initState() {
    super.initState();
    _load();
    _rtSub = ref.read(realtimeClientProvider).onMyJobsChanged.listen((_) {
      if (mounted) _load();
    });
  }

  @override
  void dispose() {
    _rtSub?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final jobs = await ref.read(apiClientProvider).listMyJobs();
      if (!mounted) return;
      setState(() {
        _jobs = jobs;
        _loading = false;
      });
      if (widget.activeOnly && mounted && !_pendingSnackShown) {
        final pc =
            jobs.where((x) => _jobNeedsPayment(x as Map<String, dynamic>)).length;
        if (pc > 0) {
          _pendingSnackShown = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  pc == 1
                      ? '1 job is waiting for payment. Open it below and tap Complete payment.'
                      : '$pc jobs are waiting for payment. Complete checkout to unlock chat with your worker.',
                ),
                duration: const Duration(seconds: 6),
              ),
            );
          });
        }
      }
    } on DioException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = messageFromDio(e);
        _loading = false;
      });
    }
  }

  void _openJob(BuildContext context, Map<String, dynamic> j) {
    final id = j['id'] as String? ?? '';
    final status = j['status'] as String? ?? '';
    switch (status) {
      case 'OPEN':
      case 'QUOTED':
        context.push('/jobs/$id/quotes');
        break;
      case 'ACCEPTED':
      case 'IN_PROGRESS':
        context.push('/history/$id');
        break;
      case 'COMPLETED':
      case 'DISPUTED':
      case 'CANCELLED':
        context.push('/history/$id');
        break;
      default:
        context.push('/jobs/$id/quotes');
    }
  }

  List<dynamic> get _displayJobs {
    if (widget.completedOnly) {
      return _jobs.where((j) {
        final s = (j as Map)['status'] as String? ?? '';
        return s == 'COMPLETED';
      }).toList();
    }
    if (!widget.activeOnly) return _jobs;
    return _jobs.where((j) {
      final s = (j as Map)['status'] as String? ?? '';
      return s == 'ACCEPTED' || s == 'IN_PROGRESS';
    }).toList();
  }

  String get _historyTitle {
    if (widget.completedOnly) return 'Completed jobs';
    if (widget.activeOnly) return 'Active jobs';
    return 'Job history';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final jobs = _displayJobs;
    final pendingCount = widget.activeOnly
        ? jobs.where((x) => _jobNeedsPayment(x as Map<String, dynamic>)).length
        : 0;
    final showPendingBanner = widget.activeOnly && pendingCount > 0;
    return Scaffold(
      backgroundColor: (widget.activeOnly || widget.completedOnly) ? cs.surfaceContainerLowest : null,
      appBar: AppBar(
        title: Text(_historyTitle),
        actions: [
          IconButton(
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: _loading
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 18),
                  Text(
                    'Loading jobs…',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                ],
              ),
            )
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.cloud_off_rounded, size: 52, color: cs.outline),
                        const SizedBox(height: 16),
                        Text(_error!, textAlign: TextAlign.center),
                        const SizedBox(height: 16),
                        FilledButton(onPressed: _load, child: const Text('Retry')),
                      ],
                    ),
                  ),
                )
              : widget.activeOnly
                  ? jobs.isEmpty
                      ? const _ActiveJobsEmptyPanel()
                      : RefreshIndicator(
                          onRefresh: _load,
                          child: ListView(
                            padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
                            children: [
                              _ActiveJobsPanelHeader(
                                jobCount: jobs.length,
                                awaitingPaymentCount: pendingCount,
                              ),
                              const SizedBox(height: 14),
                              if (showPendingBanner) ...[
                                _ActiveJobsPaymentRow(pendingCount: pendingCount),
                                const SizedBox(height: 14),
                              ],
                              ...jobs.map((e) {
                                final j = e as Map<String, dynamic>;
                                return Padding(
                                  padding: const EdgeInsets.only(bottom: 12),
                                  child: _ActiveJobPanelCard(
                                    job: j,
                                    onTap: () => _openJob(context, j),
                                  ),
                                );
                              }),
                            ],
                          ),
                        )
                  : widget.completedOnly
                      ? jobs.isEmpty
                          ? const _CompletedJobsEmptyPanel()
                          : RefreshIndicator(
                              onRefresh: _load,
                              child: ListView(
                                padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
                                children: [
                                  _CompletedJobsPanelHeader(jobCount: jobs.length),
                                  const SizedBox(height: 14),
                                  ...jobs.map((e) {
                                    final j = e as Map<String, dynamic>;
                                    return Padding(
                                      padding: const EdgeInsets.only(bottom: 12),
                                      child: _CompletedJobPanelCard(
                                        job: j,
                                        onTap: () => _openJob(context, j),
                                      ),
                                    );
                                  }),
                                ],
                              ),
                            )
                      : jobs.isEmpty
                          ? Center(
                              child: Padding(
                                padding: const EdgeInsets.all(24),
                                child: Text(
                                  'No jobs yet. Post a job from the home screen.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                                ),
                              ),
                            )
                          : RefreshIndicator(
                              onRefresh: _load,
                              child: ListView.builder(
                                padding: const EdgeInsets.symmetric(vertical: 8),
                                itemCount: jobs.length,
                                itemBuilder: (context, i) {
                                  final j = jobs[i] as Map<String, dynamic>;
                                  final title = j['title'] as String? ?? 'Job';
                                  final pendingPay = _jobNeedsPayment(j);
                                  return ListTile(
                                    leading: CircleAvatar(
                                      backgroundColor: pendingPay
                                          ? const Color(0xFFFFE0B2)
                                          : cs.primaryContainer,
                                      child: Icon(
                                        Icons.construction,
                                        color: pendingPay
                                            ? const Color(0xFFB71C00)
                                            : cs.onPrimaryContainer,
                                      ),
                                    ),
                                    title: Text(title),
                                    isThreeLine: true,
                                    subtitle: Text(
                                      _jobHistorySubtitle(j),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    trailing: const Icon(Icons.chevron_right_rounded),
                                    onTap: () => _openJob(context, j),
                                  );
                                },
                              ),
                            ),
    );
  }
}

class _JobDetailSectionCard extends StatelessWidget {
  const _JobDetailSectionCard({
    required this.child,
    this.title,
    this.leading,
    this.subtle = false,
  });

  final Widget child;
  final String? title;
  final Widget? leading;
  final bool subtle;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Material(
      color: cs.surface,
      elevation: subtle ? 0.5 : 2,
      shadowColor: cs.shadow.withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(18),
      child: Ink(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.38)),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              cs.surface,
              cs.surfaceContainerHighest.withValues(alpha: subtle ? 0.12 : 0.28),
            ],
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (title != null) ...[
                Row(
                  children: [
                    if (leading != null) ...[
                      leading!,
                      const SizedBox(width: 10),
                    ],
                    Expanded(
                      child: Text(
                        title!,
                        style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.2),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
              ],
              child,
            ],
          ),
        ),
      ),
    );
  }
}

class _JobDetailHero extends StatelessWidget {
  const _JobDetailHero({
    required this.title,
    required this.statusLabel,
    required this.escrowHeld,
    required this.needsPayment,
    this.completed = false,
  });

  final String title;
  final String statusLabel;
  final bool escrowHeld;
  final bool needsPayment;
  final bool completed;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: Stack(
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: completed
                    ? LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          cs.secondaryContainer.withValues(alpha: 0.85),
                          cs.surface,
                        ],
                      )
                    : needsPayment
                        ? LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              cs.errorContainer.withValues(alpha: 0.75),
                              cs.surface,
                            ],
                          )
                        : AppGradients.hero,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 20, 18, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: tt.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.4,
                    color: needsPayment || completed ? cs.onSurface : Colors.white,
                    height: 1.25,
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _DetailChip(
                      label: statusLabel,
                      foreground: needsPayment || completed ? cs.onSurface : Colors.white,
                      background: needsPayment || completed
                          ? cs.surface.withValues(alpha: 0.7)
                          : Colors.black.withValues(alpha: 0.2),
                    ),
                    if (escrowHeld)
                      _DetailChip(
                        label: 'Escrow active',
                        foreground: needsPayment || completed ? cs.tertiary : Colors.white,
                        background: (needsPayment || completed ? cs.tertiaryContainer : Colors.white24).withValues(alpha: 0.9),
                      ),
                    if (needsPayment)
                      _DetailChip(
                        label: 'Payment due',
                        foreground: cs.onErrorContainer,
                        background: cs.errorContainer.withValues(alpha: 0.9),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DetailChip extends StatelessWidget {
  const _DetailChip({
    required this.label,
    required this.foreground,
    required this.background,
  });

  final String label;
  final Color foreground;
  final Color background;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: foreground,
              fontWeight: FontWeight.w700,
            ),
      ),
    );
  }
}

class JobDetailHistoryScreen extends ConsumerStatefulWidget {
  const JobDetailHistoryScreen({required this.jobId, super.key});
  final String jobId;

  @override
  ConsumerState<JobDetailHistoryScreen> createState() => _JobDetailHistoryScreenState();
}

class _JobDetailHistoryScreenState extends ConsumerState<JobDetailHistoryScreen> {
  Map<String, dynamic>? _job;
  String? _error;
  bool _loading = true;
  StreamSubscription<Map<String, dynamic>>? _jobEvSub;
  StreamSubscription<void>? _meJobsSub;

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
      _meJobsSub = rt.onMyJobsChanged.listen((_) {
        if (mounted) _load();
      });
    });
  }

  @override
  void dispose() {
    _jobEvSub?.cancel();
    _meJobsSub?.cancel();
    ref.read(realtimeClientProvider).leaveJob(widget.jobId);
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await ref.read(apiClientProvider).getJob(widget.jobId);
      if (!mounted) return;
      setState(() {
        _job = data;
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

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final appTitle = _loading ? 'Job' : (_job?['title'] as String? ?? 'Job');

    return Scaffold(
      backgroundColor: cs.surfaceContainerLowest,
      appBar: AppBar(
        title: Text(
          appTitle.length > 28 ? '${appTitle.substring(0, 25)}…' : appTitle,
        ),
        actions: [
          IconButton(
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: _error != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.cloud_off_rounded, size: 56, color: cs.outline),
                    const SizedBox(height: 16),
                    Text(_error!, textAlign: TextAlign.center, style: tt.bodyLarge),
                    const SizedBox(height: 20),
                    FilledButton(onPressed: _load, child: const Text('Retry')),
                  ],
                ),
              ),
            )
          : _loading
              ? ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Container(
                      height: 120,
                      decoration: BoxDecoration(
                        color: cs.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(20),
                      ),
                    ),
                    const SizedBox(height: 20),
                    const Center(child: CircularProgressIndicator()),
                    const SizedBox(height: 20),
                    Text(
                      'Loading job…',
                      textAlign: TextAlign.center,
                      style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
                    ),
                  ],
                )
              : _job == null
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.search_off_rounded, size: 56, color: cs.outline),
                          const SizedBox(height: 16),
                          Text('Job not found', style: tt.titleMedium),
                        ],
                      ),
                    )
                  : Builder(
                      builder: (context) {
                        final j = _job!;
                        final title = j['title'] as String? ?? 'Job';
                        final status = j['status'] as String? ?? '';
                        final address = j['address'] as String? ?? '';
                        final desc = j['description'] as String? ?? '';
                        final worker = j['worker'] as Map<String, dynamic>?;
                        final workerName = worker?['name'] as String?;
                        final agreedGhs = _ghsFromPesewasNum(j['agreedPricePesewas']);
                        final acceptedQuote = j['acceptedQuote'] as Map<String, dynamic>?;
                        final breakdown = _quoteBreakdownMap(acceptedQuote?['breakdown']);
                        final quoteMessage = acceptedQuote?['message'] as String?;
                        final escrowHeld = j['escrowHeld'] == true;
                        final needsPayment = _jobNeedsPayment(j);
                        final workerRequested = j['workerRequestedCompletionAt'] != null;
                        final quoteAt = j['quoteAcceptedAt'];
                        String? quoteAtLabel;
                        if (quoteAt is String && quoteAt.isNotEmpty) {
                          try {
                            quoteAtLabel = DateFormat('d MMM yyyy · HH:mm')
                                .format(DateTime.parse(quoteAt).toLocal());
                          } catch (_) {}
                        }
                        final showAcceptedCard = acceptedQuote != null ||
                            agreedGhs.isNotEmpty ||
                            (workerName != null && workerName.isNotEmpty) ||
                            status == 'ACCEPTED' ||
                            status == 'IN_PROGRESS' ||
                            status == 'COMPLETED';
                        final statusPretty = status.replaceAll('_', ' ');
                        final isCompleted = status == 'COMPLETED';
                        final hasActions = status == 'ACCEPTED' ||
                            status == 'IN_PROGRESS' ||
                            status == 'OPEN' ||
                            status == 'QUOTED' ||
                            status == 'COMPLETED';

                        return ListView(
                          padding: const EdgeInsets.fromLTRB(12, 8, 12, 32),
                          children: [
                            Material(
                              color: Colors.transparent,
                              elevation: 5,
                              shadowColor: cs.primary.withValues(alpha: 0.22),
                              borderRadius: BorderRadius.circular(20),
                              child: _JobDetailHero(
                                title: title,
                                statusLabel: statusPretty,
                                escrowHeld: escrowHeld,
                                needsPayment: needsPayment &&
                                    (status == 'ACCEPTED' || status == 'IN_PROGRESS'),
                                completed: isCompleted,
                              ),
                            ),
                            const SizedBox(height: 16),
                            if (showAcceptedCard) ...[
                              _JobDetailSectionCard(
                                title: 'Accepted quote',
                                leading: Icon(Icons.request_quote_rounded, color: cs.primary, size: 22),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'You accepted this tradesperson\'s offer',
                                      style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                                    ),
                                    const SizedBox(height: 12),
                                    if (workerName != null && workerName.isNotEmpty) ...[
                                      Row(
                                        children: [
                                          CircleAvatar(
                                            radius: 20,
                                            backgroundColor: cs.primaryContainer,
                                            child: Icon(Icons.person_rounded, color: cs.onPrimaryContainer),
                                          ),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  'Your worker',
                                                  style: tt.labelMedium?.copyWith(color: cs.onSurfaceVariant),
                                                ),
                                                Text(
                                                  workerName,
                                                  style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 14),
                                    ],
                                    if (breakdown != null) ...[
                                      Text(
                                        'Price breakdown',
                                        style: tt.labelMedium?.copyWith(
                                          color: cs.onSurfaceVariant,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      _JobBreakdownRow(
                                        label: 'Labour',
                                        pesewas: breakdown['labour'] ?? 0,
                                        tt: tt,
                                        cs: cs,
                                      ),
                                      _JobBreakdownRow(
                                        label: 'Parts & materials',
                                        pesewas: breakdown['parts'] ?? 0,
                                        tt: tt,
                                        cs: cs,
                                      ),
                                      _JobBreakdownRow(
                                        label: 'Transportation',
                                        pesewas: breakdown['transport'] ?? 0,
                                        tt: tt,
                                        cs: cs,
                                      ),
                                      const SizedBox(height: 8),
                                    ] else if (acceptedQuote != null &&
                                        breakdown == null &&
                                        (status == 'ACCEPTED' ||
                                            status == 'IN_PROGRESS' ||
                                            status == 'COMPLETED')) ...[
                                      Text(
                                        'No labour / parts / transport breakdown was stored on this quote.',
                                        style: tt.bodySmall?.copyWith(
                                          color: cs.onSurfaceVariant,
                                          fontStyle: FontStyle.italic,
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                    ],
                                    if (agreedGhs.isNotEmpty)
                                      Container(
                                        width: double.infinity,
                                        margin: const EdgeInsets.only(top: 4),
                                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                                        decoration: BoxDecoration(
                                          color: cs.primaryContainer.withValues(alpha: 0.55),
                                          borderRadius: BorderRadius.circular(12),
                                        ),
                                        child: Row(
                                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                          children: [
                                            Text(
                                              'Total agreed',
                                              style: tt.labelLarge?.copyWith(
                                                color: cs.onPrimaryContainer,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                            Text(
                                              agreedGhs,
                                              style: tt.titleMedium?.copyWith(
                                                color: cs.primary,
                                                fontWeight: FontWeight.w800,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    if (quoteAtLabel != null) ...[
                                      const SizedBox(height: 10),
                                      Text(
                                        'Accepted · $quoteAtLabel',
                                        style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                                      ),
                                    ],
                                    if (quoteMessage != null && quoteMessage.trim().isNotEmpty) ...[
                                      const SizedBox(height: 12),
                                      Text(
                                        'Their note',
                                        style: tt.labelMedium?.copyWith(color: cs.onSurfaceVariant),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        quoteMessage.trim(),
                                        style: tt.bodyMedium?.copyWith(height: 1.4),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                              const SizedBox(height: 12),
                            ],
                            _JobDetailSectionCard(
                              title: 'Location',
                              leading: Icon(Icons.location_on_rounded, color: cs.error, size: 22),
                              child: Text(
                                address.isEmpty ? '—' : address,
                                style: tt.bodyLarge?.copyWith(height: 1.4, fontWeight: FontWeight.w500),
                              ),
                            ),
                            const SizedBox(height: 12),
                            _JobDetailSectionCard(
                              title: 'Job description',
                              leading: Icon(Icons.notes_rounded, color: cs.tertiary, size: 22),
                              subtle: true,
                              child: Text(
                                desc.isEmpty ? '—' : desc,
                                style: tt.bodyMedium?.copyWith(height: 1.45, color: cs.onSurfaceVariant),
                              ),
                            ),
                            const SizedBox(height: 20),
                            if (hasActions)
                              _JobDetailSectionCard(
                              title: 'Next steps',
                              leading: Icon(Icons.touch_app_rounded, color: cs.primary, size: 22),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  if (status == 'ACCEPTED' || status == 'IN_PROGRESS') ...[
                                    if (!escrowHeld) ...[
                                      Container(
                                        padding: const EdgeInsets.all(14),
                                        decoration: BoxDecoration(
                                          color: cs.errorContainer.withValues(alpha: 0.45),
                                          borderRadius: BorderRadius.circular(14),
                                          border: Border.all(color: cs.error.withValues(alpha: 0.25)),
                                        ),
                                        child: Row(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Icon(Icons.info_outline_rounded, color: cs.error, size: 22),
                                            const SizedBox(width: 10),
                                            Expanded(
                                              child: Text(
                                                'Complete payment to hold funds in escrow. Chat unlocks after checkout.',
                                                style: tt.bodySmall?.copyWith(
                                                  color: cs.onErrorContainer,
                                                  height: 1.4,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(height: 12),
                                      FilledButton.icon(
                                        style: FilledButton.styleFrom(
                                          padding: const EdgeInsets.symmetric(vertical: 14),
                                        ),
                                        onPressed: () => context.push('/payment/${widget.jobId}'),
                                        icon: const Icon(Icons.payments_rounded),
                                        label: const Text('Complete payment'),
                                      ),
                                      TextButton.icon(
                                        onPressed: _load,
                                        icon: const Icon(Icons.refresh_rounded, size: 18),
                                        label: const Text('I already paid — refresh'),
                                      ),
                                    ] else ...[
                                      FilledButton.icon(
                                        style: FilledButton.styleFrom(
                                          padding: const EdgeInsets.symmetric(vertical: 14),
                                        ),
                                        onPressed: () => context.push('/active-job/${widget.jobId}'),
                                        icon: const Icon(Icons.construction_rounded),
                                        label: const Text('Chat & track job'),
                                      ),
                                      const SizedBox(height: 10),
                                      Row(
                                        children: [
                                          Expanded(
                                            child: OutlinedButton.icon(
                                              onPressed: () => context.push('/chat/${widget.jobId}'),
                                              icon: const Icon(Icons.chat_rounded, size: 20),
                                              label: const Text('Chat only'),
                                            ),
                                          ),
                                          if (workerRequested) ...[
                                            const SizedBox(width: 10),
                                            Expanded(
                                              child: FilledButton.tonalIcon(
                                                onPressed: () =>
                                                    context.push('/job-complete/${widget.jobId}'),
                                                icon: const Icon(Icons.task_alt_rounded, size: 20),
                                                label: const Text('Confirm & release'),
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                      if (!workerRequested)
                                        Padding(
                                          padding: const EdgeInsets.only(top: 12),
                                          child: Text(
                                            'When your worker marks the job complete, confirm here to release payment.',
                                            style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                                          ),
                                        ),
                                    ],
                                  ],
                                  if (status == 'OPEN' || status == 'QUOTED') ...[
                                    FilledButton.icon(
                                      style: FilledButton.styleFrom(
                                        padding: const EdgeInsets.symmetric(vertical: 14),
                                      ),
                                      onPressed: () => context.push('/jobs/${widget.jobId}/quotes'),
                                      icon: const Icon(Icons.format_list_bulleted_rounded),
                                      label: const Text('View quotes'),
                                    ),
                                  ],
                                  if (status == 'COMPLETED')
                                    FilledButton.icon(
                                      style: FilledButton.styleFrom(
                                        padding: const EdgeInsets.symmetric(vertical: 14),
                                      ),
                                      onPressed: () => context.push('/review/${widget.jobId}'),
                                      icon: const Icon(Icons.star_rounded),
                                      label: const Text('Rate worker'),
                                    ),
                                ],
                              ),
                            ),
                          ],
                        );
                      },
                    ),
    );
  }
}
