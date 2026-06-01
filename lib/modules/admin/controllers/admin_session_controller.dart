import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// ═══════════════════════════════════════════════════════════════════════════════
//  ADMIN SESSION CONTROLLER — Phase 2 (Cloud Identity)
//
//  Role check now lives in Supabase `public.profiles.role` (text column).
//  The local Rx flag `isAdmin` is a CACHED VIEW of the cloud verification —
//  it is intentionally NOT persisted to GetStorage, so every cold start is
//  forced through the cloud verification path. This eliminates the previous
//  attack surface where a tampered local key could escalate role.
//
//  Required schema (apply once via Supabase SQL editor):
//
//    create table if not exists public.profiles (
//      id uuid references auth.users on delete cascade primary key,
//      email text,
//      role text not null default 'user', -- 'user' | 'usta' | 'admin'
//      created_at timestamptz default now()
//    );
//
//    alter table public.profiles enable row level security;
//    create policy "profiles self-read"
//      on public.profiles for select
//      using (auth.uid() = id);
//
//  Three entry paths:
//    1. signInWithEmail(email, password) → Supabase auth + role lookup
//    2. verifyCurrentSession()           → if there's already a session,
//                                          re-query role (force-login gate)
//    3. unlockWithDemoPasscode(code)     → demo-only fallback for Phase 1
//                                          parity; gated by kDebugMode so it
//                                          never ships in a release build.
// ═══════════════════════════════════════════════════════════════════════════════

class AdminSessionController extends GetxController {
  static const String _demoPasscode = '9999';
  // This panel is the dedicated USTA admin — only the 'usta_admin' role may
  // enter (kept separate from the product admin / super_admin).
  static const String _adminRoleValue = 'usta_admin';

  /// Cached view of the LATEST cloud verification. Never persisted —
  /// re-derived on every entry to the Admin Panel.
  final isAdmin = false.obs;

  /// Email of the verified admin (for the "logged in as …" header).
  final adminEmail = ''.obs;

  /// Set to a non-null Supabase client reference on first use. Lets us
  /// stay decoupled from Supabase.instance when tests mock the client.
  SupabaseClient get _client => Supabase.instance.client;

  // ── Cloud paths ──────────────────────────────────────────────────────────

  /// Force-login flow used by Web /admin and Mobile long-press entry.
  /// Returns null on success, a user-facing error message on failure.
  Future<String?> signInWithEmail({
    required String email,
    required String password,
  }) async {
    try {
      final res = await _client.auth.signInWithPassword(
        email: email.trim(),
        password: password,
      );
      final user = res.user;
      if (user == null) return "Kirish muvaffaqiyatsiz tugadi";
      return await _verifyRoleForUser(user.id, fallbackEmail: user.email);
    } on AuthException catch (e) {
      return e.message;
    } catch (e) {
      return "Server bilan bog'lanib bo'lmadi: $e";
    }
  }

  /// Re-verifies the current Supabase session against `profiles.role`.
  /// Called by the AdminEntryRoute every time the route is hit, so an
  /// admin whose role was revoked server-side loses access on next nav.
  Future<bool> verifyCurrentSession() async {
    try {
      final user = _client.auth.currentUser;
      if (user == null) {
        _clear();
        return false;
      }
      final err = await _verifyRoleForUser(user.id, fallbackEmail: user.email);
      return err == null;
    } catch (_) {
      _clear();
      return false;
    }
  }

  /// Reads `profiles.role` for the given Supabase auth user id. Sets
  /// [isAdmin] true on success, clears state on failure. Returns null on
  /// success or a user-facing error message on failure.
  Future<String?> _verifyRoleForUser(
    String userId, {
    String? fallbackEmail,
  }) async {
    try {
      final row = await _client
          .from('profiles')
          .select('role, email')
          .eq('id', userId)
          .maybeSingle();
      if (row == null) {
        _clear();
        return "Profil topilmadi";
      }
      final role = (row['role'] ?? '').toString().toLowerCase();
      if (role != _adminRoleValue) {
        _clear();
        return "Ushbu hisob admin emas";
      }
      isAdmin.value = true;
      adminEmail.value = (row['email'] ?? fallbackEmail ?? '').toString();
      return null;
    } on PostgrestException catch (e) {
      _clear();
      return "Server xatosi: ${e.message}";
    } catch (e) {
      _clear();
      return "Tekshirib bo'lmadi: $e";
    }
  }

  /// Signs out of Supabase and clears the local cached flag.
  Future<void> signOut() async {
    try {
      await _client.auth.signOut();
    } catch (_) {
      /* ignore — we always clear local state below */
    }
    _clear();
  }

  void _clear() {
    isAdmin.value = false;
    adminEmail.value = '';
  }

  // ── Demo passcode fallback (debug builds only) ──────────────────────────

  /// Returns true when the supplied passcode unlocks admin mode for demos.
  /// **Refuses to unlock in release builds** — preserves the Zero-Impact +
  /// Force-Login guarantees for production while keeping Phase-1 parity
  /// available during local development.
  bool unlockWithDemoPasscode(String code) {
    if (!kDebugMode) return false;
    if (code.trim() == _demoPasscode) {
      isAdmin.value = true;
      adminEmail.value = 'demo@local';
      return true;
    }
    return false;
  }

  /// Back-compat shim — kept so the old mobile long-press entry still
  /// compiles. Routes to the same demo passcode check.
  bool unlock(String code) => unlockWithDemoPasscode(code);

  /// Back-compat shim — used by older Admin Panel "Chiqish" button.
  void lock() => _clear();

  // ── Singleton bootstrap ─────────────────────────────────────────────────

  static AdminSessionController ensure() {
    if (!Get.isRegistered<AdminSessionController>()) {
      return Get.put(AdminSessionController(), permanent: true);
    }
    return Get.find<AdminSessionController>();
  }
}
