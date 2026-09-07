import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get.dart';

import '../controllers/admin_session_controller.dart';
import '../data/mock_admin_data.dart';
import '../data/realtime_admin_service.dart';
import 'admin_login_page.dart';
import 'analytics_page.dart';
import 'category_management_page.dart';
import 'chat_reports_page.dart';
import 'chats_moderation_page.dart';
import 'complaints_page.dart';
import 'pending_verifications_page.dart';
import 'provider_offerings_page.dart';
import 'telemetry_page.dart';

// ═══════════════════════════════════════════════════════════════════════════════
//  ADMIN PANEL — owner-only dashboard.
//
//  Web-first dashboard for managing Mediro Usta-Market. Three responsive
//  breakpoints:
//
//    ≥ 1280 px → DESKTOP layout: persistent left sidebar (Verifications /
//                Complaints / Telemetry), header bar with search-shortcuts
//                hint and admin email, single content surface on the right.
//                Keyboard shortcuts: Alt+1, Alt+2, Alt+3 switch sections.
//
//    ≥ 1100 px → TABLET layout: two-column overview (Verifications +
//                Complaints side by side) with a tile row underneath.
//
//    <  1100 px → MOBILE layout: stacked tile list (the original phone UI).
//
//  Sidebar nav is decoupled from Navigator — the embedded pages render
//  inside the right pane via an IndexedStack so admins stay in the same
//  shell while switching sections (no back button needed).
// ═══════════════════════════════════════════════════════════════════════════════

class AdminPanelPage extends StatefulWidget {
  const AdminPanelPage({super.key});

  @override
  State<AdminPanelPage> createState() => _AdminPanelPageState();
}

class _AdminPanelPageState extends State<AdminPanelPage> {
  /// 0 = Verifications, 1 = Complaints, 2 = Telemetry. Persisted in-memory
  /// only — survives navigation inside the panel, resets on full reload.
  int _selectedSection = 0;

  /// FocusNode that owns keyboard shortcuts (Alt+1/2/3). Attached at the
  /// scaffold root so the shortcuts fire regardless of which inner widget
  /// has focus.
  final FocusNode _shortcutFocus = FocusNode();

  /// Subscription to RealtimeAdminService — lets the panel show toast
  /// notifications and bump sidebar counters when a new application or
  /// complaint arrives, even if the admin is on a different section.
  StreamSubscription<RealtimeAdminEvent>? _realtimeSub;

  /// Quick mute toggle bound to RealtimeAdminService.isSoundEnabled —
  /// used by the sidebar's bell icon.
  bool _soundOn = true;

  void _refresh() => setState(() {});

  @override
  void initState() {
    super.initState();
    _soundOn = RealtimeAdminService.instance.isSoundEnabled;

    // Grab keyboard focus once first frame ships so Alt+N shortcuts work
    // without the user having to click into the panel first.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      _shortcutFocus.requestFocus();

      // Start the Supabase Realtime channels (idempotent).
      await RealtimeAdminService.instance.start();

      // Ask for browser Notification permission once. Browsers will
      // short-circuit if the user already chose. The prompt only fires
      // on the first admin login per browser profile.
      await RealtimeAdminService.instance.requestNotificationPermission();
    });

    // Listen for realtime arrivals so we can refresh counters + show toasts.
    _realtimeSub =
        RealtimeAdminService.instance.events.listen(_onRealtimeEvent);
  }

  @override
  void dispose() {
    _shortcutFocus.dispose();
    _realtimeSub?.cancel();
    super.dispose();
  }

  /// Reacts to every realtime event so the panel feels live:
  /// - Bumps the badge counts (via setState that re-reads providers).
  /// - Shows a Get.snackbar toast for new registrations + complaints.
  void _onRealtimeEvent(RealtimeAdminEvent ev) {
    if (!mounted) return;
    setState(() {/* badges read fresh in build */});
    switch (ev.kind) {
      case RealtimeAdminEventKind.registrationInserted:
        // Both states are worth a toast since auto-approval (2026-09-07): a
        // provider who arrives already 'approved' is LIVE, so they are the one
        // that actually needs eyes. Testing only for 'pending' here made the
        // panel silent for every real joiner. Amber, not blue, for that case —
        // it is a review to do, not a queue item to work through.
        if (ev.status == 'pending' || ev.status == 'approved') {
          final live = ev.status == 'approved';
          Get.snackbar(
            live ? "Yangi usta qo'shildi" : 'Yangi ariza',
            '${ev.name} — ${ev.category}',
            snackPosition: SnackPosition.TOP,
            backgroundColor:
                live ? const Color(0xFFB45309) : const Color(0xFF1976D2),
            colorText: Colors.white,
            margin: const EdgeInsets.all(12),
            borderRadius: 10,
            duration: const Duration(seconds: 4),
            icon: const Icon(Icons.person_add_alt_1_rounded,
                color: Colors.white),
          );
        }
        break;
      case RealtimeAdminEventKind.chatReportInserted:
        // Red, like a complaint: this is somebody saying a listing or a
        // conversation is abusive, and it is the control the stores ask about.
        Get.snackbar(
          ev.category == 'profile'
              ? 'Yangi shikoyat — profil'
              : 'Yangi shikoyat — chat',
          ev.reason,
          snackPosition: SnackPosition.TOP,
          backgroundColor: const Color(0xFFD32F2F),
          colorText: Colors.white,
          margin: const EdgeInsets.all(12),
          borderRadius: 10,
          duration: const Duration(seconds: 4),
          icon: const Icon(Icons.flag_rounded, color: Colors.white),
        );
        break;
      case RealtimeAdminEventKind.complaintInserted:
        Get.snackbar(
          'Yangi shikoyat',
          ev.name.isNotEmpty ? '${ev.name} — ${ev.reason}' : ev.reason,
          snackPosition: SnackPosition.TOP,
          backgroundColor: const Color(0xFFD32F2F),
          colorText: Colors.white,
          margin: const EdgeInsets.all(12),
          borderRadius: 10,
          duration: const Duration(seconds: 4),
          icon: const Icon(Icons.warning_amber_rounded, color: Colors.white),
        );
        break;
      case RealtimeAdminEventKind.registrationUpdated:
        // Quiet status flip from another admin tab — no toast needed.
        break;
    }
  }

  void _toggleSound() {
    final next = !_soundOn;
    RealtimeAdminService.instance.isSoundEnabled = next;
    setState(() => _soundOn = next);
  }

  Future<void> _signOut() async {
    await RealtimeAdminService.instance.stop();
    await AdminSessionController.ensure().signOut();
    if (!mounted) return;
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    } else {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const AdminLoginPage()),
      );
    }
  }

  void _selectSection(int idx) {
    if (_selectedSection == idx) return;
    setState(() => _selectedSection = idx);
  }

  @override
  Widget build(BuildContext context) {
    final pending = PendingVerificationProvider.pendingCount();
    final openComplaints = ComplaintProvider.openCount();
    final adminEmail = AdminSessionController.ensure().adminEmail.value;

    return Focus(
      focusNode: _shortcutFocus,
      autofocus: true,
      onKeyEvent: _handleShortcut,
      child: Scaffold(
        backgroundColor: const Color(0xFFF7F8FA),
        body: LayoutBuilder(builder: (context, c) {
          if (c.maxWidth >= 1280) {
            return _buildDesktopShell(
                pending, openComplaints, adminEmail);
          }
          if (c.maxWidth >= 1100) {
            return _buildTabletShell(
                pending, openComplaints, adminEmail);
          }
          return _buildMobileShell(pending, openComplaints, adminEmail);
        }),
      ),
    );
  }

  /// Alt+1/2/3 — switch sections in the desktop sidebar.
  KeyEventResult _handleShortcut(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (!HardwareKeyboard.instance.isAltPressed) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.digit1) {
      _selectSection(0);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.digit2) {
      _selectSection(1);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.digit3) {
      _selectSection(2);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.digit4) {
      _selectSection(3);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.digit5) {
      _selectSection(4);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.digit6) {
      _selectSection(5);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.digit7) {
      _selectSection(6);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  // ───────────────────────────────────────────────────────────────────────────
  //  DESKTOP SHELL (≥1280 px) — sidebar + content pane.
  // ───────────────────────────────────────────────────────────────────────────

  Widget _buildDesktopShell(
      int pending, int openComplaints, String adminEmail) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _DesktopSidebar(
          selectedIndex: _selectedSection,
          pendingBadge: pending,
          complaintsBadge: openComplaints,
          adminEmail: adminEmail,
          onSelect: _selectSection,
          onSignOut: _signOut,
          soundOn: _soundOn,
          onToggleSound: _toggleSound,
          realtimeActive: RealtimeAdminService.instance.isStarted,
        ),
        Expanded(
          child: Column(
            children: [
              _DesktopTopBar(
                section: _selectedSection,
                pending: pending,
                complaints: openComplaints,
                adminEmail: adminEmail,
              ),
              Expanded(
                child: Container(
                  color: const Color(0xFFF7F8FA),
                  padding: const EdgeInsets.fromLTRB(28, 20, 28, 20),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1600),
                    child: _desktopContent(),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _desktopContent() {
    // IndexedStack keeps each section alive so switching tabs preserves
    // scroll position and any open dialogs — a desktop-grade UX win.
    // Each child carries a ValueKey tied to _selectedSection so that a
    // future code path can force a remount if needed. The pages
    // themselves now fetch fresh Supabase data on every mount via
    // fetchAllFromCloud(force: true), so simply scrolling to a section
    // is enough to get the latest queue.
    return IndexedStack(
      index: _selectedSection,
      children: const [
        PendingVerificationsPage(embedded: true),
        ComplaintsPage(embedded: true),
        TelemetryPage(embedded: true),
        ChatsModerationPage(embedded: true),
        AnalyticsPage(embedded: true),
        CategoryManagementPage(embedded: true),
        ProviderOfferingsPage(embedded: true),
        ChatReportsPage(embedded: true),
      ],
    );
  }

  // ───────────────────────────────────────────────────────────────────────────
  //  TABLET SHELL (≥1100 px) — original 2-column overview.
  // ───────────────────────────────────────────────────────────────────────────

  Widget _buildTabletShell(
      int pending, int openComplaints, String adminEmail) {
    return Column(
      children: [
        _classicAppBar(adminEmail),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(28, 24, 28, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (adminEmail.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Text(
                      'Welcome back, $adminEmail',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF1F2937),
                      ),
                    ),
                  ),
                _SummaryRow(pending: pending, complaints: openComplaints),
                const SizedBox(height: 18),
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: _DesktopColumn(
                          title: 'admin_tile_verif_sub'.tr,
                          color: const Color(0xFF1976D2),
                          badge: pending,
                          child: const PendingVerificationsPage(
                              embedded: true),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: _DesktopColumn(
                          title: 'admin_tile_complaints_sub'.tr,
                          color: const Color(0xFFD32F2F),
                          badge: openComplaints,
                          child: const ComplaintsPage(embedded: true),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                _rbacFooter(),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ───────────────────────────────────────────────────────────────────────────
  //  MOBILE SHELL (<1100 px) — original stacked tile list.
  // ───────────────────────────────────────────────────────────────────────────

  Widget _buildMobileShell(
      int pending, int openComplaints, String adminEmail) {
    return Column(
      children: [
        _classicAppBar(adminEmail),
        Expanded(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: ListView(
                padding: EdgeInsets.fromLTRB(14.w, 14.h, 14.w, 24.h),
                children: [
                  _SummaryRow(pending: pending, complaints: openComplaints),
                  SizedBox(height: 14.h),
                  _AdminTile(
                    icon: Icons.verified_user_rounded,
                    color: const Color(0xFF1976D2),
                    title: 'admin_tile_verif_title'.tr,
                    subtitle: 'admin_tile_verif_sub'.tr,
                    badge: pending > 0 ? '$pending' : null,
                    onTap: () async {
                      await Navigator.of(context).push(MaterialPageRoute(
                          builder: (_) =>
                              const PendingVerificationsPage()));
                      _refresh();
                    },
                  ),
                  SizedBox(height: 10.h),
                  _AdminTile(
                    icon: Icons.report_gmailerrorred_rounded,
                    color: const Color(0xFFD32F2F),
                    title: 'admin_tile_complaints_title'.tr,
                    subtitle: 'admin_tile_complaints_sub'.tr,
                    badge: openComplaints > 0 ? '$openComplaints' : null,
                    onTap: () async {
                      await Navigator.of(context).push(MaterialPageRoute(
                          builder: (_) => const ComplaintsPage()));
                      _refresh();
                    },
                  ),
                  SizedBox(height: 10.h),
                  _AdminTile(
                    icon: Icons.insights_rounded,
                    color: const Color(0xFF6D28D9),
                    title: 'admin_tile_telemetry_title'.tr,
                    subtitle: 'admin_tile_telemetry_sub'.tr,
                    badge: 'BETA',
                    onTap: () async {
                      await Navigator.of(context).push(MaterialPageRoute(
                          builder: (_) => const TelemetryPage()));
                      _refresh();
                    },
                  ),
                  SizedBox(height: 18.h),
                  _rbacFooter(),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ───────────────────────────────────────────────────────────────────────────
  //  Shared chrome bits.
  // ───────────────────────────────────────────────────────────────────────────

  PreferredSizeWidget _classicAppBar(String adminEmail) {
    return PreferredSize(
      preferredSize: const Size.fromHeight(56),
      child: AppBar(
        backgroundColor: const Color(0xFF0F172A),
        foregroundColor: Colors.white,
        elevation: 0,
        leading: Navigator.of(context).canPop()
            ? IconButton(
                icon:
                    const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
                onPressed: () => Navigator.of(context).pop(),
              )
            : null,
        title: Row(children: [
          Icon(Icons.admin_panel_settings_rounded,
              size: 18.sp, color: Colors.amber.shade300),
          SizedBox(width: 8.w),
          Text(
            'admin_panel_title'.tr,
            style: TextStyle(
              fontSize: 16.sp,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.2,
            ),
          ),
        ]),
        actions: [
          if (adminEmail.isNotEmpty)
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 10.w),
              child: Center(
                child: Text(
                  adminEmail,
                  style: TextStyle(
                    fontSize: 11.sp,
                    color: Colors.white70,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          IconButton(
            tooltip: 'admin_sign_out_tooltip'.tr,
            icon: const Icon(Icons.logout_rounded, size: 18),
            onPressed: _signOut,
          ),
        ],
      ),
    );
  }

  Widget _rbacFooter() {
    return Container(
      padding: EdgeInsets.all(12.w),
      decoration: BoxDecoration(
        color: Colors.amber.withOpacity(0.10),
        borderRadius: BorderRadius.circular(10.r),
        border:
            Border.all(color: Colors.amber.withOpacity(0.40), width: 1),
      ),
      child: Row(children: [
        Icon(Icons.shield_moon_rounded,
            size: 16.sp, color: Colors.amber.shade800),
        SizedBox(width: 8.w),
        Expanded(
          child: Text(
            'admin_rbac_note'.tr,
            style: TextStyle(
              fontSize: 11.sp,
              color: const Color(0xFF92400E),
              fontWeight: FontWeight.w600,
              height: 1.35,
            ),
          ),
        ),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  DESKTOP SIDEBAR (≥1280 px) — persistent nav rail with brand, sections,
//  admin identity, and sign-out. Fixed 240 px wide so the content pane has
//  predictable space.
// ─────────────────────────────────────────────────────────────────────────────
class _DesktopSidebar extends StatelessWidget {
  final int selectedIndex;
  final int pendingBadge;
  final int complaintsBadge;
  final String adminEmail;
  final ValueChanged<int> onSelect;
  final VoidCallback onSignOut;
  final bool soundOn;
  final VoidCallback onToggleSound;
  final bool realtimeActive;

  const _DesktopSidebar({
    required this.selectedIndex,
    required this.pendingBadge,
    required this.complaintsBadge,
    required this.adminEmail,
    required this.onSelect,
    required this.onSignOut,
    required this.soundOn,
    required this.onToggleSound,
    required this.realtimeActive,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 240,
      decoration: const BoxDecoration(
        color: Color(0xFF0F172A),
        boxShadow: [
          BoxShadow(
            color: Color(0x22000000),
            blurRadius: 12,
            offset: Offset(2, 0),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Brand row + sound toggle + realtime status pill
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 22, 12, 14),
            child: Row(children: [
              Icon(Icons.admin_panel_settings_rounded,
                  size: 22, color: Colors.amber.shade300),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'Mediro Admin',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.2,
                  ),
                ),
              ),
              // Live indicator: green dot pulses when realtime is up.
              if (realtimeActive)
                Tooltip(
                  message: 'Realtime ulanish faol',
                  child: Container(
                    width: 8,
                    height: 8,
                    margin: const EdgeInsets.only(right: 8),
                    decoration: const BoxDecoration(
                      color: Color(0xFF22C55E),
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Color(0x9922C55E),
                          blurRadius: 6,
                          spreadRadius: 1,
                        ),
                      ],
                    ),
                  ),
                ),
              // Bell mute toggle.
              IconButton(
                tooltip:
                    soundOn ? "Ovozni o'chirish" : "Ovozni yoqish",
                padding: EdgeInsets.zero,
                constraints:
                    const BoxConstraints(minWidth: 32, minHeight: 32),
                onPressed: onToggleSound,
                icon: Icon(
                  soundOn
                      ? Icons.notifications_active_rounded
                      : Icons.notifications_off_rounded,
                  size: 18,
                  color: soundOn
                      ? Colors.amber.shade300
                      : Colors.white54,
                ),
              ),
            ]),
          ),
          const Divider(height: 1, color: Color(0x22FFFFFF)),
          const SizedBox(height: 10),
          _SidebarItem(
            icon: Icons.verified_user_rounded,
            label: 'admin_tile_verif_title'.tr,
            shortcut: 'Alt+1',
            badge: pendingBadge > 0 ? '$pendingBadge' : null,
            badgeColor: const Color(0xFF1976D2),
            selected: selectedIndex == 0,
            onTap: () => onSelect(0),
          ),
          _SidebarItem(
            icon: Icons.report_gmailerrorred_rounded,
            label: 'admin_tile_complaints_title'.tr,
            shortcut: 'Alt+2',
            badge: complaintsBadge > 0 ? '$complaintsBadge' : null,
            badgeColor: const Color(0xFFD32F2F),
            selected: selectedIndex == 1,
            onTap: () => onSelect(1),
          ),
          _SidebarItem(
            icon: Icons.insights_rounded,
            label: 'admin_tile_telemetry_title'.tr,
            shortcut: 'Alt+3',
            badge: 'BETA',
            badgeColor: const Color(0xFF6D28D9),
            selected: selectedIndex == 2,
            onTap: () => onSelect(2),
          ),
          _SidebarItem(
            icon: Icons.forum_rounded,
            label: 'Suhbatlar',
            shortcut: 'Alt+4',
            badge: null,
            badgeColor: const Color(0xFF0891B2),
            selected: selectedIndex == 3,
            onTap: () => onSelect(3),
          ),
          _SidebarItem(
            icon: Icons.analytics_rounded,
            label: 'Analytics',
            shortcut: 'Alt+5',
            badge: 'NEW',
            badgeColor: const Color(0xFF0F766E),
            selected: selectedIndex == 4,
            onTap: () => onSelect(4),
          ),
          _SidebarItem(
            icon: Icons.category_rounded,
            label: 'cat_title'.tr,
            shortcut: 'Alt+6',
            badge: null,
            badgeColor: const Color(0xFF198754),
            selected: selectedIndex == 5,
            onTap: () => onSelect(5),
          ),
          _SidebarItem(
            icon: Icons.engineering_rounded,
            label: 'prov_title'.tr,
            shortcut: 'Alt+7',
            badge: null,
            badgeColor: const Color(0xFF0891B2),
            selected: selectedIndex == 6,
            onTap: () => onSelect(6),
          ),
          _SidebarItem(
            icon: Icons.report_problem_rounded,
            label: 'Chat shikoyatlari',
            shortcut: 'Alt+8',
            badge: null,
            badgeColor: const Color(0xFFD32F2F),
            selected: selectedIndex == 7,
            onTap: () => onSelect(7),
          ),
          const Spacer(),
          if (adminEmail.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 6),
              child: Row(children: [
                CircleAvatar(
                  radius: 13,
                  backgroundColor: Colors.amber.shade300,
                  child: Text(
                    adminEmail.isNotEmpty
                        ? adminEmail[0].toUpperCase()
                        : '?',
                    style: const TextStyle(
                      color: Color(0xFF0F172A),
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    adminEmail,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ]),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 14),
            child: Material(
              color: const Color(0x22FFFFFF),
              borderRadius: BorderRadius.circular(8),
              child: InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: onSignOut,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 10),
                  child: Row(children: [
                    const Icon(Icons.logout_rounded,
                        size: 16, color: Colors.white),
                    const SizedBox(width: 10),
                    Text(
                      'admin_sign_out_tooltip'.tr,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ]),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SidebarItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final String shortcut;
  final String? badge;
  final Color badgeColor;
  final bool selected;
  final VoidCallback onTap;

  const _SidebarItem({
    required this.icon,
    required this.label,
    required this.shortcut,
    required this.badge,
    required this.badgeColor,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
      child: Material(
        color: selected
            ? const Color(0x33FFFFFF)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(
                horizontal: 12, vertical: 10),
            child: Row(children: [
              Icon(icon,
                  size: 18,
                  color: selected
                      ? Colors.amber.shade300
                      : Colors.white70),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    color:
                        selected ? Colors.white : Colors.white.withOpacity(0.85),
                    fontSize: 13,
                    fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                  ),
                ),
              ),
              if (badge != null)
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: badgeColor,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    badge!,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                )
              else
                Text(
                  shortcut,
                  style: const TextStyle(
                    color: Colors.white38,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
                ),
            ]),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  DESKTOP TOP BAR — title of the active section + KPI summary row + small
//  shortcuts hint. Surfaces on the right pane only.
// ─────────────────────────────────────────────────────────────────────────────
class _DesktopTopBar extends StatelessWidget {
  final int section;
  final int pending;
  final int complaints;
  final String adminEmail;

  const _DesktopTopBar({
    required this.section,
    required this.pending,
    required this.complaints,
    required this.adminEmail,
  });

  String get _title {
    switch (section) {
      case 1:
        return 'admin_tile_complaints_title'.tr;
      case 2:
        return 'admin_tile_telemetry_title'.tr;
      case 0:
      default:
        return 'admin_tile_verif_title'.tr;
    }
  }

  String get _subtitle {
    switch (section) {
      case 1:
        return 'admin_tile_complaints_sub'.tr;
      case 2:
        return 'admin_tile_telemetry_sub'.tr;
      case 0:
      default:
        return 'admin_tile_verif_sub'.tr;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(28, 18, 28, 18),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(
          bottom: BorderSide(color: Color(0x14000000)),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _title,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF1F2937),
                    letterSpacing: -0.3,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _subtitle,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade600,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          _KpiPill(
            label: 'admin_stat_pending'.tr,
            value: '$pending',
            color: const Color(0xFF1976D2),
            icon: Icons.hourglass_top_rounded,
          ),
          const SizedBox(width: 10),
          _KpiPill(
            label: 'admin_stat_complaints'.tr,
            value: '$complaints',
            color: const Color(0xFFD32F2F),
            icon: Icons.warning_amber_rounded,
          ),
        ],
      ),
    );
  }
}

class _KpiPill extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  final IconData icon;
  const _KpiPill({
    required this.label,
    required this.value,
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.20)),
      ),
      child: Row(children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 8),
        Text(
          value,
          style: TextStyle(
            color: color,
            fontSize: 14,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: TextStyle(
            color: Colors.grey.shade700,
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Tablet 2-column wrapper (kept for the 1100–1280 px range).
// ─────────────────────────────────────────────────────────────────────────────
class _DesktopColumn extends StatelessWidget {
  final String title;
  final Color color;
  final int badge;
  final Widget child;

  const _DesktopColumn({
    required this.title,
    required this.color,
    required this.badge,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0x14000000)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: color.withOpacity(0.08),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(14)),
              border: Border(
                bottom: BorderSide(color: color.withOpacity(0.18)),
              ),
            ),
            child: Row(children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: color,
                ),
              ),
              const Spacer(),
              if (badge > 0)
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    '$badge',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
            ]),
          ),
          Expanded(child: child),
        ],
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  final int pending;
  final int complaints;
  const _SummaryRow({required this.pending, required this.complaints});

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Expanded(
        child: _statCard(
          label: 'admin_stat_pending'.tr,
          value: '$pending',
          color: const Color(0xFF1976D2),
          icon: Icons.hourglass_top_rounded,
        ),
      ),
      SizedBox(width: 10.w),
      Expanded(
        child: _statCard(
          label: 'admin_stat_complaints'.tr,
          value: '$complaints',
          color: const Color(0xFFD32F2F),
          icon: Icons.warning_amber_rounded,
        ),
      ),
    ]);
  }

  Widget _statCard({
    required String label,
    required String value,
    required Color color,
    required IconData icon,
  }) {
    return Container(
      padding: EdgeInsets.all(12.w),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12.r),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 10,
              offset: const Offset(0, 3)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18.sp, color: color),
          SizedBox(height: 6.h),
          Text(value,
              style: TextStyle(
                fontSize: 20.sp,
                fontWeight: FontWeight.w800,
                color: const Color(0xFF1F2937),
              )),
          Text(label,
              style: TextStyle(
                fontSize: 11.sp,
                color: Colors.grey.shade600,
                fontWeight: FontWeight.w600,
              )),
        ],
      ),
    );
  }
}

class _AdminTile extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final String? badge;
  final VoidCallback onTap;

  const _AdminTile({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.badge,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12.r),
      child: InkWell(
        borderRadius: BorderRadius.circular(12.r),
        onTap: onTap,
        child: Container(
          padding: EdgeInsets.all(14.w),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12.r),
            border: Border.all(color: const Color(0x14000000)),
          ),
          child: Row(children: [
            Container(
              width: 42.w,
              height: 42.w,
              decoration: BoxDecoration(
                color: color.withOpacity(0.14),
                shape: BoxShape.circle,
              ),
              child: Center(child: Icon(icon, size: 20.sp, color: color)),
            ),
            SizedBox(width: 12.w),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: TextStyle(
                        fontSize: 13.5.sp,
                        fontWeight: FontWeight.w800,
                        color: const Color(0xFF1F2937),
                      )),
                  SizedBox(height: 2.h),
                  Text(subtitle,
                      style: TextStyle(
                        fontSize: 11.sp,
                        color: Colors.grey.shade600,
                      )),
                ],
              ),
            ),
            if (badge != null)
              Container(
                padding:
                    EdgeInsets.symmetric(horizontal: 8.w, vertical: 3.h),
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(999.r),
                ),
                child: Text(
                  badge!,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 11.sp,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            SizedBox(width: 4.w),
            Icon(Icons.chevron_right_rounded,
                size: 18.w, color: Colors.grey.shade500),
          ]),
        ),
      ),
    );
  }
}
