import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';

import '../../region/controllers/region_controller.dart';
import '../data/mock_admin_data.dart';

// ═══════════════════════════════════════════════════════════════════════════════
//  USTA DETAIL ADMIN VIEW — cloud-gated detail page for a single pending
//  verification. Reachable ONLY from PendingVerificationsPage (which itself
//  is reachable only from the admin-only Admin Panel).
//
//  This is the ONE place in the app where the raw phone number of a
//  self-registered usta is allowed to render — and it does so behind a
//  visible "Privileged data" banner so the admin is reminded that the screen
//  contains protected information.
//
//  Actions:
//    Approve → PendingVerificationProvider.approveByUstaId(...)
//              → UstaRegistrationProvider.approve(...) (status='approved',
//                Supabase update fired, usta becomes visible in marketplace)
//    Reject  → status='rejected' (Supabase update fired, usta hidden forever)
//  Both actions pop back to the queue so the row visibly disappears.
// ═══════════════════════════════════════════════════════════════════════════════

class UstaDetailAdminView extends StatefulWidget {
  final PendingVerification pending;

  const UstaDetailAdminView({super.key, required this.pending});

  @override
  State<UstaDetailAdminView> createState() => _UstaDetailAdminViewState();
}

class _UstaDetailAdminViewState extends State<UstaDetailAdminView> {
  bool _acting = false;

  /// Surfaced when an approve/reject write was blocked (RLS) or failed
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

  Future<void> _approve() async {
    if (_acting) return;
    setState(() => _acting = true);
    HapticFeedback.mediumImpact();
    final ok =
        await PendingVerificationProvider.approveByUstaId(widget.pending.ustaId);
    if (!mounted) return;
    if (!ok) {
      setState(() => _acting = false);
      _actionError();
      return;
    }
    Get.snackbar(
      'detail_snack_approved'.tr,
      'detail_snack_approved_body'.tr.replaceAll('{name}', widget.pending.name),
      snackPosition: SnackPosition.TOP,
      backgroundColor: const Color(0xFF198754),
      colorText: Colors.white,
      margin: EdgeInsets.all(12.w),
      borderRadius: 10,
      duration: const Duration(seconds: 3),
    );
    if (Navigator.of(context).canPop()) Navigator.of(context).pop();
  }

  Future<void> _reject() async {
    if (_acting) return;
    setState(() => _acting = true);
    HapticFeedback.mediumImpact();
    final ok =
        await PendingVerificationProvider.rejectByUstaId(widget.pending.ustaId);
    if (!mounted) return;
    if (!ok) {
      setState(() => _acting = false);
      _actionError();
      return;
    }
    Get.snackbar(
      'detail_snack_rejected'.tr,
      'detail_snack_rejected_body'.tr.replaceAll('{name}', widget.pending.name),
      snackPosition: SnackPosition.TOP,
      backgroundColor: const Color(0xFFB45309),
      colorText: Colors.white,
      margin: EdgeInsets.all(12.w),
      borderRadius: 10,
      duration: const Duration(seconds: 2),
    );
    if (Navigator.of(context).canPop()) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final pv = widget.pending;
    final provinceName = pv.provinceId == null
        ? '—'
        : (RegionController.provinces[pv.provinceId] ?? '—');
    final dateStr = DateFormat('d MMM yyyy, HH:mm').format(pv.submittedAt);
    final actionable =
        pv.source == 'self_registration' || true; // both sources actionable

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
          'detail_title'.tr,
          style: TextStyle(
            fontSize: 15.sp,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.2,
          ),
        ),
      ),
      body: LayoutBuilder(builder: (context, c) {
        final isWide = c.maxWidth >= 700;
        return Center(
          child: ConstrainedBox(
            constraints:
                BoxConstraints(maxWidth: isWide ? 560 : double.infinity),
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(16.w, 16.h, 16.w, 20.h),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _headerCard(pv),
                  SizedBox(height: 12.h),
                  _privilegedBanner(),
                  SizedBox(height: 10.h),
                  _detailsCard(pv, provinceName, dateStr),
                  SizedBox(height: 18.h),
                  if (actionable) _actionRow(),
                ],
              ),
            ),
          ),
        );
      }),
    );
  }

  // ── Header (avatar + name + source badge) ──────────────────────────────

  Widget _headerCard(PendingVerification pv) {
    return Container(
      padding: EdgeInsets.all(16.w),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1976D2), Color(0xFF0D47A1)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16.r),
      ),
      child: Row(children: [
        Container(
          width: 60.w,
          height: 60.w,
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.18),
            shape: BoxShape.circle,
            border:
                Border.all(color: Colors.white.withOpacity(0.30), width: 1.5),
          ),
          alignment: Alignment.center,
          child: Text(
            _initials(pv.name),
            style: TextStyle(
              color: Colors.white,
              fontSize: 20.sp,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        SizedBox(width: 12.w),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                pv.name,
                style: TextStyle(
                  fontSize: 16.sp,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                  letterSpacing: -0.2,
                ),
              ),
              SizedBox(height: 4.h),
              Container(
                padding: EdgeInsets.symmetric(
                    horizontal: 8.w, vertical: 3.h),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.18),
                  borderRadius: BorderRadius.circular(8.r),
                ),
                child: Text(
                  pv.source == 'self_registration'
                      ? 'detail_badge_self'.tr
                      : 'detail_badge_seeded'.tr,
                  style: TextStyle(
                    fontSize: 10.5.sp,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                    letterSpacing: 0.3,
                  ),
                ),
              ),
            ],
          ),
        ),
      ]),
    );
  }

  // ── Privileged data banner ─────────────────────────────────────────────

  Widget _privilegedBanner() {
    return Container(
      padding: EdgeInsets.all(10.w),
      decoration: BoxDecoration(
        color: Colors.amber.withOpacity(0.10),
        borderRadius: BorderRadius.circular(10.r),
        border: Border.all(color: Colors.amber.withOpacity(0.40), width: 1),
      ),
      child: Row(children: [
        Icon(Icons.shield_outlined,
            size: 14.sp, color: Colors.amber.shade800),
        SizedBox(width: 8.w),
        Expanded(
          child: Text(
            'detail_privileged_warning'.tr,
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

  // ── Details card ───────────────────────────────────────────────────────

  Widget _detailsCard(
      PendingVerification pv, String provinceName, String dateStr) {
    return Container(
      padding: EdgeInsets.all(14.w),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14.r),
        border: Border.all(color: const Color(0x14000000)),
      ),
      child: Column(children: [
        _detailRow(
          icon: Icons.person_outline_rounded,
          label: 'detail_row_name'.tr,
          value: pv.name,
        ),
        _divider(),
        _detailRow(
          icon: Icons.work_outline_rounded,
          label: 'apt_row_category'.tr,
          value: pv.specialty,
        ),
        _divider(),
        _detailRow(
          icon: Icons.public_rounded,
          label: 'reg_label_region'.tr,
          value: provinceName,
        ),
        _divider(),
        _detailRow(
          icon: Icons.workspace_premium_outlined,
          label: 'reg_label_experience'.tr,
          value: '${pv.experienceYears} yil',
        ),
        _divider(),
        // ── UNMASKED phone — admin-only, intentional per spec ───────
        if (pv.phoneRaw != null && pv.phoneRaw!.isNotEmpty)
          _phoneRow(pv.phoneRaw!)
        else
          _detailRow(
            icon: Icons.phone_outlined,
            label: 'detail_row_phone'.tr,
            value: pv.phoneMasked ?? 'detail_seeded_phone'.tr,
            valueColor: Colors.grey.shade500,
          ),
        _divider(),
        _detailRow(
          icon: Icons.access_time_rounded,
          label: 'detail_row_submitted'.tr,
          value: dateStr,
        ),
        _divider(),
        _detailRow(
          icon: Icons.tag_rounded,
          label: 'ID',
          value: pv.ustaId,
          valueStyle: TextStyle(
            fontSize: 11.sp,
            fontFamily: 'monospace',
            color: Colors.grey.shade600,
          ),
        ),
      ]),
    );
  }

  Widget _detailRow({
    required IconData icon,
    required String label,
    required String value,
    Color? valueColor,
    TextStyle? valueStyle,
  }) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 8.h),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, size: 16.sp, color: const Color(0xFF1976D2)),
        SizedBox(width: 10.w),
        SizedBox(
          width: 100.w,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 11.sp,
              color: Colors.grey.shade600,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: valueStyle ??
                TextStyle(
                  fontSize: 12.5.sp,
                  color: valueColor ?? const Color(0xFF1F2937),
                  fontWeight: FontWeight.w700,
                ),
          ),
        ),
      ]),
    );
  }

  Widget _phoneRow(String phone) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 8.h),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(Icons.phone_in_talk_rounded,
            size: 16.sp, color: const Color(0xFFD32F2F)),
        SizedBox(width: 10.w),
        SizedBox(
          width: 100.w,
          child: Text(
            'Telefon',
            style: TextStyle(
              fontSize: 11.sp,
              color: Colors.grey.shade600,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        Expanded(
          child: SelectableText(
            phone,
            style: TextStyle(
              fontSize: 14.sp,
              fontFamily: 'monospace',
              fontWeight: FontWeight.w800,
              color: const Color(0xFFD32F2F),
              letterSpacing: 0.5,
            ),
          ),
        ),
        Container(
          padding: EdgeInsets.symmetric(horizontal: 6.w, vertical: 2.h),
          decoration: BoxDecoration(
            color: const Color(0xFFFEE2E2),
            borderRadius: BorderRadius.circular(6.r),
          ),
          child: Text(
            'RAW',
            style: TextStyle(
              fontSize: 9.sp,
              fontWeight: FontWeight.w800,
              color: const Color(0xFFB91C1C),
            ),
          ),
        ),
      ]),
    );
  }

  Widget _divider() => const Divider(
        height: 1,
        thickness: 1,
        color: Color(0x0F000000),
      );

  // ── Action row ─────────────────────────────────────────────────────────

  Widget _actionRow() {
    return Row(children: [
      Expanded(
        child: OutlinedButton.icon(
          onPressed: _acting ? null : _reject,
          icon: const Icon(Icons.close_rounded, size: 16),
          label: Text('dash_action_reject'.tr,
              style: TextStyle(
                  fontSize: 13.sp, fontWeight: FontWeight.w800)),
          style: OutlinedButton.styleFrom(
            foregroundColor: const Color(0xFFB45309),
            side: const BorderSide(color: Color(0xFFB45309), width: 1.4),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12.r),
            ),
            padding: EdgeInsets.symmetric(vertical: 13.h),
          ),
        ),
      ),
      SizedBox(width: 10.w),
      Expanded(
        flex: 2,
        child: ElevatedButton.icon(
          onPressed: _acting ? null : _approve,
          icon: _acting
              ? SizedBox(
                  width: 14.w,
                  height: 14.w,
                  child: const CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white),
                )
              : const Icon(Icons.check_rounded, size: 16),
          label: Text(
            _acting ? 'reg_submitting'.tr : 'dash_action_approve'.tr,
            style:
                TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w800),
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF198754),
            foregroundColor: Colors.white,
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12.r),
            ),
            padding: EdgeInsets.symmetric(vertical: 13.h),
          ),
        ),
      ),
    ]);
  }

  String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts.first.substring(0, 1) + parts.last.substring(0, 1))
        .toUpperCase();
  }
}
