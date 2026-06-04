import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get.dart';

import 'dart:async';

import '../../usta/data/usta_registration_provider.dart';
import '../data/mock_admin_data.dart';
import '../data/realtime_admin_service.dart';
import 'usta_detail_admin_view.dart';

// ═══════════════════════════════════════════════════════════════════════════════
//  ADMIN — ALL USTALAR PAGE (formerly "Pending Verifications")
//
//  Now shows ALL registrations (pending / approved / rejected) with a top
//  status filter row. Each card's action buttons adapt to its status:
//    pending  → [Reject] [Approve]
//    approved → [Suspend] [Delete]
//    rejected → [Re-approve] [Delete]
//
//  Cloud-backed: pulls fresh data from Supabase on first open via
//  UstaRegistrationProvider.fetchAllFromCloud().
// ═══════════════════════════════════════════════════════════════════════════════

class PendingVerificationsPage extends StatefulWidget {
  /// When true, the page is rendered inside the desktop wide layout's column
  /// wrapper — no Scaffold/AppBar, just the body.
  final bool embedded;
  const PendingVerificationsPage({super.key, this.embedded = false});

  @override
  State<PendingVerificationsPage> createState() =>
      _PendingVerificationsPageState();
}

class _PendingVerificationsPageState extends State<PendingVerificationsPage> {
  bool _loading = false;
  String _statusFilter = 'pending'; // 'all'|'pending'|'approved'|'rejected'
  String _search = '';
  // Desktop table sort state.
  int _sortColumnIndex = 5; // Submitted (newest first by default)
  bool _sortAscending = false;

  StreamSubscription<RealtimeAdminEvent>? _realtimeSub;

  @override
  void initState() {
    super.initState();
    _bootstrap();
    // Re-render the table whenever a realtime registration event arrives
    // so the new row shows up without the admin clicking Yangilash. The
    // RealtimeAdminService has already merged the row into the provider
    // by the time this fires — we just need to repaint.
    _realtimeSub =
        RealtimeAdminService.instance.events.listen((ev) {
      if (!mounted) return;
      if (ev.kind == RealtimeAdminEventKind.registrationInserted ||
          ev.kind == RealtimeAdminEventKind.registrationUpdated) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _realtimeSub?.cancel();
    super.dispose();
  }

  /// First-open hook: pulls every `usta_registrations` row from Supabase
  /// so the admin queue reflects what's actually in the cloud. The cache
  /// guard is intentionally ignored on every mount — see [_refresh] for
  /// the cache-aware variant.
  Future<void> _bootstrap() async {
    setState(() => _loading = true);
    await UstaRegistrationProvider.fetchAllFromCloud(force: true);
    if (!mounted) return;
    setState(() => _loading = false);
  }

  /// Manual refresh — pulls fresh data unconditionally and shows a quick
  /// toast so the admin knows the call hit the network. Wired to the
  /// refresh icon in the embedded toolbar.
  Future<void> _refresh() async {
    setState(() => _loading = true);
    final before = UstaRegistrationProvider.allRegistrations().length;
    await UstaRegistrationProvider.fetchAllFromCloud(force: true);
    if (!mounted) return;
    final after = UstaRegistrationProvider.allRegistrations().length;
    setState(() => _loading = false);
    final delta = after - before;
    _toast(
      title: 'Yangilandi',
      body: delta > 0
          ? '$delta yangi ariza qo\'shildi (jami: $after)'
          : 'Jami $after ariza',
      bg: const Color(0xFF1976D2),
    );
  }

  // ── Actions ──────────────────────────────────────────────────────────

  void _approve(PendingVerification pv) {
    setState(() => PendingVerificationProvider.approveByUstaId(pv.ustaId));
    _toast(
      title: 'detail_snack_approved'.tr,
      body: 'verif_snack_approved_body'.tr.replaceAll('{name}', pv.name),
      bg: const Color(0xFF198754),
    );
  }

  void _reject(PendingVerification pv) {
    setState(() => PendingVerificationProvider.rejectByUstaId(pv.ustaId));
    _toast(
      title: 'detail_snack_rejected'.tr,
      body: 'verif_snack_rejected_body'.tr.replaceAll('{name}', pv.name),
      bg: const Color(0xFFB45309),
    );
  }

  /// Admin: revoke approval — usta vanishes from the marketplace listing
  /// but stays in the queue (status='rejected') for audit / re-approval.
  void _suspend(PendingVerification pv) {
    setState(() => PendingVerificationProvider.suspendByUstaId(pv.ustaId));
    _toast(
      title: "Faollik to'xtatildi",
      body: '${pv.name} marketdan vaqtinchalik olib tashlandi.',
      bg: const Color(0xFFB45309),
    );
  }

  /// Soft-delete: status='deleted'. Vanishes from every admin tab + the
  /// marketplace. Confirmation dialog first — destructive action.
  Future<void> _confirmDelete(PendingVerification pv) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(children: [
          Icon(Icons.delete_outline_rounded,
              size: 22.sp, color: Colors.red.shade700),
          SizedBox(width: 8.w),
          const Text('Ustani o\'chirish'),
        ]),
        content: Text(
          "${pv.name} arizasini o'chirmoqchimisiz? "
          "Bu amal qaytarib bo'lmaydi va usta marketdan butunlay yo'qoladi.",
          style: TextStyle(fontSize: 13.sp, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Bekor'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.red.shade700),
            child: const Text("O'chirish"),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => PendingVerificationProvider.softDeleteByUstaId(pv.ustaId));
    _toast(
      title: "O'chirildi",
      body: "${pv.name} marketdan o'chirildi.",
      bg: Colors.red.shade700,
    );
  }

  void _toast({required String title, required String body, required Color bg}) {
    Get.snackbar(
      title,
      body,
      snackPosition: SnackPosition.TOP,
      backgroundColor: bg,
      colorText: Colors.white,
      margin: EdgeInsets.all(12.w),
      borderRadius: 10,
      duration: const Duration(seconds: 2),
    );
  }

  // ── Build ────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    // Pull rows filtered by the currently selected status tab + search term.
    var list = PendingVerificationProvider.byStatus(_statusFilter);
    if (_search.trim().isNotEmpty) {
      final q = _search.trim().toLowerCase();
      list = list.where((pv) =>
          pv.name.toLowerCase().contains(q) ||
          pv.specialty.toLowerCase().contains(q) ||
          (pv.phoneMasked ?? '').toLowerCase().contains(q)).toList();
    }
    if (widget.embedded) {
      return _buildEmbeddedShell(list);
    }
    final body = _buildBody(list);
    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FA),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F172A),
        foregroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
          onPressed: () {
            if (Navigator.of(context).canPop()) Navigator.of(context).pop();
          },
        ),
        title: Text(
          'verif_title'.tr,
          style: TextStyle(
            fontSize: 15.sp,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.2,
          ),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(44),
          child: _FilterChipsRow(
            current: _statusFilter,
            onChanged: (s) => setState(() => _statusFilter = s),
          ),
        ),
      ),
      body: body,
    );
  }

  Widget _buildBody(List<PendingVerification> list) {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(
          color: Color(0xFF1976D2),
          strokeWidth: 2,
        ),
      );
    }
    if (list.isEmpty) {
      return Center(
        child: Padding(
          padding: EdgeInsets.all(28.w),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.inbox_rounded,
                  size: 42.sp, color: Colors.grey.shade400),
              SizedBox(height: 12.h),
              Text(
                _emptyMessage(),
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13.sp, color: Colors.grey.shade600),
              ),
            ],
          ),
        ),
      );
    }
    return ListView.separated(
      padding: EdgeInsets.fromLTRB(14.w, 14.h, 14.w, 24.h),
      itemCount: list.length,
      separatorBuilder: (_, __) => SizedBox(height: 10.h),
      itemBuilder: (context, i) => _UstaCard(
        pv: list[i],
        onTap: () => _openDetail(list[i]),
        onApprove: () => _approve(list[i]),
        onReject: () => _reject(list[i]),
        onSuspend: () => _suspend(list[i]),
        onDelete: () => _confirmDelete(list[i]),
      ),
    );
  }

  String _emptyMessage() {
    switch (_statusFilter) {
      case 'pending':  return 'verif_empty'.tr;
      case 'approved': return "Tasdiqlangan ustalar yo'q";
      case 'rejected': return "Rad etilgan arizalar yo'q";
      default:         return "Hech qanday ariza yo'q";
    }
  }

  // ── Embedded (admin panel desktop pane) ────────────────────────────────

  /// Shell used when this page lives inside the AdminPanel's desktop content
  /// pane. Provides a light-themed filter + search bar on top, and a
  /// DataTable view when the parent is at least 900 px wide. Below 900 px
  /// it falls back to the mobile card list so the panel works on narrow
  /// browser windows.
  Widget _buildEmbeddedShell(List<PendingVerification> list) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _EmbeddedToolbar(
          current: _statusFilter,
          onChanged: (s) => setState(() => _statusFilter = s),
          searchValue: _search,
          onSearch: (v) => setState(() => _search = v),
          totalCount: list.length,
          onRefresh: _refresh,
          isRefreshing: _loading,
        ),
        Expanded(
          child: LayoutBuilder(builder: (context, c) {
            if (_loading) {
              return const Center(
                child: CircularProgressIndicator(
                  color: Color(0xFF1976D2),
                  strokeWidth: 2,
                ),
              );
            }
            if (list.isEmpty) {
              return _emptyState();
            }
            if (c.maxWidth >= 900) {
              return _buildDesktopTable(list);
            }
            return ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
              itemCount: list.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (context, i) => _UstaCard(
                pv: list[i],
                onTap: () => _openDetail(list[i]),
                onApprove: () => _approve(list[i]),
                onReject: () => _reject(list[i]),
                onSuspend: () => _suspend(list[i]),
                onDelete: () => _confirmDelete(list[i]),
              ),
            );
          }),
        ),
      ],
    );
  }

  Widget _emptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.inbox_rounded, size: 42, color: Colors.grey.shade400),
            const SizedBox(height: 12),
            Text(
              _emptyMessage(),
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDesktopTable(List<PendingVerification> list) {
    // Resolve each row's live status from the registration provider so the
    // table reflects suspend / re-approve toggles without a page refresh.
    final rows = list.map((pv) {
      final reg = UstaRegistrationProvider.allRegistrations()
          .firstWhere((r) => r.id == pv.ustaId,
              orElse: () => UstaRegistration(
                    id: pv.ustaId,
                    name: pv.name,
                    phone: '',
                    category: pv.specialty,
                    provinceId: pv.provinceId ?? 0,
                    experienceYears: pv.experienceYears,
                    status: 'pending',
                    submittedAt: pv.submittedAt,
                  ));
      return (pv: pv, status: reg.status);
    }).toList();

    // Apply sort based on header taps.
    rows.sort((a, b) {
      int cmp;
      switch (_sortColumnIndex) {
        case 0:
          cmp = a.pv.name.toLowerCase().compareTo(b.pv.name.toLowerCase());
          break;
        case 1:
          cmp = a.pv.specialty
              .toLowerCase()
              .compareTo(b.pv.specialty.toLowerCase());
          break;
        case 2:
          cmp = (a.pv.phoneMasked ?? '')
              .compareTo(b.pv.phoneMasked ?? '');
          break;
        case 3:
          cmp = a.pv.experienceYears.compareTo(b.pv.experienceYears);
          break;
        case 4:
          cmp = a.status.compareTo(b.status);
          break;
        case 5:
        default:
          cmp = a.pv.submittedAt.compareTo(b.pv.submittedAt);
      }
      return _sortAscending ? cmp : -cmp;
    });

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0x14000000)),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: DataTable(
            sortColumnIndex: _sortColumnIndex,
            sortAscending: _sortAscending,
            headingRowColor: WidgetStateProperty.all(const Color(0xFFF1F5F9)),
            headingTextStyle: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: Color(0xFF334155),
              letterSpacing: 0.4,
            ),
            dataRowMinHeight: 56,
            dataRowMaxHeight: 64,
            columnSpacing: 18,
            horizontalMargin: 16,
            columns: [
              _sortableHeader('NAME', 0),
              _sortableHeader('SPECIALTY', 1),
              _sortableHeader('PHONE', 2),
              _sortableHeader('EXP', 3, numeric: true),
              _sortableHeader('STATUS', 4),
              _sortableHeader('SUBMITTED', 5),
              const DataColumn(label: Text('ACTIONS')),
            ],
            rows: rows.map((row) {
              final pv = row.pv;
              final sv = _statusVisualStatic(row.status);
              return DataRow(
                onSelectChanged: (_) => _openDetail(pv),
                cells: [
                  DataCell(_nameCell(pv)),
                  DataCell(
                    (pv.status == 'pending' &&
                            (pv.prevSpecialty ?? '').isNotEmpty &&
                            pv.prevSpecialty != pv.specialty)
                        ? Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(pv.specialty,
                                  style: const TextStyle(fontSize: 12.5)),
                              const SizedBox(height: 2),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 1),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFFFF3E0),
                                  borderRadius: BorderRadius.circular(5),
                                ),
                                child: Text('⟳ avval: ${pv.prevSpecialty}',
                                    style: const TextStyle(
                                      fontSize: 9.5,
                                      fontWeight: FontWeight.w700,
                                      color: Color(0xFFE65100),
                                    )),
                              ),
                            ],
                          )
                        : Text(pv.specialty,
                            style: const TextStyle(fontSize: 12.5)),
                  ),
                  DataCell(Text(pv.phoneMasked ?? '—',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade700,
                        fontWeight: FontWeight.w600,
                      ))),
                  DataCell(Text('${pv.experienceYears}y',
                      style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFFE65100),
                      ))),
                  DataCell(_statusPill(sv)),
                  DataCell(Text(_formatDate(pv.submittedAt),
                      style: TextStyle(
                        fontSize: 11.5,
                        color: Colors.grey.shade600,
                      ))),
                  DataCell(_tableActions(pv, row.status)),
                ],
              );
            }).toList(),
          ),
        ),
      ),
    );
  }

  DataColumn _sortableHeader(String label, int index, {bool numeric = false}) {
    return DataColumn(
      label: Text(label),
      numeric: numeric,
      onSort: (i, asc) => setState(() {
        _sortColumnIndex = i;
        _sortAscending = asc;
      }),
    );
  }

  Widget _nameCell(PendingVerification pv) {
    final initials = pv.name.trim().split(RegExp(r'\s+'));
    final init = initials.length == 1
        ? initials.first.substring(0, 1).toUpperCase()
        : (initials.first.substring(0, 1) + initials.last.substring(0, 1))
            .toUpperCase();
    return Row(children: [
      Container(
        width: 30,
        height: 30,
        decoration: BoxDecoration(
          color: const Color(0xFF1976D2).withOpacity(0.12),
          shape: BoxShape.circle,
        ),
        alignment: Alignment.center,
        child: Text(init,
            style: const TextStyle(
              color: Color(0xFF1976D2),
              fontWeight: FontWeight.w800,
              fontSize: 11.5,
            )),
      ),
      const SizedBox(width: 10),
      Text(pv.name,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: Color(0xFF1F2937),
          )),
    ]);
  }

  ({Color bg, Color fg, String label}) _statusVisualStatic(String s) {
    switch (s) {
      case 'pending':
        return (bg: const Color(0xFFFFF3E0), fg: const Color(0xFFE65100), label: 'KUTILMOQDA');
      case 'approved':
        return (bg: const Color(0xFFE8F5E9), fg: const Color(0xFF2E7D32), label: 'TASDIQLANGAN');
      case 'rejected':
        return (bg: const Color(0xFFFFEBEE), fg: const Color(0xFFD32F2F), label: 'RAD ETILGAN');
      default:
        return (bg: const Color(0xFFECEFF1), fg: const Color(0xFF455A64), label: s.toUpperCase());
    }
  }

  Widget _statusPill(({Color bg, Color fg, String label}) sv) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: sv.bg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        sv.label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w800,
          color: sv.fg,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  String _formatDate(DateTime d) {
    final now = DateTime.now();
    final diff = now.difference(d);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inHours < 1) return '${diff.inMinutes}m ago';
    if (diff.inDays < 1) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  Widget _tableActions(PendingVerification pv, String status) {
    switch (status) {
      case 'pending':
        return Row(mainAxisSize: MainAxisSize.min, children: [
          _miniBtn('Reject', const Color(0xFFB45309),
              Icons.close_rounded, () => _reject(pv)),
          const SizedBox(width: 6),
          _miniBtn('Approve', const Color(0xFF198754),
              Icons.check_rounded, () => _approve(pv), filled: true),
        ]);
      case 'approved':
        return Row(mainAxisSize: MainAxisSize.min, children: [
          _miniBtn('Suspend', const Color(0xFFB45309),
              Icons.block_rounded, () => _suspend(pv)),
          const SizedBox(width: 6),
          _miniBtn('Delete', const Color(0xFFD32F2F),
              Icons.delete_outline_rounded, () => _confirmDelete(pv)),
        ]);
      case 'rejected':
        return Row(mainAxisSize: MainAxisSize.min, children: [
          _miniBtn('Delete', const Color(0xFFD32F2F),
              Icons.delete_outline_rounded, () => _confirmDelete(pv)),
          const SizedBox(width: 6),
          _miniBtn('Re-approve', const Color(0xFF198754),
              Icons.check_rounded, () => _approve(pv), filled: true),
        ]);
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _miniBtn(String label, Color color, IconData icon, VoidCallback onTap,
      {bool filled = false}) {
    return SizedBox(
      height: 30,
      child: filled
          ? ElevatedButton.icon(
              onPressed: onTap,
              icon: Icon(icon, size: 12),
              label: Text(label,
                  style: const TextStyle(
                      fontSize: 11, fontWeight: FontWeight.w800)),
              style: ElevatedButton.styleFrom(
                backgroundColor: color,
                foregroundColor: Colors.white,
                elevation: 0,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(7)),
              ),
            )
          : OutlinedButton.icon(
              onPressed: onTap,
              icon: Icon(icon, size: 12),
              label:
                  Text(label, style: const TextStyle(fontSize: 11)),
              style: OutlinedButton.styleFrom(
                foregroundColor: color,
                side: BorderSide(color: color),
                padding: const EdgeInsets.symmetric(horizontal: 10),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(7)),
              ),
            ),
    );
  }

  Future<void> _openDetail(PendingVerification pv) async {
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => UstaDetailAdminView(pending: pv),
    ));
    if (mounted) setState(() {});
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  EMBEDDED TOOLBAR — light-themed filter chips + search field for the
//  desktop pane (white-on-light, in contrast to the dark navy mobile bar).
// ─────────────────────────────────────────────────────────────────────────────

class _EmbeddedToolbar extends StatelessWidget {
  final String current;
  final ValueChanged<String> onChanged;
  final String searchValue;
  final ValueChanged<String> onSearch;
  final int totalCount;
  final Future<void> Function() onRefresh;
  final bool isRefreshing;

  const _EmbeddedToolbar({
    required this.current,
    required this.onChanged,
    required this.searchValue,
    required this.onSearch,
    required this.totalCount,
    required this.onRefresh,
    required this.isRefreshing,
  });

  @override
  Widget build(BuildContext context) {
    final filters = [
      ('all',      'Barchasi',     const Color(0xFF64748B)),
      ('pending',  'Kutilmoqda',   const Color(0xFFE65100)),
      ('approved', 'Tasdiqlangan', const Color(0xFF2E7D32)),
      ('rejected', 'Rad etilgan',  const Color(0xFFD32F2F)),
    ];
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(
          bottom: BorderSide(color: Color(0x14000000)),
        ),
      ),
      child: Row(children: [
        Wrap(
          spacing: 6,
          children: filters.map((f) {
            final active = current == f.$1;
            return _FilterChipLight(
              label: f.$2,
              color: f.$3,
              active: active,
              onTap: () => onChanged(f.$1),
            );
          }).toList(),
        ),
        const SizedBox(width: 16),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: const Color(0xFFF1F5F9),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            '$totalCount rows',
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: Color(0xFF475569),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Material(
          color: const Color(0xFF1976D2),
          borderRadius: BorderRadius.circular(8),
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: isRefreshing ? null : onRefresh,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: 12, vertical: 8),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                isRefreshing
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation(Colors.white),
                        ),
                      )
                    : const Icon(Icons.refresh_rounded,
                        size: 14, color: Colors.white),
                const SizedBox(width: 6),
                const Text(
                  'Yangilash',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ]),
            ),
          ),
        ),
        const Spacer(),
        SizedBox(
          width: 260,
          height: 36,
          child: TextField(
            onChanged: onSearch,
            decoration: InputDecoration(
              hintText: 'Search name / specialty / phone…',
              hintStyle: TextStyle(
                  fontSize: 12, color: Colors.grey.shade500),
              prefixIcon: const Icon(Icons.search, size: 16),
              prefixIconConstraints:
                  const BoxConstraints(minWidth: 32, minHeight: 32),
              isDense: true,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
              filled: true,
              fillColor: const Color(0xFFF8FAFC),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: Color(0x14000000)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: Color(0x14000000)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(
                    color: Color(0xFF1976D2), width: 1.4),
              ),
            ),
            style: const TextStyle(fontSize: 12),
          ),
        ),
      ]),
    );
  }
}

class _FilterChipLight extends StatelessWidget {
  final String label;
  final Color color;
  final bool active;
  final VoidCallback onTap;
  const _FilterChipLight({
    required this.label,
    required this.color,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: active ? color : Colors.transparent,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: active ? color : color.withOpacity(0.30),
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w800,
              color: active ? Colors.white : color,
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  STATUS FILTER CHIPS ROW
// ─────────────────────────────────────────────────────────────────────────────

class _FilterChipsRow extends StatelessWidget {
  final String current;
  final ValueChanged<String> onChanged;

  const _FilterChipsRow({required this.current, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final filters = [
      ('all',      'Barchasi',     Colors.grey.shade300),
      ('pending',  'Kutilmoqda',   Colors.orange.shade300),
      ('approved', 'Tasdiqlangan', Colors.green.shade300),
      ('rejected', 'Rad etilgan',  Colors.red.shade300),
    ];
    return Container(
      color: const Color(0xFF0F172A),
      padding: EdgeInsets.only(left: 12.w, right: 12.w, bottom: 10.h),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: filters.map((f) {
            final active = current == f.$1;
            return Padding(
              padding: EdgeInsets.only(right: 8.w),
              child: ChoiceChip(
                label: Text(f.$2),
                selected: active,
                onSelected: (_) => onChanged(f.$1),
                backgroundColor: Colors.white.withOpacity(0.08),
                selectedColor: f.$3,
                labelStyle: TextStyle(
                  fontSize: 11.5.sp,
                  fontWeight: FontWeight.w700,
                  color: active ? Colors.black87 : Colors.white,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20.r),
                  side: BorderSide(
                    color: active
                        ? f.$3
                        : Colors.white.withOpacity(0.15),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  USTA CARD — status-aware actions
// ─────────────────────────────────────────────────────────────────────────────

class _UstaCard extends StatelessWidget {
  final PendingVerification pv;
  final VoidCallback onTap;
  final VoidCallback onApprove;
  final VoidCallback onReject;
  final VoidCallback onSuspend;
  final VoidCallback onDelete;

  const _UstaCard({
    required this.pv,
    required this.onTap,
    required this.onApprove,
    required this.onReject,
    required this.onSuspend,
    required this.onDelete,
  });

  String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts.first.substring(0, 1) + parts.last.substring(0, 1))
        .toUpperCase();
  }

  /// Returns the current status by querying the registration provider.
  /// (PendingVerification doesn't carry status — we derive it.)
  String _currentStatus() {
    final reg = UstaRegistrationProvider.allRegistrations()
        .firstWhere((r) => r.id == pv.ustaId,
            orElse: () => UstaRegistration(
                  id: pv.ustaId,
                  name: pv.name,
                  phone: '',
                  category: pv.specialty,
                  provinceId: pv.provinceId ?? 0,
                  experienceYears: pv.experienceYears,
                  status: 'pending',
                  submittedAt: pv.submittedAt,
                ));
    return reg.status;
  }

  ({Color bg, Color fg, String label}) _statusVisual(String s) {
    switch (s) {
      case 'pending':
        return (bg: const Color(0xFFFFF3E0), fg: const Color(0xFFE65100), label: 'KUTILMOQDA');
      case 'approved':
        return (bg: const Color(0xFFE8F5E9), fg: const Color(0xFF2E7D32), label: 'TASDIQLANGAN');
      case 'rejected':
        return (bg: const Color(0xFFFFEBEE), fg: const Color(0xFFD32F2F), label: 'RAD ETILGAN');
      default:
        return (bg: const Color(0xFFECEFF1), fg: const Color(0xFF455A64), label: s.toUpperCase());
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = _currentStatus();
    final sv = _statusVisual(status);

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12.r),
      child: InkWell(
        borderRadius: BorderRadius.circular(12.r),
        onTap: onTap,
        child: Container(
          padding: EdgeInsets.all(12.w),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12.r),
            border: Border.all(color: const Color(0x14000000)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header row: avatar + name/specialty/phone + experience badge
              Row(children: [
                Container(
                  width: 38.w,
                  height: 38.w,
                  decoration: BoxDecoration(
                    color: const Color(0xFF1976D2).withOpacity(0.12),
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    _initials(pv.name),
                    style: TextStyle(
                      color: const Color(0xFF1976D2),
                      fontWeight: FontWeight.w800,
                      fontSize: 13.sp,
                    ),
                  ),
                ),
                SizedBox(width: 10.w),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(pv.name,
                          style: TextStyle(
                            fontSize: 13.sp,
                            fontWeight: FontWeight.w800,
                            color: const Color(0xFF1F2937),
                          )),
                      SizedBox(height: 2.h),
                      Text(pv.specialty,
                          style: TextStyle(
                            fontSize: 11.sp,
                            color: Colors.grey.shade700,
                          )),
                      if (pv.phoneMasked != null) ...[
                        SizedBox(height: 2.h),
                        Row(children: [
                          Icon(Icons.phone_outlined,
                              size: 11.sp, color: Colors.grey.shade500),
                          SizedBox(width: 4.w),
                          Text(pv.phoneMasked!,
                              style: TextStyle(
                                fontSize: 10.5.sp,
                                color: Colors.grey.shade600,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 0.5,
                              )),
                        ]),
                      ],
                    ],
                  ),
                ),
                Container(
                  padding:
                      EdgeInsets.symmetric(horizontal: 8.w, vertical: 3.h),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF3E0),
                    borderRadius: BorderRadius.circular(8.r),
                  ),
                  child: Text(
                    '${pv.experienceYears} yil',
                    style: TextStyle(
                      fontSize: 10.5.sp,
                      fontWeight: FontWeight.w800,
                      color: const Color(0xFFE65100),
                    ),
                  ),
                ),
              ]),
              SizedBox(height: 8.h),
              // Status badge
              Container(
                padding:
                    EdgeInsets.symmetric(horizontal: 8.w, vertical: 3.h),
                decoration: BoxDecoration(
                  color: sv.bg,
                  borderRadius: BorderRadius.circular(6.r),
                ),
                child: Text(
                  sv.label,
                  style: TextStyle(
                    fontSize: 9.5.sp,
                    fontWeight: FontWeight.w800,
                    color: sv.fg,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
              SizedBox(height: 10.h),
              // Action row — adapts to current status
              _statusActions(status),
            ],
          ),
        ),
      ),
    );
  }

  Widget _statusActions(String status) {
    switch (status) {
      case 'pending':
        return Row(children: [
          Expanded(child: _btnOutlined('Rad etish', const Color(0xFFB45309),
              Icons.close_rounded, onReject)),
          SizedBox(width: 8.w),
          Expanded(flex: 2, child: _btnFilled('Tasdiqlash',
              const Color(0xFF198754), Icons.check_rounded, onApprove)),
        ]);
      case 'approved':
        return Row(children: [
          Expanded(child: _btnOutlined("To'xtatish", const Color(0xFFB45309),
              Icons.block_rounded, onSuspend)),
          SizedBox(width: 8.w),
          Expanded(child: _btnOutlined("O'chirish", const Color(0xFFD32F2F),
              Icons.delete_outline_rounded, onDelete)),
        ]);
      case 'rejected':
        return Row(children: [
          Expanded(child: _btnOutlined("O'chirish", const Color(0xFFD32F2F),
              Icons.delete_outline_rounded, onDelete)),
          SizedBox(width: 8.w),
          Expanded(flex: 2, child: _btnFilled('Qayta tasdiqlash',
              const Color(0xFF198754), Icons.check_rounded, onApprove)),
        ]);
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _btnOutlined(String label, Color color, IconData icon, VoidCallback onTap) {
    return OutlinedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 14),
      label: Text(label, style: TextStyle(fontSize: 11.5.sp)),
      style: OutlinedButton.styleFrom(
        foregroundColor: color,
        side: BorderSide(color: color),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10.r)),
        padding: EdgeInsets.symmetric(vertical: 8.h),
      ),
    );
  }

  Widget _btnFilled(String label, Color color, IconData icon, VoidCallback onTap) {
    return ElevatedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 14),
      label: Text(label, style: TextStyle(fontSize: 11.5.sp, fontWeight: FontWeight.w800)),
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        foregroundColor: Colors.white,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10.r)),
        padding: EdgeInsets.symmetric(vertical: 8.h),
      ),
    );
  }
}
