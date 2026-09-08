import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../usta/data/usta_registration_provider.dart';

// ═══════════════════════════════════════════════════════════════════════════════
//  MOCK ADMIN DATA — Phase 1
//
//  Three concerns, ONE file, all in-memory:
//    1. PendingVerificationProvider — ustalar awaiting admin approval
//                                     (seeded + self-registrations bridged in).
//    2. ComplaintProvider           — open / under_review / resolved.
//    3. UstaSuspensionGate          — passive boolean queried by the listing
//                                     to hide any usta with an active
//                                     `under_review` complaint.
//
//  ZERO-IMPACT contract:
//    - Nothing in this module imports from cart/checkout/marketplace.
//    - The suspension gate is a pure read; the listing decides whether to
//      consult it. If this file is deleted, the marketplace still works.
//
//  When Supabase tables `usta_verifications` + `complaints` land, swap the
//  static maps for service queries — UI/widget signatures stay identical.
// ═══════════════════════════════════════════════════════════════════════════════

class PendingVerification {
  final String ustaId;
  final String name;
  final String specialty;
  final int experienceYears;
  final DateTime submittedAt;

  /// Set for self-registrations only. Already masked — safe to render
  /// anywhere in the admin UI (e.g. the queue list).
  final String? phoneMasked;

  /// RAW phone number — populated for self-registrations ONLY, and
  /// intended to be rendered EXCLUSIVELY inside the cloud-verified
  /// Admin Panel detail view (UstaDetailAdminView). Never pass this
  /// value into telemetry, snackbars, screenshots, or public pages.
  final String? phoneRaw;

  /// Optional region id — populated for self-registrations so the
  /// admin detail view can resolve the human-readable province name.
  final int? provinceId;

  /// 'seeded' (mock fixture) | 'self_registration' (came from the new form).
  final String source;

  /// Registration status — lets the queue card decide when to show the
  /// re-review badge (only meaningful while 'pending').
  final String status;

  /// The specialty the usta had BEFORE a self-edit pushed them back to
  /// 'pending'. When set (and different from [specialty]) this row is a
  /// re-review, not a fresh sign-up.
  final String? prevSpecialty;

  /// True for a company / MCHJ (equipment owner), false for an individual usta.
  final bool isBusiness;

  /// Null while the provider is still waiting to be READ by an admin.
  /// ⛔ Orthogonal to [status]: auto-approval publishes a provider the moment
  /// they apply, so 'approved' and 'never looked at' are the normal state of a
  /// brand-new row.
  final DateTime? reviewedAt;

  bool get isReviewed => reviewedAt != null;

  const PendingVerification({
    required this.ustaId,
    required this.name,
    required this.specialty,
    required this.experienceYears,
    required this.submittedAt,
    this.phoneMasked,
    this.phoneRaw,
    this.provinceId,
    this.source = 'seeded',
    this.status = 'pending',
    this.prevSpecialty,
    this.isBusiness = false,
    this.reviewedAt,
  });
}

class PendingVerificationProvider {
  // Seeded demo entries removed (per user request) — admin queue now
  // shows ONLY real ustalar pulled from Supabase `usta_registrations`
  // via UstaRegistrationProvider.fetchAllFromCloud().
  static final Map<String, PendingVerification> _pending = {};

  /// Queue source: live self-registrations bridged from
  /// UstaRegistrationProvider (which mirrors Supabase). The masked phone
  /// is shown in the queue list — the raw phone is reserved for the
  /// admin detail view only (Zero-Leak).
  static List<PendingVerification> all() {
    final fromSeed = _pending.values.toList();
    final fromRegs = UstaRegistrationProvider.pending().map((r) {
      return PendingVerification(
        ustaId: r.id,
        name: r.name,
        specialty: r.category,
        experienceYears: r.experienceYears,
        submittedAt: r.submittedAt,
        phoneMasked: r.phoneMasked,
        // Raw phone bridged into the queue ONLY so the admin detail view
        // can render it. The queue list itself never displays this field.
        phoneRaw: r.phone,
        provinceId: r.provinceId,
        source: 'self_registration',
        status: r.status,
        prevSpecialty: r.prevCategory,
        isBusiness: r.isBusiness,
        reviewedAt: r.reviewedAt,
      );
    }).toList();
    final out = [...fromSeed, ...fromRegs];
    out.sort((a, b) => b.submittedAt.compareTo(a.submittedAt));
    return out;
  }


  /// Returns ALL registrations (any status) as PendingVerification rows.
  /// Used by the new admin "All Ustalar" page with status filter tabs.
  /// `statusFilter` can be 'all', 'pending', 'approved', 'rejected',
  /// 'deleted'. The 'deleted' entries are always hidden by default.
  static List<PendingVerification> byStatus(String statusFilter) {
    final all = UstaRegistrationProvider.allRegistrations();
    // 'unreviewed' is not a status -- it cuts ACROSS them. It asks the only
    // question auto-approval left unanswered: has a person read this row yet?
    // The bin is excluded like it is from 'all': a deleted provider needs no
    // reading.
    final filtered = switch (statusFilter) {
      'all' => all.where((r) => r.status != 'deleted').toList(),
      'unreviewed' =>
        all.where((r) => !r.isReviewed && r.status != 'deleted').toList(),
      _ => all.where((r) => r.status == statusFilter).toList(),
    };
    return filtered.map((r) {
      return PendingVerification(
        ustaId: r.id,
        name: r.name,
        specialty: r.category,
        experienceYears: r.experienceYears,
        submittedAt: r.submittedAt,
        phoneMasked: r.phoneMasked,
        phoneRaw: r.phone,
        provinceId: r.provinceId,
        source: 'self_registration',
        status: r.status,
        prevSpecialty: r.prevCategory,
        isBusiness: r.isBusiness,
        reviewedAt: r.reviewedAt,
      );
    }).toList();
  }

  /// Pass-through for the "I have read this" action.
  static Future<bool> markReviewedByUstaId(String ustaId) =>
      UstaRegistrationProvider.markReviewed(ustaId);

  /// How many providers are still waiting to be read -- the badge the empty
  /// 'pending' counter no longer earns.
  static int unreviewedCount() => UstaRegistrationProvider.allRegistrations()
      .where((r) => !r.isReviewed && r.status != 'deleted')
      .length;

  /// Pass-through to UstaRegistrationProvider for the admin delete action.
  /// Returns true only when the DB write succeeded (drops the seeded entry
  /// only then so the queue reflects the real state).
  static Future<bool> softDeleteByUstaId(String ustaId) async {
    final ok = await UstaRegistrationProvider.softDelete(ustaId);
    if (ok) _pending.removeWhere((_, v) => v.ustaId == ustaId);
    return ok;
  }

  /// Pass-through for the bin's restore action. Brings the row back as
  /// 'pending' so a moderator decides again — restoring never republishes.
  static Future<bool> restoreByUstaId(String ustaId) async {
    return UstaRegistrationProvider.restore(ustaId);
  }

  /// Pass-through for emptying the bin. Permanent: the row and its chat rooms
  /// and reviews go. Only works on a row that is already binned.
  static Future<bool> purgeByUstaId(String ustaId) async {
    final ok = await UstaRegistrationProvider.purge(ustaId);
    if (ok) _pending.removeWhere((_, v) => v.ustaId == ustaId);
    return ok;
  }

  /// Pass-through to UstaRegistrationProvider for the admin suspend action.
  /// Marks an approved usta as 'rejected' so they vanish from the
  /// marketplace listing but stay in the admin queue for audit.
  static Future<bool> suspendByUstaId(String ustaId) async {
    final ok = await UstaRegistrationProvider.suspend(ustaId);
    if (ok) _pending.removeWhere((_, v) => v.ustaId == ustaId);
    return ok;
  }

  /// Approves by usta id. Handles both seeded mock rows and bridged
  /// self-registrations — the latter flips the registration status to
  /// 'approved' so the usta becomes visible in the marketplace.
  static Future<bool> approveByUstaId(String ustaId) async {
    final ok = await UstaRegistrationProvider.approve(ustaId);
    if (ok) _pending.removeWhere((_, v) => v.ustaId == ustaId);
    return ok;
  }

  /// Rejects by usta id. Hides from both queues + marks the registration
  /// 'rejected' (which keeps it invisible from the marketplace forever).
  static Future<bool> rejectByUstaId(String ustaId) async {
    final ok = await UstaRegistrationProvider.reject(ustaId);
    if (ok) _pending.removeWhere((_, v) => v.ustaId == ustaId);
    return ok;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  COMPLAINTS
// ─────────────────────────────────────────────────────────────────────────────

class Complaint {
  final String id;
  final String ustaId;
  final String ustaName;
  final String clientLabel;
  final String orderId;
  final String reason;
  final String comment;
  String status; // 'open' | 'under_review' | 'resolved' | 'dismissed'
  final DateTime createdAt;

  Complaint({
    required this.id,
    required this.ustaId,
    required this.ustaName,
    required this.clientLabel,
    required this.orderId,
    required this.reason,
    required this.comment,
    required this.status,
    required this.createdAt,
  });
}

class ComplaintProvider {
  static int _seq = 100;
  // Real complaints are pulled from Supabase by fetchAllFromCloud(); the
  // seeded demo rows were removed so the admin only ever sees real data.
  static final List<Complaint> _all = [];
  static bool _hasFetched = false;
  static bool get hasFetched => _hasFetched;

  /// Pulls complaints from the Supabase `complaints` table into the in-memory
  /// mirror so the admin queue shows REAL complaints (not seeds). Safe to call
  /// repeatedly; pass force to bypass the once-per-session cache.
  static Future<void> fetchAllFromCloud({bool force = false}) async {
    if (_hasFetched && !force) return;
    try {
      final rows = await Supabase.instance.client
          .from('complaints')
          .select(
              'id, usta_id, usta_name, client_label, order_id, reason, comment, status, created_at')
          .order('created_at', ascending: false);
      _all
        ..clear()
        ..addAll((rows as List).map((raw) {
          final m = Map<String, dynamic>.from(raw as Map);
          return Complaint(
            id: (m['id'] ?? '').toString(),
            ustaId: (m['usta_id'] ?? '').toString(),
            ustaName: (m['usta_name'] ?? '').toString(),
            clientLabel: (m['client_label'] ?? '').toString(),
            orderId: (m['order_id'] ?? '').toString(),
            reason: (m['reason'] ?? '').toString(),
            comment: (m['comment'] ?? '').toString(),
            status: (m['status'] ?? 'open').toString(),
            createdAt:
                DateTime.tryParse((m['created_at'] ?? '').toString()) ??
                    DateTime.now(),
          );
        }));
      _hasFetched = true;
    } catch (e) {
      if (kDebugMode) {
        // ignore: avoid_print
        print('[complaints] fetch failed: $e');
      }
    }
  }

  static List<Complaint> all() =>
      List<Complaint>.from(_all)..sort((a, b) => b.createdAt.compareTo(a.createdAt));

  static List<Complaint> open() =>
      _all.where((c) => c.status == 'open' || c.status == 'under_review').toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

  static int openCount() => open().length;

  /// Filed by a client from the order/profile flow. Defaults to 'under_review'
  /// per the spec — this automatically triggers temporary suspension of the
  /// usta until an admin clears the complaint.
  static Complaint fileComplaint({
    required String ustaId,
    required String ustaName,
    required String clientLabel,
    required String orderId,
    required String reason,
    required String comment,
  }) {
    final c = Complaint(
      id: 'cmp-${DateTime.now().millisecondsSinceEpoch}-${_seq++}',
      ustaId: ustaId,
      ustaName: ustaName,
      clientLabel: clientLabel,
      orderId: orderId,
      reason: reason,
      comment: comment,
      status: 'under_review',
      createdAt: DateTime.now(),
    );
    _all.add(c);
    // Fire-and-forget remote insert. Local mirror already has the row so
    // the admin queue stays consistent even when offline / RLS denies.
    unawaited(_remoteInsert(c));
    return c;
  }

  /// Admin: marks the complaint resolved (lifts suspension if this was the
  /// last `under_review` entry for that usta).
  static Future<bool> resolve(String complaintId) =>
      _setStatus(complaintId, 'resolved');

  /// Admin: rejects the complaint (also lifts suspension, same as resolve).
  static Future<bool> dismiss(String complaintId) =>
      _setStatus(complaintId, 'dismissed');

  /// Writes to Supabase first (with `.select()` so an RLS-blocked 0-row
  /// update reports failure) and only mutates the in-memory mirror on
  /// success. Returns true when the DB actually changed.
  static Future<bool> _setStatus(String complaintId, String status) async {
    final ok = await _remoteUpdateStatus(complaintId, status);
    if (ok) {
      for (final c in _all) {
        if (c.id == complaintId) {
          c.status = status;
          break;
        }
      }
    }
    return ok;
  }

  // ── Supabase bridge ──────────────────────────────────────────────────

  static Future<void> _remoteInsert(Complaint c) async {
    try {
      await Supabase.instance.client.from('complaints').insert({
        'id': c.id,
        'usta_id': c.ustaId,
        'usta_name': c.ustaName,
        'client_label': c.clientLabel,
        'order_id': c.orderId,
        'reason': c.reason,
        'comment': c.comment,
        'status': c.status,
      });
    } catch (e) {
      if (kDebugMode) {
        // ignore: avoid_print
        print('[complaints] insert skipped: $e');
      }
    }
  }

  static Future<bool> _remoteUpdateStatus(String id, String status) async {
    try {
      final res = await Supabase.instance.client
          .from('complaints')
          .update({'status': status})
          .eq('id', id)
          .select();
      return (res as List).isNotEmpty;
    } catch (e) {
      if (kDebugMode) {
        // ignore: avoid_print
        print('[complaints] update failed: $e');
      }
      return false;
    }
  }

  /// Pure read used by [UstaSuspensionGate]. Kept in this provider so all
  /// complaint state stays co-located.
  static bool hasActiveAgainst(String ustaId) =>
      _all.any((c) => c.ustaId == ustaId && c.status == 'under_review');
}

// ─────────────────────────────────────────────────────────────────────────────
//  SUSPENSION GATE — single public read used by the marketplace listing.
//
//  Stays in the admin module by design: if the admin module is removed, the
//  listing's filter call short-circuits to `false` and nothing breaks.
// ─────────────────────────────────────────────────────────────────────────────

class UstaSuspensionGate {
  /// Returns true when [ustaId] has an unresolved `under_review` complaint.
  /// The marketplace listing hides suspended ustalar until admin clears them.
  static bool isSuspended(String ustaId) =>
      ComplaintProvider.hasActiveAgainst(ustaId);
}
