import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../core/api_client.dart';
import '../core/notification_utils.dart';
import '../providers/auth_provider.dart';
import '../providers/realtime_provider.dart';

String _disputeStatusLabel(String raw) {
  switch (raw.toUpperCase()) {
    case 'OPEN':
      return 'Open';
    case 'UNDER_REVIEW':
      return 'Under review';
    case 'RESOLVED':
      return 'Resolved';
    default:
      return raw.replaceAll('_', ' ');
  }
}

Color _disputeStatusAccent(ColorScheme cs, String raw) {
  switch (raw.toUpperCase()) {
    case 'OPEN':
      return cs.primary;
    case 'UNDER_REVIEW':
      return cs.tertiary;
    case 'RESOLVED':
      return cs.secondary;
    default:
      return cs.outline;
  }
}

String _formatMessageTime(dynamic createdAt) {
  if (createdAt is! String) return '';
  try {
    return DateFormat.jm().format(DateTime.parse(createdAt).toLocal());
  } catch (_) {
    return '';
  }
}

String _senderRoleLabel(String role) {
  switch (role) {
    case 'ADMIN':
      return 'Support';
    case 'CUSTOMER':
      return 'Customer';
    case 'WORKER':
      return 'Worker';
    default:
      return role;
  }
}

/// Which channel is shown in the dispute thread (support tab is default).
enum _DisputeChannelTab { support, everyone }

/// List of disputes linked to this worker (raised by them or on their jobs).
class MyDisputesScreen extends ConsumerStatefulWidget {
  const MyDisputesScreen({super.key});

  @override
  ConsumerState<MyDisputesScreen> createState() => _MyDisputesScreenState();
}

class _MyDisputesScreenState extends ConsumerState<MyDisputesScreen> {
  List<dynamic> _rows = [];
  Map<String, int> _unreadByDispute = {};
  bool _loading = true;
  String? _error;
  StreamSubscription<void>? _notifSocketSub;

  @override
  void initState() {
    super.initState();
    _notifSocketSub = ref.read(realtimeClientProvider).onNotificationsUpdated.listen((_) {
      if (mounted) _load();
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

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await ref.read(apiClientProvider).listMyDisputes();
      Map<String, int> byD = {};
      try {
        final notifs = await ref.read(apiClientProvider).listNotifications();
        byD = unreadDisputeMessageCountsByDispute(notifs);
      } catch (_) {}
      if (!mounted) return;
      setState(() {
        _rows = list;
        _unreadByDispute = byD;
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

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        title: const Text('Disputes'),
        surfaceTintColor: Colors.transparent,
        actions: [
          IconButton(
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              cs.primaryContainer.withValues(alpha: 0.12),
              cs.surface,
            ],
          ),
        ),
        child: _loading
            ? Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SizedBox(
                      width: 36,
                      height: 36,
                      child: CircularProgressIndicator(
                        strokeWidth: 3,
                        color: cs.primary,
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'Loading disputes…',
                      style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
                    ),
                  ],
                ),
              )
            : _error != null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(28),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.cloud_off_rounded, size: 56, color: cs.outline),
                          const SizedBox(height: 16),
                          Text(
                            _error!,
                            textAlign: TextAlign.center,
                            style: tt.bodyLarge,
                          ),
                          const SizedBox(height: 20),
                          FilledButton.icon(
                            onPressed: _load,
                            icon: const Icon(Icons.refresh_rounded),
                            label: const Text('Try again'),
                          ),
                        ],
                      ),
                    ),
                  )
                : RefreshIndicator(
                    color: cs.primary,
                    onRefresh: _load,
                    child: CustomScrollView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      slivers: [
                        if (_rows.isEmpty)
                          SliverFillRemaining(
                            hasScrollBody: false,
                            child: Padding(
                              padding: const EdgeInsets.all(32),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.inbox_rounded,
                                    size: 72,
                                    color: cs.outline.withValues(alpha: 0.7),
                                  ),
                                  const SizedBox(height: 20),
                                  Text(
                                    'No disputes yet',
                                    style: tt.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                                    textAlign: TextAlign.center,
                                  ),
                                  const SizedBox(height: 12),
                                  Text(
                                    'When a dispute is opened on a job with funds in escrow, it will appear here. Chat with support and the customer from one thread.',
                                    textAlign: TextAlign.center,
                                    style: tt.bodyMedium?.copyWith(
                                      color: cs.onSurfaceVariant,
                                      height: 1.45,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          )
                        else ...[
                          SliverPadding(
                            padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
                            sliver: SliverToBoxAdapter(
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.chat_bubble_outline_rounded,
                                    size: 20,
                                    color: cs.primary,
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      'Open a thread to message support and follow the dispute.',
                                      style: tt.bodySmall?.copyWith(
                                        color: cs.onSurfaceVariant,
                                        height: 1.35,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          SliverPadding(
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 28),
                            sliver: SliverList.separated(
                              itemCount: _rows.length,
                              separatorBuilder: (_, __) => const SizedBox(height: 12),
                              itemBuilder: (context, i) {
                                final j = _rows[i] as Map<String, dynamic>;
                                final id = j['id'] as String? ?? '';
                                final job = j['job'] as Map<String, dynamic>?;
                                final title = job?['title'] as String? ?? 'Dispute';
                                final statusRaw = j['status'] as String? ?? '';
                                final accent = _disputeStatusAccent(cs, statusRaw);
                                final reason = (j['reason'] as String? ?? '').trim();
                                final preview =
                                    reason.length > 100 ? '${reason.substring(0, 100)}…' : reason;
                                final unread = _unreadByDispute[id] ?? 0;
                                return Material(
                                  elevation: 0,
                                  color: Colors.transparent,
                                  child: InkWell(
                                    onTap: id.isEmpty
                                        ? null
                                        : () async {
                                            await context.push('/dispute/$id');
                                            if (mounted) await _load();
                                          },
                                    borderRadius: BorderRadius.circular(20),
                                    child: Ink(
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(20),
                                        border: Border.all(
                                          color: cs.outlineVariant.withValues(alpha: 0.45),
                                        ),
                                        gradient: LinearGradient(
                                          begin: Alignment.topLeft,
                                          end: Alignment.bottomRight,
                                          colors: [
                                            cs.surfaceContainerHighest.withValues(alpha: 0.65),
                                            cs.surface.withValues(alpha: 0.95),
                                          ],
                                        ),
                                        boxShadow: [
                                          BoxShadow(
                                            color: cs.shadow.withValues(alpha: 0.06),
                                            blurRadius: 16,
                                            offset: const Offset(0, 6),
                                          ),
                                        ],
                                      ),
                                      child: Padding(
                                        padding: const EdgeInsets.all(16),
                                        child: Row(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Stack(
                                              clipBehavior: Clip.none,
                                              children: [
                                                Container(
                                                  width: 48,
                                                  height: 48,
                                                  decoration: BoxDecoration(
                                                    color: accent.withValues(alpha: 0.18),
                                                    borderRadius: BorderRadius.circular(14),
                                                  ),
                                                  child: Icon(
                                                    Icons.gavel_rounded,
                                                    color: accent,
                                                    size: 26,
                                                  ),
                                                ),
                                                if (unread > 0)
                                                  Positioned(
                                                    right: -6,
                                                    top: -6,
                                                    child: Badge(
                                                      label: Text(unread > 9 ? '9+' : '$unread'),
                                                      backgroundColor: cs.error,
                                                    ),
                                                  ),
                                              ],
                                            ),
                                            const SizedBox(width: 14),
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  Row(
                                                    crossAxisAlignment: CrossAxisAlignment.start,
                                                    children: [
                                                      Expanded(
                                                        child: Text(
                                                          title,
                                                          maxLines: 2,
                                                          overflow: TextOverflow.ellipsis,
                                                          style: tt.titleSmall?.copyWith(
                                                            fontWeight: FontWeight.w800,
                                                            height: 1.25,
                                                          ),
                                                        ),
                                                      ),
                                                      const SizedBox(width: 8),
                                                      Container(
                                                        padding: const EdgeInsets.symmetric(
                                                          horizontal: 10,
                                                          vertical: 4,
                                                        ),
                                                        decoration: BoxDecoration(
                                                          color: accent.withValues(alpha: 0.2),
                                                          borderRadius: BorderRadius.circular(20),
                                                        ),
                                                        child: Text(
                                                          _disputeStatusLabel(statusRaw),
                                                          style: tt.labelSmall?.copyWith(
                                                            fontWeight: FontWeight.w700,
                                                            color: accent,
                                                            letterSpacing: 0.2,
                                                          ),
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                  if (preview.isNotEmpty) ...[
                                                    const SizedBox(height: 8),
                                                    Text(
                                                      preview,
                                                      maxLines: 2,
                                                      overflow: TextOverflow.ellipsis,
                                                      style: tt.bodySmall?.copyWith(
                                                        color: cs.onSurfaceVariant,
                                                        height: 1.35,
                                                      ),
                                                    ),
                                                  ],
                                                  const SizedBox(height: 10),
                                                  Row(
                                                    children: [
                                                      Text(
                                                        'Open chat',
                                                        style: tt.labelLarge?.copyWith(
                                                          color: cs.primary,
                                                          fontWeight: FontWeight.w700,
                                                        ),
                                                      ),
                                                      const SizedBox(width: 4),
                                                      Icon(
                                                        Icons.arrow_forward_ios_rounded,
                                                        size: 12,
                                                        color: cs.primary,
                                                      ),
                                                    ],
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
      ),
    );
  }
}

/// Shared thread with admin + other party (worker messaging in their app).
class DisputeThreadScreen extends ConsumerStatefulWidget {
  const DisputeThreadScreen({required this.disputeId, super.key});

  final String disputeId;

  @override
  ConsumerState<DisputeThreadScreen> createState() => _DisputeThreadScreenState();
}

class _DisputeThreadScreenState extends ConsumerState<DisputeThreadScreen> {
  final _text = TextEditingController();
  final _scroll = ScrollController();
  List<dynamic> _messagesPrivate = [];
  List<dynamic> _messagesEveryone = [];
  _DisputeChannelTab _tab = _DisputeChannelTab.support;
  Map<String, dynamic>? _disputeMeta;
  String? _myUserId;
  bool _loading = true;
  bool _sending = false;
  String? _error;
  bool _everyoneChannelEnabled = false;
  bool _disputeChatLocked = false;
  StreamSubscription<Map<String, dynamic>>? _disputeSub;
  StreamSubscription<Map<String, dynamic>>? _disputeSettingsSub;
  final List<XFile> _pendingImages = [];
  static const int _maxChatImages = 5;

  List<dynamic> get _activeMessages =>
      _tab == _DisputeChannelTab.support ? _messagesPrivate : _messagesEveryone;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    await ref.read(realtimeClientProvider).connect();
    try {
      final me = await ref.read(apiClientProvider).getCurrentUser();
      if (!mounted) return;
      final id = me['id'];
      if (id is String) setState(() => _myUserId = id);
    } catch (_) {}
    ref.read(realtimeClientProvider).joinDispute(widget.disputeId);
    _disputeSub = ref.read(realtimeClientProvider).onDisputeMessage.listen((data) {
      final did = data['disputeId'] as String?;
      if (did != widget.disputeId || !mounted) return;
      _loadMessages();
    });
    _disputeSettingsSub = ref.read(realtimeClientProvider).onDisputeChatSettings.listen((_) {
      if (!mounted) return;
      _loadMessages();
    });
    await _loadMeta();
    await _loadMessages();
  }

  Future<void> _loadMeta() async {
    try {
      final d = await ref.read(apiClientProvider).getDispute(widget.disputeId);
      if (!mounted) return;
      setState(() => _disputeMeta = d);
    } on DioException catch (e) {
      if (!mounted) return;
      setState(() => _error = messageFromDio(e));
    }
  }

  Future<void> _loadMessages() async {
    try {
      final bundle = await ref.read(apiClientProvider).fetchDisputeThreadMessages(widget.disputeId);
      if (!mounted) return;
      setState(() {
        _messagesPrivate = bundle.privateChannelMessages;
        _messagesEveryone = bundle.everyoneChannelMessages;
        _everyoneChannelEnabled = bundle.everyoneChannelEnabled;
        _disputeChatLocked = bundle.disputeChatLocked;
        _loading = false;
        _error = null;
      });
      _scrollToBottom();
      _markDisputeNotificationsRead();
    } on DioException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = messageFromDio(e);
        _loading = false;
      });
    }
  }

  Future<void> _markDisputeNotificationsRead() async {
    try {
      final list = await ref.read(apiClientProvider).listNotifications();
      final ids = <String>[];
      for (final n in list) {
        if (n['isRead'] == true) continue;
        if (n['type'] != 'dispute_message') continue;
        final data = n['data'];
        if (data is! Map || data['disputeId'] != widget.disputeId) continue;
        final nid = n['id'];
        if (nid is String) ids.add(nid);
      }
      if (ids.isEmpty) return;
      await ref.read(apiClientProvider).markNotificationsRead(ids: ids);
    } catch (_) {}
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    });
  }

  bool get _showMessageComposer {
    if (_disputeChatLocked) return false;
    if (_tab == _DisputeChannelTab.everyone && !_everyoneChannelEnabled) return false;
    return true;
  }

  bool get _canSendMessages => _showMessageComposer;

  String get _sendChannel =>
      _tab == _DisputeChannelTab.everyone ? 'ALL' : 'ADMIN_WORKER';

  Future<void> _pickImages() async {
    final picker = ImagePicker();
    final list = await picker.pickMultiImage(imageQuality: 82);
    if (!mounted || list.isEmpty) return;
    final room = _maxChatImages - _pendingImages.length;
    if (room <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Maximum $_maxChatImages images per message.')),
      );
      return;
    }
    setState(() => _pendingImages.addAll(list.take(room)));
  }

  Future<void> _send() async {
    if (!_canSendMessages) return;
    final body = _text.text.trim();
    if (body.isEmpty && _pendingImages.isEmpty) return;
    setState(() => _sending = true);
    try {
      List<String> urls = [];
      if (_pendingImages.isNotEmpty) {
        final paths = _pendingImages.map((x) => x.path).toList();
        urls = await ref.read(apiClientProvider).uploadDisputeEvidence(paths);
      }
      await ref.read(apiClientProvider).postDisputeMessage(
            disputeId: widget.disputeId,
            body: body,
            imageUrls: urls,
            channel: _sendChannel,
          );
      if (!mounted) return;
      _text.clear();
      setState(() => _pendingImages.clear());
      await _loadMessages();
    } on DioException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(messageFromDio(e))),
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Widget _messageBubble(Map<String, dynamic> m) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final sender = m['sender'] as Map<String, dynamic>?;
    final senderId = sender?['id'] as String?;
    final name = sender?['name'] as String? ?? '?';
    final role = sender?['role'] as String? ?? '';
    final body = m['body'] as String? ?? '';
    final imgs = m['imageUrls'];
    final listUrls = imgs is List ? imgs.map((e) => e.toString()).toList() : <String>[];
    final isAdmin = role == 'ADMIN';
    final isMine = _myUserId != null && senderId == _myUserId;
    final timeStr = _formatMessageTime(m['createdAt']);

    final bubbleColor = isMine
        ? cs.primaryContainer.withValues(alpha: 0.88)
        : isAdmin
            ? cs.tertiaryContainer.withValues(alpha: 0.55)
            : cs.surfaceContainerHighest.withValues(alpha: 0.7);

    final borderColor =
        isMine ? cs.primary.withValues(alpha: 0.24) : cs.outlineVariant.withValues(alpha: 0.42);

    return Align(
      alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.88),
        child: Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: bubbleColor,
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(18),
              topRight: const Radius.circular(18),
              bottomLeft: Radius.circular(isMine ? 18 : 4),
              bottomRight: Radius.circular(isMine ? 4 : 18),
            ),
            border: Border.all(color: borderColor),
            boxShadow: [
              BoxShadow(
                color: cs.shadow.withValues(alpha: 0.05),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: isMine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (!isMine) ...[
                    Icon(
                      isAdmin ? Icons.support_agent_rounded : Icons.person_outline_rounded,
                      size: 16,
                      color: cs.onSurfaceVariant,
                    ),
                    const SizedBox(width: 6),
                  ],
                  Flexible(
                    child: Text(
                      isMine ? 'You' : '$name · ${_senderRoleLabel(role)}',
                      style: tt.labelMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: isAdmin && !isMine ? cs.tertiary : cs.onSurface,
                      ),
                    ),
                  ),
                  if (timeStr.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    Text(
                      timeStr,
                      style: tt.labelSmall?.copyWith(color: cs.onSurfaceVariant),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 6),
              if (body.isNotEmpty && body != '(Images attached)')
                Text(body, style: tt.bodyMedium?.copyWith(height: 1.38)),
              if (listUrls.isNotEmpty)
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  alignment: isMine ? WrapAlignment.end : WrapAlignment.start,
                  children: listUrls
                      .map(
                        (u) => ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: Image.network(
                            u,
                            width: 96,
                            height: 96,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => const SizedBox(
                              width: 96,
                              height: 96,
                              child: Icon(Icons.broken_image_outlined),
                            ),
                          ),
                        ),
                      )
                      .toList(),
                ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _disputeSub?.cancel();
    _disputeSettingsSub?.cancel();
    ref.read(realtimeClientProvider).leaveDispute(widget.disputeId);
    _text.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final title = _disputeMeta?['job'] != null
        ? ((_disputeMeta!['job'] as Map)['title'] as String? ?? 'Dispute')
        : 'Dispute';

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        surfaceTintColor: Colors.transparent,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            Text(
              'Dispute chat',
              style: tt.labelSmall?.copyWith(color: cs.onSurfaceVariant, fontWeight: FontWeight.w500),
            ),
          ],
        ),
        actions: [
          IconButton(
            onPressed: () async {
              await _loadMeta();
              await _loadMessages();
            },
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: Column(
        children: [
          if (_error != null && _messagesPrivate.isEmpty && _messagesEveryone.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Material(
                color: cs.errorContainer.withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(12),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      Icon(Icons.error_outline_rounded, color: cs.error, size: 22),
                      const SizedBox(width: 10),
                      Expanded(child: Text(_error!, style: TextStyle(color: cs.onErrorContainer))),
                    ],
                  ),
                ),
              ),
            ),
          if (_disputeChatLocked)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
              child: Material(
                color: cs.errorContainer.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(14),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.lock_outline_rounded, color: cs.error, size: 22),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'This dispute chat has been locked by admin. Please wait for further instructions.',
                          style: tt.bodySmall?.copyWith(
                            color: cs.onErrorContainer,
                            fontWeight: FontWeight.w600,
                            height: 1.35,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          if (!_disputeChatLocked &&
              _tab == _DisputeChannelTab.everyone &&
              !_everyoneChannelEnabled)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
              child: Material(
                color: cs.primaryContainer.withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(14),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.visibility_outlined, color: cs.primary, size: 22),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Admin has posted here. You can read but cannot reply until discussion is opened.',
                          style: tt.bodySmall?.copyWith(
                            color: cs.onPrimaryContainer.withValues(alpha: 0.92),
                            height: 1.35,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: SegmentedButton<_DisputeChannelTab>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(
                  value: _DisputeChannelTab.support,
                  label: Text('You & support'),
                  icon: Icon(Icons.support_agent_rounded, size: 18),
                ),
                ButtonSegment(
                  value: _DisputeChannelTab.everyone,
                  label: Text('Everyone'),
                  icon: Icon(Icons.groups_rounded, size: 18),
                ),
              ],
              selected: {_tab},
              onSelectionChanged: (Set<_DisputeChannelTab> next) {
                if (next.isEmpty) return;
                setState(() => _tab = next.first);
                _scrollToBottom();
              },
            ),
          ),
          Expanded(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    cs.surfaceContainerLowest.withValues(alpha: 0.95),
                    cs.surface,
                  ],
                ),
              ),
              child: _loading
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          SizedBox(
                            width: 32,
                            height: 32,
                            child: CircularProgressIndicator(color: cs.primary, strokeWidth: 3),
                          ),
                          const SizedBox(height: 14),
                          Text(
                            'Loading messages…',
                            style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
                          ),
                        ],
                      ),
                    )
                  : _activeMessages.isEmpty
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(32),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.chat_bubble_outline_rounded,
                                  size: 56,
                                  color: cs.outline.withValues(alpha: 0.65),
                                ),
                                const SizedBox(height: 14),
                                Text(
                                  _tab == _DisputeChannelTab.support
                                      ? 'No messages here yet'
                                      : 'No messages in Everyone yet',
                                  style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  _tab == _DisputeChannelTab.support
                                      ? 'Say hello — support will see your message here.'
                                      : 'When someone posts in Everyone, it will show up here.',
                                  textAlign: TextAlign.center,
                                  style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
                                ),
                              ],
                            ),
                          ),
                        )
                      : ListView.builder(
                          controller: _scroll,
                          padding: const EdgeInsets.fromLTRB(14, 8, 14, 16),
                          itemCount: _activeMessages.length,
                          itemBuilder: (context, i) {
                            final m = _activeMessages[i] as Map<String, dynamic>;
                            return _messageBubble(m);
                          },
                        ),
            ),
          ),
          if (_pendingImages.isNotEmpty)
            SizedBox(
              height: 76,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                itemCount: _pendingImages.length,
                itemBuilder: (_, i) {
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: Image.file(
                            File(_pendingImages[i].path),
                            width: 64,
                            height: 64,
                            fit: BoxFit.cover,
                          ),
                        ),
                        Positioned(
                          right: -4,
                          top: -4,
                          child: InkWell(
                            onTap: () => setState(() => _pendingImages.removeAt(i)),
                            child: CircleAvatar(
                              radius: 12,
                              backgroundColor: cs.error,
                              child: const Icon(Icons.close, size: 14, color: Colors.white),
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          if (_showMessageComposer)
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 6, 10, 8),
                child: Material(
                  elevation: 2,
                  shadowColor: cs.shadow.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(22),
                  color: cs.surfaceContainerHighest.withValues(alpha: 0.65),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        IconButton(
                          onPressed: (_sending || !_canSendMessages) ? null : _pickImages,
                          icon: Icon(Icons.add_photo_alternate_outlined, color: cs.primary),
                          tooltip: 'Images',
                        ),
                        Expanded(
                          child: TextField(
                            controller: _text,
                            minLines: 1,
                            maxLines: 5,
                            textCapitalization: TextCapitalization.sentences,
                            decoration: InputDecoration(
                              hintText: 'Type a message…',
                              filled: true,
                              fillColor: cs.surface.withValues(alpha: 0.92),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(16),
                                borderSide: BorderSide.none,
                              ),
                              contentPadding:
                                  const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                              isDense: true,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        FilledButton(
                          style: FilledButton.styleFrom(
                            minimumSize: const Size(48, 48),
                            padding: EdgeInsets.zero,
                            shape: const CircleBorder(),
                          ),
                          onPressed: (_sending || !_canSendMessages) ? null : _send,
                          child: _sending
                              ? const SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(strokeWidth: 2.5),
                                )
                              : const Icon(Icons.send_rounded, size: 22),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
