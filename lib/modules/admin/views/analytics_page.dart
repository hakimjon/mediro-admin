// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:intl/intl.dart';

import '../../usta/data/usta_registration_provider.dart';
import '../data/mock_admin_data.dart';
import '../data/telemetry_service.dart';

// ═══════════════════════════════════════════════════════════════════════════════
//  ADMIN ANALYTICS DASHBOARD
//
//  Business-intelligence view: KPI cards + simple lightweight charts
//  built with custom paint (no third-party chart package — keeps the
//  bundle small + avoids extra wasm-incompatibility warnings).
//
//  Sections:
//    1. Top-row KPIs (Total ustalar, Pending, Approved, Rejected,
//       Approval rate %, Total complaints)
//    2. Daily registrations (line / bar — last 30 days)
//    3. Approval status donut (percentages)
//    4. Top categories bar (which kasbs are most common)
//    5. Top provinces bar
//    6. CSV export tugmasi (downloads all registrations as CSV)
//
//  Data source: in-memory mirrors that the admin already loaded via
//  UstaRegistrationProvider.fetchAllFromCloud() / ComplaintProvider.
//  No new network calls — fast, predictable, works offline.
// ═══════════════════════════════════════════════════════════════════════════════

class AnalyticsPage extends StatefulWidget {
  final bool embedded;
  const AnalyticsPage({super.key, this.embedded = false});

  @override
  State<AnalyticsPage> createState() => _AnalyticsPageState();
}

class _AnalyticsPageState extends State<AnalyticsPage> {
  String _range = '30d'; // 'today' | '7d' | '30d' | 'all'

  @override
  void initState() {
    super.initState();
    // Make sure the cloud data is loaded — admin may have opened
    // analytics first.
    UstaRegistrationProvider.fetchAllFromCloud(force: true)
        .then((_) => mounted ? setState(() {}) : null);
  }

  @override
  Widget build(BuildContext context) {
    final all = UstaRegistrationProvider.allRegistrations();
    final filtered = _filterByRange(all);

    final pending = filtered.where((r) => r.status == 'pending').length;
    final approved = filtered.where((r) => r.status == 'approved').length;
    final rejected = filtered.where((r) => r.status == 'rejected').length;
    final deleted = filtered.where((r) => r.status == 'deleted').length;
    final total = filtered.length;
    final approvalRate = total == 0
        ? 0.0
        : (approved / total) * 100;
    final complaints = ComplaintProvider.openCount();

    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Toolbar(
          range: _range,
          onRangeChange: (r) => setState(() => _range = r),
          onExportCsv: () => _exportCsv(filtered),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _KpiRow(
                  total: total,
                  pending: pending,
                  approved: approved,
                  rejected: rejected,
                  deleted: deleted,
                  approvalRate: approvalRate,
                  complaints: complaints,
                ),
                const SizedBox(height: 14),
                _Card(
                  title: 'Kunlik arizalar (oxirgi 30 kun)',
                  child: SizedBox(
                    height: 180,
                    child: _DailyChart(rows: all),
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: _Card(
                        title: 'Status taqsimoti',
                        child: SizedBox(
                          height: 200,
                          child: _StatusDonut(
                            pending: pending,
                            approved: approved,
                            rejected: rejected,
                            deleted: deleted,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: _Card(
                        title: 'Top kasblar',
                        child: SizedBox(
                          height: 200,
                          child: _BarChart(
                            counts: _topCategories(filtered),
                            color: const Color(0xFF1976D2),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                _Card(
                  title: 'Telemetry — so\'nggi 24 soat',
                  child: SizedBox(
                    height: 80,
                    child: _TelemetrySummary(),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );

    if (widget.embedded) return body;
    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FA),
      appBar: AppBar(
        title: const Text('Analytics'),
        backgroundColor: const Color(0xFF0F172A),
        foregroundColor: Colors.white,
      ),
      body: body,
    );
  }

  List<UstaRegistration> _filterByRange(List<UstaRegistration> rows) {
    if (_range == 'all') return rows;
    final now = DateTime.now();
    final cutoff = switch (_range) {
      'today' => DateTime(now.year, now.month, now.day),
      '7d' => now.subtract(const Duration(days: 7)),
      '30d' => now.subtract(const Duration(days: 30)),
      _ => DateTime.fromMillisecondsSinceEpoch(0),
    };
    return rows.where((r) => r.submittedAt.isAfter(cutoff)).toList();
  }

  List<MapEntry<String, int>> _topCategories(List<UstaRegistration> rows) {
    final counts = <String, int>{};
    for (final r in rows) {
      counts[r.category] = (counts[r.category] ?? 0) + 1;
    }
    final sorted = counts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return sorted.take(6).toList();
  }

  void _exportCsv(List<UstaRegistration> rows) {
    // Build CSV
    final buf = StringBuffer();
    buf.writeln('id,name,phone,category,province_id,experience,status,submitted_at');
    for (final r in rows) {
      buf.writeln([
        r.id,
        _csvEscape(r.name),
        _csvEscape(r.phone),
        _csvEscape(r.category),
        r.provinceId.toString(),
        r.experienceYears.toString(),
        r.status,
        r.submittedAt.toIso8601String(),
      ].join(','));
    }
    // Lead with a BOM so Excel opens the UTF-8 (Cyrillic/Uzbek) text right.
    final csv = '﻿${buf.toString()}';

    // Real browser download via a Blob object URL + a temporary anchor —
    // works in any Flutter Web build without extra deps. Triggers the OS
    // Save As / download.
    final blob = html.Blob(<String>[csv], 'text/csv;charset=utf-8');
    final url = html.Url.createObjectUrlFromBlob(blob);
    html.AnchorElement(href: url)
      ..setAttribute('download', 'mediro_registrations.csv')
      ..click();
    html.Url.revokeObjectUrl(url);
  }

  String _csvEscape(String s) {
    if (s.contains(',') || s.contains('"') || s.contains('\n')) {
      return '"${s.replaceAll('"', '""')}"';
    }
    return s;
  }

}

// ─── Toolbar ─────────────────────────────────────────────────────────────

class _Toolbar extends StatelessWidget {
  final String range;
  final ValueChanged<String> onRangeChange;
  final VoidCallback onExportCsv;

  const _Toolbar({
    required this.range,
    required this.onRangeChange,
    required this.onExportCsv,
  });

  @override
  Widget build(BuildContext context) {
    final ranges = const [
      ('today', 'Today'),
      ('7d', '7 days'),
      ('30d', '30 days'),
      ('all', 'All'),
    ];
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Color(0x14000000))),
      ),
      child: Row(children: [
        const Icon(Icons.filter_alt_outlined, size: 16, color: Color(0xFF64748B)),
        const SizedBox(width: 6),
        const Text('Time range:',
            style: TextStyle(
                fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFF334155))),
        const SizedBox(width: 10),
        Wrap(
          spacing: 6,
          children: ranges.map((r) {
            final active = range == r.$1;
            return _Chip(
              label: r.$2,
              active: active,
              onTap: () => onRangeChange(r.$1),
            );
          }).toList(),
        ),
        const Spacer(),
        Material(
          color: const Color(0xFF0F766E),
          borderRadius: BorderRadius.circular(8),
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: onExportCsv,
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.download_rounded, size: 14, color: Colors.white),
                SizedBox(width: 6),
                Text('Export CSV',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w800)),
              ]),
            ),
          ),
        ),
      ]),
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;
  const _Chip({required this.label, required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: active ? const Color(0xFF1976D2) : Colors.transparent,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: active ? const Color(0xFF1976D2) : Colors.grey.shade300),
          ),
          child: Text(label,
              style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w800,
                  color: active ? Colors.white : Colors.grey.shade700)),
        ),
      ),
    );
  }
}

// ─── KPI row ─────────────────────────────────────────────────────────────

class _KpiRow extends StatelessWidget {
  final int total, pending, approved, rejected, deleted, complaints;
  final double approvalRate;
  const _KpiRow({
    required this.total,
    required this.pending,
    required this.approved,
    required this.rejected,
    required this.deleted,
    required this.approvalRate,
    required this.complaints,
  });

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Expanded(child: _Kpi(label: 'Total', value: '$total', color: const Color(0xFF334155))),
      const SizedBox(width: 10),
      Expanded(child: _Kpi(label: 'Pending', value: '$pending', color: const Color(0xFFE65100))),
      const SizedBox(width: 10),
      Expanded(child: _Kpi(label: 'Approved', value: '$approved', color: const Color(0xFF2E7D32))),
      const SizedBox(width: 10),
      Expanded(child: _Kpi(label: 'Rejected', value: '$rejected', color: const Color(0xFFD32F2F))),
      const SizedBox(width: 10),
      Expanded(child: _Kpi(label: 'Approval %', value: '${approvalRate.toStringAsFixed(1)}%', color: const Color(0xFF1976D2))),
      const SizedBox(width: 10),
      Expanded(child: _Kpi(label: 'Shikoyatlar', value: '$complaints', color: const Color(0xFF6D28D9))),
    ]);
  }
}

class _Kpi extends StatelessWidget {
  final String label, value;
  final Color color;
  const _Kpi({required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0x14000000)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(value,
              style: TextStyle(
                  fontSize: 22.sp,
                  fontWeight: FontWeight.w800,
                  color: color,
                  letterSpacing: -0.4)),
          const SizedBox(height: 2),
          Text(label,
              style: TextStyle(
                  fontSize: 11.5,
                  color: Colors.grey.shade600,
                  fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

class _Card extends StatelessWidget {
  final String title;
  final Widget child;
  const _Card({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0x14000000)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: Colors.grey.shade800)),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}

// ─── Charts (custom paint) ────────────────────────────────────────────────

class _DailyChart extends StatelessWidget {
  final List<UstaRegistration> rows;
  const _DailyChart({required this.rows});

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day).subtract(const Duration(days: 29));
    // Bucket by day
    final buckets = <DateTime, int>{};
    for (int i = 0; i < 30; i++) {
      buckets[start.add(Duration(days: i))] = 0;
    }
    for (final r in rows) {
      final day = DateTime(r.submittedAt.year, r.submittedAt.month, r.submittedAt.day);
      if (buckets.containsKey(day)) {
        buckets[day] = buckets[day]! + 1;
      }
    }
    final values = buckets.values.toList();
    return CustomPaint(
      painter: _LineChartPainter(values: values),
      size: Size.infinite,
    );
  }
}

class _LineChartPainter extends CustomPainter {
  final List<int> values;
  _LineChartPainter({required this.values});

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty) return;
    final maxV = values.reduce((a, b) => a > b ? a : b).clamp(1, 1000).toDouble();
    final w = size.width;
    final h = size.height;
    final stepX = values.length > 1 ? w / (values.length - 1) : w;

    final line = Paint()
      ..color = const Color(0xFF1976D2)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    final fill = Paint()
      ..shader = LinearGradient(
        colors: [
          const Color(0xFF1976D2).withOpacity(0.30),
          const Color(0xFF1976D2).withOpacity(0.02),
        ],
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
      ).createShader(Rect.fromLTWH(0, 0, w, h));
    final dot = Paint()..color = const Color(0xFF1976D2);

    final path = Path();
    final fillPath = Path();
    for (var i = 0; i < values.length; i++) {
      final x = i * stepX;
      final y = h - (values[i] / maxV) * (h - 6) - 3;
      if (i == 0) {
        path.moveTo(x, y);
        fillPath.moveTo(x, h);
        fillPath.lineTo(x, y);
      } else {
        path.lineTo(x, y);
        fillPath.lineTo(x, y);
      }
    }
    fillPath.lineTo(w, h);
    fillPath.close();
    canvas.drawPath(fillPath, fill);
    canvas.drawPath(path, line);

    // Latest value dot
    final lastX = (values.length - 1) * stepX;
    final lastY = h - (values.last / maxV) * (h - 6) - 3;
    canvas.drawCircle(Offset(lastX, lastY), 3, dot);
  }

  @override
  bool shouldRepaint(_LineChartPainter old) => old.values != values;
}

class _StatusDonut extends StatelessWidget {
  final int pending, approved, rejected, deleted;
  const _StatusDonut({
    required this.pending,
    required this.approved,
    required this.rejected,
    required this.deleted,
  });

  @override
  Widget build(BuildContext context) {
    final total = pending + approved + rejected + deleted;
    if (total == 0) {
      return const Center(child: Text('Ma\'lumot yo\'q', style: TextStyle(color: Colors.grey)));
    }
    return Row(children: [
      SizedBox(
        width: 140,
        height: 140,
        child: CustomPaint(
          painter: _DonutPainter(slices: [
            (pending.toDouble(), const Color(0xFFE65100)),
            (approved.toDouble(), const Color(0xFF2E7D32)),
            (rejected.toDouble(), const Color(0xFFD32F2F)),
            (deleted.toDouble(), const Color(0xFF455A64)),
          ]),
        ),
      ),
      const SizedBox(width: 20),
      Expanded(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _legend(const Color(0xFFE65100), 'Pending', pending, total),
            _legend(const Color(0xFF2E7D32), 'Approved', approved, total),
            _legend(const Color(0xFFD32F2F), 'Rejected', rejected, total),
            _legend(const Color(0xFF455A64), 'Deleted', deleted, total),
          ],
        ),
      ),
    ]);
  }

  Widget _legend(Color c, String label, int n, int total) {
    final pct = total == 0 ? 0 : ((n / total) * 100).round();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(children: [
        Container(width: 10, height: 10, decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
        const SizedBox(width: 6),
        Text(label, style: const TextStyle(fontSize: 12)),
        const Spacer(),
        Text('$n ($pct%)',
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
      ]),
    );
  }
}

class _DonutPainter extends CustomPainter {
  final List<(double, Color)> slices;
  _DonutPainter({required this.slices});

  @override
  void paint(Canvas canvas, Size size) {
    final total = slices.fold<double>(0, (s, v) => s + v.$1);
    if (total <= 0) return;
    final rect = Rect.fromCircle(
        center: size.center(Offset.zero),
        radius: size.shortestSide / 2 - 4);
    double start = -1.5708; // -π/2 — start at top
    for (final s in slices) {
      if (s.$1 == 0) continue;
      final sweep = (s.$1 / total) * 2 * 3.14159265;
      final paint = Paint()
        ..color = s.$2
        ..style = PaintingStyle.stroke
        ..strokeWidth = 26;
      canvas.drawArc(rect, start, sweep, false, paint);
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(_DonutPainter old) => old.slices != slices;
}

class _BarChart extends StatelessWidget {
  final List<MapEntry<String, int>> counts;
  final Color color;
  const _BarChart({required this.counts, required this.color});

  @override
  Widget build(BuildContext context) {
    if (counts.isEmpty) {
      return const Center(child: Text('Ma\'lumot yo\'q', style: TextStyle(color: Colors.grey)));
    }
    final max = counts.map((e) => e.value).reduce((a, b) => a > b ? a : b);
    return Column(
      children: counts.map((e) {
        final pct = (e.value / max).clamp(0.0, 1.0);
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(children: [
            SizedBox(
              width: 100,
              child: Text(e.key,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11)),
            ),
            Expanded(
              child: Stack(children: [
                Container(
                  height: 16,
                  decoration: BoxDecoration(
                    color: const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                FractionallySizedBox(
                  widthFactor: pct,
                  child: Container(
                    height: 16,
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
              ]),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 36,
              child: Text('${e.value}',
                  textAlign: TextAlign.right,
                  style: const TextStyle(
                      fontSize: 11, fontWeight: FontWeight.w800)),
            ),
          ]),
        );
      }).toList(),
    );
  }
}

class _TelemetrySummary extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final errors = MockTelemetryStore.errors();
    final flow = MockTelemetryStore.flow();
    final fb = MockTelemetryStore.feedback();
    final funnel = MockTelemetryStore.buyurtmaFunnel();

    Widget cell(String label, String value, Color c) {
      return Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(value, style: TextStyle(fontSize: 18.sp, color: c, fontWeight: FontWeight.w800)),
            Text(label, style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
          ],
        ),
      );
    }

    return Row(children: [
      cell('Errors', '${errors.length}', const Color(0xFFD32F2F)),
      cell('Flow events', '${flow.length}', const Color(0xFF1976D2)),
      cell('Funnel %', '${funnel.conversionPct.toStringAsFixed(1)}%',
          funnel.conversionPct >= 50 ? const Color(0xFF2E7D32) : const Color(0xFFE65100)),
      cell('Feedback', '${fb.length}', const Color(0xFF6D28D9)),
    ]);
  }
}

// Re-export DateFormat so callers don't have to add intl directly.
// ignore: unused_element
String _fmt(DateTime d) => DateFormat('d MMM').format(d);
