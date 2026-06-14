import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../theme/colors.dart';

// ═══════════════════════════════════════════════════════════════════════════
//  CATEGORY MANAGEMENT — the no-code lever for the services catalog.
//
//  The admin adds / edits / removes service categories (Kamera ustanovka,
//  Pod klyuch remont, Bo'yoqchi, …) here — a new service type is a DB row,
//  never a code change. Categories live under a group (Ustalar / Texnika /
//  Boshqa). Writes go direct to service_categories under the usta_admin RLS
//  policy, with .select() so an RLS-blocked write reports as a real failure.
// ═══════════════════════════════════════════════════════════════════════════

class CategoryManagementPage extends StatefulWidget {
  final bool embedded;
  const CategoryManagementPage({super.key, this.embedded = false});

  @override
  State<CategoryManagementPage> createState() => _CategoryManagementPageState();
}

class _CategoryManagementPageState extends State<CategoryManagementPage> {
  final _client = Supabase.instance.client;
  List<Map<String, dynamic>> _groups = const [];
  List<Map<String, dynamic>> _cats = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final g = await _client
          .from('service_groups')
          .select('id, key, name_uz, sort_order')
          .order('sort_order');
      final c = await _client
          .from('service_categories')
          .select('id, group_id, key, name_uz, name_ru, sort_order')
          .order('sort_order');
      if (!mounted) return;
      setState(() {
        _groups = List<Map<String, dynamic>>.from(g);
        _cats = List<Map<String, dynamic>>.from(c);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      _toast('cat_err_load'.tr, isError: true);
    }
  }

  List<Map<String, dynamic>> _catsOf(String groupId) =>
      _cats.where((c) => c['group_id'] == groupId).toList();

  String _slug(String s) {
    final base = s
        .toLowerCase()
        .trim()
        .replaceAll(RegExp(r"['`’]"), '')
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
    return base.isEmpty
        ? 'cat_${DateTime.now().millisecondsSinceEpoch}'
        : base;
  }

  // ── CRUD ──────────────────────────────────────────────────────────────────

  Future<void> _addOrEdit({Map<String, dynamic>? existing}) async {
    final isEdit = existing != null;
    String? groupId = isEdit
        ? existing['group_id'] as String?
        : (_groups.isNotEmpty ? _groups.first['id'] as String? : null);
    final nameUz = TextEditingController(text: existing?['name_uz'] ?? '');
    final nameRu = TextEditingController(text: existing?['name_ru'] ?? '');

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          backgroundColor: AppColors.card,
          title: Text(isEdit ? 'cat_edit_title'.tr : 'cat_add_title'.tr,
              style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.w800)),
          content: SizedBox(
            width: 360,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              DropdownButtonFormField<String>(
                value: groupId,
                isExpanded: true,
                decoration: InputDecoration(
                    labelText: 'cat_group'.tr, isDense: true),
                items: [
                  for (final g in _groups)
                    DropdownMenuItem(
                        value: g['id'] as String,
                        child: Text((g['name_uz'] ?? '').toString())),
                ],
                onChanged: (v) => setLocal(() => groupId = v),
              ),
              SizedBox(height: 10.h),
              TextField(
                controller: nameUz,
                decoration: InputDecoration(
                    labelText: 'cat_name_uz'.tr, isDense: true),
              ),
              SizedBox(height: 10.h),
              TextField(
                controller: nameRu,
                decoration: InputDecoration(
                    labelText: 'cat_name_ru'.tr, isDense: true),
              ),
            ]),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text('common_cancel'.tr)),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white),
              child: Text('common_save'.tr),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;

    final uz = nameUz.text.trim();
    final ru = nameRu.text.trim();
    if (groupId == null || uz.isEmpty) {
      _toast('cat_err_required'.tr, isError: true);
      return;
    }

    try {
      if (isEdit) {
        final res = await _client
            .from('service_categories')
            .update({'name_uz': uz, 'name_ru': ru, 'group_id': groupId})
            .eq('id', existing['id'])
            .select();
        if ((res as List).isEmpty) throw Exception('blocked');
      } else {
        final maxSort = _catsOf(groupId!).fold<int>(
            0, (m, c) => (c['sort_order'] as int? ?? 0) > m
                ? (c['sort_order'] as int)
                : m);
        final res = await _client.from('service_categories').insert({
          'group_id': groupId,
          'key': _slug(uz),
          'name_uz': uz,
          'name_ru': ru,
          'sort_order': maxSort + 1,
        }).select();
        if ((res as List).isEmpty) throw Exception('blocked');
      }
      _toast('cat_saved'.tr);
      await _load();
    } catch (e) {
      final dup = e.toString().toLowerCase().contains('duplicate') ||
          e.toString().contains('23505');
      _toast(dup ? 'cat_err_dup'.tr : 'cat_err_save'.tr, isError: true);
    }
  }

  Future<void> _delete(Map<String, dynamic> c) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.card,
        title: Text('cat_delete_title'.tr,
            style: TextStyle(fontSize: 15.sp, fontWeight: FontWeight.w800)),
        content: Text('cat_delete_body'.tr
            .replaceAll('{name}', (c['name_uz'] ?? '').toString())),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text('common_cancel'.tr)),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: Text('common_delete'.tr),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _client.from('service_categories').delete().eq('id', c['id']);
      _toast('cat_deleted'.tr);
      await _load();
    } catch (e) {
      // FK violation = the category is in use by an offering.
      _toast('cat_err_in_use'.tr, isError: true);
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
                    child: Text('cat_title'.tr,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 20.sp, fontWeight: FontWeight.w800)),
                  ),
                  ElevatedButton.icon(
                    onPressed: () => _addOrEdit(),
                    icon: const Icon(Icons.add_rounded, size: 18),
                    label: Text('cat_add'.tr),
                    style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white),
                  ),
                ]),
                SizedBox(height: 6.h),
                Text('cat_subtitle'.tr,
                    style: TextStyle(
                        fontSize: 12.sp, color: AppColors.textSecondary)),
                SizedBox(height: 16.h),
                for (final g in _groups) _groupBlock(g),
              ],
            ),
          );

    if (widget.embedded) return body;
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(title: Text('cat_title'.tr)),
      body: Padding(padding: const EdgeInsets.all(20), child: body),
    );
  }

  Widget _groupBlock(Map<String, dynamic> g) {
    final cats = _catsOf(g['id'] as String);
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
          child: Text((g['name_uz'] ?? '').toString(),
              style: TextStyle(
                  fontSize: 14.sp,
                  fontWeight: FontWeight.w800,
                  color: AppColors.primary)),
        ),
        if (cats.isEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 14),
            child: Text('cat_empty_group'.tr,
                style: TextStyle(
                    fontSize: 12.sp, color: AppColors.textHint)),
          )
        else
          for (final c in cats) _catRow(c),
      ]),
    );
  }

  Widget _catRow(Map<String, dynamic> c) {
    return Container(
      decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: AppColors.divider))),
      padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
      child: Row(children: [
        Expanded(
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text((c['name_uz'] ?? '').toString(),
                    style: TextStyle(
                        fontSize: 13.5.sp, fontWeight: FontWeight.w600)),
                if ((c['name_ru'] ?? '').toString().isNotEmpty)
                  Text((c['name_ru']).toString(),
                      style: TextStyle(
                          fontSize: 11.sp, color: AppColors.textHint)),
              ]),
        ),
        IconButton(
          icon: const Icon(Icons.edit_outlined,
              size: 18, color: AppColors.textSecondary),
          onPressed: () => _addOrEdit(existing: c),
          tooltip: 'common_edit'.tr,
        ),
        IconButton(
          icon: const Icon(Icons.delete_outline_rounded,
              size: 18, color: AppColors.error),
          onPressed: () => _delete(c),
          tooltip: 'common_delete'.tr,
        ),
      ]),
    );
  }
}
