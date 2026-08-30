import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../admin/data/telemetry_service.dart';
// NOTE: This is the admin-web build. The mobile-only `UstaModel` import
// is removed here; the `approvedAsUstaModels()` helper has been stripped
// because the admin panel never renders the public marketplace listing.

// ═══════════════════════════════════════════════════════════════════════════════
//  USTA REGISTRATION PROVIDER — self-onboarding flow.
//
//  Single source of truth for all usta self-registrations. Each entry starts
//  with status='pending' and is INVISIBLE to the marketplace until an admin
//  flips it to 'approved' from the Admin Panel.
//
//  Three states:
//    pending  → in admin queue, hidden from MockUstaProvider
//    approved → visible in marketplace (forProvince / forSpecialty)
//    rejected → hidden everywhere except admin audit log
//
//  Privacy / Zero-Leak:
//    - The full phone number is stored in [UstaRegistration.phone] for
//      backend-only use (Supabase RLS gates who can read it).
//    - The public getter [phoneMasked] returns "+998 ** *** ** 67" (last 4)
//      and is the ONLY string the Admin Panel UI ever renders.
//    - A submission also fires a `usta_registration_submit` flow telemetry
//      event with the category bucket only — no name / phone / address.
//
//  Required Supabase schema (apply once via SQL editor):
//
//    create table if not exists public.usta_registrations (
//      id text primary key,
//      name text not null,
//      phone text not null,
//      category text not null,
//      province_id int not null,
//      experience_years int not null,
//      status text not null default 'pending',  -- pending|approved|rejected
//      submitted_at timestamptz default now()
//    );
//    alter table public.usta_registrations enable row level security;
//    create policy "anon insert" on public.usta_registrations
//      for insert to anon with check (true);
//    create policy "admin read" on public.usta_registrations
//      for select using (
//        exists (select 1 from public.profiles
//                where id = auth.uid() and role = 'admin'));
//    create policy "admin update" on public.usta_registrations
//      for update using (
//        exists (select 1 from public.profiles
//                where id = auth.uid() and role = 'admin'));
// ═══════════════════════════════════════════════════════════════════════════════

class UstaRegistration {
  final String id;
  final String name;
  final String phone;             // stored — masked in admin UI
  final String category;          // 'Elektrik' | 'Santexnik' | ...
  final int provinceId;
  final int experienceYears;
  String status;                  // 'pending' | 'approved' | 'rejected'
  final DateTime submittedAt;
  String? prevCategory;           // set when a re-edit sent an approved usta
                                  // back to 'pending' (the OLD specialty)
  final String providerType;      // 'individual' | 'business' (MCHJ/firm)

  UstaRegistration({
    required this.id,
    required this.name,
    required this.phone,
    required this.category,
    required this.provinceId,
    required this.experienceYears,
    required this.status,
    required this.submittedAt,
    this.prevCategory,
    this.providerType = 'individual',
  });

  /// True for a company / MCHJ (equipment owner), false for an individual usta.
  bool get isBusiness => providerType == 'business';

  /// Zero-Leak: returns "+998 ** *** ** 67" so the admin can identify the
  /// applicant without exposing the full number on screen / in screenshots.
  String get phoneMasked {
    final d = phone.replaceAll(RegExp(r'\D'), '');
    if (d.length < 4) return '+•••••';
    final last4 = d.substring(d.length - 4);
    return '+••• •• ••• ${last4.substring(0, 2)} ${last4.substring(2, 4)}';
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'phone': phone,
        'category': category,
        'province_id': provinceId,
        'experience_years': experienceYears,
        'status': status,
        'submitted_at': submittedAt.toIso8601String(),
      };
}

/// Thrown by [UstaRegistrationProvider.submit] when the supplied phone
/// number already maps to an existing registration. The caller (typically
/// the registration form) should catch this and show a friendly UI
/// message that includes the existing entry's current status.
class DuplicatePhoneException implements Exception {
  final UstaRegistration existing;
  DuplicatePhoneException(this.existing);
  @override
  String toString() =>
      'DuplicatePhoneException(status=${existing.status}, id=${existing.id})';
}

class UstaRegistrationProvider {
  /// In-memory mirror — always available even when Supabase is offline / when
  /// the `usta_registrations` table is not yet provisioned. Admin Panel reads
  /// from here so the QA loop never gets stuck on a backend dependency.
  static final List<UstaRegistration> _all = [];

  // ── Submission ──────────────────────────────────────────────────────────

  /// Exception thrown when a phone is already registered.
  /// Caught by [UstaRegistrationPage] to show a friendly error message
  /// instead of silently submitting a duplicate.
  static UstaRegistration? checkDuplicatePhone(String phone) =>
      findByPhone(phone);

  /// Persists a new registration. Fire-and-forget for the remote write —
  /// the user sees an instant success even if the Supabase table is missing.
  ///
  /// Throws [_DuplicatePhoneException] if the phone is already in use by
  /// any existing registration (regardless of status). Caller must catch
  /// this and show a user-facing error.
  static UstaRegistration submit({
    required String name,
    required String phone,
    required String category,
    required int provinceId,
    required int experienceYears,
  }) {
    // Phone uniqueness gate — must match the UNIQUE constraint on the DB
    // column so server and client agree. Without this check the Supabase
    // insert would fail with a Postgres error and the user would see a
    // confusing crash instead of a clear message.
    final existing = findByPhone(phone);
    if (existing != null) {
      throw DuplicatePhoneException(existing);
    }
    final id = 'reg-${DateTime.now().millisecondsSinceEpoch}';
    final reg = UstaRegistration(
      id: id,
      name: name,
      phone: phone,
      category: category,
      provinceId: provinceId,
      experienceYears: experienceYears,
      status: 'pending',
      submittedAt: DateTime.now(),
    );
    _all.add(reg);
    // Flow telemetry: bucket only, no PII.
    TelemetryService.instance.recordFlowEvent(
      eventId: 'usta_registration_submit',
      payload: {
        'category': category,
        'province_id': provinceId,
        'experience_years': experienceYears,
      },
    );
    unawaited(_persistRemote(reg));
    return reg;
  }

  static Future<void> _persistRemote(UstaRegistration reg) async {
    try {
      await Supabase.instance.client
          .from('usta_registrations')
          .insert(reg.toJson());
    } catch (e) {
      // Silent fallback — local mirror already has the row. Admin Panel
      // shows it the same way regardless of remote outcome.
      if (kDebugMode) {
        // ignore: avoid_print
        print('[usta_registration] remote insert skipped: $e');
      }
    }
  }

  // ── Admin actions ───────────────────────────────────────────────────────

  /// Flips [id]'s status to 'approved' and pushes the change remotely.
  /// The next render of UstaListingPage / cross-sell will include this usta.
  static Future<bool> approve(String id) => _setStatus(id, 'approved');

  static Future<bool> reject(String id) => _setStatus(id, 'rejected');

  /// Writes the status to Supabase FIRST and only mutates the in-memory
  /// mirror when the DB confirms the change — so the admin never sees a fake
  /// "success" when the write was blocked (RLS) or failed (network). Returns
  /// true only when a row was actually updated.
  static Future<bool> _setStatus(String id, String status) async {
    final ok = await _updateRemote(id, status);
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

  /// Returns true when the update touched a row. Uses `.select()` so an
  /// RLS-blocked update (0 rows, no exception) reports failure instead of a
  /// silent no-op.
  static Future<bool> _updateRemote(String id, String status) async {
    try {
      final res = await Supabase.instance.client
          .from('usta_registrations')
          .update({'status': status})
          .eq('id', id)
          .select();
      return (res as List).isNotEmpty;
    } catch (e) {
      if (kDebugMode) {
        // ignore: avoid_print
        print('[usta_registration] remote update failed: $e');
      }
      return false;
    }
  }

  // ── Cloud fetch ──────────────────────────────────────────────────────

  /// Tracks whether the cloud sync has been attempted at least once this
  /// app session. Pages use this to show a one-shot loading spinner.
  static bool _hasFetched = false;
  static bool get hasFetched => _hasFetched;

  /// Loads ALL rows from Supabase (`usta_registrations`) and merges them
  /// into the in-memory list. De-duped by `id`. Local-only entries
  /// (submitted in this session before cloud reach) are preserved.
  ///
  /// Called from UstaListingPage on first open so the marketplace shows
  /// approved ustalar from the database. Safe to call repeatedly — only
  /// new ids are appended; existing rows are refreshed.
  ///
  /// Pass [force]=true from manual refresh handlers to bypass the
  /// [hasFetched] guard (used by the admin web's "Yangilash" button).
  static Future<void> fetchAllFromCloud({bool force = false}) async {
    if (_hasFetched && !force) return;
    try {
      final rows = await Supabase.instance.client
          .from('usta_registrations')
          .select('*');
      final existingById = {for (final r in _all) r.id: r};
      for (final raw in rows as List) {
        final m = Map<String, dynamic>.from(raw as Map);
        final id = (m['id'] ?? '').toString();
        if (id.isEmpty) continue;
        final entry = UstaRegistration(
          id: id,
          name: (m['name'] ?? '').toString(),
          phone: (m['phone'] ?? '').toString(),
          category: (m['category'] ?? '').toString(),
          provinceId: (m['province_id'] ?? 0) is int
              ? m['province_id'] as int
              : int.tryParse('${m['province_id']}') ?? 0,
          experienceYears: (m['experience_years'] ?? 0) is int
              ? m['experience_years'] as int
              : int.tryParse('${m['experience_years']}') ?? 0,
          status: (m['status'] ?? 'pending').toString(),
          submittedAt:
              DateTime.tryParse((m['submitted_at'] ?? '').toString()) ??
                  DateTime.now(),
          prevCategory: (m['prev_category'] as String?),
          providerType: (m['provider_type'] ?? 'individual').toString(),
        );
        if (existingById.containsKey(id)) {
          // Refresh status + prev-category in case it changed remotely.
          existingById[id]!.status = entry.status;
          existingById[id]!.prevCategory = entry.prevCategory;
        } else {
          _all.add(entry);
        }
      }
    } catch (e) {
      if (kDebugMode) {
        // ignore: avoid_print
        print('[usta_registration] cloud fetch failed: $e');
      }
    } finally {
      _hasFetched = true;
    }
  }

  // ── Reads ──────────────────────────────────────────────────────────────

  static List<UstaRegistration> pending() =>
      _all.where((r) => r.status == 'pending').toList()
        ..sort((a, b) => b.submittedAt.compareTo(a.submittedAt));

  /// Returns all registrations regardless of status. Used by Admin Panel
  /// when filtering by tabs (All / Pending / Approved / Rejected).
  static List<UstaRegistration> allRegistrations() =>
      List<UstaRegistration>.from(_all)
        ..sort((a, b) => b.submittedAt.compareTo(a.submittedAt));

  /// Looks up an existing registration by phone (normalised — only digits
  /// compared). Returns null if no entry matches. Used by [submit] to
  /// block duplicate phone registrations and by the client login flow
  /// to detect "this phone is already an approved usta".
  static UstaRegistration? findByPhone(String phone) {
    final normalized = phone.replaceAll(RegExp(r'\D'), '');
    if (normalized.isEmpty) return null;
    for (final r in _all) {
      final candidate = r.phone.replaceAll(RegExp(r'\D'), '');
      if (candidate == normalized) return r;
    }
    return null;
  }

  /// Cloud-first lookup by phone. Forces a fresh fetch from Supabase first
  /// (so a usta who was approved on another device is still detected) then
  /// falls back to the in-memory lookup. Called from LoginController after
  /// a successful OTP verification to bind the user to their usta identity.
  ///
  /// Returns null when no row matches OR when the row's status != 'approved'.
  static Future<UstaRegistration?> findApprovedByPhoneFromCloud(
      String phone) async {
    await fetchAllFromCloud();
    final reg = findByPhone(phone);
    if (reg == null || reg.status != 'approved') return null;
    return reg;
  }

  /// Soft-deletes a registration. Sets status to 'deleted' so the entry
  /// is hidden everywhere (marketplace, admin queue) but the row stays
  /// in Supabase for audit. [restore] brings it back; [purge] ends it.
  static Future<bool> softDelete(String id) => _setStatus(id, 'deleted');

  /// Brings a binned registration back — to 'pending', never straight to
  /// 'approved'.
  ///
  /// The status column keeps no memory of what the row was before it was
  /// binned, so restoring to 'approved' would be a guess, and a wrong guess
  /// puts a provider in front of customers again with nobody having decided
  /// that. Landing in the moderation queue costs one more click and cannot
  /// republish anyone by accident — the same reason the product bin restores
  /// to draft rather than to published.
  static Future<bool> restore(String id) => _setStatus(id, 'pending');

  /// Permanently removes a binned registration, with the clean-up the schema
  /// does not cascade: chat rooms (their messages follow) and reviews.
  /// Complaints are kept — they are a moderation record and carry their own
  /// copy of the name, so they still read correctly afterwards.
  ///
  /// Goes through the admin_purge_usta RPC rather than deleting from here,
  /// because usta_registrations has policies for read, update and insert and
  /// NO delete policy: a client-side delete matches zero rows and reports
  /// success. The RPC also refuses a row that is not already in the bin, so
  /// nothing can be destroyed straight from the live list.
  static Future<bool> purge(String id) async {
    try {
      final res = await Supabase.instance.client
          .rpc('admin_purge_usta', params: {'p_id': id});
      final row = (res is List && res.isNotEmpty) ? res.first : res;
      final ok = row is Map && row['r_ok'] == true;
      if (ok) _all.removeWhere((r) => r.id == id);
      return ok;
    } catch (e) {
      if (kDebugMode) {
        // ignore: avoid_print
        print('[usta_registration] purge failed: $e');
      }
      return false;
    }
  }

  /// Admin action: revoke approval. Sets status back to 'rejected' so the
  /// usta is removed from the marketplace listing but kept in the queue
  /// for audit (admin can re-approve later if it was a mistake).
  static Future<bool> suspend(String id) => _setStatus(id, 'rejected');

  // approvedAsUstaModels() — REMOVED in admin-web build (marketplace-only)

  /// True when the id maps to a registration that is NOT yet approved.
  /// MockUstaProvider's filters use this to hide pending applicants
  /// from the public marketplace.
  static bool isHiddenFromMarketplace(String id) {
    for (final r in _all) {
      if (r.id == id) return r.status != 'approved';
    }
    return false; // not a self-registered usta → always visible
  }
}
