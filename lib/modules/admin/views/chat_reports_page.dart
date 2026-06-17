import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/chat_report_provider.dart';

// ═══════════════════════════════════════════════════════════════════════════
//  CHAT REPORTS PAGE — usta-admin reviews chat complaints (UGC moderation).
//  Each report: Warn the usta (→ in-app banner) or Dismiss. Mirrors the
//  ComplaintsPage embedded/full pattern.
// ═══════════════════════════════════════════════════════════════════════════

class ChatReportsPage extends StatefulWidget {
  final bool embedded;
  const ChatReportsPage({super.key, this.embedded = false});

  @override
  State<ChatReportsPage> createState() => _ChatReportsPageState();
}

class _ChatReportsPageState extends State<ChatReportsPage> {
  String _statusFilter = 'all';
  bool _loading = true;
  RealtimeChannel? _channel;

  static const _reasonLabels = <String, String>{
    'haqorat': 'Haqorat',
    'spam': 'Spam',
    'aldash': 'Aldash',
    'boshqa': 'Boshqa',
  };

  @override
  void initState() {
    super.initState();
    _load();
    // Live: new reports + status changes appear without a manual refresh.
    _channel = Supabase.instance.client
        .channel('admin_chat_reports')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'chat_reports',
          callback: (_) {
            if (mounted) _load();
          },
        )
        .subscribe();
  }

  @override
  void dispose() {
    _channel?.unsubscribe();
    super.dispose();
  }

  Future<void> _load() async {
    await ChatReportProvider.fetchAllFromCloud(force: true);
    if (mounted) setState(() => _loading = false);
  }

  List<ChatReport> _filtered() {
    final all = ChatReportProvider.all();
    if (_statusFilter == 'all') return all;
    return all.where((r) => r.status == _statusFilter).toList();
  }

  Future<void> _warn(ChatReport r) async {
    final ok = await ChatReportProvider.warn(r.id);
    if (!mounted) return;
    if (!ok) return _err();
    setState(() {});
    Get.snackbar('Ogohlantirildi', 'Ustaga ogohlantirish yuborildi.',
        snackPosition: SnackPosition.TOP,
        backgroundColor: const Color(0xFF198754),
        colorText: Colors.white,
        margin: const EdgeInsets.all(12),
        borderRadius: 10,
        duration: const Duration(seconds: 2));
  }

  Future<void> _dismiss(ChatReport r) async {
    final ok = await ChatReportProvider.dismiss(r.id);
    if (!mounted) return;
    if (!ok) return _err();
    setState(() {});
  }

  void _err() {
    Get.snackbar('Xatolik', "Saqlab bo'lmadi. Ruxsat / internetni tekshiring.",
        snackPosition: SnackPosition.TOP,
        backgroundColor: const Color(0xFFD32F2F),
        colorText: Colors.white,
        margin: const EdgeInsets.all(12),
        borderRadius: 10,
        duration: const Duration(seconds: 3));
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      const spinner = Center(
        child: Padding(padding: EdgeInsets.all(40), child: CircularProgressIndicator()),
      );
      return widget.embedded ? spinner : const Scaffold(body: spinner);
    }
    final body = _buildBody();
    if (widget.embedded) return body;
    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FA),
      appBar: AppBar(
        title: const Text('Chat shikoyatlari'),
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF111827),
        elevation: 0.5,
      ),
      body: body,
    );
  }

  Widget _buildBody() {
    final list = _filtered();
    const filters = [
      ('all', 'Barchasi'),
      ('new', 'Yangi'),
      ('warned', 'Ogohlantirilgan'),
      ('dismissed', 'Rad etilgan'),
    ];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Container(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(bottom: BorderSide(color: Color(0x14000000))),
        ),
        child: Wrap(
          spacing: 6,
          runSpacing: 6,
          children: filters.map((f) {
            final active = _statusFilter == f.$1;
            return GestureDetector(
              onTap: () => setState(() => _statusFilter = f.$1),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: active ? const Color(0xFF198754) : const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(f.$2,
                    style: TextStyle(
                        fontSize: 12.5.sp,
                        fontWeight: FontWeight.w600,
                        color: active ? Colors.white : const Color(0xFF475569))),
              ),
            );
          }).toList(),
        ),
      ),
      Expanded(
        child: list.isEmpty
            ? Center(
                child: Text('Shikoyatlar yo\'q',
                    style: TextStyle(fontSize: 13.sp, color: Colors.grey.shade600)))
            : ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: list.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (_, i) => _card(list[i]),
              ),
      ),
    ]);
  }

  Widget _card(ChatReport r) {
    final reason = _reasonLabels[r.reason] ?? r.reason;
    final date = DateFormat('dd.MM.yyyy HH:mm').format(r.createdAt);
    final actionable = r.status == 'new';
    final sv = _statusVisual(r.status);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFEAEDF2)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Text('Sabab: $reason',
                style: TextStyle(
                    fontSize: 14.sp,
                    fontWeight: FontWeight.w800,
                    color: const Color(0xFF111827))),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(color: sv.bg, borderRadius: BorderRadius.circular(6)),
            child: Text(sv.label,
                style: TextStyle(fontSize: 11.sp, fontWeight: FontWeight.w700, color: sv.fg)),
          ),
        ]),
        const SizedBox(height: 6),
        Text('${r.reportedIsUsta ? "Usta" : "Mijoz"} (shikoyat qilingan): ${r.reportedId}',
            style: TextStyle(fontSize: 12.sp, color: const Color(0xFF374151))),
        Text('Shikoyatchi: ${r.reporterId}',
            style: TextStyle(fontSize: 11.5.sp, color: const Color(0xFF6B7280))),
        if (r.note.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text('Izoh: ${r.note}',
                style: TextStyle(fontSize: 12.sp, color: const Color(0xFF374151))),
          ),
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(date, style: TextStyle(fontSize: 11.sp, color: const Color(0xFF9CA3AF))),
        ),
        if (actionable) ...[
          const SizedBox(height: 12),
          Row(children: [
            SizedBox(
              height: 32,
              child: OutlinedButton(
                onPressed: () => _dismiss(r),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF455A64),
                  side: const BorderSide(color: Color(0xFF455A64)),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                child: const Text('Rad etish', style: TextStyle(fontSize: 12)),
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              height: 32,
              child: ElevatedButton(
                onPressed: () => _warn(r),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFD32F2F),
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                child: const Text('Ustani ogohlantirish',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
              ),
            ),
          ]),
        ],
      ]),
    );
  }

  ({Color bg, Color fg, String label}) _statusVisual(String s) {
    switch (s) {
      case 'new':
        return (bg: const Color(0xFFFFF3E0), fg: const Color(0xFFE65100), label: 'Yangi');
      case 'warned':
        return (bg: const Color(0xFFFFEBEE), fg: const Color(0xFFD32F2F), label: 'Ogohlantirilgan');
      case 'dismissed':
        return (bg: const Color(0xFFECEFF1), fg: const Color(0xFF455A64), label: 'Rad etilgan');
      case 'banned':
        return (bg: const Color(0xFF111827), fg: Colors.white, label: 'Bloklangan');
      default:
        return (bg: const Color(0xFFECEFF1), fg: const Color(0xFF455A64), label: s);
    }
  }
}
