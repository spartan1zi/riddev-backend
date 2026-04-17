import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../providers/auth_provider.dart';
import '../providers/realtime_provider.dart';
import '../core/api_client.dart';
import '../core/push_notifications.dart';
import '../core/api_url.dart';
import '../core/notification_utils.dart';
import '../widgets/app_gradients.dart';
import '../widgets/map_placeholder.dart';

class WorkerSplashScreen extends ConsumerStatefulWidget {
  const WorkerSplashScreen({super.key});

  @override
  ConsumerState<WorkerSplashScreen> createState() => _WorkerSplashScreenState();
}

class _WorkerSplashScreenState extends ConsumerState<WorkerSplashScreen> {
  bool _checkingSession = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _tryRestoreSession());
  }

  Future<void> _tryRestoreSession() async {
    final api = ref.read(apiClientProvider);
    final ok = await api.restoreSession();
    if (!mounted) return;
    if (ok) {
      await ref.read(realtimeClientProvider).connect();
      if (!mounted) return;
      context.go('/dashboard');
      unawaited(registerPushNotifications(api));
    } else {
      setState(() => _checkingSession = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(gradient: WorkerGradients.splash),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: Column(
              children: [
                const Spacer(flex: 2),
                Container(
                  padding: const EdgeInsets.all(26),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.14),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.25),
                        blurRadius: 28,
                        offset: const Offset(0, 14),
                      ),
                    ],
                  ),
                  child: Icon(Icons.engineering_rounded, size: 72, color: cs.onPrimary),
                ),
                const SizedBox(height: 28),
                Text(
                  'RidDev Worker',
                  style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                      ),
                ),
                const SizedBox(height: 10),
                Text(
                  'Get nearby jobs, send quotes, and get paid —\nall in GHS with escrow protection.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: Colors.white.withOpacity(0.92),
                        height: 1.45,
                      ),
                ),
                const Spacer(flex: 3),
                if (_checkingSession)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 32),
                    child: CircularProgressIndicator(color: Colors.white),
                  )
                else ...[
                  FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: cs.primary,
                      minimumSize: const Size.fromHeight(52),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                    onPressed: () => context.go('/dashboard'),
                    child: const Text('Get started'),
                  ),
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: () => context.go('/login'),
                    child: Text(
                      'Already have an account? Log in',
                      style: TextStyle(color: Colors.white.withOpacity(0.95)),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: () => context.go('/register'),
                    child: Text(
                      'New worker? Create an account',
                      style: TextStyle(color: Colors.white.withOpacity(0.85)),
                    ),
                  ),
                ],
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class WorkerLoginScreen extends ConsumerStatefulWidget {
  const WorkerLoginScreen({super.key});

  @override
  ConsumerState<WorkerLoginScreen> createState() => _WorkerLoginScreenState();
}

class _WorkerLoginScreenState extends ConsumerState<WorkerLoginScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final email = _email.text.trim().toLowerCase();
    final password = _password.text.trim();
    if (email.isEmpty || password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter your email and password.')),
      );
      return;
    }
    setState(() => _busy = true);
    final api = ref.read(apiClientProvider);
    try {
      final data = await api.login(email: email, password: password);
      final access = data['accessToken'] as String;
      final refresh = data['refreshToken'] as String?;
      if (refresh != null && refresh.isNotEmpty) {
        await api.saveSession(accessToken: access, refreshToken: refresh);
      } else {
        await api.saveToken(access);
      }
      await ref.read(realtimeClientProvider).connect();
      if (!mounted) return;
      context.go('/dashboard');
      unawaited(registerPushNotifications(api));
    } on DioException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(messageFromDio(e))),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 168,
            pinned: true,
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
                decoration: const BoxDecoration(gradient: WorkerGradients.hero),
                alignment: Alignment.bottomLeft,
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Worker login',
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(color: Colors.white),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Access your dashboard & quotes',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.white70),
                    ),
                  ],
                ),
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.all(24),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                TextField(
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  autocorrect: false,
                  decoration: const InputDecoration(
                    labelText: 'Email',
                    prefixIcon: Icon(Icons.email_outlined),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _password,
                  decoration: const InputDecoration(
                    labelText: 'Password',
                    prefixIcon: Icon(Icons.lock_outline_rounded),
                  ),
                  obscureText: true,
                ),
                const SizedBox(height: 28),
                FilledButton(
                  onPressed: _busy ? null : _submit,
                  child: _busy
                      ? const SizedBox(height: 22, width: 22, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('Log in'),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(child: Divider(color: cs.outlineVariant)),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Text('or', style: TextStyle(color: cs.onSurfaceVariant)),
                    ),
                    Expanded(child: Divider(color: cs.outlineVariant)),
                  ],
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: () {},
                  icon: const Icon(Icons.sms_outlined),
                  label: const Text('OTP with phone'),
                ),
                const SizedBox(height: 24),
                Center(
                  child: TextButton(
                    onPressed: () => context.go('/register'),
                    child: const Text('Create a worker account'),
                  ),
                ),
              ]),
            ),
          ),
        ],
      ),
    );
  }
}

class WorkerRegisterScreen extends ConsumerStatefulWidget {
  const WorkerRegisterScreen({super.key});

  @override
  ConsumerState<WorkerRegisterScreen> createState() => _WorkerRegisterScreenState();
}

class _WorkerRegisterScreenState extends ConsumerState<WorkerRegisterScreen> {
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _phone.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final name = _name.text.trim();
    final email = _email.text.trim();
    final phoneRaw = _phone.text.trim();
    final password = _password.text.trim();
    final phone = phoneRaw.replaceAll(RegExp(r'[\s\-.]'), '');
    if (name.isEmpty || email.isEmpty || phoneRaw.isEmpty || password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Fill in all fields.')),
      );
      return;
    }
    if (name.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Name must be at least 2 characters.')),
      );
      return;
    }
    if (password.length < 8) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Password must be at least 8 characters.')),
      );
      return;
    }
    if (phone.length < 10) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Phone must be at least 10 digits. Example: 0241234567 or +233241234567',
          ),
        ),
      );
      return;
    }
    if (!email.contains('@')) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a valid email address.')),
      );
      return;
    }
    setState(() => _busy = true);
    final api = ref.read(apiClientProvider);
    try {
      final data = await api.register(
        name: name,
        email: email,
        phone: phone,
        password: password,
        role: 'WORKER',
      );
      final access = data['accessToken'] as String;
      final refresh = data['refreshToken'] as String?;
      if (refresh != null && refresh.isNotEmpty) {
        await api.saveSession(accessToken: access, refreshToken: refresh);
      } else {
        await api.saveToken(access);
      }
      await ref.read(realtimeClientProvider).connect();
      if (!mounted) return;
      context.go('/dashboard');
      unawaited(registerPushNotifications(api));
    } on DioException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(messageFromDio(e))),
      );
    } on StateError catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message)),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Register as worker')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Account', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 14),
                  TextField(
                    controller: _name,
                    decoration: const InputDecoration(labelText: 'Full name', prefixIcon: Icon(Icons.person_outline)),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _email,
                    keyboardType: TextInputType.emailAddress,
                    autocorrect: false,
                    decoration: const InputDecoration(labelText: 'Email', prefixIcon: Icon(Icons.email_outlined)),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _phone,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(labelText: 'Phone', prefixIcon: Icon(Icons.phone_iphone_rounded)),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _password,
                    decoration: const InputDecoration(labelText: 'Password (min 8 chars)', prefixIcon: Icon(Icons.lock_outline_rounded)),
                    obscureText: true,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 22),
          FilledButton(
            onPressed: _busy ? null : _submit,
            child: _busy
                ? const SizedBox(height: 22, width: 22, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Register'),
          ),
        ],
      ),
    );
  }
}

class WorkerProfileSetupScreen extends StatelessWidget {
  const WorkerProfileSetupScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Profile setup')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Photo', style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 36,
                        backgroundColor: cs.primaryContainer,
                        child: Icon(Icons.add_a_photo_rounded, color: cs.onPrimaryContainer, size: 28),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Text(
                          'A clear photo helps customers trust you.',
                          style: TextStyle(color: cs.onSurfaceVariant, height: 1.35),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Service categories', style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: ['Carpenter', 'Plumber', 'Electrician', 'AC Repair', 'Mechanic']
                        .map(
                          (c) => FilterChip(
                            label: Text(c),
                            selected: false,
                            onSelected: (_) {},
                            showCheckmark: false,
                          ),
                        )
                        .toList(),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  const TextField(
                    decoration: InputDecoration(labelText: 'Bio', alignLabelWithHint: true),
                    maxLines: 3,
                  ),
                  const SizedBox(height: 12),
                  const TextField(
                    decoration: InputDecoration(
                      labelText: 'MoMo number',
                      prefixIcon: Icon(Icons.account_balance_wallet_outlined),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: () => context.go('/upload-documents'),
            child: const Text('Next: verification'),
          ),
        ],
      ),
    );
  }
}

class DocumentUploadScreen extends StatelessWidget {
  const DocumentUploadScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Documents')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Upload a valid ID and any certifications.',
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 20),
            Expanded(
              child: Card(
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: BorderSide(color: cs.outlineVariant, width: 2),
                ),
                child: InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: () {},
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.cloud_upload_rounded, size: 56, color: cs.primary),
                      const SizedBox(height: 12),
                      Text('Tap to upload', style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 4),
                      Text('JPEG / PNG · max 5 MB', style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13)),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () => context.go('/verification-pending'),
              child: const Text('Upload ID & continue'),
            ),
          ],
        ),
      ),
    );
  }
}

class VerificationPendingScreen extends StatelessWidget {
  const VerificationPendingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            children: [
              const Spacer(),
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: cs.secondaryContainer.withOpacity(0.5),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.hourglass_top_rounded, size: 64, color: cs.secondary),
              ),
              const SizedBox(height: 24),
              Text(
                'Verification pending',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 12),
              Text(
                'We’ll review your documents. You can still explore the app.',
                textAlign: TextAlign.center,
                style: TextStyle(color: cs.onSurfaceVariant, height: 1.4),
              ),
              const Spacer(),
              FilledButton(
                onPressed: () => context.go('/dashboard'),
                child: const Text('Go to dashboard'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Dashboard app bar bell — same unread badge behaviour as the customer home screen.
class WorkerDashboardNotificationIcon extends ConsumerStatefulWidget {
  const WorkerDashboardNotificationIcon({super.key});

  @override
  ConsumerState<WorkerDashboardNotificationIcon> createState() =>
      _WorkerDashboardNotificationIconState();
}

class _WorkerDashboardNotificationIconState extends ConsumerState<WorkerDashboardNotificationIcon> {
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
    } catch (_) {}
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

/// Worker profile rating for dashboard hero (hide meaningless 0.0 before first reviews).
String _dashboardRatingLabel(Map<String, dynamic> me) {
  final wp = me['workerProfile'];
  if (wp is! Map) return '—';
  final r = wp['rating'];
  final jobs = wp['totalJobsCompleted'];
  final jc = jobs is int ? jobs : (jobs is num ? jobs.toInt() : 0);
  if (r is! num) return '—';
  if (jc == 0) return 'New';
  return r.toStringAsFixed(1);
}

String _pesewasToGhsDisplay(int? p) {
  final v = p ?? 0;
  if (v <= 0) return 'GHS 0.00';
  return 'GHS ${(v / 100).toStringAsFixed(2)}';
}

String _openJobRelativeTime(String? iso) {
  if (iso == null || iso.isEmpty) return '';
  final d = DateTime.tryParse(iso);
  if (d == null) return '';
  final diff = DateTime.now().difference(d);
  if (diff.inMinutes < 1) return 'Just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  if (diff.inDays < 7) return '${diff.inDays}d ago';
  return DateFormat('d MMM').format(d);
}

String _truncateOneLine(String s, int maxChars) {
  final t = s.trim();
  if (t.length <= maxChars) return t;
  return '${t.substring(0, maxChars - 1)}…';
}

class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  bool _online = true;
  List<dynamic> _myActiveJobs = [];
  int _openJobCount = 0;
  int _completedJobCount = 0;
  int _pendingQuoteCount = 0;
  bool _loadingDash = true;
  int? _earningsTodayPesewas;
  String _ratingLabel = '—';
  StreamSubscription<void>? _rtMe;
  StreamSubscription<void>? _rtFeed;

  @override
  void initState() {
    super.initState();
    _loadDash();
    final rt = ref.read(realtimeClientProvider);
    _rtMe = rt.onMyJobsChanged.listen((_) {
      if (mounted) _loadDash();
    });
    _rtFeed = rt.onWorkerFeedChanged.listen((_) {
      if (mounted) _loadDash();
    });
  }

  @override
  void dispose() {
    _rtMe?.cancel();
    _rtFeed?.cancel();
    super.dispose();
  }

  Future<void> _loadDash() async {
    setState(() => _loadingDash = true);
    try {
      final api = ref.read(apiClientProvider);
      final me = await api.getCurrentUser();
      final uid = me['id'] as String?;
      int? earningsToday;
      try {
        final w = await api.getWallet();
        final raw = w['earningsTodayPesewas'];
        if (raw is int) {
          earningsToday = raw;
        } else if (raw is num) {
          earningsToday = raw.round();
        }
      } catch (_) {}
      final list = await api.listOpenJobs();
      if (!mounted || uid == null) return;
      final mine = list.where((e) {
        final j = e as Map<String, dynamic>;
        return j['workerId'] == uid &&
            (j['status'] == 'ACCEPTED' ||
                j['status'] == 'IN_PROGRESS' ||
                j['status'] == 'DISPUTED');
      }).toList();
      final completed = list.where((e) {
        final j = e as Map<String, dynamic>;
        return j['workerId'] == uid && j['status'] == 'COMPLETED';
      }).length;
      final pendingQuotes = list.where((e) {
        final j = e as Map<String, dynamic>;
        return j['status'] == 'OPEN' && j['pendingQuote'] != null;
      }).length;
      final open = list.where((e) {
        final j = e as Map<String, dynamic>;
        return j['status'] == 'OPEN';
      }).length;
      setState(() {
        _myActiveJobs = mine;
        _completedJobCount = completed;
        _pendingQuoteCount = pendingQuotes;
        _openJobCount = open;
        _earningsTodayPesewas = earningsToday;
        _ratingLabel = _dashboardRatingLabel(me);
        _loadingDash = false;
      });
    } on DioException {
      if (mounted) setState(() => _loadingDash = false);
    }
  }

  String _activeSubtitle() {
    if (_loadingDash) return 'Loading…';
    if (_myActiveJobs.isEmpty) return 'None in progress';
    if (_myActiveJobs.length == 1) {
      final j = _myActiveJobs.first as Map<String, dynamic>;
      final t = j['title'] as String? ?? 'Job';
      final s = (j['status'] as String? ?? '').replaceAll('_', ' ');
      return '$t · $s';
    }
    return '${_myActiveJobs.length} jobs in progress';
  }

  String _completedSubtitle() {
    if (_loadingDash) return 'Loading…';
    if (_completedJobCount == 0) return 'None yet';
    if (_completedJobCount == 1) return '1 finished job';
    return '$_completedJobCount finished jobs';
  }

  String _pendingSubtitle() {
    if (_loadingDash) return 'Loading…';
    if (_pendingQuoteCount == 0) return 'None waiting';
    if (_pendingQuoteCount == 1) return '1 quote awaiting customer';
    return '$_pendingQuoteCount quotes awaiting customer';
  }

  void _onActiveJobTap() {
    if (_myActiveJobs.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No active jobs yet. When a customer accepts your quote, it appears here.')),
      );
      return;
    }
    if (_myActiveJobs.length == 1) {
      final id = (_myActiveJobs.first as Map<String, dynamic>)['id'] as String? ?? '';
      if (id.isNotEmpty) context.push('/active-job/$id');
    } else {
      context.push('/my-active-jobs');
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final activeCount = _myActiveJobs.length;
    return Scaffold(
      backgroundColor: cs.surfaceContainerLowest,
      body: CustomScrollView(
        slivers: [
          SliverAppBar.large(
            pinned: true,
            title: const Text('Dashboard'),
            actions: [
              const WorkerDashboardNotificationIcon(),
            ],
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Material(
                color: Colors.transparent,
                elevation: 8,
                shadowColor: cs.primary.withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(22),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(22),
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Positioned.fill(
                        child: DecoratedBox(
                          decoration: const BoxDecoration(gradient: WorkerGradients.hero),
                        ),
                      ),
                      Positioned(
                      right: -28,
                      top: -36,
                      child: Icon(Icons.blur_on_rounded, size: 150, color: Colors.white.withValues(alpha: 0.12)),
                    ),
                    Positioned(
                      left: -24,
                      bottom: -20,
                      child: Icon(Icons.blur_circular_rounded, size: 100, color: Colors.white.withValues(alpha: 0.08)),
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
                                      _online ? 'You’re visible' : 'You’re offline',
                                      style: tt.headlineSmall?.copyWith(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w800,
                                        letterSpacing: -0.5,
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      _online
                                          ? 'Customers can find you. New requests show under Open jobs.'
                                          : 'Go online to see nearby requests and alerts.',
                                      style: tt.bodyMedium?.copyWith(
                                        color: Colors.white.withValues(alpha: 0.88),
                                        height: 1.35,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: 0.2),
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(color: Colors.white24),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      _online ? Icons.visibility_rounded : Icons.visibility_off_rounded,
                                      size: 16,
                                      color: Colors.white.withValues(alpha: 0.95),
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      _online ? 'Live' : 'Hidden',
                                      style: tt.labelLarge?.copyWith(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w700,
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
                            elevation: 3,
                            shadowColor: Colors.black26,
                            child: SwitchListTile(
                              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
                              title: Text(
                                'Available for work',
                                style: TextStyle(fontWeight: FontWeight.w700, color: cs.primary),
                              ),
                              subtitle: Text(
                                _online ? 'You appear in customer search' : 'Tap to go online',
                                style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                              ),
                              value: _online,
                              activeTrackColor: cs.primary.withValues(alpha: 0.45),
                              activeThumbColor: cs.primary,
                              onChanged: (v) => setState(() => _online = v),
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
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            sliver: SliverToBoxAdapter(
              child: _DashboardSectionLabel(icon: Icons.insights_rounded, title: 'Today'),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
            sliver: SliverToBoxAdapter(
              child: Row(
                children: [
                  Expanded(
                    child: _StatCard(
                      icon: Icons.payments_rounded,
                      label: 'Earnings today',
                      value: _loadingDash ? '…' : _pesewasToGhsDisplay(_earningsTodayPesewas),
                      color: cs.secondary,
                      lightAccent: const Color(0xFFFFF3E0),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _StatCard(
                      icon: Icons.star_rounded,
                      label: 'Your rating',
                      value: _loadingDash ? '…' : _ratingLabel,
                      color: cs.tertiary,
                      lightAccent: const Color(0xFFE8F5E9),
                    ),
                  ),
                ],
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
            sliver: SliverToBoxAdapter(
              child: _DashboardSectionLabel(icon: Icons.dashboard_customize_rounded, title: 'Work & jobs'),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
            sliver: SliverToBoxAdapter(
              child: Column(
                children: [
                  _DashboardActionCard(
                    title: 'Active jobs',
                    subtitle: _activeSubtitle(),
                    icon: Icons.work_history_rounded,
                    accent: cs.primary,
                    badge: (!_loadingDash && activeCount > 0) ? activeCount : null,
                    onTap: _onActiveJobTap,
                  ),
                  _DashboardActionCard(
                    title: 'Pending quotes',
                    subtitle: _pendingSubtitle(),
                    icon: Icons.pending_actions_rounded,
                    accent: cs.tertiary,
                    badge: (!_loadingDash && _pendingQuoteCount > 0) ? _pendingQuoteCount : null,
                    onTap: () => context.push('/pending-jobs'),
                  ),
                  _DashboardActionCard(
                    title: 'Completed jobs',
                    subtitle: _completedSubtitle(),
                    icon: Icons.task_alt_rounded,
                    accent: cs.secondary,
                    badge: (!_loadingDash && _completedJobCount > 0) ? _completedJobCount : null,
                    onTap: () => context.push('/completed-jobs'),
                  ),
                  _DashboardActionCard(
                    title: 'Open jobs',
                    subtitle: _loadingDash
                        ? 'Loading…'
                        : '$_openJobCount nearby you can quote',
                    icon: Icons.handyman_rounded,
                    accent: cs.primary,
                    badge: (!_loadingDash && _openJobCount > 0) ? _openJobCount : null,
                    onTap: () => context.push('/jobs'),
                  ),
                ],
              ),
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 32)),
        ],
      ),
    );
  }
}

/// Bold section title with icon (worker dashboard).
class _DashboardSectionLabel extends StatelessWidget {
  const _DashboardSectionLabel({required this.icon, required this.title});

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

class _DashboardActionCard extends StatelessWidget {
  const _DashboardActionCard({
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

String _workerJobAgreedGhs(Map<String, dynamic> job) {
  final v = job['agreedPricePesewas'];
  if (v == null) return '';
  final n = v is int ? v : int.tryParse(v.toString());
  if (n == null || n <= 0) return '';
  return 'GHS ${(n / 100).toStringAsFixed(2)}';
}

/// Hero summary on [MyActiveJobsScreen] — splits funded escrow vs awaiting payment.
class _WorkerActiveJobsPanelHeader extends StatelessWidget {
  const _WorkerActiveJobsPanelHeader({
    required this.fundedCount,
    required this.awaitingCount,
  });

  final int fundedCount;
  final int awaitingCount;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final total = fundedCount + awaitingCount;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: WorkerGradients.hero,
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
            child: const Icon(Icons.account_balance_wallet_rounded, color: Colors.white, size: 28),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  total == 1 ? '1 active job' : '$total active jobs',
                  style: tt.titleLarge?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.4,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  fundedCount > 0 && awaitingCount > 0
                      ? '$fundedCount with customer payment held in escrow · $awaitingCount waiting for the customer to pay'
                      : fundedCount > 0
                          ? 'Customer funds are in escrow — you can work and mark done when ready.'
                          : 'Waiting for the customer to complete payment — funds will show here once deposited.',
                  style: tt.bodySmall?.copyWith(
                    color: Colors.white.withValues(alpha: 0.88),
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

class _WorkerActiveJobPanelCard extends StatelessWidget {
  const _WorkerActiveJobPanelCard({
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
    final customer = job['customer'] as Map<String, dynamic>?;
    final customerName = customer?['name'] as String?;
    final status = (job['status'] as String? ?? '').replaceAll('_', ' ');
    final inProgress = (job['status'] as String? ?? '') == 'IN_PROGRESS';
    final ghs = _workerJobAgreedGhs(job);

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
              color: cs.outlineVariant.withValues(alpha: 0.42),
              width: 1,
            ),
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
                        cs.primaryContainer.withValues(alpha: 0.95),
                        cs.primaryContainer.withValues(alpha: 0.45),
                      ],
                    ),
                  ),
                  child: Icon(
                    inProgress ? Icons.construction_rounded : Icons.handshake_rounded,
                    color: cs.onPrimaryContainer,
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
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (customerName != null && customerName.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Icon(Icons.person_outline_rounded, size: 14, color: cs.primary),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                customerName,
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
                          if (job['workerId'] != null) ...[
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: (job['escrowHeld'] == true)
                                    ? cs.tertiaryContainer.withValues(alpha: 0.95)
                                    : cs.secondaryContainer.withValues(alpha: 0.92),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    (job['escrowHeld'] == true)
                                        ? Icons.verified_rounded
                                        : Icons.payments_outlined,
                                    size: 14,
                                    color: (job['escrowHeld'] == true)
                                        ? cs.onTertiaryContainer
                                        : cs.onSecondaryContainer,
                                  ),
                                  const SizedBox(width: 4),
                                  Flexible(
                                    child: Text(
                                      (job['escrowHeld'] == true)
                                          ? 'Payment in escrow'
                                          : 'Awaiting customer payment',
                                      style: tt.labelMedium?.copyWith(
                                        color: (job['escrowHeld'] == true)
                                            ? cs.onTertiaryContainer
                                            : cs.onSecondaryContainer,
                                        fontWeight: FontWeight.w800,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
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
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (ghs.isNotEmpty)
                            Text(
                              ghs,
                              style: tt.labelLarge?.copyWith(fontWeight: FontWeight.w700),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
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

class _WorkerActiveJobsEmptyPanel extends StatelessWidget {
  const _WorkerActiveJobsEmptyPanel();

  @override
  Widget build(BuildContext context) {
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
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    cs.primaryContainer.withValues(alpha: 0.65),
                    cs.tertiaryContainer.withValues(alpha: 0.45),
                  ],
                ),
                boxShadow: [
                  BoxShadow(
                    color: cs.primary.withValues(alpha: 0.14),
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
              'When a customer accepts your quote, the job appears here so you can coordinate and complete the work.',
              textAlign: TextAlign.center,
              style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant, height: 1.45),
            ),
            const SizedBox(height: 28),
            FilledButton.icon(
              onPressed: () => context.go('/jobs'),
              icon: const Icon(Icons.work_outline_rounded),
              label: const Text('Browse open jobs'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Section label on [MyActiveJobsScreen] (escrow vs awaiting payment).
class _WorkerActiveJobsSectionTitle extends StatelessWidget {
  const _WorkerActiveJobsSectionTitle({
    required this.title,
    required this.subtitle,
    required this.icon,
  });

  final String title;
  final String subtitle;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 4, 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 22, color: cs.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.2),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant, height: 1.35),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class MyActiveJobsScreen extends ConsumerStatefulWidget {
  const MyActiveJobsScreen({super.key});

  @override
  ConsumerState<MyActiveJobsScreen> createState() => _MyActiveJobsScreenState();
}

class _MyActiveJobsScreenState extends ConsumerState<MyActiveJobsScreen> {
  List<dynamic> _withEscrow = [];
  List<dynamic> _awaitingPayment = [];
  String? _error;
  bool _loading = true;
  StreamSubscription<void>? _rtMe;
  StreamSubscription<void>? _rtFeed;

  @override
  void initState() {
    super.initState();
    _load();
    final rt = ref.read(realtimeClientProvider);
    _rtMe = rt.onMyJobsChanged.listen((_) {
      if (mounted) _load();
    });
    _rtFeed = rt.onWorkerFeedChanged.listen((_) {
      if (mounted) _load();
    });
  }

  @override
  void dispose() {
    _rtMe?.cancel();
    _rtFeed?.cancel();
    super.dispose();
  }

  void _sortJobsNewestFirst(List<dynamic> jobs) {
    jobs.sort((a, b) {
      final ja = a as Map<String, dynamic>;
      final jb = b as Map<String, dynamic>;
      final ca = DateTime.tryParse(ja['createdAt'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0);
      final cb = DateTime.tryParse(jb['createdAt'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0);
      return cb.compareTo(ca);
    });
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final api = ref.read(apiClientProvider);
      final me = await api.getCurrentUser();
      final uid = me['id'] as String?;
      final list = await api.listOpenJobs();
      if (!mounted || uid == null) return;
      final mine = list.where((e) {
        final j = e as Map<String, dynamic>;
        return j['workerId'] == uid &&
            (j['status'] == 'ACCEPTED' ||
                j['status'] == 'IN_PROGRESS' ||
                j['status'] == 'DISPUTED');
      }).toList();
      final funded = mine.where((e) => (e as Map)['escrowHeld'] == true).toList();
      final waiting = mine.where((e) => (e as Map)['escrowHeld'] != true).toList();
      _sortJobsNewestFirst(funded);
      _sortJobsNewestFirst(waiting);
      setState(() {
        _withEscrow = funded;
        _awaitingPayment = waiting;
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
    final total = _withEscrow.length + _awaitingPayment.length;
    return Scaffold(
      backgroundColor: cs.surfaceContainerLowest,
      appBar: AppBar(title: const Text('Your active jobs')),
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
                          color: cs.onSurfaceVariant,
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
              : total == 0
                  ? const _WorkerActiveJobsEmptyPanel()
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
                        children: [
                          _WorkerActiveJobsPanelHeader(
                            fundedCount: _withEscrow.length,
                            awaitingCount: _awaitingPayment.length,
                          ),
                          const SizedBox(height: 14),
                          if (_withEscrow.isNotEmpty) ...[
                            const _WorkerActiveJobsSectionTitle(
                              title: 'Payment in escrow',
                              subtitle:
                                  'Customer has paid. Funds are held until the job is completed and released.',
                              icon: Icons.savings_rounded,
                            ),
                            ..._withEscrow.map((e) {
                              final j = e as Map<String, dynamic>;
                              final id = j['id'] as String? ?? '';
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 12),
                                child: _WorkerActiveJobPanelCard(
                                  job: j,
                                  onTap: () => context.push('/active-job/$id'),
                                ),
                              );
                            }),
                          ],
                          if (_awaitingPayment.isNotEmpty) ...[
                            _WorkerActiveJobsSectionTitle(
                              title: 'Waiting for customer to pay',
                              subtitle: _withEscrow.isEmpty
                                  ? 'No escrow yet — ask the customer to complete payment in their app before you start work.'
                                  : 'These jobs are accepted but the customer has not deposited payment yet.',
                              icon: Icons.pending_actions_rounded,
                            ),
                            ..._awaitingPayment.map((e) {
                              final j = e as Map<String, dynamic>;
                              final id = j['id'] as String? ?? '';
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 12),
                                child: _WorkerActiveJobPanelCard(
                                  job: j,
                                  onTap: () => context.push('/active-job/$id'),
                                ),
                              );
                            }),
                          ],
                        ],
                      ),
                    ),
    );
  }
}

String _workerCompletedEarningsGhs(Map<String, dynamic> job) {
  final v = job['workerPayoutPesewas'] ?? job['agreedPricePesewas'];
  if (v == null) return '';
  final n = v is int ? v : (v is num ? v.round() : int.tryParse(v.toString()));
  if (n == null || n <= 0) return '';
  return 'GHS ${(n / 100).toStringAsFixed(2)}';
}

/// Hero summary on [WorkerCompletedJobsScreen].
class _WorkerCompletedJobsPanelHeader extends StatelessWidget {
  const _WorkerCompletedJobsPanelHeader({required this.jobCount});

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
                  'Tap a job for payout details, the agreed price, and the job record.',
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

class _WorkerCompletedJobPanelCard extends StatelessWidget {
  const _WorkerCompletedJobPanelCard({
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
    final customer = job['customer'] as Map<String, dynamic>?;
    final customerName = customer?['name'] as String?;
    final earnings = _workerCompletedEarningsGhs(job);
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
                      if (customerName != null && customerName.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Icon(Icons.person_outline_rounded, size: 14, color: cs.primary),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                customerName,
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
                          if (earnings.isNotEmpty)
                            Text(
                              'Your earnings $earnings',
                              style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                            )
                          else
                            Text(
                              'Tap for payout details',
                              style: tt.bodySmall?.copyWith(
                                color: cs.onSurfaceVariant,
                                fontStyle: FontStyle.italic,
                              ),
                            ),
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

class _WorkerCompletedJobsEmptyPanel extends StatelessWidget {
  const _WorkerCompletedJobsEmptyPanel();

  @override
  Widget build(BuildContext context) {
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
              'When you finish the work and the customer confirms, jobs land here with your earnings and summary.',
              textAlign: TextAlign.center,
              style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant, height: 1.45),
            ),
            const SizedBox(height: 28),
            FilledButton.icon(
              onPressed: () => context.go('/jobs'),
              icon: const Icon(Icons.work_outline_rounded),
              label: const Text('Browse open jobs'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Jobs assigned to this worker with status `COMPLETED` (same feed as [MyActiveJobsScreen]).
class WorkerCompletedJobsScreen extends ConsumerStatefulWidget {
  const WorkerCompletedJobsScreen({super.key});

  @override
  ConsumerState<WorkerCompletedJobsScreen> createState() => _WorkerCompletedJobsScreenState();
}

class _WorkerCompletedJobsScreenState extends ConsumerState<WorkerCompletedJobsScreen> {
  List<dynamic> _jobs = [];
  String? _error;
  bool _loading = true;
  StreamSubscription<void>? _rtMe;
  StreamSubscription<void>? _rtFeed;

  @override
  void initState() {
    super.initState();
    _load();
    final rt = ref.read(realtimeClientProvider);
    _rtMe = rt.onMyJobsChanged.listen((_) {
      if (mounted) _load();
    });
    _rtFeed = rt.onWorkerFeedChanged.listen((_) {
      if (mounted) _load();
    });
  }

  @override
  void dispose() {
    _rtMe?.cancel();
    _rtFeed?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final api = ref.read(apiClientProvider);
      final me = await api.getCurrentUser();
      final uid = me['id'] as String?;
      final list = await api.listOpenJobs();
      if (!mounted || uid == null) return;
      final mine = list.where((e) {
        final j = e as Map<String, dynamic>;
        return j['workerId'] == uid && j['status'] == 'COMPLETED';
      }).toList();
      setState(() {
        _jobs = mine;
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
    return Scaffold(
      backgroundColor: cs.surfaceContainerLowest,
      appBar: AppBar(title: const Text('Completed jobs')),
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
                          color: cs.onSurfaceVariant,
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
              : _jobs.isEmpty
                  ? const _WorkerCompletedJobsEmptyPanel()
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
                        children: [
                          _WorkerCompletedJobsPanelHeader(jobCount: _jobs.length),
                          const SizedBox(height: 14),
                          ..._jobs.map((e) {
                            final j = e as Map<String, dynamic>;
                            final id = j['id'] as String? ?? '';
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: _WorkerCompletedJobPanelCard(
                                job: j,
                                onTap: () => context.push('/job/$id'),
                              ),
                            );
                          }),
                        ],
                      ),
                    ),
    );
  }
}

/// OPEN jobs where this worker has a PENDING (sent) or COUNTERED quote — [WorkerCompletedJobsScreen] pattern.
class WorkerPendingJobsScreen extends ConsumerStatefulWidget {
  const WorkerPendingJobsScreen({super.key});

  @override
  ConsumerState<WorkerPendingJobsScreen> createState() => _WorkerPendingJobsScreenState();
}

class _WorkerPendingJobsScreenState extends ConsumerState<WorkerPendingJobsScreen> {
  List<dynamic> _jobs = [];
  String? _error;
  bool _loading = true;
  StreamSubscription<void>? _rtMe;
  StreamSubscription<void>? _rtFeed;

  @override
  void initState() {
    super.initState();
    _load();
    final rt = ref.read(realtimeClientProvider);
    _rtMe = rt.onMyJobsChanged.listen((_) {
      if (mounted) _load();
    });
    _rtFeed = rt.onWorkerFeedChanged.listen((_) {
      if (mounted) _load();
    });
  }

  @override
  void dispose() {
    _rtMe?.cancel();
    _rtFeed?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await ref.read(apiClientProvider).listOpenJobs();
      if (!mounted) return;
      final pending = list.where((e) {
        final j = e as Map<String, dynamic>;
        return j['status'] == 'OPEN' && j['pendingQuote'] != null;
      }).toList();
      setState(() {
        _jobs = pending;
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

  String _quoteLine(Map<String, dynamic> pq) {
    final st = pq['status'] as String? ?? '';
    int? pesewas(dynamic v) {
      if (v == null) return null;
      if (v is int) return v;
      if (v is num) return v.round();
      return null;
    }

    final amt = pesewas(pq['amountPesewas']);
    final ghs = amt != null && amt > 0 ? 'GHS ${(amt / 100).toStringAsFixed(2)}' : '';
    if (st == 'COUNTERED') {
      final ca = pesewas(pq['counterAmountPesewas']);
      final cgh = ca != null && ca > 0 ? 'GHS ${(ca / 100).toStringAsFixed(2)}' : '';
      return cgh.isNotEmpty ? 'Counter-offer $cgh — respond in job detail' : 'Counter-offer — open to review';
    }
    return ghs.isNotEmpty ? 'Quote sent · $ghs — awaiting customer' : 'Quote sent — awaiting customer';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Pending quotes')),
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
              : _jobs.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          'No pending quotes. When you send a quote on an open job, it appears here until the customer responds.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: cs.onSurfaceVariant, height: 1.4),
                        ),
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: _jobs.length,
                        itemBuilder: (context, i) {
                          final j = _jobs[i] as Map<String, dynamic>;
                          final id = j['id'] as String? ?? '';
                          final title = j['title'] as String? ?? 'Job';
                          final pq = j['pendingQuote'] as Map<String, dynamic>?;
                          final sub = pq != null ? _quoteLine(pq) : 'Pending';
                          return Card(
                            margin: const EdgeInsets.only(bottom: 10),
                            child: ListTile(
                              leading: CircleAvatar(
                                backgroundColor: cs.tertiaryContainer,
                                child: Icon(Icons.pending_actions_rounded, color: cs.onTertiaryContainer),
                              ),
                              title: Text(title),
                              isThreeLine: true,
                              subtitle: Text(sub, maxLines: 2, overflow: TextOverflow.ellipsis),
                              trailing: const Icon(Icons.chevron_right_rounded),
                              onTap: () => context.push('/job/$id'),
                            ),
                          );
                        },
                      ),
                    ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
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
      shadowColor: cs.shadow.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(18),
      child: Ink(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.35)),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              lightAccent.withValues(alpha: 0.55),
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

class _OpenJobsPanelHeader extends StatelessWidget {
  const _OpenJobsPanelHeader({
    required this.jobCount,
    required this.awaitingCustomerCount,
  });

  final int jobCount;
  final int awaitingCustomerCount;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: WorkerGradients.hero,
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
            child: const Icon(Icons.radar_rounded, color: Colors.white, size: 28),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  jobCount == 1 ? '1 open job' : '$jobCount open jobs',
                  style: tt.titleLarge?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.4,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Jobs with your pending quote are listed first. Open a job to send a quote or reply to the customer.',
                  style: tt.bodySmall?.copyWith(
                    color: Colors.white.withValues(alpha: 0.88),
                    height: 1.4,
                  ),
                ),
                if (awaitingCustomerCount > 0) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.amber.shade100.withValues(alpha: 0.25),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.amber.shade200.withValues(alpha: 0.55)),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.hourglass_top_rounded, size: 20, color: Colors.amber.shade100),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            awaitingCustomerCount == 1
                                ? '1 job is waiting on the customer'
                                : '$awaitingCustomerCount jobs are waiting on the customer',
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

enum _OpenJobsViewMode { list, grid }

int? _pesewasField(dynamic v) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  return null;
}

/// Jiji-inspired open job card: photo strip + accent border, GHS line, chips, address (list vs grid).
class _OpenJobPanelCard extends StatelessWidget {
  const _OpenJobPanelCard({
    required this.job,
    required this.onTap,
    this.compact = false,
  });

  final Map<String, dynamic> job;
  final VoidCallback onTap;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final title = job['title'] as String? ?? 'Job';
    final cat = job['category'] as String? ?? '';
    final catLabel = cat.replaceAll('_', ' ');
    final address = (job['address'] as String? ?? '').trim();
    final createdAt = job['createdAt'] as String?;
    final rel = _openJobRelativeTime(createdAt);
    final cust = job['customer'];
    final customerName = cust is Map<String, dynamic> ? (cust['name'] as String? ?? '').trim() : '';

    String? firstPhotoUrl;
    final photos = job['photos'];
    if (photos is List && photos.isNotEmpty) {
      final u = photos.first;
      if (u is String && u.isNotEmpty) firstPhotoUrl = u;
    }

    final pq = job['pendingQuote'] as Map<String, dynamic>?;
    final pending = pq != null;
    final qs = pq?['status'] as String? ?? '';
    final countered = pending && qs == 'COUNTERED';

    String statusBadge;
    if (countered) {
      statusBadge = 'Counter-offer';
    } else if (pending) {
      statusBadge = 'Quote sent';
    } else {
      statusBadge = 'Open';
    }

    String detailLine;
    if (pq != null) {
      detailLine = qs == 'COUNTERED'
          ? 'Customer sent a counter — open to review'
          : 'Your quote is with the customer';
    } else {
      detailLine = 'Send a quote to get considered';
    }

    final accent = cs.primary;
    final counterAmt = _pesewasField(pq?['counterAmountPesewas']);
    final quoteAmt = _pesewasField(pq?['amountPesewas']);
    final String headlineMoney;
    final String? moneySub;
    if (countered && counterAmt != null && counterAmt > 0) {
      headlineMoney = _pesewasToGhsDisplay(counterAmt);
      moneySub = quoteAmt != null && quoteAmt > 0 ? 'Your quote ${_pesewasToGhsDisplay(quoteAmt)}' : null;
    } else if (pending && quoteAmt != null && quoteAmt > 0) {
      headlineMoney = _pesewasToGhsDisplay(quoteAmt);
      moneySub = null;
    } else {
      headlineMoney = '';
      moneySub = null;
    }

    final metaBits = <String>[
      catLabel,
      if (rel.isNotEmpty) rel,
    ];
    final metaLine = metaBits.join(' • ');
    final locLine = address.isNotEmpty ? _truncateOneLine(address, compact ? 42 : 56) : '';

    Widget miniChip(IconData icon, String label) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest.withValues(alpha: 0.95),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: cs.onSurfaceVariant),
            const SizedBox(width: 3),
            Text(
              label,
              style: tt.labelSmall?.copyWith(
                color: cs.onSurfaceVariant,
                fontWeight: FontWeight.w600,
                fontSize: 11,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      );
    }

    Widget photoPlaceholder({required double iconSize}) {
      return Container(
        width: double.infinity,
        height: double.infinity,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              cs.primaryContainer.withValues(alpha: 0.75),
              cs.tertiaryContainer.withValues(alpha: 0.35),
            ],
          ),
        ),
        child: Icon(
          countered
              ? Icons.reply_rounded
              : pending
                  ? Icons.schedule_send_rounded
                  : Icons.handyman_rounded,
          size: iconSize,
          color: cs.onPrimaryContainer.withValues(alpha: 0.9),
        ),
      );
    }

    Widget imageBadge() {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          statusBadge.toUpperCase(),
          style: tt.labelSmall?.copyWith(
            color: Colors.white,
            fontWeight: FontWeight.w800,
            fontSize: 10,
            letterSpacing: 0.3,
          ),
        ),
      );
    }

    /// Jiji-style L border on three sides (left, bottom, right).
    Widget wrapAccentBorder({required Widget child}) {
      return Container(
        decoration: BoxDecoration(
          border: Border(
            left: BorderSide(color: accent, width: 2),
            right: BorderSide(color: accent, width: 2),
            bottom: BorderSide(color: accent, width: 2),
          ),
        ),
        child: child,
      );
    }

    Widget buildPhotoBlock({required bool grid}) {
      final radius = grid ? 16.0 : 14.0;
      final stack = Stack(
        fit: StackFit.expand,
        children: [
          if (firstPhotoUrl != null)
            Image.network(
              firstPhotoUrl,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) =>
                  photoPlaceholder(iconSize: grid ? 40 : 36),
              loadingBuilder: (context, child, progress) {
                if (progress == null) return child;
                return ColoredBox(
                  color: cs.surfaceContainerHighest,
                  child: Center(
                    child: SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: cs.primary,
                      ),
                    ),
                  ),
                );
              },
            )
          else
            photoPlaceholder(iconSize: grid ? 40 : 36),
          Positioned(
            top: 8,
            left: 8,
            child: imageBadge(),
          ),
        ],
      );

      if (grid) {
        return ClipRRect(
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(radius),
            topRight: Radius.circular(radius),
          ),
          child: AspectRatio(
            aspectRatio: 4 / 3,
            child: wrapAccentBorder(child: stack),
          ),
        );
      }

      return SizedBox(
        width: 102,
        height: 102,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(radius),
          child: wrapAccentBorder(child: stack),
        ),
      );
    }

    final cardBorder = Border.all(
      color: cs.outlineVariant.withValues(alpha: 0.5),
      width: 1,
    );

    if (compact) {
      return Material(
        color: cs.surface,
        elevation: 2,
        shadowColor: cs.shadow.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(18),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Ink(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              border: cardBorder,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                buildPhotoBlock(grid: true),
                Padding(
                  padding: const EdgeInsets.fromLTRB(10, 10, 10, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (headlineMoney.isNotEmpty)
                        Text(
                          headlineMoney,
                          style: tt.titleMedium?.copyWith(
                            color: accent,
                            fontWeight: FontWeight.w900,
                            letterSpacing: -0.3,
                          ),
                        )
                      else
                        Text(
                          'Send a quote',
                          style: tt.titleSmall?.copyWith(
                            color: accent,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      if (moneySub != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          moneySub,
                          style: tt.labelSmall?.copyWith(color: cs.onSurfaceVariant, fontWeight: FontWeight.w600),
                        ),
                      ],
                      const SizedBox(height: 6),
                      Text(
                        title,
                        style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.2),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          miniChip(
                            countered
                                ? Icons.reply_rounded
                                : pending
                                    ? Icons.schedule_send_rounded
                                    : Icons.flag_rounded,
                            statusBadge,
                          ),
                          miniChip(Icons.category_rounded, catLabel),
                          if (customerName.isNotEmpty)
                            miniChip(Icons.person_outline_rounded, customerName),
                        ],
                      ),
                      if (locLine.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text(
                          locLine,
                          style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant, height: 1.25),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                      if (metaLine.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          metaLine,
                          style: tt.bodySmall?.copyWith(
                            color: cs.onSurfaceVariant.withValues(alpha: 0.85),
                            fontSize: 11,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                      const SizedBox(height: 4),
                      Text(
                        detailLine,
                        style: tt.bodySmall?.copyWith(
                          color: cs.onSurfaceVariant,
                          height: 1.25,
                          fontSize: 11,
                        ),
                        maxLines: compact ? 2 : 3,
                        overflow: TextOverflow.ellipsis,
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

    // List layout: thumbnail left, price top-right, title + chips + meta.
    return Material(
      color: cs.surface,
      elevation: 2,
      shadowColor: cs.shadow.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: cardBorder,
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                buildPhotoBlock(grid: false),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Align(
                        alignment: Alignment.centerRight,
                        child: headlineMoney.isNotEmpty
                            ? Text(
                                headlineMoney,
                                style: tt.titleSmall?.copyWith(
                                  color: accent,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: -0.2,
                                ),
                              )
                            : Text(
                                'Send quote',
                                style: tt.labelLarge?.copyWith(
                                  color: accent,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                      ),
                      if (moneySub != null) ...[
                        const SizedBox(height: 2),
                        Align(
                          alignment: Alignment.centerRight,
                          child: Text(
                            moneySub,
                            style: tt.labelSmall?.copyWith(color: cs.onSurfaceVariant, fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                      const SizedBox(height: 4),
                      Text(
                        title,
                        style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.2),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          miniChip(
                            countered
                                ? Icons.reply_rounded
                                : pending
                                    ? Icons.schedule_send_rounded
                                    : Icons.flag_rounded,
                            statusBadge,
                          ),
                          miniChip(Icons.category_rounded, catLabel),
                          if (customerName.isNotEmpty)
                            miniChip(Icons.person_outline_rounded, customerName),
                        ],
                      ),
                      if (locLine.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(
                          locLine,
                          style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant, height: 1.3),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                      if (metaLine.isNotEmpty)
                        Text(
                          metaLine,
                          style: tt.bodySmall?.copyWith(
                            color: cs.onSurfaceVariant.withValues(alpha: 0.88),
                            fontSize: 11,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      const SizedBox(height: 4),
                      Text(
                        detailLine,
                        style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant, height: 1.3),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right_rounded, color: cs.outline, size: 22),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _OpenJobsEmptyPanel extends StatelessWidget {
  const _OpenJobsEmptyPanel();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Column(
        children: [
          const SizedBox(height: 28),
          Container(
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  cs.primaryContainer.withValues(alpha: 0.65),
                  cs.tertiaryContainer.withValues(alpha: 0.45),
                ],
              ),
              boxShadow: [
                BoxShadow(
                  color: cs.primary.withValues(alpha: 0.12),
                  blurRadius: 20,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Icon(Icons.work_off_rounded, size: 52, color: cs.primary),
          ),
          const SizedBox(height: 24),
          Text(
            'No open jobs yet',
            textAlign: TextAlign.center,
            style: tt.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 12),
          Text(
            'Nothing matches your categories and radius right now. Assigned and finished work is on Home. '
            'Customer jobs default to Accra — try aligning your categories.',
            textAlign: TextAlign.center,
            style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant, height: 1.45),
          ),
          const SizedBox(height: 28),
          FilledButton.icon(
            onPressed: () => context.go('/dashboard'),
            icon: const Icon(Icons.dashboard_rounded),
            label: const Text('Go to Home'),
          ),
        ],
      ),
    );
  }
}

class AvailableJobsScreen extends ConsumerStatefulWidget {
  const AvailableJobsScreen({super.key});

  @override
  ConsumerState<AvailableJobsScreen> createState() => _AvailableJobsScreenState();
}

class _AvailableJobsScreenState extends ConsumerState<AvailableJobsScreen> {
  static const _kOpenJobsViewPref = 'open_jobs_view_mode';

  List<dynamic> _jobs = [];
  bool _loading = true;
  String? _error;
  _OpenJobsViewMode _viewMode = _OpenJobsViewMode.list;
  StreamSubscription<void>? _rtMe;
  StreamSubscription<void>? _rtFeed;

  @override
  void initState() {
    super.initState();
    _loadOpenJobsViewPref();
    _load();
    final rt = ref.read(realtimeClientProvider);
    _rtMe = rt.onMyJobsChanged.listen((_) {
      if (mounted) _load();
    });
    _rtFeed = rt.onWorkerFeedChanged.listen((_) {
      if (mounted) _load();
    });
  }

  @override
  void dispose() {
    _rtMe?.cancel();
    _rtFeed?.cancel();
    super.dispose();
  }

  Future<void> _loadOpenJobsViewPref() async {
    final prefs = await SharedPreferences.getInstance();
    final v = prefs.getString(_kOpenJobsViewPref);
    if (!mounted) return;
    if (v == 'grid') {
      setState(() => _viewMode = _OpenJobsViewMode.grid);
    } else if (v == 'list') {
      setState(() => _viewMode = _OpenJobsViewMode.list);
    }
  }

  Future<void> _setOpenJobsViewMode(_OpenJobsViewMode mode) async {
    setState(() => _viewMode = mode);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kOpenJobsViewPref, mode == _OpenJobsViewMode.grid ? 'grid' : 'list');
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final api = ref.read(apiClientProvider);
      final list = await api.listOpenJobs();
      if (!mounted) return;
      final openOnly = list.where((e) {
        final j = e as Map<String, dynamic>;
        return (j['status'] as String? ?? '') == 'OPEN';
      }).toList();
      openOnly.sort((a, b) {
        final pa = (a as Map<String, dynamic>)['pendingQuote'] != null;
        final pb = (b as Map<String, dynamic>)['pendingQuote'] != null;
        if (pa != pb) return pa ? -1 : 1;
        return 0;
      });
      setState(() {
        _jobs = openOnly;
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
    final awaitingOnCustomer = _jobs.where((e) {
      final j = e as Map<String, dynamic>;
      return j['pendingQuote'] != null;
    }).length;

    return Scaffold(
      backgroundColor: cs.surfaceContainerLowest,
      appBar: AppBar(
        title: const Text('Open jobs'),
        actions: [
          IconButton(
            tooltip: 'List',
            icon: const Icon(Icons.view_list_rounded),
            color: _viewMode == _OpenJobsViewMode.list ? cs.primary : cs.onSurfaceVariant,
            onPressed: () => _setOpenJobsViewMode(_OpenJobsViewMode.list),
          ),
          IconButton(
            tooltip: 'Grid',
            icon: const Icon(Icons.grid_view_rounded),
            color: _viewMode == _OpenJobsViewMode.grid ? cs.primary : cs.onSurfaceVariant,
            onPressed: () => _setOpenJobsViewMode(_OpenJobsViewMode.grid),
          ),
          const SizedBox(width: 4),
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
                    'Loading open jobs…',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: cs.onSurfaceVariant,
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
              : RefreshIndicator(
                  onRefresh: _load,
                  child: _jobs.isEmpty
                      ? LayoutBuilder(
                          builder: (context, constraints) {
                            return SingleChildScrollView(
                              physics: const AlwaysScrollableScrollPhysics(),
                              child: ConstrainedBox(
                                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                                child: const Center(child: _OpenJobsEmptyPanel()),
                              ),
                            );
                          },
                        )
                      : _viewMode == _OpenJobsViewMode.list
                          ? ListView(
                              padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
                              children: [
                                _OpenJobsPanelHeader(
                                  jobCount: _jobs.length,
                                  awaitingCustomerCount: awaitingOnCustomer,
                                ),
                                const SizedBox(height: 14),
                                ..._jobs.map((e) {
                                  final j = e as Map<String, dynamic>;
                                  final id = j['id'] as String? ?? '';
                                  return Padding(
                                    padding: const EdgeInsets.only(bottom: 12),
                                    child: _OpenJobPanelCard(
                                      job: j,
                                      onTap: () => context.push('/job/$id'),
                                    ),
                                  );
                                }),
                              ],
                            )
                          : CustomScrollView(
                              physics: const AlwaysScrollableScrollPhysics(),
                              slivers: [
                                SliverPadding(
                                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 14),
                                  sliver: SliverToBoxAdapter(
                                    child: _OpenJobsPanelHeader(
                                      jobCount: _jobs.length,
                                      awaitingCustomerCount: awaitingOnCustomer,
                                    ),
                                  ),
                                ),
                                SliverPadding(
                                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
                                  sliver: SliverGrid(
                                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                                      crossAxisCount: 2,
                                      mainAxisSpacing: 12,
                                      crossAxisSpacing: 12,
                                      childAspectRatio: 0.54,
                                    ),
                                    delegate: SliverChildBuilderDelegate(
                                      (context, index) {
                                        final j = _jobs[index] as Map<String, dynamic>;
                                        final id = j['id'] as String? ?? '';
                                        return _OpenJobPanelCard(
                                          job: j,
                                          compact: true,
                                          onTap: () => context.push('/job/$id'),
                                        );
                                      },
                                      childCount: _jobs.length,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                ),
    );
  }
}

class WorkerJobDetailScreen extends ConsumerStatefulWidget {
  const WorkerJobDetailScreen({required this.jobId, super.key});
  final String jobId;

  @override
  ConsumerState<WorkerJobDetailScreen> createState() => _WorkerJobDetailScreenState();
}

class _WorkerJobDetailScreenState extends ConsumerState<WorkerJobDetailScreen> {
  Map<String, dynamic>? _job;
  bool _loading = true;
  String? _error;
  StreamSubscription<Map<String, dynamic>>? _jobEvSub;
  late final PageController _photoPageController;
  int _photoPageIndex = 0;
  bool _descriptionExpanded = false;

  @override
  void initState() {
    super.initState();
    _photoPageController = PageController();
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
    _photoPageController.dispose();
    _jobEvSub?.cancel();
    ref.read(realtimeClientProvider).leaveJob(widget.jobId);
    super.dispose();
  }

  Future<void> _callCustomer(String? rawPhone) async {
    final t = rawPhone?.trim() ?? '';
    if (t.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Phone number not available for this customer.')),
      );
      return;
    }
    final uri = Uri(scheme: 'tel', path: t);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not start the phone call.')),
      );
    }
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
    final jobId = widget.jobId;

    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Job')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    if (_error != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Job')),
        body: Center(
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
        ),
      );
    }

    final j = _job!;
    final title = j['title'] as String? ?? 'Job';
    final desc = j['description'] as String? ?? '';
    final cat = j['category'] as String? ?? '';
    final address = j['address'] as String? ?? '';
    final status = j['status'] as String? ?? '';
    final myQuote = j['myQuote'] as Map<String, dynamic>?;
    final quoteStatus = myQuote?['status'] as String?;
    final acceptedQuote = j['acceptedQuote'] as Map<String, dynamic>?;
    final customer = j['customer'] as Map<String, dynamic>?;
    final customerName = customer?['name'] as String?;

    int? pesewas(dynamic v) {
      if (v == null) return null;
      if (v is int) return v;
      if (v is num) return v.round();
      return null;
    }

    String ghsFromPesewas(int? p) {
      if (p == null || p <= 0) return '—';
      return 'GHS ${(p / 100).toStringAsFixed(2)}';
    }

    Map<String, int>? quoteBreakdownMap(dynamic raw) {
      if (raw == null) return null;
      if (raw is! Map) return null;
      final out = <String, int>{};
      for (final k in ['labour', 'parts', 'transport']) {
        final v = raw[k];
        final p = pesewas(v);
        if (p != null && p > 0) out[k] = p;
      }
      return out.isEmpty ? null : out;
    }

    String? formatIsoDate(String? iso) {
      if (iso == null || iso.isEmpty) return null;
      try {
        return DateFormat('d MMM yyyy · HH:mm').format(DateTime.parse(iso).toLocal());
      } catch (_) {
        return null;
      }
    }

    final agreed = pesewas(j['agreedPricePesewas']);
    final payout = pesewas(j['workerPayoutPesewas']);
    final platformFee = pesewas(j['platformFeePesewas']);
    final completedAt = j['completedAt'] as String?;
    final quoteAcceptedAt = j['quoteAcceptedAt'] as String?;
    final completedLabel = formatIsoDate(completedAt);
    final breakdown = quoteBreakdownMap(acceptedQuote?['breakdown']);

    final tt = Theme.of(context).textTheme;
    final statusPretty = status.replaceAll('_', ' ');
    final showFinishedPaymentCard =
        status == 'COMPLETED' || status == 'DISPUTED';
    final catLabel = cat.replaceAll('_', ' ');
    final quoteAmt = pesewas(myQuote?['amountPesewas']);
    final counterAmt = pesewas(myQuote?['counterAmountPesewas']);
    final isCountered = quoteStatus == 'COUNTERED';
    String? headlinePriceLine;
    String? headlinePriceSub;
    if (status == 'OPEN' && myQuote != null) {
      if (isCountered && counterAmt != null && counterAmt > 0) {
        headlinePriceLine = ghsFromPesewas(counterAmt);
        if (quoteAmt != null && quoteAmt > 0) {
          headlinePriceSub = 'Your quote ${ghsFromPesewas(quoteAmt)}';
        }
      } else if (quoteAmt != null && quoteAmt > 0) {
        headlinePriceLine = ghsFromPesewas(quoteAmt);
      }
    }
    if (headlinePriceLine == null && agreed != null && agreed > 0) {
      headlinePriceLine = ghsFromPesewas(agreed);
    }

    if (showFinishedPaymentCard) {
      return Scaffold(
        appBar: AppBar(title: const Text('Job')),
        body: ListView(
          padding: EdgeInsets.zero,
          children: [
            Container(
              width: double.infinity,
              decoration: const BoxDecoration(gradient: WorkerGradients.earnings),
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      CircleAvatar(
                        backgroundColor: Colors.white24,
                        child: Icon(
                          status == 'COMPLETED' ? Icons.verified_rounded : Icons.gavel_rounded,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              title,
                              style: tt.titleLarge?.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.w800,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              statusPretty,
                              style: tt.labelLarge?.copyWith(
                                color: Colors.white70,
                                letterSpacing: 0.3,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  if (completedLabel != null) ...[
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Icon(Icons.event_available_rounded, size: 18, color: Colors.white.withValues(alpha: 0.85)),
                        const SizedBox(width: 6),
                        Text(
                          'Finished $completedLabel',
                          style: tt.bodySmall?.copyWith(color: Colors.white70),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 22),
                  Text(
                    'Your earnings (after fees)',
                    style: tt.labelMedium?.copyWith(color: Colors.white.withValues(alpha: 0.9)),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    ghsFromPesewas(payout ?? agreed),
                    style: tt.headlineMedium?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 32,
                    ),
                  ),
                  if (payout == null && agreed != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        'Shown from agreed job amount — payout detail may update when the job is fully closed.',
                        style: tt.bodySmall?.copyWith(color: Colors.white70, height: 1.35),
                      ),
                    ),
                  const SizedBox(height: 18),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: Colors.black26,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        children: [
                          _moneyRow(
                            context,
                            Icons.payments_rounded,
                            'Customer paid (job total)',
                            ghsFromPesewas(agreed),
                            subtle: false,
                          ),
                          if (platformFee != null && platformFee > 0) ...[
                            const Divider(color: Colors.white24, height: 20),
                            _moneyRow(
                              context,
                              Icons.percent_rounded,
                              'Platform fee',
                              ghsFromPesewas(platformFee),
                              subtle: true,
                            ),
                          ],
                          if (payout != null && agreed != null && payout != agreed) ...[
                            const Divider(color: Colors.white24, height: 20),
                            _moneyRow(
                              context,
                              Icons.savings_rounded,
                              'You receive',
                              ghsFromPesewas(payout),
                              subtle: false,
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  if (quoteAcceptedAt != null && formatIsoDate(quoteAcceptedAt) != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      'Quote accepted · ${formatIsoDate(quoteAcceptedAt)}',
                      style: tt.bodySmall?.copyWith(color: Colors.white60),
                    ),
                  ],
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (breakdown != null) ...[
                    Card(
                      elevation: 0,
                      color: cs.surfaceContainerHighest,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(Icons.receipt_long_rounded, color: cs.primary, size: 22),
                                const SizedBox(width: 8),
                                Text(
                                  'Quote breakdown',
                                  style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            if (breakdown['labour'] != null)
                              _breakdownRow(context, 'Labour', breakdown['labour']!, ghsFromPesewas),
                            if (breakdown['parts'] != null)
                              _breakdownRow(context, 'Parts & materials', breakdown['parts']!, ghsFromPesewas),
                            if (breakdown['transport'] != null)
                              _breakdownRow(context, 'Transportation', breakdown['transport']!, ghsFromPesewas),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  if (customerName != null && customerName.isNotEmpty)
                    Card(
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: cs.primaryContainer,
                          child: Icon(Icons.person_rounded, color: cs.onPrimaryContainer),
                        ),
                        title: const Text('Customer'),
                        subtitle: Text(customerName),
                      ),
                    ),
                  if (customerName != null && customerName.isNotEmpty) const SizedBox(height: 12),
                ],
              ),
            ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Card(
              elevation: 2,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (!showFinishedPaymentCard && (agreed != null && agreed > 0)) ...[
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: cs.tertiaryContainer.withValues(alpha: 0.5),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.attach_money_rounded, color: cs.tertiary),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Agreed job amount',
                                    style: tt.labelMedium?.copyWith(color: cs.onTertiaryContainer),
                                  ),
                                  Text(
                                    ghsFromPesewas(agreed),
                                    style: tt.titleLarge?.copyWith(
                                      fontWeight: FontWeight.w800,
                                      color: cs.onTertiaryContainer,
                                    ),
                                  ),
                                  if (payout != null && payout > 0)
                                    Text(
                                      'Your estimated payout ${ghsFromPesewas(payout)}',
                                      style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                                    ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],
                    _detailIconRow(
                      context,
                      Icons.category_rounded,
                      'Category',
                      cat.replaceAll('_', ' '),
                    ),
                    const Divider(height: 28),
                    _detailIconRow(
                      context,
                      Icons.flag_rounded,
                      'Status',
                      statusPretty,
                    ),
                    const Divider(height: 28),
                    _detailIconRow(
                      context,
                      Icons.location_on_rounded,
                      'Location',
                      address.isEmpty ? '—' : address,
                    ),
                    const Divider(height: 28),
                    Text('About the job', style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 8),
                    Text(
                      desc.isEmpty ? '—' : desc,
                      style: TextStyle(color: cs.onSurfaceVariant, height: 1.45),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
    }

    final photoUrls = <String>[];
    final photosRaw = j['photos'];
    if (photosRaw is List) {
      for (final p in photosRaw) {
        if (p is String && p.isNotEmpty) photoUrls.add(p);
      }
    }
    final createdAtRaw = j['createdAt'] as String?;
    final postedRel = _openJobRelativeTime(createdAtRaw);
    final customerPhone = customer?['phone'] as String?;
    final canChat = myQuote != null;
    final scheduledAt = j['scheduledAt'] as String?;
    String? schedLabel;
    if (scheduledAt != null && scheduledAt.isNotEmpty) {
      try {
        schedLabel = DateFormat('d MMM yyyy · HH:mm').format(DateTime.parse(scheduledAt).toLocal());
      } catch (_) {
        schedLabel = null;
      }
    }
    final postedLabel = formatIsoDate(createdAtRaw);
    final custInitial =
        (customerName != null && customerName.isNotEmpty) ? customerName[0].toUpperCase() : '?';

    void openChat() {
      if (!canChat) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Send a quote first — then you can message the customer in chat.'),
          ),
        );
        return;
      }
      context.push('/chat/$jobId');
    }

    return Scaffold(
      backgroundColor: cs.surfaceContainerLowest,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 280,
            pinned: true,
            stretch: true,
            backgroundColor: cs.surface,
            surfaceTintColor: Colors.transparent,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_rounded),
              onPressed: () => context.pop(),
            ),
            title: Text(
              catLabel,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            actions: [
              IconButton(
                tooltip: 'Share',
                icon: const Icon(Icons.share_outlined),
                onPressed: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Sharing coming soon.')),
                  );
                },
              ),
              IconButton(
                tooltip: 'Save',
                icon: const Icon(Icons.bookmark_border_rounded),
                onPressed: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Saved jobs coming soon.')),
                  );
                },
              ),
              PopupMenuButton<String>(
                onSelected: (v) {
                  if (v == 'report') {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Thanks — we will review this listing.')),
                    );
                  }
                },
                itemBuilder: (context) => [
                  const PopupMenuItem(value: 'report', child: Text('Report listing')),
                ],
              ),
            ],
            flexibleSpace: FlexibleSpaceBar(
              collapseMode: CollapseMode.parallax,
              background: Stack(
                fit: StackFit.expand,
                children: [
                  if (photoUrls.isEmpty)
                    Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            cs.primaryContainer,
                            cs.tertiaryContainer.withValues(alpha: 0.55),
                          ],
                        ),
                      ),
                      child: Icon(Icons.engineering_rounded, size: 88, color: cs.primary.withValues(alpha: 0.28)),
                    )
                  else
                    PageView.builder(
                      controller: _photoPageController,
                      onPageChanged: (i) => setState(() => _photoPageIndex = i),
                      itemCount: photoUrls.length,
                      itemBuilder: (context, i) {
                        return Image.network(
                          photoUrls[i],
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) => ColoredBox(
                            color: cs.surfaceContainerHighest,
                            child: Icon(Icons.broken_image_outlined, color: cs.outline, size: 48),
                          ),
                          loadingBuilder: (context, child, progress) {
                            if (progress == null) return child;
                            return ColoredBox(
                              color: cs.surfaceContainerHighest,
                              child: Center(
                                child: SizedBox(
                                  width: 28,
                                  height: 28,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: cs.primary),
                                ),
                              ),
                            );
                          },
                        );
                      },
                    ),
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    height: 88,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.transparent,
                            Colors.black.withValues(alpha: 0.38),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    bottom: 12,
                    left: 12,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.45),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.photo_camera_outlined, color: Colors.white, size: 18),
                          const SizedBox(width: 6),
                          Text(
                            photoUrls.isEmpty
                                ? '0'
                                : '${_photoPageIndex + 1} / ${photoUrls.length}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.location_on_outlined, size: 18, color: cs.onSurfaceVariant),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          [
                            if (address.isNotEmpty) _truncateOneLine(address, 52),
                            if (postedRel.isNotEmpty) postedRel,
                          ].join(' · '),
                          style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant, height: 1.35),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: cs.secondaryContainer.withValues(alpha: 0.85),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          statusPretty,
                          style: tt.labelSmall?.copyWith(
                            color: cs.onSecondaryContainer,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    title,
                    style: tt.headlineSmall?.copyWith(fontWeight: FontWeight.w900, letterSpacing: -0.4),
                  ),
                  const SizedBox(height: 10),
                  if (headlinePriceLine != null) ...[
                    Text(
                      headlinePriceLine,
                      style: tt.headlineSmall?.copyWith(
                        color: cs.primary,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.3,
                      ),
                    ),
                    if (headlinePriceSub != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        headlinePriceSub,
                        style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ] else ...[
                    Text(
                      'Name your price',
                      style: tt.titleMedium?.copyWith(color: cs.primary, fontWeight: FontWeight.w800),
                    ),
                  ],
                  const SizedBox(height: 8),
                  Text(
                    'Quotes are negotiable in chat',
                    style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: status == 'OPEN'
                            ? OutlinedButton(
                                onPressed: () => context.push('/job/$jobId/quote'),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: cs.primary,
                                  side: BorderSide(color: cs.primary.withValues(alpha: 0.85)),
                                  padding: const EdgeInsets.symmetric(vertical: 14),
                                ),
                                child: Text(myQuote != null ? 'Edit quote' : 'Send quote'),
                              )
                            : OutlinedButton(
                                onPressed: () => context.push('/dashboard'),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: cs.primary,
                                  side: BorderSide(color: cs.primary.withValues(alpha: 0.85)),
                                  padding: const EdgeInsets.symmetric(vertical: 14),
                                ),
                                child: const Text('Back to Home'),
                              ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: () => _callCustomer(customerPhone),
                          style: FilledButton.styleFrom(
                            backgroundColor: cs.primary,
                            foregroundColor: cs.onPrimary,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                          icon: const Icon(Icons.call_rounded, size: 20),
                          label: const Text('Call'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 22),
                  Text(
                    'Chat with the customer',
                    style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    height: 38,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      children: [
                        _jobDetailQuickChip(
                          context,
                          'Is this still available?',
                          () => openChat(),
                        ),
                        _jobDetailQuickChip(
                          context,
                          'I can start tomorrow',
                          () => openChat(),
                        ),
                        _jobDetailQuickChip(
                          context,
                          'What time works?',
                          () => openChat(),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  InkWell(
                    onTap: openChat,
                    borderRadius: BorderRadius.circular(12),
                    child: InputDecorator(
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: cs.surfaceContainerHighest,
                        hintText: 'Write your message here',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                      ),
                      child: Text(
                        'Write your message here',
                        style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant.withValues(alpha: 0.65)),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: () => openChat(),
                      style: FilledButton.styleFrom(
                        backgroundColor: cs.secondary,
                        foregroundColor: cs.onSecondary,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                      child: Text(
                        canChat ? 'Open chat' : 'Send a quote to unlock chat',
                        style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w800),
                      ),
                    ),
                  ),
                  if (!canChat)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        'After your first quote, you can message the customer here.',
                        style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                      ),
                    ),
                  const SizedBox(height: 22),
                  Row(
                    children: [
                      Expanded(
                        child: _jobDetailAttrTile(
                          context,
                          Icons.category_rounded,
                          catLabel,
                          'Category',
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _jobDetailAttrTile(
                          context,
                          Icons.flag_rounded,
                          statusPretty,
                          'Status',
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  Text(
                    'Job details',
                    style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 12),
                  _jobDetailSpecGrid(
                    context,
                    rows: [
                      [catLabel, statusPretty],
                      [
                        postedLabel ?? (postedRel.isNotEmpty ? postedRel : '—'),
                        schedLabel ?? '—',
                      ],
                      [
                        address.isEmpty ? '—' : _truncateOneLine(address, 36),
                        jobId.length > 8 ? '${jobId.substring(0, 8)}…' : jobId,
                      ],
                    ],
                    labels: const [
                      ['Category', 'Status'],
                      ['Posted', 'Scheduled'],
                      ['Location', 'Job ID'],
                    ],
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'Description',
                    style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    desc.isEmpty ? '—' : desc,
                    maxLines: _descriptionExpanded ? null : 5,
                    overflow: _descriptionExpanded ? null : TextOverflow.ellipsis,
                    style: TextStyle(color: cs.onSurfaceVariant, height: 1.45),
                  ),
                  if (desc.isNotEmpty && desc.length > 160)
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: () => setState(() => _descriptionExpanded = !_descriptionExpanded),
                        child: Text(_descriptionExpanded ? 'Show less' : 'Show more'),
                      ),
                    ),
                  const SizedBox(height: 16),
                  if (status == 'OPEN' &&
                      myQuote != null &&
                      (quoteStatus == 'PENDING' || quoteStatus == 'COUNTERED'))
                    Card(
                      color: cs.primaryContainer.withValues(alpha: 0.35),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Icon(
                                  quoteStatus == 'COUNTERED'
                                      ? Icons.swap_horiz_rounded
                                      : Icons.schedule_rounded,
                                  color: cs.primary,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    quoteStatus == 'COUNTERED'
                                        ? 'Customer sent a counter-offer — open chat or check the customer app.'
                                        : 'Quote sent — awaiting customer confirmation.',
                                    style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            Text(
                              'Your quote: ${ghsFromPesewas(pesewas(myQuote['amountPesewas']))}',
                              style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
                            ),
                            if (quoteStatus == 'COUNTERED' && myQuote['counterAmountPesewas'] != null) ...[
                              const SizedBox(height: 4),
                              Text(
                                'Their offer: ${ghsFromPesewas(pesewas(myQuote['counterAmountPesewas']))}',
                                style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  if (status == 'OPEN' &&
                      myQuote != null &&
                      (quoteStatus == 'PENDING' || quoteStatus == 'COUNTERED'))
                    const SizedBox(height: 12),
                  Material(
                    color: cs.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(16),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(16),
                      onTap: () {},
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          children: [
                            CircleAvatar(
                              radius: 26,
                              backgroundColor: cs.primaryContainer,
                              child: Text(
                                custInitial,
                                style: tt.titleMedium?.copyWith(
                                  color: cs.onPrimaryContainer,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    customerName ?? 'Customer',
                                    style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w800),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    'Posted ${_openJobRelativeTime(createdAtRaw)}',
                                    style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
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
                  if (status == 'OPEN' && myQuote == null) ...[
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: () => context.push('/job/$jobId/quote'),
                      icon: const Icon(Icons.request_quote_rounded),
                      label: const Text('Send quote'),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

Widget _jobDetailQuickChip(BuildContext context, String label, VoidCallback onTap) {
  final cs = Theme.of(context).colorScheme;
  return Padding(
    padding: const EdgeInsets.only(right: 8),
    child: ActionChip(
      label: Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
      onPressed: onTap,
      side: BorderSide(color: cs.primary.withValues(alpha: 0.85)),
      backgroundColor: cs.surface,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    ),
  );
}

Widget _jobDetailAttrTile(
  BuildContext context,
  IconData icon,
  String value,
  String label,
) {
  final cs = Theme.of(context).colorScheme;
  final tt = Theme.of(context).textTheme;
  return Container(
    padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
    decoration: BoxDecoration(
      color: cs.surfaceContainerHighest.withValues(alpha: 0.9),
      borderRadius: BorderRadius.circular(14),
    ),
    child: Column(
      children: [
        Icon(icon, color: cs.primary, size: 26),
        const SizedBox(height: 8),
        Text(
          value,
          textAlign: TextAlign.center,
          style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w800),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: tt.labelSmall?.copyWith(color: cs.onSurfaceVariant),
        ),
      ],
    ),
  );
}

Widget _jobDetailSpecGrid(
  BuildContext context, {
  required List<List<String>> rows,
  required List<List<String>> labels,
}) {
  final tt = Theme.of(context).textTheme;
  final cs = Theme.of(context).colorScheme;
  final out = <Widget>[];
  for (var i = 0; i < rows.length; i++) {
    final r = rows[i];
    final l = labels[i];
    out.add(
      Padding(
        padding: EdgeInsets.only(bottom: i < rows.length - 1 ? 16 : 0),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _jobDetailSpecCell(
                tt,
                cs,
                r[0],
                l[0],
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _jobDetailSpecCell(
                tt,
                cs,
                r[1],
                l[1],
              ),
            ),
          ],
        ),
      ),
    );
  }
  return Column(crossAxisAlignment: CrossAxisAlignment.start, children: out);
}

Widget _jobDetailSpecCell(
  TextTheme tt,
  ColorScheme cs,
  String value,
  String label,
) {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        value,
        style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w800),
      ),
      const SizedBox(height: 4),
      Text(
        label,
        style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
      ),
    ],
  );
}

Widget _moneyRow(
  BuildContext context,
  IconData icon,
  String label,
  String value, {
  required bool subtle,
}) {
  final tt = Theme.of(context).textTheme;
  return Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Icon(icon, size: 20, color: subtle ? Colors.white54 : Colors.white),
      const SizedBox(width: 10),
      Expanded(
        child: Text(
          label,
          style: tt.bodyMedium?.copyWith(
            color: subtle ? Colors.white60 : Colors.white70,
          ),
        ),
      ),
      Text(
        value,
        style: tt.titleSmall?.copyWith(
          color: Colors.white,
          fontWeight: FontWeight.w700,
        ),
      ),
    ],
  );
}

Widget _breakdownRow(
  BuildContext context,
  String label,
  int pesewas,
  String Function(int?) ghs,
) {
  final tt = Theme.of(context).textTheme;
  final cs = Theme.of(context).colorScheme;
  return Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
        Text(ghs(pesewas), style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
      ],
    ),
  );
}

Widget _detailIconRow(
  BuildContext context,
  IconData icon,
  String label,
  String value,
) {
  final tt = Theme.of(context).textTheme;
  final cs = Theme.of(context).colorScheme;
  return Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Icon(icon, color: cs.primary, size: 22),
      const SizedBox(width: 12),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: tt.labelMedium?.copyWith(color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 4),
            Text(value, style: tt.bodyLarge?.copyWith(fontWeight: FontWeight.w500)),
          ],
        ),
      ),
    ],
  );
}

class SendQuoteScreen extends ConsumerStatefulWidget {
  const SendQuoteScreen({required this.jobId, super.key});
  final String jobId;

  @override
  ConsumerState<SendQuoteScreen> createState() => _SendQuoteScreenState();
}

class _SendQuoteScreenState extends ConsumerState<SendQuoteScreen> {
  final _amount = TextEditingController();
  final _labour = TextEditingController();
  final _parts = TextEditingController();
  final _transport = TextEditingController();
  final _message = TextEditingController();
  bool _submitting = false;

  @override
  void dispose() {
    _amount.dispose();
    _labour.dispose();
    _parts.dispose();
    _transport.dispose();
    _message.dispose();
    super.dispose();
  }

  int? _parseGhsToPesewas(String raw) {
    final t = raw.trim().replaceAll(',', '');
    final v = double.tryParse(t);
    if (v == null || v <= 0) return null;
    return (v * 100).round();
  }

  Future<void> _submit() async {
    final pesewas = _parseGhsToPesewas(_amount.text);
    if (pesewas == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a valid total amount in GHS.')),
      );
      return;
    }
    final l = _parseGhsToPesewas(_labour.text);
    final p = _parseGhsToPesewas(_parts.text);
    final tr = _parseGhsToPesewas(_transport.text);
    final breakdownMap = <String, int>{};
    if (l != null) breakdownMap['labour'] = l;
    if (p != null) breakdownMap['parts'] = p;
    if (tr != null) breakdownMap['transport'] = tr;
    final Map<String, int>? breakdown =
        breakdownMap.isEmpty ? null : breakdownMap;
    setState(() => _submitting = true);
    try {
      await ref.read(apiClientProvider).submitQuote(
            jobId: widget.jobId,
            amountPesewas: pesewas,
            message: _message.text,
            breakdownPesewas: breakdown,
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Quote sent to the customer.')),
      );
      context.pop();
    } on DioException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(messageFromDio(e))),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Send quote')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Total price', style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _amount,
                    decoration: const InputDecoration(
                      labelText: 'Amount (GHS)',
                      prefixText: 'GHS ',
                    ),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Breakdown (optional)', style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _labour,
                    decoration: const InputDecoration(labelText: 'Labour (GHS)'),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _parts,
                    decoration: const InputDecoration(labelText: 'Parts (GHS)'),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _transport,
                    decoration: const InputDecoration(labelText: 'Transport (GHS)'),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: TextField(
                controller: _message,
                decoration: const InputDecoration(labelText: 'Message to customer', alignLabelWithHint: true),
                maxLines: 3,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              children: [
                Icon(Icons.schedule_rounded, size: 18, color: cs.onSurfaceVariant),
                const SizedBox(width: 6),
                Text('Quote expires in 2 hours', style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13)),
              ],
            ),
          ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: _submitting ? null : _submit,
            child: _submitting
                ? const SizedBox(
                    height: 22,
                    width: 22,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Submit quote'),
          ),
        ],
      ),
    );
  }
}

class WorkerActiveJobScreen extends ConsumerStatefulWidget {
  const WorkerActiveJobScreen({required this.jobId, super.key});
  final String jobId;

  @override
  ConsumerState<WorkerActiveJobScreen> createState() => _WorkerActiveJobScreenState();
}

class _WorkerActiveJobScreenState extends ConsumerState<WorkerActiveJobScreen>
    with SingleTickerProviderStateMixin {
  Map<String, dynamic>? _job;
  bool _loading = true;
  bool _busy = false;
  bool _disputeSubmitting = false;
  StreamSubscription<Map<String, dynamic>>? _jobEvSub;
  StreamSubscription<void>? _meJobsSub;
  late TabController _tabController;
  final _disputeReason = TextEditingController();
  final List<XFile> _disputeEvidenceImages = [];
  static const int _maxDisputePhotos = 5;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
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
    _disputeReason.dispose();
    _tabController.dispose();
    _jobEvSub?.cancel();
    _meJobsSub?.cancel();
    ref.read(realtimeClientProvider).leaveJob(widget.jobId);
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final data = await ref.read(apiClientProvider).getJob(widget.jobId);
      if (!mounted) return;
      setState(() {
        _job = data;
        _loading = false;
      });
    } on DioException catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Future<void> _startWork() async {
    setState(() => _busy = true);
    try {
      await ref.read(apiClientProvider).updateJobStatus(widget.jobId, 'IN_PROGRESS');
      if (!mounted) return;
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Marked as in progress.')),
      );
    } on DioException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(messageFromDio(e))),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pickDisputePhotos() async {
    final picker = ImagePicker();
    final picked = await picker.pickMultiImage(imageQuality: 82);
    if (!mounted || picked.isEmpty) return;
    final room = _maxDisputePhotos - _disputeEvidenceImages.length;
    if (room <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('You can add up to 5 photos.')),
      );
      return;
    }
    setState(() {
      _disputeEvidenceImages.addAll(picked.take(room));
    });
  }

  void _removeDisputePhoto(int index) {
    setState(() => _disputeEvidenceImages.removeAt(index));
  }

  Future<void> _requestCompletion() async {
    setState(() => _busy = true);
    try {
      await ref.read(apiClientProvider).requestJobCompletion(widget.jobId);
      if (!mounted) return;
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Customer notified — they confirm payment to finish.')),
      );
    } on DioException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(messageFromDio(e))),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _submitDispute() async {
    final reason = _disputeReason.text.trim();
    if (reason.length < 10) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please describe the issue in at least 10 characters.')),
      );
      return;
    }
    setState(() => _disputeSubmitting = true);
    try {
      final paths = _disputeEvidenceImages.map((x) => x.path).toList();
      final evidenceUrls = paths.isEmpty
          ? <String>[]
          : await ref.read(apiClientProvider).uploadDisputeEvidence(paths);
      await ref.read(apiClientProvider).createDispute(
            jobId: widget.jobId,
            reason: reason,
            evidencePhotos: evidenceUrls,
          );
      if (!mounted) return;
      _disputeReason.clear();
      setState(() => _disputeEvidenceImages.clear());
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Dispute submitted. Escrow is frozen until support resolves it.')),
      );
      if (_tabController.index != 0) {
        _tabController.animateTo(0);
      }
    } on DioException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(messageFromDio(e))),
      );
    } finally {
      if (mounted) setState(() => _disputeSubmitting = false);
    }
  }

  Widget _buildJobTab(ColorScheme cs, String status, bool completionPending, bool escrowHeld) {
    return Column(
      children: [
        if (!escrowHeld)
          MaterialBanner(
            content: const Text(
              'Customer payment must be held in escrow before you can start work or mark done. Ask them to complete payment in their app.',
            ),
            actions: [TextButton(onPressed: _load, child: const Text('Refresh'))],
          )
        else if (completionPending)
          MaterialBanner(
            content: const Text('Waiting for customer to confirm and release payment.'),
            actions: [TextButton(onPressed: _load, child: const Text('Refresh'))],
          ),
        const Expanded(
          child: MapPlaceholder(
            hint: 'Navigation preview — add a Google Maps API key later for live maps.',
          ),
        ),
        Container(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          decoration: BoxDecoration(
            color: cs.surface,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.08),
                blurRadius: 12,
                offset: const Offset(0, -4),
              ),
            ],
          ),
          child: SafeArea(
            top: false,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                FilledButton.tonalIcon(
                  onPressed: () {},
                  icon: const Icon(Icons.map_rounded),
                  label: const Text('Open in Google Maps'),
                ),
                const SizedBox(height: 8),
                FilledButton.icon(
                  onPressed: () => context.push('/chat/${widget.jobId}'),
                  icon: const Icon(Icons.chat_rounded),
                  label: const Text('Chat'),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed:
                            (_busy || status == 'IN_PROGRESS' || completionPending || !escrowHeld)
                                ? null
                                : _startWork,
                        child: const Text("I've arrived / Start job"),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => context.push('/extra-cost/${widget.jobId}'),
                        child: const Text('Extra cost'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: cs.secondary),
                  onPressed: (_busy || completionPending || !escrowHeld) ? null : _requestCompletion,
                  child: Text(completionPending ? 'Work done — pending customer' : 'Mark work done'),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDisputeTab(ColorScheme cs) {
    final status = _job?['status'] as String? ?? '';
    final escrowHeld = _job?['escrowHeld'] == true;

    if (status == 'DISPUTED') {
      return ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Icon(Icons.gavel_rounded, size: 48, color: cs.primary),
          const SizedBox(height: 16),
          Text('Dispute open', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 12),
          Text(
            'This job is under dispute. Support will review and either refund the customer or release your share from escrow. You will be notified when it is resolved.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
          ),
        ],
      );
    }

    if (status == 'COMPLETED' || status == 'CANCELLED') {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'This job is closed. Contact support if you still need help.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: cs.onSurfaceVariant),
          ),
        ),
      );
    }

    if (!escrowHeld) {
      return ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Icon(Icons.lock_outline_rounded, size: 40, color: cs.outline),
          const SizedBox(height: 16),
          Text(
            'Payment disputes after the customer pays',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(
            'You can open a dispute once the customer has paid and funds are held in escrow. Until then, use Chat to resolve issues.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
          ),
        ],
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        Text(
          'Describe what went wrong (minimum 10 characters). This is shared with RidDev support.',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _disputeReason,
          minLines: 4,
          maxLines: 10,
          decoration: const InputDecoration(
            labelText: 'What happened?',
            hintText: 'Be specific — e.g. scope disagreement, access issues…',
            border: OutlineInputBorder(),
            alignLabelWithHint: true,
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'Photos (optional)',
          style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 6),
        Text(
          'Add up to $_maxDisputePhotos images as evidence. They are uploaded securely before the dispute is filed.',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
        ),
        const SizedBox(height: 10),
        if (_disputeEvidenceImages.isNotEmpty) ...[
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: List.generate(_disputeEvidenceImages.length, (i) {
              return Stack(
                clipBehavior: Clip.none,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.file(
                      File(_disputeEvidenceImages[i].path),
                      width: 92,
                      height: 92,
                      fit: BoxFit.cover,
                    ),
                  ),
                  Positioned(
                    top: -8,
                    right: -8,
                    child: Material(
                      color: cs.surface,
                      elevation: 1,
                      shape: const CircleBorder(),
                      child: InkWell(
                        customBorder: const CircleBorder(),
                        onTap: _disputeSubmitting ? null : () => _removeDisputePhoto(i),
                        child: Padding(
                          padding: const EdgeInsets.all(4),
                          child: Icon(Icons.close_rounded, size: 18, color: cs.error),
                        ),
                      ),
                    ),
                  ),
                ],
              );
            }),
          ),
          const SizedBox(height: 12),
        ],
        OutlinedButton.icon(
          onPressed: _disputeSubmitting
              ? null
              : () async {
                  await _pickDisputePhotos();
                },
          icon: const Icon(Icons.add_photo_alternate_outlined),
          label: Text(
            _disputeEvidenceImages.isEmpty
                ? 'Choose photos from gallery'
                : 'Add more (${_disputeEvidenceImages.length}/$_maxDisputePhotos)',
          ),
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: _disputeSubmitting ? null : _submitDispute,
          icon: _disputeSubmitting
              ? SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: cs.onPrimary,
                  ),
                )
              : const Icon(Icons.send_rounded),
          label: Text(_disputeSubmitting ? 'Submitting…' : 'Submit dispute'),
        ),
        const SizedBox(height: 16),
        Text(
          'Submitting marks the job as disputed and keeps escrow until an admin refunds the customer or pays you.',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final status = _job?['status'] as String? ?? '';
    final completionPending = _job?['workerRequestedCompletionAt'] != null;
    final escrowHeld = _job?['escrowHeld'] == true;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Active job'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Job'),
            Tab(text: 'Dispute'),
          ],
        ),
        actions: [
          IconButton(
            onPressed: _busy ? null : _load,
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                _buildJobTab(cs, status, completionPending, escrowHeld),
                _buildDisputeTab(cs),
              ],
            ),
    );
  }
}

class ExtraCostRequestScreen extends StatelessWidget {
  const ExtraCostRequestScreen({required this.jobId, super.key});
  final String jobId;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Extra cost')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Request add-on', style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 12),
                    const TextField(
                      decoration: InputDecoration(labelText: 'Amount (GHS)', prefixText: 'GHS '),
                    ),
                    const SizedBox(height: 12),
                    const TextField(
                      decoration: InputDecoration(labelText: 'Reason'),
                      maxLines: 2,
                    ),
                  ],
                ),
              ),
            ),
            const Spacer(),
            FilledButton(onPressed: () => context.pop(), child: const Text('Send for approval')),
          ],
        ),
      ),
    );
  }
}

class WorkerChatScreen extends ConsumerStatefulWidget {
  const WorkerChatScreen({required this.jobId, super.key});
  final String jobId;

  @override
  ConsumerState<WorkerChatScreen> createState() => _WorkerChatScreenState();
}

class _WorkerChatScreenState extends ConsumerState<WorkerChatScreen> {
  final _text = TextEditingController();
  final _scroll = ScrollController();
  List<dynamic> _messages = [];
  String? _myUserId;
  String? _error;
  bool _loading = true;
  bool _sending = false;
  StreamSubscription<Map<String, dynamic>>? _chatSub;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    final api = ref.read(apiClientProvider);
    try {
      final me = await api.getCurrentUser();
      if (!mounted) return;
      _myUserId = me['id'] as String?;
      await ref.read(realtimeClientProvider).connect();
      if (!mounted) return;
      await _load();
      if (!mounted) return;
      final rt = ref.read(realtimeClientProvider);
      rt.joinJob(widget.jobId);
      _chatSub?.cancel();
      _chatSub = rt.onChatMessage.listen((msg) {
        final jid = msg['jobId'] as String?;
        if (jid != widget.jobId) return;
        final mid = msg['id'] as String?;
        if (mid != null &&
            _messages.any((m) => (m as Map)['id'] == mid)) {
          return;
        }
        if (!mounted) return;
        setState(() {
          _messages = [..._messages, msg];
        });
        _scrollToBottom();
      });
    } on DioException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = messageFromDio(e);
        _loading = false;
      });
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await ref.read(apiClientProvider).listChatMessages(widget.jobId);
      if (!mounted) return;
      setState(() {
        _messages = list;
        _loading = false;
      });
      _scrollToBottom();
    } on DioException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = messageFromDio(e);
        _loading = false;
      });
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    });
  }

  Future<void> _send() async {
    final raw = _text.text.trim();
    if (raw.isEmpty) return;
    setState(() => _sending = true);
    try {
      final created = await ref.read(apiClientProvider).sendChatMessage(widget.jobId, raw);
      if (!mounted) return;
      _text.clear();
      setState(() {
        _messages = [..._messages, created];
        _sending = false;
      });
      _scrollToBottom();
    } on DioException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(messageFromDio(e))),
      );
      setState(() => _sending = false);
    }
  }

  @override
  void dispose() {
    _chatSub?.cancel();
    ref.read(realtimeClientProvider).leaveJob(widget.jobId);
    _text.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Chat'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => context.pop(),
        ),
        actions: [
          IconButton(
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: Column(
        children: [
          MaterialBanner(
            content: const Text('Sharing phone numbers or WhatsApp is blocked.'),
            actions: [TextButton(onPressed: () {}, child: const Text('OK'))],
          ),
          Expanded(
            child: _loading
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
                              FilledButton(onPressed: _bootstrap, child: const Text('Retry')),
                            ],
                          ),
                        ),
                      )
                    : _messages.isEmpty
                        ? Center(
                            child: Text(
                              'No messages yet.\nType below and tap send.',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: cs.onSurfaceVariant),
                            ),
                          )
                        : ListView.builder(
                            controller: _scroll,
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            itemCount: _messages.length,
                            itemBuilder: (context, i) {
                              final m = _messages[i] as Map<String, dynamic>;
                              final senderId = m['senderId'] as String?;
                              final mine = _myUserId != null && senderId == _myUserId;
                              final content = m['content'] as String? ?? '';
                              return Align(
                                alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
                                child: Container(
                                  margin: const EdgeInsets.only(bottom: 8),
                                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                  constraints: BoxConstraints(
                                    maxWidth: MediaQuery.sizeOf(context).width * 0.78,
                                  ),
                                  decoration: BoxDecoration(
                                    color: mine ? cs.primaryContainer : cs.surfaceContainerHighest,
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                  child: Text(content, style: TextStyle(color: cs.onSurface)),
                                ),
                              );
                            },
                          ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _text,
                      decoration: const InputDecoration(
                        hintText: 'Message',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _send(),
                      minLines: 1,
                      maxLines: 5,
                    ),
                  ),
                  const SizedBox(width: 4),
                  IconButton.filled(
                    onPressed: _sending ? null : _send,
                    icon: _sending
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.send_rounded),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class EarningsScreen extends ConsumerStatefulWidget {
  const EarningsScreen({super.key});

  @override
  ConsumerState<EarningsScreen> createState() => _EarningsScreenState();
}

class _EarningsScreenState extends ConsumerState<EarningsScreen> {
  int? _walletPesewas;
  int? _earningsTodayPesewas;
  int? _earningsWeekPesewas;
  int? _earningsMonthPesewas;
  List<dynamic> _recent = [];
  String? _loadError;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final w = await ref.read(apiClientProvider).getWallet();
      if (!mounted) return;
      final recent = w['recent'];
      int? parsePesewas(dynamic raw) {
        if (raw is int) return raw;
        if (raw is num) return raw.round();
        return null;
      }
      setState(() {
        _walletPesewas = parsePesewas(w['balancePesewas']);
        _earningsTodayPesewas = parsePesewas(w['earningsTodayPesewas']);
        _earningsWeekPesewas = parsePesewas(w['earningsThisWeekPesewas']);
        _earningsMonthPesewas = parsePesewas(w['earningsThisMonthPesewas']);
        _recent = recent is List ? recent : <dynamic>[];
        _loading = false;
      });
    } on DioException catch (e) {
      if (!mounted) return;
      setState(() {
        _loadError = messageFromDio(e);
        _loading = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _loadError = 'Could not load wallet.';
          _loading = false;
        });
      }
    }
  }

  String _ghs(int? p) =>
      'GHS ${p == null ? '0.00' : (p / 100).toStringAsFixed(2)}';

  Future<void> _withdraw() async {
    final bal = _walletPesewas ?? 0;
    if (bal < 2000) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Minimum withdrawal GHS 20. Earn more first.')),
      );
      return;
    }
    final amount = TextEditingController(text: (bal / 100).toStringAsFixed(2));
    final momo = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Withdraw to MoMo'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: amount,
              decoration: const InputDecoration(labelText: 'Amount (GHS)'),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: momo,
              decoration: const InputDecoration(labelText: 'MoMo number'),
              keyboardType: TextInputType.phone,
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Withdraw')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final ghs = double.tryParse(amount.text.trim());
    if (ghs == null) return;
    final pesewas = (ghs * 100).round();
    if (pesewas < 2000 || pesewas > bal) return;
    try {
      await ref.read(apiClientProvider).withdrawWallet(
            amountPesewas: pesewas,
            momoNumber: momo.text.trim(),
            momoProvider: 'MTN',
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Withdrawal recorded (demo).')));
      await _load();
    } on DioException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(messageFromDio(e))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final today = _earningsTodayPesewas ?? 0;
    final week = _earningsWeekPesewas ?? 0;
    final month = _earningsMonthPesewas ?? 0;
    final preview = _recent.take(4).toList();

    return Scaffold(
      backgroundColor: cs.surfaceContainerLowest,
      appBar: AppBar(
        title: const Text('Earnings'),
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
                    'Loading wallet…',
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
                        Icon(Icons.cloud_off_rounded, size: 52, color: cs.outline),
                        const SizedBox(height: 16),
                        Text(_loadError!, textAlign: TextAlign.center),
                        const SizedBox(height: 16),
                        FilledButton(onPressed: _load, child: const Text('Retry')),
                      ],
                    ),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                    children: [
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(20),
                          gradient: WorkerGradients.earnings,
                          boxShadow: [
                            BoxShadow(
                              color: cs.secondary.withValues(alpha: 0.35),
                              blurRadius: 16,
                              offset: const Offset(0, 8),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Wallet balance',
                              style: tt.labelLarge?.copyWith(color: Colors.white.withValues(alpha: 0.92)),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _ghs(_walletPesewas),
                              style: tt.headlineMedium?.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'Released from jobs lands here. Withdraw to MoMo or keep in-app.',
                              style: TextStyle(color: Colors.white.withValues(alpha: 0.88), fontSize: 13, height: 1.35),
                            ),
                            const SizedBox(height: 12),
                            FilledButton.tonal(
                              onPressed: _withdraw,
                              child: const Text('Withdraw to MoMo'),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 18),
                      Text(
                        'Earnings snapshot',
                        style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.2),
                      ),
                      const SizedBox(height: 10),
                      _EarningsPeriodCard(
                        icon: Icons.wb_sunny_rounded,
                        label: 'Today',
                        amountGhs: _ghs(today),
                        caption: 'Since midnight (UTC)',
                        accent: const Color(0xFFFF8F00),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: _EarningsPeriodCard(
                              icon: Icons.date_range_rounded,
                              label: 'This week',
                              amountGhs: _ghs(week),
                              caption: 'Mon–Sun (UTC)',
                              accent: const Color(0xFFE65100),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _EarningsPeriodCard(
                              icon: Icons.calendar_month_rounded,
                              label: 'This month',
                              amountGhs: _ghs(month),
                              caption: 'Month to date (UTC)',
                              accent: const Color(0xFFF57C00),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'From job payouts & tips credited to your wallet. Withdrawals are separate.',
                        style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant, height: 1.35),
                      ),
                      const SizedBox(height: 20),
                      Material(
                        color: cs.surface,
                        elevation: 1,
                        shadowColor: cs.shadow.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(18),
                        child: InkWell(
                          onTap: () => context.push('/earnings/detail'),
                          borderRadius: BorderRadius.circular(18),
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(14),
                                    gradient: LinearGradient(
                                      colors: [
                                        cs.primaryContainer.withValues(alpha: 0.9),
                                        cs.tertiaryContainer.withValues(alpha: 0.5),
                                      ],
                                    ),
                                  ),
                                  child: Icon(Icons.receipt_long_rounded, color: cs.primary),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Payout history',
                                        style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w800),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        _recent.isEmpty
                                            ? 'No wallet activity yet'
                                            : '${_recent.length} recent ${(_recent.length == 1) ? 'entry' : 'entries'} on file',
                                        style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
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
                      if (preview.isNotEmpty) ...[
                        const SizedBox(height: 20),
                        Text(
                          'Recent activity',
                          style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.2),
                        ),
                        const SizedBox(height: 10),
                        ...preview.map((e) {
                          final m = e as Map<String, dynamic>;
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: _LedgerLinePreviewTile(entry: m),
                          );
                        }),
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton(
                            onPressed: () => context.push('/earnings/detail'),
                            child: const Text('See all activity'),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
    );
  }
}

class _EarningsPeriodCard extends StatelessWidget {
  const _EarningsPeriodCard({
    required this.icon,
    required this.label,
    required this.amountGhs,
    required this.caption,
    required this.accent,
  });

  final IconData icon;
  final String label;
  final String amountGhs;
  final String caption;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        color: cs.surface,
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.5)),
        boxShadow: [
          BoxShadow(
            color: cs.shadow.withValues(alpha: 0.06),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            cs.surface,
            Color.lerp(cs.surface, accent.withValues(alpha: 0.12), 0.85)!,
          ],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 20, color: accent),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  style: tt.labelLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: cs.onSurface,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              amountGhs,
              style: tt.titleLarge?.copyWith(
                fontWeight: FontWeight.w900,
                letterSpacing: -0.5,
                color: cs.onSurface,
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            caption,
            style: tt.bodySmall?.copyWith(
              color: cs.onSurfaceVariant,
              fontSize: 11,
              height: 1.25,
            ),
          ),
        ],
      ),
    );
  }
}

class _LedgerLinePreviewTile extends StatelessWidget {
  const _LedgerLinePreviewTile({required this.entry});

  final Map<String, dynamic> entry;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final dir = entry['direction'] as String? ?? '';
    final credit = dir == 'CREDIT';
    final amount = entry['amountPesewas'] as int? ?? 0;
    final amountLabel = '${credit ? '+' : '−'} GHS ${(amount / 100).toStringAsFixed(2)}';
    final title = _ledgerShortTitle(entry);
    String? when;
    final raw = entry['createdAt'];
    if (raw is String && raw.isNotEmpty) {
      try {
        when = DateFormat('d MMM · HH:mm').format(DateTime.parse(raw).toLocal());
      } catch (_) {}
    }

    return Material(
      color: cs.surface,
      elevation: 0,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: (credit ? cs.primary : cs.error).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                credit ? Icons.south_west_rounded : Icons.north_east_rounded,
                size: 20,
                color: credit ? cs.primary : cs.error,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: tt.bodyMedium?.copyWith(fontWeight: FontWeight.w600, height: 1.25),
                  ),
                  if (when != null)
                    Text(
                      when,
                      style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                    ),
                ],
              ),
            ),
            Text(
              amountLabel,
              style: tt.labelLarge?.copyWith(
                fontWeight: FontWeight.w800,
                color: credit ? cs.primary : cs.error,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _ledgerShortTitle(Map<String, dynamic> e) {
  final d = e['description'] as String?;
  if (d != null && d.trim().isNotEmpty) return d.trim();
  return _ledgerTypeLabel(e['type'] as String? ?? '');
}

String _ledgerTypeLabel(String type) {
  switch (type) {
    case 'JOB_PAYMENT':
      return 'Job payment';
    case 'WITHDRAWAL':
      return 'Withdrawal';
    case 'TOPUP':
      return 'Wallet top-up';
    case 'ESCROW_HOLD':
      return 'Escrow hold';
    case 'ESCROW_RELEASE':
      return 'Escrow release';
    case 'ADMIN_CREDIT':
      return 'Admin credit';
    case 'ADMIN_DEBIT':
      return 'Admin debit';
    case 'REFUND':
      return 'Refund';
    case 'TIP':
      return 'Tip';
    default:
      return type.replaceAll('_', ' ');
  }
}

class PayoutDetailScreen extends ConsumerStatefulWidget {
  const PayoutDetailScreen({super.key});

  @override
  ConsumerState<PayoutDetailScreen> createState() => _PayoutDetailScreenState();
}

class _PayoutDetailScreenState extends ConsumerState<PayoutDetailScreen> {
  List<dynamic> _entries = [];
  int? _balancePesewas;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final w = await ref.read(apiClientProvider).getWallet();
      if (!mounted) return;
      final recent = w['recent'];
      setState(() {
        _balancePesewas = w['balancePesewas'] as int?;
        _entries = recent is List ? recent : <dynamic>[];
        _loading = false;
      });
    } on DioException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = messageFromDio(e);
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not load history.';
        _loading = false;
      });
    }
  }

  String _ghs(int? p) =>
      'GHS ${p == null ? '0.00' : (p / 100).toStringAsFixed(2)}';

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Scaffold(
      backgroundColor: cs.surfaceContainerLowest,
      appBar: AppBar(
        title: const Text('Payout history'),
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
                  Text('Loading…', style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
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
              : RefreshIndicator(
                  onRefresh: _load,
                  child: CustomScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    slivers: [
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                          child: Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(18),
                              gradient: LinearGradient(
                                colors: [
                                  cs.surface,
                                  cs.primaryContainer.withValues(alpha: 0.35),
                                ],
                              ),
                              border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.45)),
                            ),
                            child: Row(
                              children: [
                                Icon(Icons.account_balance_wallet_outlined, color: cs.primary),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Current balance',
                                        style: tt.labelMedium?.copyWith(color: cs.onSurfaceVariant),
                                      ),
                                      Text(
                                        _ghs(_balancePesewas),
                                        style: tt.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      if (_entries.isEmpty)
                        SliverFillRemaining(
                          hasScrollBody: false,
                          child: Center(
                            child: Padding(
                              padding: const EdgeInsets.all(32),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.inbox_outlined, size: 56, color: cs.outline),
                                  const SizedBox(height: 16),
                                  Text(
                                    'No activity yet',
                                    style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    'When you complete jobs and payment is released, entries appear here. Withdrawals show as debits.',
                                    textAlign: TextAlign.center,
                                    style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant, height: 1.45),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        )
                      else
                        SliverPadding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                          sliver: SliverList.separated(
                            itemCount: _entries.length,
                            separatorBuilder: (_, i) => const SizedBox(height: 10),
                            itemBuilder: (context, i) {
                              final e = _entries[i] as Map<String, dynamic>;
                              return _PayoutLedgerDetailCard(entry: e);
                            },
                          ),
                        ),
                    ],
                  ),
                ),
    );
  }
}

class _PayoutLedgerDetailCard extends StatelessWidget {
  const _PayoutLedgerDetailCard({required this.entry});

  final Map<String, dynamic> entry;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final dir = entry['direction'] as String? ?? '';
    final credit = dir == 'CREDIT';
    final amount = entry['amountPesewas'] as int? ?? 0;
    final amountLabel = '${credit ? '+' : '−'} GHS ${(amount / 100).toStringAsFixed(2)}';
    final title = _ledgerShortTitle(entry);
    final typeLabel = _ledgerTypeLabel(entry['type'] as String? ?? '');
    final jobId = entry['jobId'] as String?;
    String? when;
    final raw = entry['createdAt'];
    if (raw is String && raw.isNotEmpty) {
      try {
        when = DateFormat('EEEE, d MMM yyyy · HH:mm').format(DateTime.parse(raw).toLocal());
      } catch (_) {}
    }
    final ref = entry['reference'] as String?;

    return Material(
      color: cs.surface,
      elevation: 2,
      shadowColor: cs.shadow.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(18),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: (credit ? cs.primary : cs.error).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    credit ? Icons.south_west_rounded : Icons.north_east_rounded,
                    color: credit ? cs.primary : cs.error,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w800, height: 1.25),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        typeLabel,
                        style: tt.labelMedium?.copyWith(color: cs.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                Text(
                  amountLabel,
                  style: tt.titleMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                    color: credit ? cs.primary : cs.error,
                  ),
                ),
              ],
            ),
            if (when != null) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  Icon(Icons.schedule_rounded, size: 16, color: cs.outline),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      when,
                      style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                    ),
                  ),
                ],
              ),
            ],
            if (jobId != null && jobId.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                'Job ID: $jobId',
                style: tt.bodySmall?.copyWith(
                  color: cs.onSurfaceVariant,
                  fontFamily: 'monospace',
                  fontSize: 11,
                ),
              ),
            ],
            if (ref != null && ref.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                'Ref: $ref',
                style: tt.bodySmall?.copyWith(
                  color: cs.onSurfaceVariant,
                  fontSize: 11,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

String _workerProfileInitials(String? name) {
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

String _workerTierLabel(String? tierRaw) {
  final t = (tierRaw ?? 'BRONZE').toUpperCase();
  switch (t) {
    case 'GOLD':
      return 'Gold';
    case 'SILVER':
      return 'Silver';
    default:
      return 'Bronze';
  }
}

(Color bg, Color fg) _workerTierChipColors(String? tierRaw) {
  switch ((tierRaw ?? 'BRONZE').toUpperCase()) {
    case 'GOLD':
      return (const Color(0xFFFFC107), const Color(0xFF5D4037));
    case 'SILVER':
      return (const Color(0xFFECEFF1), const Color(0xFF455A64));
    default:
      return (const Color(0xFF8D6E63), Colors.white);
  }
}

class WorkerProfileScreen extends ConsumerStatefulWidget {
  const WorkerProfileScreen({super.key});

  @override
  ConsumerState<WorkerProfileScreen> createState() => _WorkerProfileScreenState();
}

class _WorkerProfileScreenState extends ConsumerState<WorkerProfileScreen> {
  Map<String, dynamic>? _user;
  bool _loading = true;
  String? _error;
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
    try {
      final data = await ref.read(apiClientProvider).getCurrentUser();
      var unreadN = 0;
      var unreadD = 0;
      try {
        final notifs = await ref.read(apiClientProvider).listNotifications();
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
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not load profile.';
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
    final wp = _user?['workerProfile'] as Map<String, dynamic>?;
    final tierRaw = wp?['tier'] as String?;
    final tierLabel = _workerTierLabel(tierRaw);
    final tierColors = _workerTierChipColors(tierRaw);
    final name = _user?['name'] as String? ?? '—';
    final email = _user?['email'] as String? ?? '—';
    final phone = _user?['phone'] as String? ?? '—';
    final photo = _user?['profilePhoto'] as String?;
    final rating = wp?['rating'];
    final jobsDone = wp?['totalJobsCompleted'];
    double? ratingVal;
    if (rating is num) {
      ratingVal = rating.toDouble();
    }

    return Scaffold(
      backgroundColor: cs.surfaceContainerLowest,
      appBar: AppBar(
        title: const Text('My profile'),
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
                          gradient: WorkerGradients.hero,
                          boxShadow: [
                            BoxShadow(
                              color: cs.primary.withValues(alpha: 0.26),
                              blurRadius: 18,
                              offset: const Offset(0, 10),
                            ),
                          ],
                        ),
                        child: Column(
                          children: [
                            Stack(
                              clipBehavior: Clip.none,
                              alignment: Alignment.bottomRight,
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
                                            _workerProfileInitials(name == '—' ? null : name),
                                            style: tt.headlineMedium?.copyWith(
                                              color: cs.primary,
                                              fontWeight: FontWeight.w800,
                                            ),
                                          )
                                        : null,
                                  ),
                                ),
                                Positioned(
                                  bottom: -2,
                                  right: -2,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                    decoration: BoxDecoration(
                                      color: tierColors.$1,
                                      borderRadius: BorderRadius.circular(20),
                                      border: Border.all(color: Colors.white.withValues(alpha: 0.9), width: 2),
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.black.withValues(alpha: 0.15),
                                          blurRadius: 8,
                                        ),
                                      ],
                                    ),
                                    child: Text(
                                      tierLabel,
                                      style: TextStyle(
                                        color: tierColors.$2,
                                        fontSize: 11,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
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
                                'Worker',
                                style: tt.labelLarge?.copyWith(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            if (ratingVal != null || jobsDone != null) ...[
                              const SizedBox(height: 12),
                              Text(
                                [
                                  if (ratingVal != null) '★ ${ratingVal.toStringAsFixed(1)} rating',
                                  if (jobsDone != null) '$jobsDone jobs completed',
                                ].join(' · '),
                                textAlign: TextAlign.center,
                                style: tt.bodySmall?.copyWith(
                                  color: Colors.white.withValues(alpha: 0.92),
                                  height: 1.35,
                                ),
                              ),
                            ],
                            const SizedBox(height: 12),
                            Text(
                              'Reviews, documents, and settings — all in one place.',
                              textAlign: TextAlign.center,
                              style: tt.bodySmall?.copyWith(
                                color: Colors.white.withValues(alpha: 0.88),
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
                      _WorkerProfileInfoCard(
                        rows: [
                          _WorkerProfileInfoRow(icon: Icons.badge_outlined, label: 'Name', value: name),
                          _WorkerProfileInfoRow(icon: Icons.email_outlined, label: 'Email', value: email),
                          _WorkerProfileInfoRow(icon: Icons.phone_outlined, label: 'Phone', value: phone),
                        ],
                      ),
                      const SizedBox(height: 22),
                      Text(
                        'Shortcuts',
                        style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 10),
                      _WorkerProfileLinkTile(
                        icon: Icons.reviews_outlined,
                        iconBg: cs.primaryContainer,
                        iconFg: cs.primary,
                        title: 'Reviews',
                        subtitle: 'What customers say about you',
                        onTap: () => context.push('/my-reviews'),
                      ),
                      const SizedBox(height: 10),
                      _WorkerProfileLinkTile(
                        icon: Icons.folder_open_outlined,
                        iconBg: cs.tertiaryContainer,
                        iconFg: cs.tertiary,
                        title: 'Documents',
                        subtitle: 'ID and certifications',
                        onTap: () => context.push('/my-documents'),
                      ),
                      const SizedBox(height: 10),
                      _WorkerProfileLinkTile(
                        icon: Icons.notifications_outlined,
                        iconBg: cs.secondaryContainer,
                        iconFg: cs.secondary,
                        title: 'Notifications',
                        subtitle: 'Alerts & dispute updates',
                        badgeCount: _unreadNotifications,
                        onTap: () async {
                          await context.push('/notifications');
                          if (mounted) await _load();
                        },
                      ),
                      const SizedBox(height: 10),
                      _WorkerProfileLinkTile(
                        icon: Icons.gavel_rounded,
                        iconBg: cs.errorContainer,
                        iconFg: cs.error,
                        title: 'Disputes',
                        subtitle: 'Your disputes & chat with support',
                        badgeCount: _unreadDisputeMessages,
                        onTap: () async {
                          await context.push('/my-disputes');
                          if (mounted) await _load();
                        },
                      ),
                      const SizedBox(height: 10),
                      _WorkerProfileLinkTile(
                        icon: Icons.settings_outlined,
                        iconBg: cs.surfaceContainerHighest,
                        iconFg: cs.onSurfaceVariant,
                        title: 'Settings',
                        subtitle: 'App & API preferences',
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

class _WorkerProfileInfoRow {
  const _WorkerProfileInfoRow({
    required this.icon,
    required this.label,
    required this.value,
  });
  final IconData icon;
  final String label;
  final String value;
}

class _WorkerProfileInfoCard extends StatelessWidget {
  const _WorkerProfileInfoCard({required this.rows});

  final List<_WorkerProfileInfoRow> rows;

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

class _WorkerProfileLinkTile extends StatelessWidget {
  const _WorkerProfileLinkTile({
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

class MyReviewsScreen extends StatelessWidget {
  const MyReviewsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Reviews')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.star_border_rounded, size: 64, color: cs.outline),
              const SizedBox(height: 16),
              Text('No reviews yet', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              Text(
                'Complete jobs to build your rating.',
                textAlign: TextAlign.center,
                style: TextStyle(color: cs.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class WorkerDocumentsScreen extends StatelessWidget {
  const WorkerDocumentsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Documents')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'National ID & certifications',
            style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
        ),
      ),
    );
  }
}

class WorkerNotificationsScreen extends ConsumerStatefulWidget {
  const WorkerNotificationsScreen({super.key});

  @override
  ConsumerState<WorkerNotificationsScreen> createState() => _WorkerNotificationsScreenState();
}

class _WorkerNotificationsScreenState extends ConsumerState<WorkerNotificationsScreen> {
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
                          title: Text(
                            title,
                            style: TextStyle(fontWeight: read ? FontWeight.normal : FontWeight.w600),
                          ),
                          subtitle: Text(body),
                          trailing: tappable ? const Icon(Icons.chevron_right_rounded) : null,
                          onTap: !tappable
                              ? null
                              : () {
                                  if (disputeId != null) {
                                    context.push('/dispute/$disputeId');
                                  } else if (jobId != null) {
                                    context.push('/job/$jobId');
                                  }
                                },
                        );
                      },
                    ),
    );
  }
}

class WorkerSettingsScreen extends ConsumerStatefulWidget {
  const WorkerSettingsScreen({super.key});

  @override
  ConsumerState<WorkerSettingsScreen> createState() => _WorkerSettingsScreenState();
}

class _WorkerSettingsScreenState extends ConsumerState<WorkerSettingsScreen> {
  final _apiUrl = TextEditingController();
  bool _loadingPrefs = true;

  @override
  void initState() {
    super.initState();
    _loadApiOverride();
  }

  Future<void> _loadApiOverride() async {
    final v = await getWorkerApiBaseUrlOverride();
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
    await saveWorkerApiBaseUrlOverride(raw.isEmpty ? null : raw);
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
            'If the dashboard shows “Cannot reach the API”, set your PC\'s LAN URL here (same Wi‑Fi), '
            'e.g. http://192.168.1.50:4000. Leave blank for the default (emulator: http://10.0.2.2:4000).',
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
          const ListTile(
            leading: Icon(Icons.language),
            title: Text('Language'),
            subtitle: Text('English'),
          ),
          const ListTile(
            leading: Icon(Icons.schedule),
            title: Text('Time zone'),
            subtitle: Text('Africa/Accra'),
          ),
        ],
      ),
    );
  }
}

class WorkerDisputeCentreScreen extends StatelessWidget {
  const WorkerDisputeCentreScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Disputes')),
      body: Center(
        child: Text(
          'Raise or respond to disputes',
          style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
      ),
    );
  }
}
