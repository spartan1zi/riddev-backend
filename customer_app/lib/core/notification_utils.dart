// Helpers for in-app notification lists from GET /api/notifications.

int unreadNotificationCount(List<Map<String, dynamic>> items) =>
    items.where((x) => x['isRead'] != true).length;

/// Unread `dispute_message` notifications grouped by `data.disputeId`.
Map<String, int> unreadDisputeMessageCountsByDispute(List<Map<String, dynamic>> items) {
  final m = <String, int>{};
  for (final n in items) {
    if (n['isRead'] == true) continue;
    if (n['type'] != 'dispute_message') continue;
    final data = n['data'];
    if (data is! Map) continue;
    final did = data['disputeId'];
    if (did is! String) continue;
    m[did] = (m[did] ?? 0) + 1;
  }
  return m;
}

int totalUnreadDisputeMessages(List<Map<String, dynamic>> items) {
  var c = 0;
  for (final n in items) {
    if (n['isRead'] != true && n['type'] == 'dispute_message') {
      c++;
    }
  }
  return c;
}
