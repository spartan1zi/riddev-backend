import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/realtime_client.dart';
import 'auth_provider.dart';

final realtimeClientProvider = Provider<RealtimeClient>((ref) {
  final api = ref.watch(apiClientProvider);
  final c = RealtimeClient(getToken: () => api.getStoredToken());
  ref.onDispose(c.dispose);
  return c;
});
