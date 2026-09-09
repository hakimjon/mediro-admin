// ignore_for_file: avoid_web_libraries_in_flutter
//
// This file is admin-web only (the project itself is web-only). The
// `dart:html` import is intentional — used to wire browser-native
// Notification API + Audio cues into the admin dashboard.

import 'dart:async';
import 'dart:html' as html;

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../usta/data/usta_registration_provider.dart';

// ═══════════════════════════════════════════════════════════════════════════════
//  REALTIME ADMIN SERVICE
//
//  Owns the two Supabase Realtime channels the admin dashboard listens on:
//
//    1. `usta_registrations` INSERT — fires when a usta self-registers from
//       the mobile app. The new row is merged into UstaRegistrationProvider
//       so the verifications page shows it without a manual refresh.
//
//    2. `complaints` INSERT — fires when a client files a complaint from the
//       mobile app. (Optional; if the table isn't enabled for realtime in
//       Supabase, the subscription just stays idle.)
//
//  Side effects on every new row:
//    • A browser-native Notification is shown ("🆕 Yangi ariza — Ali V.").
//      First-time visitors are prompted for permission once.
//    • A short audio "ding" is played so the admin notices even if their
//       monitor is angled away. The user can mute it from the toolbar.
//    • A broadcast stream emits the event so any UI page can react
//       (auto-refresh tables, increment badges, show a toast).
//
//  Lifecycle:
//    start()  → called from AdminPanelPage.initState (only when admin
//                authenticated). Idempotent.
//    stop()   → called from signOut + dispose. Closes both channels.
//
//  All errors are logged + swallowed — a Realtime hiccup never bricks the
//  admin panel; the manual Yangilash button remains the fallback.
// ═══════════════════════════════════════════════════════════════════════════════

/// Singleton wrapper. UI talks to it via `RealtimeAdminService.instance`.
class RealtimeAdminService {
  RealtimeAdminService._();
  static final RealtimeAdminService instance = RealtimeAdminService._();

  RealtimeChannel? _registrationsChannel;
  RealtimeChannel? _complaintsChannel;
  RealtimeChannel? _chatReportsChannel;

  final StreamController<RealtimeAdminEvent> _events =
      StreamController<RealtimeAdminEvent>.broadcast();

  /// Stream of all incoming realtime events. Pages subscribe to this in
  /// initState and dispose the subscription in dispose().
  Stream<RealtimeAdminEvent> get events => _events.stream;

  bool _started = false;
  bool get isStarted => _started;

  /// True when the user has explicitly granted Notification permission.
  /// Pages can read this to show a banner asking for permission if false.
  bool get hasNotificationPermission =>
      html.Notification.permission == 'granted';

  /// User can toggle this off from the toolbar to silence the audio ding.
  /// Persisted in localStorage so the choice survives reloads.
  bool get isSoundEnabled {
    final v = html.window.localStorage['admin_realtime_sound'];
    // Default: enabled.
    return v == null || v == 'true';
  }

  set isSoundEnabled(bool v) {
    html.window.localStorage['admin_realtime_sound'] = v ? 'true' : 'false';
  }

  // ── Lifecycle ───────────────────────────────────────────────────────────

  /// Opens both Supabase Realtime channels. Safe to call repeatedly —
  /// only the first call wires the listeners.
  Future<void> start() async {
    if (_started) return;
    _started = true;

    final client = Supabase.instance.client;

    // ── usta_registrations channel ────────────────────────────────────
    _registrationsChannel = client.channel('admin-usta-registrations')
      ..onPostgresChanges(
        event: PostgresChangeEvent.insert,
        schema: 'public',
        table: 'usta_registrations',
        callback: (payload) => _onRegistrationInsert(payload),
      )
      ..onPostgresChanges(
        event: PostgresChangeEvent.update,
        schema: 'public',
        table: 'usta_registrations',
        callback: (payload) => _onRegistrationUpdate(payload),
      )
      ..subscribe((status, err) {
        if (err != null && kDebugMode) {
          // ignore: avoid_print
          print('[realtime] usta_registrations channel error: $err');
        }
      });

    // ── complaints channel ────────────────────────────────────────────
    _complaintsChannel = client.channel('admin-complaints')
      ..onPostgresChanges(
        event: PostgresChangeEvent.insert,
        schema: 'public',
        table: 'complaints',
        callback: (payload) => _onComplaintInsert(payload),
      )
      ..subscribe((status, err) {
        if (err != null && kDebugMode) {
          // ignore: avoid_print
          print('[realtime] complaints channel error: $err');
        }
      });

    // ── chat_reports channel ──────────────────────────────────────────
    // The UGC control (Apple 1.2): a customer reporting a chat or, since
    // 2026-09-07, a provider's profile. It had no channel at all, so a report
    // was only ever seen by an admin already sitting on the reports page —
    // reported and unnoticed is the same as unreported.
    _chatReportsChannel = client.channel('admin-chat-reports')
      ..onPostgresChanges(
        event: PostgresChangeEvent.insert,
        schema: 'public',
        table: 'chat_reports',
        callback: (payload) => _onChatReportInsert(payload),
      )
      ..subscribe((status, err) {
        if (err != null && kDebugMode) {
          // ignore: avoid_print
          print('[realtime] chat_reports channel error: $err');
        }
      });
  }

  /// Closes both channels and resets state. Called from signOut +
  /// AdminPanelPage.dispose.
  Future<void> stop() async {
    if (!_started) return;
    _started = false;
    try {
      await _registrationsChannel?.unsubscribe();
    } catch (_) {/* ignore */}
    try {
      await _complaintsChannel?.unsubscribe();
    } catch (_) {/* ignore */}
    try {
      await _chatReportsChannel?.unsubscribe();
    } catch (_) {/* ignore */}
    _registrationsChannel = null;
    _complaintsChannel = null;
    _chatReportsChannel = null;
  }

  // ── Permission flow ─────────────────────────────────────────────────────

  /// Asks the browser for Notification permission. Idempotent — if the
  /// user already granted/denied, the browser short-circuits. Returns
  /// true when permission is now 'granted'.
  Future<bool> requestNotificationPermission() async {
    if (html.Notification.permission == 'granted') return true;
    if (html.Notification.permission == 'denied') return false;
    try {
      final result = await html.Notification.requestPermission();
      return result == 'granted';
    } catch (e) {
      if (kDebugMode) {
        // ignore: avoid_print
        print('[realtime] notification permission request failed: $e');
      }
      return false;
    }
  }

  // ── Event handlers ──────────────────────────────────────────────────────

  void _onRegistrationInsert(PostgresChangePayload payload) {
    final row = Map<String, dynamic>.from(payload.newRecord);
    final name = (row['name'] ?? '').toString();
    final category = (row['category'] ?? '').toString();
    final status = (row['status'] ?? 'pending').toString();

    // Merge into the local provider so the verifications page picks it
    // up immediately when the user navigates to that section.
    _mergeRegistrationRow(row);

    // Ping for a genuinely-new provider, whichever state they arrive in.
    //
    // ⛔ This used to test `status == 'pending'`, which stopped meaning "new"
    // on 2026-09-07: auto-approval lands a registration as 'approved', so the
    // old check silenced the notification for every real joiner — the admin
    // heard nothing at exactly the moment review moved from before publication
    // to after it. The status still decides the WORDING, because an
    // auto-approved provider is already live and is the one worth looking at.
    //
    // What the check was really guarding against is an admin's own status flip
    // echoing back; those arrive on the UPDATE channel, which is separate.
    if (status == 'pending' || status == 'approved') {
      _showBrowserNotification(
        title: status == 'approved'
            ? "🆕 Yangi usta qo'shildi — tekshiring"
            : '🆕 Yangi usta arizasi',
        body: '$name — $category',
        tag: 'reg-${row['id']}',
      );
      _playDing();
    }

    _events.add(RealtimeAdminEvent.registrationInserted(
      id: (row['id'] ?? '').toString(),
      name: name,
      category: category,
      status: status,
    ));
  }

  void _onRegistrationUpdate(PostgresChangePayload payload) {
    final row = Map<String, dynamic>.from(payload.newRecord);
    _mergeRegistrationRow(row);
    _events.add(RealtimeAdminEvent.registrationUpdated(
      id: (row['id'] ?? '').toString(),
      status: (row['status'] ?? '').toString(),
    ));
  }

  /// A report filed from the app — chat or profile.
  ///
  /// room_id tells the two apart: a profile report has none, and says so, so
  /// the admin knows whether to open a conversation or the listing itself.
  void _onChatReportInsert(PostgresChangePayload payload) {
    final row = Map<String, dynamic>.from(payload.newRecord);
    final reason = (row['reason'] ?? '').toString();
    final fromProfile = (row['room_id'] ?? '').toString().isEmpty;
    final where = fromProfile ? 'Profil' : 'Chat';

    _showBrowserNotification(
      title: '⚠️ Yangi shikoyat ($where)',
      body: reason,
      tag: 'rep-${row['id']}',
    );
    _playDing();

    _events.add(RealtimeAdminEvent.chatReportInserted(
      id: (row['id'] ?? '').toString(),
      reason: reason,
      fromProfile: fromProfile,
    ));
  }

  void _onComplaintInsert(PostgresChangePayload payload) {
    final row = Map<String, dynamic>.from(payload.newRecord);
    final ustaName = (row['usta_name'] ?? row['ustaName'] ?? '').toString();
    final reason = (row['reason'] ?? '').toString();

    _showBrowserNotification(
      title: '⚠️ Yangi shikoyat',
      body: ustaName.isNotEmpty
          ? '$ustaName — $reason'
          : reason,
      tag: 'cmp-${row['id']}',
    );
    _playDing();

    _events.add(RealtimeAdminEvent.complaintInserted(
      id: (row['id'] ?? '').toString(),
      ustaName: ustaName,
      reason: reason,
    ));
  }

  /// Inserts/updates a row in UstaRegistrationProvider's in-memory list
  /// so the admin UI reflects realtime arrivals without a network round
  /// trip. Mirrors the mapping logic in fetchAllFromCloud.
  void _mergeRegistrationRow(Map<String, dynamic> m) {
    final id = (m['id'] ?? '').toString();
    if (id.isEmpty) return;

    final entry = UstaRegistration(
      id: id,
      name: (m['name'] ?? '').toString(),
      phone: (m['phone'] ?? '').toString(),
      category: (m['category'] ?? '').toString(),
      provinceId: m['province_id'] is int
          ? m['province_id'] as int
          : int.tryParse('${m['province_id']}') ?? 0,
      experienceYears: m['experience_years'] is int
          ? m['experience_years'] as int
          : int.tryParse('${m['experience_years']}') ?? 0,
      status: (m['status'] ?? 'pending').toString(),
      submittedAt:
          DateTime.tryParse((m['submitted_at'] ?? '').toString()) ??
              DateTime.now(),
      reviewedAt: DateTime.tryParse((m['reviewed_at'] ?? '').toString()),
    );

    final existing = UstaRegistrationProvider.allRegistrations()
        .where((r) => r.id == id)
        .toList();
    if (existing.isNotEmpty) {
      existing.first.status = entry.status;
      // ⛔ status alone is not enough. A provider adding a trade clears
      // reviewed_at server-side and touches nothing else, so merging only the
      // status left the row looking read: the "Ko'rilmagan" chip and the header
      // count both stayed put until someone pressed Yangilash. Same when
      // another tab marks one read.
      existing.first.reviewedAt = entry.reviewedAt;
    } else {
      // No public mutating method exists; fall back to fetch so the
      // provider's invariants stay intact. Cheap one-shot network call.
      UstaRegistrationProvider.fetchAllFromCloud(force: true);
    }
  }

  // ── Browser surfaces ───────────────────────────────────────────────────

  void _showBrowserNotification({
    required String title,
    required String body,
    String? tag,
  }) {
    if (html.Notification.permission != 'granted') return;
    try {
      html.Notification(
        title,
        body: body,
        tag: tag,
        icon: '/favicon.png',
      );
    } catch (e) {
      if (kDebugMode) {
        // ignore: avoid_print
        print('[realtime] browser notification failed: $e');
      }
    }
  }

  /// Plays a short audio "ding" using an inline data URL. The browser
  /// system notification itself usually plays a sound, but this gives
  /// us an in-page audible cue when the tab is focused (system
  /// notifications often suppress in that case). The asset is a tiny
  /// (~1 KB) sine pulse encoded as base64 so we don't need to ship a
  /// separate audio file.
  void _playDing() {
    if (!isSoundEnabled) return;
    try {
      // Short MP3 "ding" embedded as a data URL. ~700 ms, sine wave.
      // Kept inline so the deploy artifact stays single-file.
      const ding =
          'data:audio/mp3;base64,SUQzBAAAAAAAI1RTU0UAAAAPAAADTGF2ZjU4Ljc2LjEwMAAAAAAAAAAAAAAA//tQwAAAAAAAAAAAAAAAAAAAAAAASW5mbwAAAA8AAAAEAAAEgABYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFj/+xDEAAAJ3wEpsAAAACDLgEUYAAACAAJzEPAAAAAjE5gBgIYAYBmAJAhgAQOMAUAJgB4AYAAACMAAAAH/+1DEDQAJgAFB8AAACBwAJ8AAAACoCEAQwAEAUUACoBgIYBYDmAQA5gFgKYBYE4ASCkAyDM6BBzGEYAQB8wB';
      final audio = html.AudioElement(ding);
      audio.volume = 0.4;
      audio.play();
    } catch (e) {
      if (kDebugMode) {
        // ignore: avoid_print
        print('[realtime] ding failed: $e');
      }
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Event types broadcast on the `events` stream.
// ─────────────────────────────────────────────────────────────────────────────

enum RealtimeAdminEventKind {
  registrationInserted,
  registrationUpdated,
  complaintInserted,
  chatReportInserted,
}

class RealtimeAdminEvent {
  final RealtimeAdminEventKind kind;
  final String id;
  final String name;
  final String category;
  final String status;
  final String reason;

  RealtimeAdminEvent._({
    required this.kind,
    required this.id,
    this.name = '',
    this.category = '',
    this.status = '',
    this.reason = '',
  });

  factory RealtimeAdminEvent.registrationInserted({
    required String id,
    required String name,
    required String category,
    required String status,
  }) =>
      RealtimeAdminEvent._(
        kind: RealtimeAdminEventKind.registrationInserted,
        id: id,
        name: name,
        category: category,
        status: status,
      );

  factory RealtimeAdminEvent.registrationUpdated({
    required String id,
    required String status,
  }) =>
      RealtimeAdminEvent._(
        kind: RealtimeAdminEventKind.registrationUpdated,
        id: id,
        status: status,
      );

  factory RealtimeAdminEvent.chatReportInserted({
    required String id,
    required String reason,
    required bool fromProfile,
  }) =>
      RealtimeAdminEvent._(
        kind: RealtimeAdminEventKind.chatReportInserted,
        id: id,
        reason: reason,
        // Reused rather than a new field: the panel only needs to say WHERE it
        // came from, and every consumer already reads `category`.
        category: fromProfile ? 'profile' : 'chat',
      );

  factory RealtimeAdminEvent.complaintInserted({
    required String id,
    required String ustaName,
    required String reason,
  }) =>
      RealtimeAdminEvent._(
        kind: RealtimeAdminEventKind.complaintInserted,
        id: id,
        name: ustaName,
        reason: reason,
      );
}

