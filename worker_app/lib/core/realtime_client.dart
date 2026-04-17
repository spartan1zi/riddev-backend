import 'dart:async';

import 'package:socket_io_client/socket_io_client.dart' as io;

import 'api_url.dart';

/// Socket.IO client (same origin as HTTP API). Connect after login with a valid access JWT.
class RealtimeClient {
  RealtimeClient({required Future<String?> Function() getToken}) : _getToken = getToken;

  final Future<String?> Function() _getToken;
  io.Socket? _socket;

  final _meJobsController = StreamController<Object?>.broadcast();
  final _workersFeedController = StreamController<Object?>.broadcast();
  final _jobEventController = StreamController<Map<String, dynamic>>.broadcast();
  final _chatMessageController = StreamController<Map<String, dynamic>>.broadcast();
  final _disputeMessageController = StreamController<Map<String, dynamic>>.broadcast();
  final _disputeChatSettingsController = StreamController<Map<String, dynamic>>.broadcast();
  final _notificationsUpdateController = StreamController<Object?>.broadcast();

  Stream<void> get onMyJobsChanged => _meJobsController.stream.map((_) {});

  Stream<void> get onWorkerFeedChanged => _workersFeedController.stream.map((_) {});

  Stream<Map<String, dynamic>> get onJobEvent => _jobEventController.stream;

  Stream<Map<String, dynamic>> get onChatMessage => _chatMessageController.stream;

  Stream<Map<String, dynamic>> get onDisputeMessage => _disputeMessageController.stream;

  Stream<Map<String, dynamic>> get onDisputeChatSettings => _disputeChatSettingsController.stream;

  Stream<void> get onNotificationsUpdated => _notificationsUpdateController.stream.map((_) {});

  Future<void> reconnect() async {
    disconnect();
    await connect();
  }

  Future<void> connect() async {
    final token = await _getToken();
    if (token == null || token.isEmpty) {
      disconnect();
      return;
    }
    _socket?.dispose();
    final origin = await resolveWorkerApiBaseUrl();
    _socket = io.io(
      origin,
      io.OptionBuilder()
          .setTransports(['websocket'])
          .enableAutoConnect()
          .setAuth({'token': token})
          .build(),
    );
    _socket!.on('me:jobs', (_) => _meJobsController.add(null));
    _socket!.on('jobs:feed', (_) => _workersFeedController.add(null));
    _socket!.on('job:event', (data) {
      if (data is Map) {
        _jobEventController.add(Map<String, dynamic>.from(data));
      }
    });
    _socket!.on('chat:message', (data) {
      if (data is Map) {
        _chatMessageController.add(Map<String, dynamic>.from(data));
      }
    });
    _socket!.on('dispute:message', (data) {
      if (data is Map) {
        _disputeMessageController.add(Map<String, dynamic>.from(data));
      }
    });
    _socket!.on('dispute:chat_settings', (data) {
      if (data is Map) {
        _disputeChatSettingsController.add(Map<String, dynamic>.from(data));
      }
    });
    _socket!.on('notifications:update', (_) => _notificationsUpdateController.add(null));
  }

  void joinJob(String jobId) {
    _socket?.emit('join:job', jobId);
  }

  void leaveJob(String jobId) {
    _socket?.emit('leave:job', jobId);
  }

  void joinDispute(String disputeId) {
    _socket?.emit('join:dispute', disputeId);
  }

  void leaveDispute(String disputeId) {
    _socket?.emit('leave:dispute', disputeId);
  }

  void disconnect() {
    _socket?.dispose();
    _socket = null;
  }

  void dispose() {
    disconnect();
    _meJobsController.close();
    _workersFeedController.close();
    _jobEventController.close();
    _chatMessageController.close();
    _disputeMessageController.close();
    _disputeChatSettingsController.close();
    _notificationsUpdateController.close();
  }
}
