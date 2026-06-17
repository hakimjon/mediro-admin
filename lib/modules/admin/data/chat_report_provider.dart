import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// ═══════════════════════════════════════════════════════════════════════════
//  CHAT REPORT PROVIDER — UGC moderation for the usta-admin panel.
//
//  Reads the `chat_reports` table (filed from the mobile app's chat). The admin
//  reviews each report and either WARNS the usta (status='warned' → the usta
//  sees an in-app banner) or DISMISSES it. Mirrors ComplaintProvider.
// ═══════════════════════════════════════════════════════════════════════════

class ChatReport {
  final String id;
  final String reporterId;
  final String reportedId;
  final String roomId;
  final String reason;
  final String note;
  final bool reportedIsUsta;
  String status; // 'new' | 'warned' | 'dismissed' | 'banned'
  final DateTime createdAt;

  ChatReport({
    required this.id,
    required this.reporterId,
    required this.reportedId,
    required this.roomId,
    required this.reason,
    required this.note,
    required this.reportedIsUsta,
    required this.status,
    required this.createdAt,
  });
}

class ChatReportProvider {
  ChatReportProvider._();

  static final List<ChatReport> _all = [];
  static bool _hasFetched = false;

  static List<ChatReport> all() => List.unmodifiable(_all);
  static int newCount() => _all.where((r) => r.status == 'new').length;

  static Future<void> fetchAllFromCloud({bool force = false}) async {
    if (_hasFetched && !force) return;
    try {
      final rows = await Supabase.instance.client
          .from('chat_reports')
          .select(
              'id, reporter_id, reported_id, room_id, reason, note, reported_is_usta, status, created_at')
          .order('created_at', ascending: false);
      _all
        ..clear()
        ..addAll((rows as List).map((raw) {
          final m = Map<String, dynamic>.from(raw as Map);
          return ChatReport(
            id: (m['id'] ?? '').toString(),
            reporterId: (m['reporter_id'] ?? '').toString(),
            reportedId: (m['reported_id'] ?? '').toString(),
            roomId: (m['room_id'] ?? '').toString(),
            reason: (m['reason'] ?? '').toString(),
            note: (m['note'] ?? '').toString(),
            reportedIsUsta: m['reported_is_usta'] == true,
            status: (m['status'] ?? 'new').toString(),
            createdAt:
                DateTime.tryParse((m['created_at'] ?? '').toString()) ??
                    DateTime.now(),
          );
        }));
      _hasFetched = true;
    } catch (e) {
      if (kDebugMode) {
        // ignore: avoid_print
        print('[chat_reports] fetch failed: $e');
      }
    }
  }

  static Future<bool> warn(String id) => _setStatus(id, 'warned');
  static Future<bool> dismiss(String id) => _setStatus(id, 'dismissed');

  static Future<bool> _setStatus(String id, String status) async {
    final ok = await _remoteUpdateStatus(id, status);
    if (ok) {
      for (final r in _all) {
        if (r.id == id) {
          r.status = status;
          break;
        }
      }
    }
    return ok;
  }

  static Future<bool> _remoteUpdateStatus(String id, String status) async {
    try {
      // .select() so an RLS-blocked / failed write returns 0 rows (= false).
      final res = await Supabase.instance.client
          .from('chat_reports')
          .update({
            'status': status,
            'reviewed_at': DateTime.now().toIso8601String(),
          })
          .eq('id', id)
          .select();
      return (res as List).isNotEmpty;
    } catch (e) {
      if (kDebugMode) {
        // ignore: avoid_print
        print('[chat_reports] update failed: $e');
      }
      return false;
    }
  }
}
