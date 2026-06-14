import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../region/controllers/region_controller.dart';
import '../../theme/colors.dart';
import '../data/service_storage.dart';

// ═══════════════════════════════════════════════════════════════════════════
//  PROVIDER + OFFERINGS — the year-1 onboarding engine.
//
//  The admin adds a provider (an usta, a person with equipment, or an MCHJ)
//  and gives them one or more OFFERINGS (a trade for ustalar; a piece of
//  equipment for texnika). One MCHJ → many equipment; one usta → many trades.
//  Writes go direct under the usta_admin RLS policy (.select() confirms).
// ═══════════════════════════════════════════════════════════════════════════

class ProviderOfferingsPage extends StatefulWidget {
  final bool embedded;
  const ProviderOfferingsPage({super.key, this.embedded = false});

  @override
  State<ProviderOfferingsPage> createState() => _ProviderOfferingsPageState();
}

class _ProviderOfferingsPageState extends State<ProviderOfferingsPage> {
  final _client = Supabase.instance.client;
  List<Map<String, dynamic>> _providers = const [];
  List<Map<String, dynamic>> _cats = const [];
  Map<String, int> _offeringCounts = {};
  Map<String, int> _pendingCounts = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final cats = await _client
          .from('service_categories')
          .select('id, group_id, name_uz')
          .order('sort_order');
      final provs = await _client
          .from('usta_registrations')
          .select(
              'id, name, phone, status, provider_type, province_id, legal_name, inn, contact_mode, about, avatar_url, district_id, covers_province')
          .neq('status', 'deleted')
          .order('submitted_at', ascending: false)
          .limit(500);
      final offs = await _client
          .from('service_offerings')
          .select('provider_id, status');
      final counts = <String, int>{};
      final pending = <String, int>{};
      for (final o in (offs as List)) {
        final pid = (o['provider_id'] ?? '').toString();
        counts[pid] = (counts[pid] ?? 0) + 1;
        if ((o['status'] ?? '').toString() == 'pending') {
          pending[pid] = (pending[pid] ?? 0) + 1;
        }
      }
      if (!mounted) return;
      setState(() {
        _cats = List<Map<String, dynamic>>.from(cats);
        _providers = List<Map<String, dynamic>>.from(provs);
        _offeringCounts = counts;
        _pendingCounts = pending;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      _toast('prov_err_load'.tr, isError: true);
    }
  }

  Future<void> _openEditor({Map<String, dynamic>? provider}) async {
    final changed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _ProviderEditorDialog(provider: provider, cats: _cats),
    );
    if (changed == true) await _load();
  }

  void _toast(String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: isError ? AppColors.error : AppColors.primary,
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 2),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final body = _loading
        ? const Center(
            child: CircularProgressIndicator(color: AppColors.primary))
        : RefreshIndicator(
            color: AppColors.primary,
            onRefresh: _load,
            child: ListView(
              padding: const EdgeInsets.only(bottom: 24),
              children: [
                Row(children: [
                  Expanded(
                    child: Text('prov_title'.tr,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 20.sp, fontWeight: FontWeight.w800)),
                  ),
                  ElevatedButton.icon(
                    onPressed: () => _openEditor(),
                    icon: const Icon(Icons.person_add_alt_1_rounded, size: 18),
                    label: Text('prov_add'.tr),
                    style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white),
                  ),
                ]),
                SizedBox(height: 6.h),
                Text('prov_subtitle'.tr,
                    style: TextStyle(
                        fontSize: 12.sp, color: AppColors.textSecondary)),
                SizedBox(height: 16.h),
                if (_providers.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text('prov_empty'.tr,
                        style: TextStyle(color: AppColors.textHint)),
                  )
                else
                  for (final p in _providers) _providerCard(p),
              ],
            ),
          );
    if (widget.embedded) return body;
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(title: Text('prov_title'.tr)),
      body: Padding(padding: const EdgeInsets.all(20), child: body),
    );
  }

  Widget _providerCard(Map<String, dynamic> p) {
    final id = (p['id'] ?? '').toString();
    final business = (p['provider_type'] ?? '') == 'business';
    final status = (p['status'] ?? '').toString();
    final count = _offeringCounts[id] ?? 0;
    final pendingN = _pendingCounts[id] ?? 0;
    final region =
        RegionController.provinces[p['province_id'] as int? ?? -1] ?? '';
    return InkWell(
      onTap: () => _openEditor(provider: p),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(children: [
          CircleAvatar(
            radius: 22,
            backgroundColor: AppColors.primaryLight,
            backgroundImage: (p['avatar_url'] ?? '').toString().isNotEmpty
                ? NetworkImage(p['avatar_url'])
                : null,
            child: (p['avatar_url'] ?? '').toString().isEmpty
                ? Icon(business ? Icons.business : Icons.person,
                    color: AppColors.primary)
                : null,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text((p['name'] ?? '').toString(),
                      style: TextStyle(
                          fontSize: 14.sp, fontWeight: FontWeight.w700)),
                  SizedBox(height: 2.h),
                  Text(
                      '${business ? 'MCHJ/Biznes' : 'Shaxs'} · $region · ${'prov_offerings_n'.tr.replaceAll('{n}', '$count')}',
                      style: TextStyle(
                          fontSize: 11.5.sp, color: AppColors.textSecondary)),
                ]),
          ),
          if (pendingN > 0) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
              decoration: BoxDecoration(
                color: AppColors.warning.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text('prov_pending_n'.tr.replaceAll('{n}', '$pendingN'),
                  style: TextStyle(
                      fontSize: 9.5.sp,
                      fontWeight: FontWeight.w800,
                      color: AppColors.warning)),
            ),
            const SizedBox(width: 6),
          ],
          _statusChip(status),
          const Icon(Icons.chevron_right, color: AppColors.textHint),
        ]),
      ),
    );
  }

  Widget _statusChip(String status) {
    final (label, color) = switch (status) {
      'approved' => ('prov_st_approved'.tr, AppColors.primary),
      'pending' => ('prov_st_pending'.tr, AppColors.warning),
      'rejected' => ('prov_st_rejected'.tr, AppColors.error),
      _ => (status, AppColors.textHint),
    };
    return Container(
      margin: const EdgeInsets.only(right: 8),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
          color: color.withOpacity(0.14),
          borderRadius: BorderRadius.circular(20)),
      child: Text(label,
          style: TextStyle(
              fontSize: 10.5.sp, color: color, fontWeight: FontWeight.w700)),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
//  PROVIDER EDITOR — provider fields + offerings management.
// ─────────────────────────────────────────────────────────────────────────
class _ProviderEditorDialog extends StatefulWidget {
  final Map<String, dynamic>? provider;
  final List<Map<String, dynamic>> cats;
  const _ProviderEditorDialog({required this.provider, required this.cats});

  @override
  State<_ProviderEditorDialog> createState() => _ProviderEditorDialogState();
}

class _ProviderEditorDialogState extends State<_ProviderEditorDialog> {
  final _client = Supabase.instance.client;
  final _name = TextEditingController();
  final _phone = TextEditingController(text: '+998 ');
  final _legalName = TextEditingController();
  final _inn = TextEditingController();
  final _about = TextEditingController();
  String _type = 'individual';
  String _contact = 'chat'; // individual default — protects personal phone (PII)
  int _province = RegionController.defaultProvinceId;
  String? _avatarUrl;
  String? _savedId;
  bool _saving = false;
  bool _dirty = false;

  List<Map<String, dynamic>> _offerings = const [];
  // District (base location) + "serves whole province" coverage.
  String? _districtId;
  bool _coversProvince = false;
  List<Map<String, dynamic>> _districts = const [];

  @override
  void initState() {
    super.initState();
    final p = widget.provider;
    if (p != null) {
      _savedId = (p['id'] ?? '').toString();
      _name.text = (p['name'] ?? '').toString();
      _phone.text = (p['phone'] ?? '+998 ').toString();
      _legalName.text = (p['legal_name'] ?? '').toString();
      _inn.text = (p['inn'] ?? '').toString();
      _about.text = (p['about'] ?? '').toString();
      _type = (p['provider_type'] ?? 'individual').toString();
      _contact = (p['contact_mode'] ?? 'both').toString();
      _province = p['province_id'] as int? ?? RegionController.defaultProvinceId;
      _districtId = p['district_id']?.toString();
      _coversProvince = p['covers_province'] == true;
      _avatarUrl = p['avatar_url']?.toString();
      _loadOfferings();
    }
    _loadDistricts(_province);
  }

  Future<void> _loadDistricts(int province) async {
    try {
      final res =
          await _client.rpc('districts_of', params: {'p_province': province});
      if (!mounted) return;
      setState(() {
        _districts =
            (res as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
        // Drop a district that no longer belongs to the chosen province.
        if (_districtId != null &&
            !_districts.any((d) => d['id'].toString() == _districtId)) {
          _districtId = null;
        }
      });
    } catch (_) {/* leave empty — district is optional */}
  }

  Future<void> _loadOfferings() async {
    if (_savedId == null) return;
    try {
      final res = await _client
          .from('service_offerings')
          .select('id, category_id, title, rate_amount, rate_unit, photos, status')
          .eq('provider_id', _savedId!)
          .order('sort_order');
      if (mounted) {
        setState(() => _offerings = List<Map<String, dynamic>>.from(res));
      }
    } catch (_) {}
  }

  String _catName(String? id) {
    final c = widget.cats.firstWhere((x) => x['id'] == id,
        orElse: () => const {'name_uz': '?'});
    return (c['name_uz'] ?? '?').toString();
  }

  Future<void> _saveProvider() async {
    final name = _name.text.trim();
    if (name.isEmpty || _phone.text.replaceAll(RegExp(r'\D'), '').length < 12) {
      _toast('prov_err_required'.tr, isError: true);
      return;
    }
    setState(() => _saving = true);
    final payload = {
      'name': name,
      'phone': _phone.text.trim(),
      'provider_type': _type,
      'contact_mode': _contact,
      'province_id': _province,
      'district_id': _districtId,
      'covers_province': _coversProvince,
      'legal_name': _type == 'business' ? _legalName.text.trim() : null,
      'inn': _type == 'business' ? _inn.text.trim() : null,
      'about': _about.text.trim(),
      'avatar_url': _avatarUrl,
    };
    try {
      if (_savedId == null) {
        final id = 'reg-${DateTime.now().millisecondsSinceEpoch}';
        final res = await _client.from('usta_registrations').insert({
          'id': id,
          ...payload,
          'category': '', // legacy NOT NULL column — categories live in offerings
          'experience_years': 0,
          'status': 'approved', // admin-added → live immediately
          'submitted_at': DateTime.now().toIso8601String(),
        }).select();
        if ((res as List).isEmpty) throw Exception('blocked');
        _savedId = id;
      } else {
        final res = await _client
            .from('usta_registrations')
            .update(payload)
            .eq('id', _savedId!)
            .select();
        if ((res as List).isEmpty) throw Exception('blocked');
      }
      _dirty = true;
      _toast('prov_saved'.tr);
      setState(() {});
    } catch (e) {
      _toast('prov_err_save'.tr, isError: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _pickAvatar() async {
    final url = await ServiceStorage.pickAndUpload();
    if (url != null && mounted) setState(() => _avatarUrl = url);
  }

  Future<void> _addOrEditOffering({Map<String, dynamic>? offering}) async {
    if (_savedId == null) {
      _toast('prov_save_first'.tr, isError: true);
      return;
    }
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _OfferingDialog(
          providerId: _savedId!, cats: widget.cats, offering: offering),
    );
    if (saved == true) {
      _dirty = true;
      await _loadOfferings();
    }
  }

  Future<void> _deleteOffering(String id) async {
    try {
      await _client.from('service_offerings').delete().eq('id', id);
      _dirty = true;
      await _loadOfferings();
    } catch (_) {
      _toast('prov_err_save'.tr, isError: true);
    }
  }

  // Approve a provider-submitted offering (pending → active = goes live).
  Future<void> _approveOffering(String id) async {
    try {
      await _client
          .from('service_offerings')
          .update({'status': 'active'}).eq('id', id);
      _dirty = true;
      await _loadOfferings();
      _toast('prov_approved'.tr);
    } catch (_) {
      _toast('prov_err_save'.tr, isError: true);
    }
  }

  void _toast(String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: isError ? AppColors.error : AppColors.primary,
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 2),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final business = _type == 'business';
    return Dialog(
      backgroundColor: AppColors.card,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520, maxHeight: 680),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 8, 8),
            child: Row(children: [
              Expanded(
                child: Text(
                    widget.provider == null ? 'prov_add'.tr : 'prov_edit'.tr,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 17.sp, fontWeight: FontWeight.w800)),
              ),
              IconButton(
                  tooltip: 'common_close'.tr,
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context, _dirty)),
            ]),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                // Avatar / logo
                Center(
                  child: GestureDetector(
                    onTap: _pickAvatar,
                    child: CircleAvatar(
                      radius: 40,
                      backgroundColor: AppColors.primaryLight,
                      backgroundImage: (_avatarUrl ?? '').isNotEmpty
                          ? NetworkImage(_avatarUrl!)
                          : null,
                      child: (_avatarUrl ?? '').isEmpty
                          ? const Icon(Icons.add_a_photo_outlined,
                              color: AppColors.primary)
                          : null,
                    ),
                  ),
                ),
                SizedBox(height: 14.h),
                _field(_name, 'prov_name'.tr),
                _field(_phone, 'prov_phone'.tr,
                    keyboard: TextInputType.phone),
                _dropdown<String>(
                  label: 'prov_type'.tr,
                  value: _type,
                  items: {
                    'individual': 'prov_type_individual'.tr,
                    'business': 'prov_type_business'.tr,
                  },
                  // PII nudge: individual → chat (hide personal phone);
                  // business → both (public company number + chat).
                  onChanged: (v) => setState(() {
                    _type = v!;
                    // Firma = faqat qo'ng'iroq (ilovani ishlatmaydi → chat
                    // o'qilmay qoladi). Yakka usta = chat (shaxsiy raqam maxfiy).
                    _contact = _type == 'business' ? 'call' : 'chat';
                  }),
                ),
                if (business) ...[
                  _field(_legalName, 'prov_legal_name'.tr),
                  _field(_inn, 'prov_inn'.tr,
                      keyboard: TextInputType.number),
                ],
                _dropdownInt(
                  label: 'prov_region'.tr,
                  value: _province,
                  items: RegionController.provinces,
                  onChanged: (v) => setState(() {
                    _province = v!;
                    _districtId = null;
                    _loadDistricts(_province);
                  }),
                ),
                // District (base location) — cascades from the province.
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: DropdownButtonFormField<String?>(
                    // Fall back to null while districts are still loading, so the
                    // value always matches an item (avoids a transient assert).
                    value: _districts
                            .any((d) => d['id'].toString() == _districtId)
                        ? _districtId
                        : null,
                    isExpanded: true,
                    decoration: InputDecoration(
                        labelText: 'prov_district'.tr, isDense: true),
                    items: [
                      DropdownMenuItem(
                          value: null, child: Text('prov_district_any'.tr)),
                      for (final d in _districts)
                        DropdownMenuItem(
                            value: d['id'].toString(),
                            child: Text((d['name_uz'] ?? '').toString())),
                    ],
                    onChanged: (v) => setState(() => _districtId = v),
                  ),
                ),
                // Coverage: serves the whole province (e.g. a crane that travels).
                Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  decoration: BoxDecoration(
                    border: Border.all(color: AppColors.border),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: SwitchListTile(
                    value: _coversProvince,
                    onChanged: (v) => setState(() => _coversProvince = v),
                    title: Text('prov_covers_province'.tr,
                        style: TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w600)),
                    subtitle: Text('prov_covers_hint'.tr,
                        style: const TextStyle(
                            fontSize: 11, color: AppColors.textSecondary)),
                    activeColor: AppColors.primary,
                    dense: true,
                  ),
                ),
                _dropdown<String>(
                  label: 'prov_contact'.tr,
                  value: _contact,
                  items: {
                    'chat': 'prov_contact_chat'.tr,
                    'call': 'prov_contact_call'.tr,
                    'both': 'prov_contact_both'.tr,
                  },
                  onChanged: (v) => setState(() => _contact = v!),
                ),
                _field(_about, 'prov_about'.tr, maxLines: 2),
                SizedBox(height: 6.h),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _saving ? null : _saveProvider,
                    style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white),
                    child: _saving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white))
                        : Text('prov_save'.tr),
                  ),
                ),
                SizedBox(height: 18.h),

                // ── Offerings ──
                Row(children: [
                  Text('prov_offerings'.tr,
                      style: TextStyle(
                          fontSize: 14.sp, fontWeight: FontWeight.w800)),
                  const Spacer(),
                  TextButton.icon(
                    onPressed: () => _addOrEditOffering(),
                    icon: const Icon(Icons.add, size: 16),
                    label: Text('prov_add_offering'.tr),
                  ),
                ]),
                if (_savedId == null)
                  Text('prov_save_first'.tr,
                      style: TextStyle(
                          fontSize: 11.5.sp, color: AppColors.textHint))
                else if (_offerings.isEmpty)
                  Text('prov_no_offerings'.tr,
                      style: TextStyle(
                          fontSize: 11.5.sp, color: AppColors.textHint))
                else
                  for (final o in _offerings) _offeringRow(o),
              ],
            ),
          ),
        ]),
      ),
    );
  }

  Widget _offeringRow(Map<String, dynamic> o) {
    final rate = o['rate_amount'];
    final rateText = rate == null
        ? 'prov_negotiable'.tr
        : '$rate so\'m${o['rate_unit'] != null ? '/${o['rate_unit']}' : ''}';
    final photos = (o['photos'] as List?)?.length ?? 0;
    final isPending = (o['status'] ?? '').toString() == 'pending';
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
      decoration: BoxDecoration(
          color: isPending
              ? AppColors.warning.withValues(alpha: 0.06)
              : AppColors.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
              color: isPending ? AppColors.warning : AppColors.border)),
      child: Row(children: [
        Expanded(
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(children: [
                  Flexible(
                    child: Text(
                        '${_catName(o['category_id']?.toString())}'
                        '${(o['title'] ?? '').toString().isNotEmpty ? ' · ${o['title']}' : ''}',
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 12.5.sp, fontWeight: FontWeight.w600)),
                  ),
                  if (isPending) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 1),
                      decoration: BoxDecoration(
                        color: AppColors.warning.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text('prov_st_pending'.tr,
                          style: TextStyle(
                              fontSize: 9.5.sp,
                              fontWeight: FontWeight.w700,
                              color: AppColors.warning)),
                    ),
                  ],
                ]),
                Text('$rateText · $photos 📷',
                    style: TextStyle(
                        fontSize: 10.5.sp, color: AppColors.textSecondary)),
              ]),
        ),
        if (isPending)
          IconButton(
              tooltip: 'prov_approve'.tr,
              icon: const Icon(Icons.check_circle_outline,
                  size: 18, color: AppColors.primary),
              onPressed: () => _approveOffering(o['id'].toString())),
        IconButton(
            icon: const Icon(Icons.edit_outlined, size: 16),
            onPressed: () => _addOrEditOffering(offering: o)),
        IconButton(
            icon: const Icon(Icons.delete_outline,
                size: 16, color: AppColors.error),
            onPressed: () => _deleteOffering(o['id'].toString())),
      ]),
    );
  }

  Widget _field(TextEditingController c, String label,
          {TextInputType? keyboard, int maxLines = 1}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: TextField(
          controller: c,
          keyboardType: keyboard,
          maxLines: maxLines,
          decoration: InputDecoration(labelText: label, isDense: true),
        ),
      );

  Widget _dropdown<T>(
          {required String label,
          required T value,
          required Map<T, String> items,
          required ValueChanged<T?> onChanged}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: DropdownButtonFormField<T>(
          value: value,
          isExpanded: true,
          decoration: InputDecoration(labelText: label, isDense: true),
          items: [
            for (final e in items.entries)
              DropdownMenuItem(value: e.key, child: Text(e.value)),
          ],
          onChanged: onChanged,
        ),
      );

  Widget _dropdownInt(
          {required String label,
          required int value,
          required Map<int, String> items,
          required ValueChanged<int?> onChanged}) =>
      _dropdown<int>(
          label: label, value: value, items: items, onChanged: onChanged);
}

// ─────────────────────────────────────────────────────────────────────────
//  OFFERING DIALOG — add / edit one offering (category + rate + photos).
// ─────────────────────────────────────────────────────────────────────────
class _OfferingDialog extends StatefulWidget {
  final String providerId;
  final List<Map<String, dynamic>> cats;
  final Map<String, dynamic>? offering;
  const _OfferingDialog(
      {required this.providerId, required this.cats, this.offering});

  @override
  State<_OfferingDialog> createState() => _OfferingDialogState();
}

class _OfferingDialogState extends State<_OfferingDialog> {
  final _client = Supabase.instance.client;
  final _title = TextEditingController();
  final _rate = TextEditingController();
  String? _catId;
  String? _rateUnit;
  List<String> _photos = [];
  bool _saving = false;
  bool _uploading = false;

  @override
  void initState() {
    super.initState();
    final o = widget.offering;
    _catId = o?['category_id']?.toString() ??
        (widget.cats.isNotEmpty ? widget.cats.first['id'].toString() : null);
    _title.text = (o?['title'] ?? '').toString();
    if (o?['rate_amount'] != null) _rate.text = o!['rate_amount'].toString();
    _rateUnit = o?['rate_unit']?.toString();
    _photos = (o?['photos'] as List?)?.map((e) => e.toString()).toList() ?? [];
  }

  Future<void> _addPhoto() async {
    setState(() => _uploading = true);
    final url = await ServiceStorage.pickAndUpload(counter: _photos.length);
    if (url != null && mounted) setState(() => _photos.add(url));
    if (mounted) setState(() => _uploading = false);
  }

  Future<void> _save() async {
    if (_catId == null) return;
    setState(() => _saving = true);
    final payload = {
      'provider_id': widget.providerId,
      'category_id': _catId,
      'title': _title.text.trim().isEmpty ? null : _title.text.trim(),
      'rate_amount': _rate.text.trim().isEmpty
          ? null
          : num.tryParse(_rate.text.replaceAll(' ', '').trim()),
      'rate_unit': _rateUnit,
      'photos': _photos,
      'status': 'active',
    };
    try {
      if (widget.offering == null) {
        final res =
            await _client.from('service_offerings').insert(payload).select();
        if ((res as List).isEmpty) throw Exception('blocked');
      } else {
        final res = await _client
            .from('service_offerings')
            .update(payload)
            .eq('id', widget.offering!['id'])
            .select();
        if ((res as List).isEmpty) throw Exception('blocked');
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('prov_err_save'.tr),
            backgroundColor: AppColors.error));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.card,
      title: Text(
          widget.offering == null
              ? 'prov_add_offering'.tr
              : 'prov_edit_offering'.tr,
          style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.w800)),
      content: SizedBox(
        width: 380,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            DropdownButtonFormField<String>(
              value: _catId,
              isExpanded: true,
              decoration:
                  InputDecoration(labelText: 'prov_category'.tr, isDense: true),
              items: [
                for (final c in widget.cats)
                  DropdownMenuItem(
                      value: c['id'].toString(),
                      child: Text((c['name_uz'] ?? '').toString())),
              ],
              onChanged: (v) => setState(() => _catId = v),
            ),
            SizedBox(height: 10.h),
            TextField(
                controller: _title,
                decoration: InputDecoration(
                    labelText: 'prov_off_title'.tr,
                    hintText: 'Avtokran 25t',
                    isDense: true)),
            SizedBox(height: 10.h),
            Row(children: [
              Expanded(
                child: TextField(
                    controller: _rate,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                        labelText: 'prov_rate'.tr,
                        hintText: 'prov_rate_hint'.tr,
                        isDense: true)),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 110,
                child: DropdownButtonFormField<String?>(
                  value: _rateUnit,
                  isExpanded: true,
                  decoration: InputDecoration(
                      labelText: 'prov_unit'.tr, isDense: true),
                  items: [
                    DropdownMenuItem(value: null, child: Text('—')),
                    for (final u in ['soat', 'kun', 'smena', 'loyiha'])
                      DropdownMenuItem(value: u, child: Text(u)),
                  ],
                  onChanged: (v) => setState(() => _rateUnit = v),
                ),
              ),
            ]),
            SizedBox(height: 12.h),
            Align(
              alignment: Alignment.centerLeft,
              child: Text('prov_photos'.tr,
                  style: TextStyle(
                      fontSize: 11.5.sp, color: AppColors.textSecondary)),
            ),
            SizedBox(height: 6.h),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (var i = 0; i < _photos.length; i++)
                Stack(children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.network(_photos[i],
                        width: 60, height: 60, fit: BoxFit.cover),
                  ),
                  Positioned(
                    right: -6,
                    top: -6,
                    child: IconButton(
                      icon: const Icon(Icons.cancel,
                          size: 18, color: AppColors.error),
                      onPressed: () => setState(() => _photos.removeAt(i)),
                    ),
                  ),
                ]),
              InkWell(
                onTap: _uploading ? null : _addPhoto,
                child: Container(
                  width: 60,
                  height: 60,
                  decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppColors.border)),
                  child: _uploading
                      ? const Center(
                          child: SizedBox(
                              width: 18,
                              height: 18,
                              child:
                                  CircularProgressIndicator(strokeWidth: 2)))
                      : const Icon(Icons.add_a_photo_outlined,
                          color: AppColors.primary),
                ),
              ),
            ]),
          ]),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('common_cancel'.tr)),
        ElevatedButton(
          onPressed: _saving ? null : _save,
          style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary, foregroundColor: Colors.white),
          child: Text('common_save'.tr),
        ),
      ],
    );
  }
}
