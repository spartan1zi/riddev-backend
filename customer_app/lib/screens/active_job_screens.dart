import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/api_client.dart';
import '../providers/auth_provider.dart';
import '../providers/realtime_provider.dart';
import '../widgets/map_placeholder.dart';

class ActiveJobScreen extends ConsumerStatefulWidget {
  const ActiveJobScreen({
    required this.jobId,
    this.fromPayment = false,
    super.key,
  });

  final String jobId;
  /// After paying, [Navigator] stack is cleared — back must return to job history.
  final bool fromPayment;

  @override
  ConsumerState<ActiveJobScreen> createState() => _ActiveJobScreenState();
}

class _ActiveJobScreenState extends ConsumerState<ActiveJobScreen> {
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

  void _onBack() {
    if (widget.fromPayment) {
      context.go('/history');
    } else {
      context.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    final title = _job?['title'] as String? ?? 'Active job';
    final worker = _job?['worker'] as Map<String, dynamic>?;
    final workerName = worker?['name'] as String? ?? 'Worker';
    final workerRequestedCompletion = _job?['workerRequestedCompletionAt'] != null;
    final escrowHeld = _job?['escrowHeld'] == true;

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: _onBack,
          tooltip: 'Back',
        ),
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
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (!escrowHeld)
                      MaterialBanner(
                        content: const Text(
                          'Payment is not in escrow yet. Complete checkout so funds are held — then your worker can track the job and mark work done.',
                        ),
                        actions: [
                          TextButton(
                            onPressed: () =>
                                context.push('/payment/${widget.jobId}'),
                            child: const Text('Pay now'),
                          ),
                          TextButton(onPressed: _load, child: const Text('Refresh')),
                        ],
                      )
                    else if (workerRequestedCompletion)
                      MaterialBanner(
                        content: const Text(
                          'Your worker marked the job complete. Tap below to confirm and release payment.',
                        ),
                        actions: [TextButton(onPressed: _load, child: const Text('Refresh'))],
                      ),
                    if (escrowHeld)
                      ListTile(
                        leading: CircleAvatar(
                          backgroundColor: cs.primaryContainer,
                          child: Icon(Icons.person_rounded, color: cs.onPrimaryContainer),
                        ),
                        title: Text(workerName, style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
                        subtitle: Text('Chat with your tradesperson', style: TextStyle(color: cs.onSurfaceVariant)),
                        trailing: FilledButton.tonal(
                          onPressed: () => context.push('/chat/${widget.jobId}'),
                          child: const Text('Chat'),
                        ),
                      ),
                    const Expanded(
                      child: MapPlaceholder(
                        hint: 'Live worker location can be shown here when Maps is enabled.',
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                      child: Text(
                        !escrowHeld
                            ? 'Finish payment first. “Held in escrow” must be true before the worker can mark done.'
                            : workerRequestedCompletion
                                ? 'Next: open Confirm job complete and release payment.'
                                : 'Escrow is set. Ask your worker to tap “Mark work done”, then confirm here (Refresh if needed).',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      child: !escrowHeld
                          ? FilledButton.icon(
                              onPressed: () =>
                                  context.push('/payment/${widget.jobId}'),
                              icon: const Icon(Icons.payments_rounded),
                              label: const Text('Complete payment'),
                            )
                          : workerRequestedCompletion
                              ? FilledButton.icon(
                                  onPressed: () => context.push(
                                      '/job-complete/${widget.jobId}'),
                                  icon: const Icon(Icons.task_alt_rounded),
                                  label: const Text('Confirm job complete'),
                                )
                              : const SizedBox.shrink(),
                    ),
                  ],
                ),
    );
  }
}

class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({required this.jobId, super.key});
  final String jobId;

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final _text = TextEditingController();
  final _scroll = ScrollController();
  List<dynamic> _messages = [];
  String? _myUserId;
  String? _error;
  bool _loading = true;
  bool _sending = false;
  bool _paymentBlocked = false;
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
        _paymentBlocked = false;
      });
      _scrollToBottom();
    } on DioException catch (e) {
      if (!mounted) return;
      final code = e.response?.data is Map
          ? (e.response!.data as Map)['code'] as String?
          : null;
      final blocked = e.response?.statusCode == 403 && code == 'PAYMENT_REQUIRED';
      setState(() {
        _paymentBlocked = blocked;
        _error = blocked ? null : messageFromDio(e);
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
    final tt = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Chat'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => context.pop(),
          tooltip: 'Back',
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
          const MaterialBanner(
            content: Text('Phone numbers and off-platform contact are blocked.'),
            actions: [SizedBox()],
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _paymentBlocked
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.lock_outline_rounded, size: 48, color: cs.primary),
                              const SizedBox(height: 16),
                              Text(
                                'Complete payment first',
                                style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w600),
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 10),
                              Text(
                                'Funds must be held in escrow before you can message your worker.',
                                textAlign: TextAlign.center,
                                style: TextStyle(color: cs.onSurfaceVariant, height: 1.35),
                              ),
                              const SizedBox(height: 20),
                              FilledButton.icon(
                                onPressed: () =>
                                    context.push('/payment/${widget.jobId}'),
                                icon: const Icon(Icons.payments_rounded),
                                label: const Text('Complete payment'),
                              ),
                            ],
                          ),
                        ),
                      )
                    : _error != null
                        ? Center(
                            child: Padding(
                              padding: const EdgeInsets.all(24),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(_error!, textAlign: TextAlign.center),
                                  const SizedBox(height: 16),
                                  FilledButton(
                                      onPressed: _bootstrap,
                                      child: const Text('Retry')),
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
          if (!_paymentBlocked)
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _text,
                        enabled: !_loading && _error == null,
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
                      onPressed: (_sending || _loading || _error != null) ? null : _send,
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

class JobCompleteScreen extends ConsumerStatefulWidget {
  const JobCompleteScreen({required this.jobId, super.key});
  final String jobId;

  @override
  ConsumerState<JobCompleteScreen> createState() => _JobCompleteScreenState();
}

class _JobCompleteScreenState extends ConsumerState<JobCompleteScreen> {
  Map<String, dynamic>? _job;
  String? _error;
  bool _loading = true;
  bool _submitting = false;
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

  Future<void> _confirmRelease() async {
    setState(() => _submitting = true);
    try {
      await ref.read(apiClientProvider).releaseEscrowPayment(widget.jobId);
      if (!mounted) return;
      context.push('/review/${widget.jobId}');
    } on DioException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(messageFromDio(e))),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  String _explainForCustomer() {
    final escrowHeld = _job?['escrowHeld'] == true;
    final workerRequested = _job?['workerRequestedCompletionAt'] != null;
    if (!escrowHeld) {
      return 'Your payment is not held in escrow yet. Complete the Paystack payment flow first. '
          'Until escrow shows as active, your worker cannot tap “Mark work done”. '
          'After payment is held, they mark done, then you return here and tap **Confirm & release payment**.';
    }
    if (!workerRequested) {
      return 'Funds are in escrow. Ask your worker to open this job in the **worker app** and tap **Mark work done**. '
          'Then press **Refresh** here if the button stays disabled.';
    }
    return 'The worker marked this job as done. Confirm to release payment from escrow.';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final workerRequested = _job?['workerRequestedCompletionAt'] != null;
    final escrowHeld = _job?['escrowHeld'] == true;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Complete job'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => context.pop(),
          tooltip: 'Back',
        ),
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
              : Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Icon(Icons.handshake_outlined, size: 56, color: cs.primary),
                      const SizedBox(height: 16),
                      Text(
                        _explainForCustomer(),
                        textAlign: TextAlign.center,
                        style: TextStyle(color: cs.onSurfaceVariant, height: 1.4),
                      ),
                      const Spacer(),
                      FilledButton(
                        onPressed: (!escrowHeld || !workerRequested || _submitting) ? null : _confirmRelease,
                        child: _submitting
                            ? const SizedBox(
                                height: 22,
                                width: 22,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Text('Confirm & release payment'),
                      ),
                    ],
                  ),
                ),
    );
  }
}

class RateWorkerScreen extends StatelessWidget {
  const RateWorkerScreen({required this.jobId, super.key});
  final String jobId;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Rate worker'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => context.pop(),
          tooltip: 'Back',
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.star, size: 40),
                Icon(Icons.star, size: 40),
                Icon(Icons.star, size: 40),
                Icon(Icons.star, size: 40),
                Icon(Icons.star_border, size: 40),
              ],
            ),
            const SizedBox(height: 16),
            const TextField(decoration: InputDecoration(labelText: 'Written review'), maxLines: 3),
            const Spacer(),
            FilledButton(
              onPressed: () => context.go('/history'),
              child: const Text('Submit'),
            ),
          ],
        ),
      ),
    );
  }
}
