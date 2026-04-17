import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/api_client.dart';
import '../core/config.dart';
import '../providers/auth_provider.dart';
import '../providers/post_job_provider.dart';
import '../widgets/map_placeholder.dart';

class SelectCategoryScreen extends ConsumerWidget {
  const SelectCategoryScreen({this.initialExpandGroupId, super.key});

  /// `group` query from home (e.g. `home_repairs`) — expands that section first.
  final String? initialExpandGroupId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final draft = ref.watch(postJobProvider);
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Category')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'What kind of work is it?',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Text(
            'Pick a group, then a service.',
            style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
          ),
          const SizedBox(height: 12),
          for (final g in jobCategoryGroups) ...[
            ExpansionTile(
              key: PageStorageKey<String>('cat_${g.id}'),
              initiallyExpanded: initialExpandGroupId != null && initialExpandGroupId == g.id,
              leading: Icon(g.icon, color: g.accentColor),
              title: Text(g.title, style: const TextStyle(fontWeight: FontWeight.w600)),
              childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final c in g.entries)
                      ChoiceChip(
                        label: Text(c.$2),
                        selected: draft.category == c.$1,
                        onSelected: (_) {
                          ref.read(postJobProvider.notifier).setCategory(c.$1);
                        },
                      ),
                  ],
                ),
              ],
            ),
          ],
          const SizedBox(height: 16),
          FilledButton(
            onPressed: draft.category == null
                ? null
                : () => context.push('/post/details'),
            child: const Text('Continue to details'),
          ),
          if (draft.category != null) ...[
            const SizedBox(height: 12),
            Text(
              'Selected: ${labelForCategory(draft.category)}',
              style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
            ),
          ],
        ],
      ),
    );
  }
}

class JobDetailsScreen extends ConsumerStatefulWidget {
  const JobDetailsScreen({super.key});

  @override
  ConsumerState<JobDetailsScreen> createState() => _JobDetailsScreenState();
}

class _JobDetailsScreenState extends ConsumerState<JobDetailsScreen> {
  late final TextEditingController _title;
  late final TextEditingController _description;

  @override
  void initState() {
    super.initState();
    final s = ref.read(postJobProvider);
    _title = TextEditingController(text: s.title);
    _description = TextEditingController(text: s.description);
  }

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    super.dispose();
  }

  void _next() {
    ref.read(postJobProvider.notifier).setDetails(
          _title.text.trim(),
          _description.text.trim(),
        );
    context.push('/post/location');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Job details')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _title,
            decoration: const InputDecoration(
              labelText: 'Title',
              hintText: 'e.g. Fix leaking kitchen tap',
            ),
            textCapitalization: TextCapitalization.sentences,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _description,
            decoration: const InputDecoration(
              labelText: 'Description',
              alignLabelWithHint: true,
              hintText: 'Describe the work, access, materials…',
            ),
            minLines: 4,
            maxLines: 8,
            textCapitalization: TextCapitalization.sentences,
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: () {},
            icon: const Icon(Icons.photo_camera_outlined),
            label: const Text('Add photos (coming soon)'),
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _next,
            child: const Text('Next: location'),
          ),
        ],
      ),
    );
  }
}

class JobLocationScreen extends ConsumerStatefulWidget {
  const JobLocationScreen({super.key});

  @override
  ConsumerState<JobLocationScreen> createState() => _JobLocationScreenState();
}

class _JobLocationScreenState extends ConsumerState<JobLocationScreen> {
  late final TextEditingController _address;

  @override
  void initState() {
    super.initState();
    final s = ref.read(postJobProvider);
    _address = TextEditingController(text: s.address.isNotEmpty ? s.address : 'Accra');
  }

  @override
  void dispose() {
    _address.dispose();
    super.dispose();
  }

  void _review() {
    ref.read(postJobProvider.notifier).setLocation(
          _address.text.trim(),
          kAccraLat,
          kAccraLng,
        );
    context.push('/post/review');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Location')),
      body: Column(
        children: [
          const Expanded(
            child: MapPlaceholder(
              hint: 'Pin is set to Accra for now. Address below is sent to workers.',
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: _address,
                  decoration: const InputDecoration(
                    labelText: 'Address',
                    hintText: 'Street, area, landmark',
                  ),
                  textCapitalization: TextCapitalization.words,
                ),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: _review,
                  child: const Text('Review & post'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class JobReviewScreen extends ConsumerStatefulWidget {
  const JobReviewScreen({super.key});

  @override
  ConsumerState<JobReviewScreen> createState() => _JobReviewScreenState();
}

class _JobReviewScreenState extends ConsumerState<JobReviewScreen> {
  bool _posting = false;

  Future<void> _post() async {
    final d = ref.read(postJobProvider);
    final category = d.category;
    final title = d.title.trim();
    final description = d.description.trim();
    final address = d.address.trim();

    if (category == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Choose a category first.')),
      );
      return;
    }
    if (title.length < 3) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Title must be at least 3 characters.')),
      );
      return;
    }
    if (description.length < 10) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Description must be at least 10 characters.')),
      );
      return;
    }
    if (address.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter an address.')),
      );
      return;
    }

    setState(() => _posting = true);
    final api = ref.read(apiClientProvider);
    try {
      final job = await api.createJob(
        category: category,
        title: title,
        description: description,
        photos: const [],
        locationLat: d.locationLat,
        locationLng: d.locationLng,
        address: address,
      );
      if (!mounted) return;
      ref.read(postJobProvider.notifier).reset();
      final jobId = job['id'];
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Job posted — open Quotes to review offers when workers respond.')),
      );
      if (jobId is String && jobId.isNotEmpty) {
        context.go('/jobs/$jobId/quotes');
      } else {
        context.go('/home');
      }
    } on DioException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(messageFromDio(e)),
          action: SnackBarAction(
            label: 'API settings',
            onPressed: () => context.push('/settings'),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _posting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = ref.watch(postJobProvider);
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Review & confirm')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Check everything before posting',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _row('Category', labelForCategory(d.category)),
                  const Divider(height: 24),
                  _row('Title', d.title.trim().isEmpty ? '—' : d.title.trim()),
                  const Divider(height: 24),
                  _row('Description', d.description.trim().isEmpty ? '—' : d.description.trim()),
                  const Divider(height: 24),
                  _row('Address', d.address.trim().isEmpty ? '—' : d.address.trim()),
                  const Divider(height: 24),
                  _row(
                    'Location',
                    '${d.locationLat.toStringAsFixed(4)}, ${d.locationLng.toStringAsFixed(4)}',
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'You must be logged in as a customer. Title ≥3 chars, description ≥10 chars.',
            style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12, height: 1.35),
          ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: _posting ? null : _post,
            child: _posting
                ? const SizedBox(
                    height: 22,
                    width: 22,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Post job'),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: _posting ? null : () => context.pop(),
            child: const Text('Back to edit'),
          ),
        ],
      ),
    );
  }

  static Widget _row(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        Text(value, style: const TextStyle(height: 1.35)),
      ],
    );
  }
}
