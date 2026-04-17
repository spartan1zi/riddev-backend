import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api_url.dart';
import 'config.dart';

/// Result of `GET /disputes/:id/messages` — split channels plus chat controls (customer app).
class DisputeThreadMessagesResult {
  const DisputeThreadMessagesResult({
    required this.privateChannelMessages,
    required this.everyoneChannelMessages,
    required this.everyoneChannelEnabled,
    required this.disputeChatLocked,
  });

  /// `ADMIN_CUSTOMER` — You & Support Only.
  final List<dynamic> privateChannelMessages;

  /// `ALL` — Everyone tab (empty from API when everyone channel is disabled).
  final List<dynamic> everyoneChannelMessages;

  final bool everyoneChannelEnabled;
  final bool disputeChatLocked;
}

/// Separate from worker app so both can be installed without clobbering tokens.
const _tokenKey = 'riddev_customer_access_token';
const _refreshTokenKey = 'riddev_customer_refresh_token';

/// Parses API JSON (Zod flatten, string errors) so we don't show Dio's long 400 text.
String? _messageFromResponseData(dynamic data) {
  if (data is! Map) return null;
  final err = data['error'];
  if (err is String) return err;
  if (err is Map) {
    final fieldErrors = err['fieldErrors'];
    if (fieldErrors is Map) {
      final parts = <String>[];
      for (final entry in fieldErrors.entries) {
        final v = entry.value;
        if (v is List && v.isNotEmpty) {
          parts.add('${entry.key}: ${v.first}');
        }
      }
      if (parts.isNotEmpty) return parts.join(' · ');
    }
    final formErrors = err['formErrors'];
    if (formErrors is List && formErrors.isNotEmpty) {
      return formErrors.map((x) => x.toString()).join(' ');
    }
  }
  return null;
}

String messageFromDio(DioException e) {
  switch (e.type) {
    case DioExceptionType.connectionTimeout:
    case DioExceptionType.sendTimeout:
    case DioExceptionType.receiveTimeout:
      return 'Request timed out. On a physical phone use your PC IP, e.g. '
          'flutter run --dart-define=API_BASE_URL=http://192.168.x.x:4000';
    case DioExceptionType.connectionError:
      return 'Cannot reach the API server. '
          'Emulator: default http://10.0.2.2:4000 is OK. '
          'On a real phone: open Settings → API server URL and enter '
          'http://YOUR_PC_LAN_IP:4000 (PC and phone on same Wi‑Fi), or use '
          'flutter run --dart-define=API_BASE_URL=http://192.168.x.x:4000';
    case DioExceptionType.badResponse:
    default:
      break;
  }
  final fromBody = _messageFromResponseData(e.response?.data);
  if (fromBody != null) return fromBody;
  return 'Something went wrong (${e.response?.statusCode ?? '?'})';
}

class ApiClient {
  ApiClient()
      : _dio = Dio(
          BaseOptions(
            baseUrl: '$kApiBaseUrl/api',
            connectTimeout: const Duration(seconds: 12),
            receiveTimeout: const Duration(seconds: 25),
            sendTimeout: const Duration(seconds: 12),
          ),
        ) {
    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          final base = await resolveCustomerApiBaseUrl();
          options.baseUrl = '$base/api';
          return handler.next(options);
        },
      ),
    );
    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          final prefs = await SharedPreferences.getInstance();
          final t = prefs.getString(_tokenKey);
          if (t != null && t.isNotEmpty) {
            options.headers['Authorization'] = 'Bearer $t';
          }
          return handler.next(options);
        },
      ),
    );
    _dio.interceptors.add(
      InterceptorsWrapper(
        onError: (err, handler) async {
          if (err.response?.statusCode != 401) {
            return handler.next(err);
          }
          final path = err.requestOptions.path;
          if (path.contains('/auth/login') ||
              path.contains('/auth/register') ||
              path.contains('/auth/refresh')) {
            return handler.next(err);
          }
          if (err.requestOptions.extra['retryAfterRefresh'] == true) {
            return handler.next(err);
          }
          final prefs = await SharedPreferences.getInstance();
          final refresh = prefs.getString(_refreshTokenKey);
          if (refresh == null || refresh.isEmpty) {
            return handler.next(err);
          }
          try {
            final apiBase = await resolveCustomerApiBaseUrl();
            final refreshDio = Dio(
              BaseOptions(
                baseUrl: '$apiBase/api',
                connectTimeout: const Duration(seconds: 12),
                receiveTimeout: const Duration(seconds: 25),
              ),
            );
            final r = await refreshDio.post<Map<String, dynamic>>(
              '/auth/refresh',
              data: {'refreshToken': refresh},
            );
            final newAccess = r.data?['accessToken'] as String?;
            if (newAccess == null || newAccess.isEmpty) {
              await clearToken();
              return handler.next(err);
            }
            await prefs.setString(_tokenKey, newAccess);
            final ro = err.requestOptions;
            ro.headers['Authorization'] = 'Bearer $newAccess';
            ro.extra['retryAfterRefresh'] = true;
            final response = await _dio.fetch(ro);
            return handler.resolve(response);
          } catch (_) {
            await clearToken();
            return handler.next(err);
          }
        },
      ),
    );
  }

  final Dio _dio;
  Dio get dio => _dio;

  /// Persist both tokens; access JWT expires in ~15 minutes — refresh keeps the session alive.
  Future<void> saveSession({
    required String accessToken,
    required String refreshToken,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_tokenKey, accessToken);
    await prefs.setString(_refreshTokenKey, refreshToken);
  }

  @Deprecated('Use saveSession with access + refresh tokens')
  Future<void> saveToken(String token) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_tokenKey, token);
  }

  /// Registers or clears the device FCM token for system push notifications.
  Future<void> registerFcmToken(String? token) async {
    await _dio.post<Map<String, dynamic>>('/users/me/fcm-token', data: {'token': token});
  }

  Future<void> clearToken() async {
    try {
      await registerFcmToken(null);
    } catch (_) {}
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey);
    await prefs.remove(_refreshTokenKey);
  }

  Future<String?> getStoredToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_tokenKey);
  }

  /// Returns true if a token exists and `/users/me` succeeds, or if offline (keeps you signed in).
  Future<bool> restoreSession() async {
    final t = await getStoredToken();
    if (t == null || t.isEmpty) return false;
    try {
      await getCurrentUser();
      return true;
    } on DioException catch (e) {
      if (e.response?.statusCode == 401) {
        final prefs = await SharedPreferences.getInstance();
        final refresh = prefs.getString(_refreshTokenKey);
        if (refresh != null && refresh.isNotEmpty) {
          try {
            final apiBase = await resolveCustomerApiBaseUrl();
            final refreshDio = Dio(
              BaseOptions(
                baseUrl: '$apiBase/api',
                connectTimeout: const Duration(seconds: 12),
                receiveTimeout: const Duration(seconds: 25),
              ),
            );
            final r = await refreshDio.post<Map<String, dynamic>>(
              '/auth/refresh',
              data: {'refreshToken': refresh},
            );
            final newAccess = r.data?['accessToken'] as String?;
            if (newAccess != null && newAccess.isNotEmpty) {
              await prefs.setString(_tokenKey, newAccess);
              await getCurrentUser();
              return true;
            }
          } catch (_) {}
        }
        await clearToken();
        return false;
      }
      return true;
    } catch (_) {
      return true;
    }
  }

  Future<Map<String, dynamic>> login({
    required String email,
    required String password,
  }) async {
    final r = await _dio.post<Map<String, dynamic>>(
      '/auth/login',
      data: {
        'email': email.trim().toLowerCase(),
        'password': password.trim(),
      },
    );
    return r.data!;
  }

  Future<Map<String, dynamic>> register({
    required String name,
    required String email,
    required String phone,
    required String password,
    required String role,
  }) async {
    final r = await _dio.post<Map<String, dynamic>>(
      '/auth/register',
      data: {
        'name': name,
        'email': email.trim().toLowerCase(),
        'phone': phone,
        'password': password.trim(),
        'role': role,
      },
    );
    final data = r.data;
    final token = data?['accessToken'];
    if (data == null || token is! String || token.isEmpty) {
      throw StateError('Registration succeeded but no access token was returned.');
    }
    return data;
  }

  /// Authenticated: `Authorization` header from stored access token.
  Future<Map<String, dynamic>> getCurrentUser() async {
    final r = await _dio.get<Map<String, dynamic>>('/users/me');
    return r.data!;
  }

  /// Customer only — `POST /jobs`.
  Future<Map<String, dynamic>> createJob({
    required String category,
    required String title,
    required String description,
    required List<String> photos,
    required double locationLat,
    required double locationLng,
    required String address,
  }) async {
    final r = await _dio.post<Map<String, dynamic>>(
      '/jobs',
      data: {
        'category': category,
        'title': title,
        'description': description,
        'photos': photos,
        'locationLat': locationLat,
        'locationLng': locationLng,
        'address': address,
      },
    );
    return r.data!;
  }

  /// Single job — `GET /jobs/:id` (customer must own the job or be admin).
  Future<Map<String, dynamic>> getJob(String jobId) async {
    final r = await _dio.get<Map<String, dynamic>>('/jobs/$jobId');
    return r.data!;
  }

  /// Customer's jobs — `GET /jobs`.
  Future<List<dynamic>> listMyJobs() async {
    final r = await _dio.get<Map<String, dynamic>>('/jobs');
    final jobs = r.data?['jobs'];
    if (jobs is List) return jobs;
    return [];
  }

  /// Quotes for a job — `GET /jobs/:id/quotes`.
  Future<List<dynamic>> listJobQuotes(String jobId) async {
    final r = await _dio.get<Map<String, dynamic>>('/jobs/$jobId/quotes');
    final quotes = r.data?['quotes'];
    if (quotes is List) return quotes;
    return [];
  }

  Future<void> acceptQuote(String quoteId) async {
    await _dio.put('/quotes/$quoteId/accept');
  }

  Future<void> rejectQuote(String quoteId) async {
    await _dio.put('/quotes/$quoteId/reject');
  }

  /// `GET /chat/:jobId`
  Future<List<dynamic>> listChatMessages(String jobId) async {
    final r = await _dio.get<Map<String, dynamic>>('/chat/$jobId');
    final messages = r.data?['messages'];
    if (messages is List) return messages;
    return [];
  }

  /// `POST /chat/:jobId`
  Future<Map<String, dynamic>> sendChatMessage(String jobId, String content) async {
    final r = await _dio.post<Map<String, dynamic>>(
      '/chat/$jobId',
      data: {'content': content.trim()},
    );
    return r.data!;
  }

  /// Customer confirms the worker finished and releases escrow (`POST /payments/release/:jobId`).
  Future<Map<String, dynamic>> releaseEscrowPayment(String jobId) async {
    final r = await _dio.post<Map<String, dynamic>>('/payments/release/$jobId');
    return r.data ?? <String, dynamic>{};
  }

  /// Start payment (`POST /payments/initiate`). Use [fundingSource] `WALLET` to pay from in-app balance.
  Future<Map<String, dynamic>> initiatePayment({
    required String jobId,
    String fundingSource = 'PAYSTACK',
    String? momoNumber,
    String? momoProvider,
  }) async {
    final r = await _dio.post<Map<String, dynamic>>(
      '/payments/initiate',
      data: <String, dynamic>{
        'jobId': jobId,
        'fundingSource': fundingSource,
        if (momoNumber != null && momoNumber.trim().isNotEmpty) 'momoNumber': momoNumber.trim(),
        if (momoProvider != null && momoProvider.isNotEmpty) 'momoProvider': momoProvider,
      },
    );
    return r.data ?? <String, dynamic>{};
  }

  /// `GET /wallet` — balance, escrow held, recent ledger.
  Future<Map<String, dynamic>> getWallet() async {
    final r = await _dio.get<Map<String, dynamic>>('/wallet');
    return r.data ?? <String, dynamic>{};
  }

  /// `POST /wallet/topup` — simulated top-up when backend dev flags allow.
  Future<Map<String, dynamic>> topUpWallet(int amountPesewas) async {
    final r = await _dio.post<Map<String, dynamic>>(
      '/wallet/topup',
      data: {'amountPesewas': amountPesewas},
    );
    return r.data ?? <String, dynamic>{};
  }

  /// `GET /notifications` — in-app notifications (e.g. payment pending).
  Future<List<Map<String, dynamic>>> listNotifications() async {
    final r = await _dio.get<Map<String, dynamic>>('/notifications');
    final raw = r.data?['notifications'];
    if (raw is! List) return [];
    return raw.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  /// `PUT /notifications/read` — pass [ids] or omit to mark all as read.
  Future<void> markNotificationsRead({List<String>? ids}) async {
    await _dio.put<Map<String, dynamic>>(
      '/notifications/read',
      data: ids != null && ids.isNotEmpty ? {'ids': ids} : <String, dynamic>{},
    );
  }

  Future<List<dynamic>> listMyDisputes() async {
    final r = await _dio.get<Map<String, dynamic>>('/disputes/mine');
    final list = r.data?['disputes'];
    if (list is List) return list;
    return [];
  }

  Future<Map<String, dynamic>> getDispute(String disputeId) async {
    final r = await _dio.get<Map<String, dynamic>>('/disputes/$disputeId');
    return r.data ?? <String, dynamic>{};
  }

  Future<DisputeThreadMessagesResult> fetchDisputeThreadMessages(String disputeId) async {
    final r = await _dio.get<Map<String, dynamic>>('/disputes/$disputeId/messages');
    final data = r.data ?? <String, dynamic>{};
    final ch = data['channels'] as Map<String, dynamic>?;
    List<dynamic> priv = [];
    List<dynamic> everyone = [];
    if (ch != null) {
      final p = ch['ADMIN_CUSTOMER'];
      final a = ch['ALL'];
      if (p is List) priv = List<dynamic>.from(p);
      if (a is List) everyone = List<dynamic>.from(a);
    }
    final cs = data['chatSettings'];
    var everyoneEnabled = false;
    var locked = false;
    if (cs is Map) {
      everyoneEnabled = cs['everyoneChannelEnabled'] == true;
      locked = cs['disputeChatLocked'] == true;
    }
    return DisputeThreadMessagesResult(
      privateChannelMessages: priv,
      everyoneChannelMessages: everyone,
      everyoneChannelEnabled: everyoneEnabled,
      disputeChatLocked: locked,
    );
  }

  Future<List<dynamic>> listDisputeMessages(String disputeId) async {
    final bundle = await fetchDisputeThreadMessages(disputeId);
    return [...bundle.privateChannelMessages, ...bundle.everyoneChannelMessages];
  }

  Future<Map<String, dynamic>> postDisputeMessage({
    required String disputeId,
    String body = '',
    List<String> imageUrls = const [],
    String? channel,
  }) async {
    final data = <String, dynamic>{};
    if (body.trim().isNotEmpty) data['body'] = body.trim();
    if (imageUrls.isNotEmpty) data['imageUrls'] = imageUrls;
    if (channel != null) data['channel'] = channel;
    final r = await _dio.post<Map<String, dynamic>>(
      '/disputes/$disputeId/messages',
      data: data,
    );
    return r.data ?? <String, dynamic>{};
  }

  Future<List<String>> uploadDisputeEvidence(List<String> filePaths) async {
    if (filePaths.isEmpty) return [];
    final formData = FormData();
    for (final p in filePaths) {
      final name = p.split(RegExp(r'[\\/]')).last;
      formData.files.add(
        MapEntry('photos', await MultipartFile.fromFile(p, filename: name)),
      );
    }
    final r = await _dio.post<Map<String, dynamic>>(
      '/uploads/dispute-evidence',
      data: formData,
    );
    final urls = r.data?['urls'];
    if (urls is List) {
      return urls.map((e) => e.toString()).toList();
    }
    return [];
  }

  Future<Map<String, dynamic>> createDispute({
    required String jobId,
    required String reason,
    List<String> evidencePhotos = const [],
  }) async {
    final r = await _dio.post<Map<String, dynamic>>(
      '/disputes',
      data: {
        'jobId': jobId,
        'reason': reason,
        'evidencePhotos': evidencePhotos,
      },
    );
    return r.data ?? <String, dynamic>{};
  }
}
