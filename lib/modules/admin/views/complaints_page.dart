import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';

import '../data/mock_admin_data.dart';

class ComplaintsPage extends StatefulWidget {
  /// When true, render the body only (no Scaffold/AppBar) so the desktop
  /// wide layout can embed this page inside its column wrapper.
  final bool embedded;
  const ComplaintsPage({super.key, this.embedded = false});

  @override
  State<ComplaintsPage> createState() => _ComplaintsPageState();
}

class _ComplaintsPageState extends State<ComplaintsPage> {
  String _statusFilter = 'all'; // 'all'|'open'|'under_review'|'resolved'|'dismissed'
  String _search = '';
  int _sortColumnIndex = 4; // Created (newest first by default)
  bool _sortAscending = false;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    await ComplaintProvider.fetchAllFromCloud(force: true);
    if (mounted) setState(() => _loading = false);
  }

  /// Surfaced when a complaint status write was blocked (RLS) or failed
  /// (network) — the change did NOT persist.
  void _actionError() {
    Get.snackbar(
      'Xatolik',
      "Saqlab bo'lmadi. Internet yoki ruxsatni tekshiring.",
      snackPosition: SnackPosition.TOP,
      backgroundColor: const Color(0xFFD32F2F),
      colorText: Colors.white,
      margin: EdgeInsets.all(12.w),
      borderRadius: 10,
      duration: const Duration(seconds: 3),
    );
  }

  Future<void> _resolve(Complaint c) async {
    final ok = await ComplaintProvider.resolve(c.id);
    if (!mounted) return;
    if (!ok) return _actionError();
    setState(() {});
    Get.snackbar(
      'cmp_admin_snack_resolved'.tr,
      'cmp_admin_snack_resolved_body'.tr.replaceAll('{name}', c.ustaName),
      snackPosition: SnackPosition.TOP,
      backgroundColor: const Color(0xFF198754),
      colorText: Colors.white,
      margin: EdgeInsets.all(12.w),
      borderRadius: 10,
      duration: const Duration(seconds: 3),
    );
  }

  Future<void> _dismiss(Complaint c) async {
    final ok = await ComplaintProvider.dismiss(c.id);
    if (!mounted) return;
    if (!ok) return _actionError();
    setState(() {});
    Get.snackbar(
      'cmp_admin_snack_rejected'.tr,
      'cmp_admin_snack_rejected_body'.tr,
      snackPosition: SnackPosition.TOP,
      backgroundColor: const Color(0xFFB45309),
      colorText: Colors.white,
      margin: EdgeInsets.all(12.w),
      borderRadius: 10,
      duration: const Duration(seconds: 2),
    );
  }

  List<Complaint> _filtered() {
    var list = ComplaintProvider.all();
    if (_statusFilter != 'all') {
      list = list.where((c) => c.status == _statusFilter).toList();
    }
    if (_search.trim().isNotEmpty) {
      final q = _search.trim().toLowerCase();
      list = list
          .where((c) =>
              c.ustaName.toLowerCase().contains(q) ||
              c.clientLabel.toLowerCase().contains(q) ||
              c.orderId.toLowerCase().contains(q) ||
              c.reason.toLowerCase().contains(q))
          .toList();
    }
    return list;
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      const spinner = Center(
        child: Padding(
          padding: EdgeInsets.all(40),
          child: CircularProgressIndicator(),
        ),
      );
      return widget.embedded ? spinner : const Scaffold(body: spinner);
    }
    final list = _filtered();
    if (widget.embedded) return _buildEmbedded(list);
    final body = list.isEmpty
        ? Center(
            child: Padding(
              padding: EdgeInsets.all(28.w),
              child: Text('cmp_admin_empty'.tr,
                  style: TextStyle(
                      fontSize: 13.sp, color: Colors.grey.shade600)),
            ),
          )
        : ListView.separated(
            padding: EdgeInsets.fromLTRB(14.w, 14.h, 14.w, 24.h),
            itemCount: list.length,
            separatorBuilder: (_, __) => SizedBox(height: 10.h),
            itemBuilder: (_, i) => _ComplaintCard(
              complaint: list[i],
              onResolve: _resolve,
              onDismiss: _dismiss,
            ),
          );
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
          'cmp_admin_title'.tr,
          style: TextStyle(
            fontSize: 15.sp,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.2,
          ),
        ),
      ),
      body: body,
    );
  }

  // ── Embedded (desktop pane) ─────────────────────────────────────────

  Widget _buildEmbedded(List<Complaint> list) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _ComplaintsToolbar(
          current: _statusFilter,
          onChanged: (s) => setState(() => _statusFilter = s),
          searchValue: _search,
          onSearch: (v) => setState(() => _search = v),
          totalCount: list.length,
        ),
        Expanded(
          child: LayoutBuilder(builder: (context, c) {
            if (list.isEmpty) {
              return Center(
                child: Text('cmp_admin_empty'.tr,
                    style: TextStyle(
                        fontSize: 13, color: Colors.grey.shade600)),
              );
            }
            if (c.maxWidth >= 900) return _complaintsTable(list);
            return ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
              itemCount: list.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (_, i) => _ComplaintCard(
                complaint: list[i],
                onResolve: _resolve,
                onDismiss: _dismiss,
              ),
            );
          }),
        ),
      ],
    );
  }

  Widget _complaintsTable(List<Complaint> rows) {
    rows.sort((a, b) {
      int cmp;
      switch (_sortColumnIndex) {
        case 0:
          cmp = a.ustaName.toLowerCase().compareTo(b.ustaName.toLowerCase());
          break;
        case 1:
          cmp = a.clientLabel.compareTo(b.clientLabel);
          break;
        case 2:
          cmp = a.reason.toLowerCase().compareTo(b.reason.toLowerCase());
          break;
        case 3:
          cmp = a.status.compareTo(b.status);
          break;
        case 4:
        default:
          cmp = a.createdAt.compareTo(b.createdAt);
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
            headingRowColor:
                WidgetStateProperty.all(const Color(0xFFF1F5F9)),
            headingTextStyle: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: Color(0xFF334155),
              letterSpacing: 0.4,
            ),
            dataRowMinHeight: 56,
            dataRowMaxHeight: 72,
            columnSpacing: 18,
            horizontalMargin: 16,
            columns: [
              _col('USTA', 0),
              _col('CLIENT / ORDER', 1),
              _col('REASON', 2),
              _col('STATUS', 3),
              _col('CREATED', 4),
              const DataColumn(label: Text('ACTIONS')),
            ],
            rows: rows.map((c) {
              final v = _statusVisualFor(c.status);
              final actionable =
                  c.status == 'under_review' || c.status == 'open';
              return DataRow(cells: [
                DataCell(Text(c.ustaName,
                    style: const TextStyle(
                        fontSize: 12.5, fontWeight: FontWeight.w700))),
                DataCell(Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(c.clientLabel,
                        style: const TextStyle(fontSize: 12)),
                    Text(c.orderId,
                        style: TextStyle(
                            fontSize: 10.5,
                            color: Colors.grey.shade600,
                            fontWeight: FontWeight.w600)),
                  ],
                )),
                DataCell(SizedBox(
                  width: 220,
                  child: Text(c.reason,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12)),
                )),
                DataCell(Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: v.bg,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(v.label,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        color: v.fg,
                        letterSpacing: 0.4,
                      )),
                )),
                DataCell(Text(
                  DateFormat('d MMM, HH:mm').format(c.createdAt),
                  style: TextStyle(
                      fontSize: 11.5, color: Colors.grey.shade600),
                )),
                DataCell(actionable
                    ? Row(mainAxisSize: MainAxisSize.min, children: [
                        SizedBox(
                          height: 30,
                          child: OutlinedButton.icon(
                            onPressed: () => _dismiss(c),
                            icon: const Icon(Icons.close_rounded, size: 12),
                            label: Text('cmp_admin_btn_dismiss'.tr,
                                style: const TextStyle(fontSize: 11)),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: const Color(0xFFB45309),
                              side: const BorderSide(color: Color(0xFFB45309)),
                              padding: const EdgeInsets.symmetric(horizontal: 10),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(7),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        SizedBox(
                          height: 30,
                          child: ElevatedButton.icon(
                            onPressed: () => _resolve(c),
                            icon: const Icon(
                                Icons.check_circle_outline_rounded, size: 12),
                            label: Text('cmp_admin_btn_resolve'.tr,
                                style: const TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w800)),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF198754),
                              foregroundColor: Colors.white,
                              elevation: 0,
                              padding: const EdgeInsets.symmetric(horizontal: 10),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(7),
                              ),
                            ),
                          ),
                        ),
                      ])
                    : Text('—',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade400,
                        ))),
              ]);
            }).toList(),
          ),
        ),
      ),
    );
  }

  DataColumn _col(String label, int index) {
    return DataColumn(
      label: Text(label),
      onSort: (i, asc) => setState(() {
        _sortColumnIndex = i;
        _sortAscending = asc;
      }),
    );
  }

  ({Color bg, Color fg, String label}) _statusVisualFor(String s) {
    switch (s) {
      case 'under_review':
        return (
          bg: const Color(0xFFFFEBEE),
          fg: const Color(0xFFD32F2F),
          label: 'cmp_admin_status_review'.tr,
        );
      case 'open':
        return (
          bg: const Color(0xFFFFF3E0),
          fg: const Color(0xFFE65100),
          label: 'cmp_admin_status_open'.tr,
        );
      case 'resolved':
        return (
          bg: const Color(0xFFE8F5E9),
          fg: const Color(0xFF2E7D32),
          label: 'cmp_admin_status_resolved'.tr,
        );
      case 'dismissed':
        return (
          bg: const Color(0xFFECEFF1),
          fg: const Color(0xFF455A64),
          label: 'cmp_admin_status_dismissed'.tr,
        );
      default:
        return (
          bg: const Color(0xFFECEFF1),
          fg: const Color(0xFF455A64),
          label: s,
        );
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Complaints toolbar — light-themed filter chips + search field for the
//  desktop embedded pane.
// ─────────────────────────────────────────────────────────────────────────────
class _ComplaintsToolbar extends StatelessWidget {
  final String current;
  final ValueChanged<String> onChanged;
  final String searchValue;
  final ValueChanged<String> onSearch;
  final int totalCount;

  const _ComplaintsToolbar({
    required this.current,
    required this.onChanged,
    required this.searchValue,
    required this.onSearch,
    required this.totalCount,
  });

  @override
  Widget build(BuildContext context) {
    final filters = [
      ('all',          'Barchasi',     const Color(0xFF64748B)),
      ('open',         'Yangi',        const Color(0xFFE65100)),
      ('under_review', "Ko'rilmoqda",  const Color(0xFFD32F2F)),
      ('resolved',     'Hal qilindi',  const Color(0xFF2E7D32)),
      ('dismissed',    'Bekor',        const Color(0xFF455A64)),
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
        Expanded(
          child: Wrap(
            spacing: 6,
            runSpacing: 6,
            children: filters.map((f) {
              final active = current == f.$1;
              return _ComplaintChip(
                label: f.$2,
                color: f.$3,
                active: active,
                onTap: () => onChanged(f.$1),
              );
            }).toList(),
          ),
        ),
        const SizedBox(width: 12),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: const Color(0xFFF1F5F9),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text('$totalCount rows',
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: Color(0xFF475569),
              )),
        ),
        const SizedBox(width: 12),
        SizedBox(
          width: 260,
          height: 36,
          child: TextField(
            onChanged: onSearch,
            decoration: InputDecoration(
              hintText: 'Search usta / order / reason…',
              hintStyle:
                  TextStyle(fontSize: 12, color: Colors.grey.shade500),
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
                    color: Color(0xFFD32F2F), width: 1.4),
              ),
            ),
            style: const TextStyle(fontSize: 12),
          ),
        ),
      ]),
    );
  }
}

class _ComplaintChip extends StatelessWidget {
  final String label;
  final Color color;
  final bool active;
  final VoidCallback onTap;
  const _ComplaintChip({
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

class _ComplaintCard extends StatelessWidget {
  final Complaint complaint;
  final void Function(Complaint) onResolve;
  final void Function(Complaint) onDismiss;

  const _ComplaintCard({
    required this.complaint,
    required this.onResolve,
    required this.onDismiss,
  });

  ({Color bg, Color fg, String label}) _statusVisual(String s) {
    switch (s) {
      case 'under_review':
        return (
          bg: const Color(0xFFFFEBEE),
          fg: const Color(0xFFD32F2F),
          label: 'cmp_admin_status_review'.tr,
        );
      case 'open':
        return (
          bg: const Color(0xFFFFF3E0),
          fg: const Color(0xFFE65100),
          label: 'cmp_admin_status_open'.tr,
        );
      case 'resolved':
        return (
          bg: const Color(0xFFE8F5E9),
          fg: const Color(0xFF2E7D32),
          label: 'cmp_admin_status_resolved'.tr,
        );
      case 'dismissed':
        return (
          bg: const Color(0xFFECEFF1),
          fg: const Color(0xFF455A64),
          label: 'cmp_admin_status_dismissed'.tr,
        );
      default:
        return (
          bg: const Color(0xFFECEFF1),
          fg: const Color(0xFF455A64),
          label: s,
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final v = _statusVisual(complaint.status);
    final actionable =
        complaint.status == 'under_review' || complaint.status == 'open';
    final dateStr =
        DateFormat('d MMM, HH:mm').format(complaint.createdAt);

    return Container(
      padding: EdgeInsets.all(12.w),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12.r),
        border: Border.all(color: const Color(0x14000000)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    complaint.ustaName,
                    style: TextStyle(
                      fontSize: 13.5.sp,
                      fontWeight: FontWeight.w800,
                      color: const Color(0xFF1F2937),
                    ),
                  ),
                  SizedBox(height: 2.h),
                  Text(
                    '${complaint.clientLabel} · ${complaint.orderId}',
                    style: TextStyle(
                      fontSize: 11.sp,
                      color: Colors.grey.shade600,
                    ),
                  ),
                ],
              ),
            ),
            Container(
              padding:
                  EdgeInsets.symmetric(horizontal: 8.w, vertical: 3.h),
              decoration: BoxDecoration(
                color: v.bg,
                borderRadius: BorderRadius.circular(8.r),
              ),
              child: Text(
                v.label,
                style: TextStyle(
                  fontSize: 10.5.sp,
                  fontWeight: FontWeight.w800,
                  color: v.fg,
                ),
              ),
            ),
          ]),
          SizedBox(height: 10.h),
          Container(
            width: double.infinity,
            padding: EdgeInsets.all(10.w),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(10.r),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  complaint.reason,
                  style: TextStyle(
                    fontSize: 12.sp,
                    fontWeight: FontWeight.w800,
                    color: const Color(0xFF1F2937),
                  ),
                ),
                SizedBox(height: 4.h),
                Text(
                  complaint.comment,
                  style: TextStyle(
                    fontSize: 11.5.sp,
                    color: Colors.grey.shade700,
                    height: 1.4,
                  ),
                ),
                SizedBox(height: 6.h),
                Text(
                  dateStr,
                  style: TextStyle(
                    fontSize: 10.5.sp,
                    color: Colors.grey.shade500,
                  ),
                ),
              ],
            ),
          ),
          if (actionable) ...[
            SizedBox(height: 10.h),
            Row(children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => onDismiss(complaint),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFFB45309),
                    side: const BorderSide(color: Color(0xFFB45309)),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10.r),
                    ),
                    padding: EdgeInsets.symmetric(vertical: 9.h),
                  ),
                  child: Text('cmp_admin_btn_dismiss'.tr,
                      style: TextStyle(fontSize: 12.sp)),
                ),
              ),
              SizedBox(width: 8.w),
              Expanded(
                flex: 2,
                child: ElevatedButton.icon(
                  onPressed: () => onResolve(complaint),
                  icon: const Icon(Icons.check_circle_outline_rounded,
                      size: 16),
                  label: Text('cmp_admin_btn_resolve'.tr,
                      style: TextStyle(
                        fontSize: 12.sp,
                        fontWeight: FontWeight.w800,
                      )),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF198754),
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10.r),
                    ),
                    padding: EdgeInsets.symmetric(vertical: 9.h),
                  ),
                ),
              ),
            ]),
          ],
        ],
      ),
    );
  }
}
