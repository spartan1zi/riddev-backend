import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/api_client.dart';

final apiClientProvider = Provider<ApiClient>((ref) => ApiClient());
