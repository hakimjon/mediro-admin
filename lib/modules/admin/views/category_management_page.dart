import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../theme/colors.dart';
import '../data/service_storage.dart';

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
          .select('id, key, name_uz, name_ru, image_url, sort_order')
          .order('sort_order');
      final c = await _client
          .from('service_categories')
          .select('id, group_id, key, name_uz, name_ru, sort_order, image_url')
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
    // Admin-managed tile artwork. Uploaded to the service-photos bucket; the
    // app shows it on the services landing (NULL → the app's icon fallback).
    String? imageUrl = existing?['image_url'] as String?;
    bool uploading = false;

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
              SizedBox(height: 14.h),
              Align(
                alignment: Alignment.centerLeft,
                child: Text('cat_image'.tr,
                    style: TextStyle(
                        fontSize: 12.sp, color: AppColors.textSecondary)),
              ),
              SizedBox(height: 6.h),
              GestureDetector(
                onTap: uploading
                    ? null
                    : () async {
                        setLocal(() => uploading = true);
                        // Tile thumbnails — cap at 1000px so a huge photo is
                        // auto-downscaled (stays light; the app crops to fit).
                        final url = await ServiceStorage.pickAndUpload(
                            maxWidth: 1000, maxHeight: 1000);
                        if (url != null) imageUrl = url;
                        setLocal(() => uploading = false);
                      },
                child: Container(
                  height: 120,
                  width: double.infinity,
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: uploading
                      ? const Center(
                          child: CircularProgressIndicator(
                              color: AppColors.primary, strokeWidth: 2))
                      : (imageUrl == null
                          ? Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(Icons.add_photo_alternate_outlined,
                                    color: AppColors.textHint, size: 28),
                                SizedBox(height: 4.h),
                                Text('cat_pick_image'.tr,
                                    style: TextStyle(
                                        fontSize: 12.sp,
                                        color: AppColors.textHint)),
                              ],
                            )
                          : Stack(
                              fit: StackFit.expand,
                              children: [
                                Image.network(imageUrl!, fit: BoxFit.cover),
                                Align(
                                  alignment: Alignment.bottomCenter,
                                  child: Container(
                                    width: double.infinity,
                                    color: Colors.black54,
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 4),
                                    child: Text('cat_change_image'.tr,
                                        textAlign: TextAlign.center,
                                        style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 11)),
                                  ),
                                ),
                              ],
                            )),
                ),
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
            .update({
              'name_uz': uz,
              'name_ru': ru,
              'group_id': groupId,
              'image_url': imageUrl,
            })
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
          'image_url': imageUrl,
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

  // ── GROUP CRUD — top-level catalog sections (Ustalar, Texnika, Tozalash…) ──

  Future<void> _addOrEditGroup({Map<String, dynamic>? existing}) async {
    final isEdit = existing != null;
    final nameUz = TextEditingController(text: existing?['name_uz'] ?? '');
    final nameRu = TextEditingController(text: existing?['name_ru'] ?? '');
    String? imageUrl = existing?['image_url'] as String?;
    bool uploading = false;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          backgroundColor: AppColors.card,
          title: Text(isEdit ? 'grp_edit_title'.tr : 'grp_add_title'.tr,
              style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.w800)),
          content: SizedBox(
            width: 360,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(
                controller: nameUz,
                decoration:
                    InputDecoration(labelText: 'cat_name_uz'.tr, isDense: true),
              ),
              SizedBox(height: 10.h),
              TextField(
                controller: nameRu,
                decoration:
                    InputDecoration(labelText: 'cat_name_ru'.tr, isDense: true),
              ),
              SizedBox(height: 14.h),
              Align(
                alignment: Alignment.centerLeft,
                child: Text('cat_image'.tr,
                    style: TextStyle(
                        fontSize: 12.sp, color: AppColors.textSecondary)),
              ),
              SizedBox(height: 6.h),
              GestureDetector(
                onTap: uploading
                    ? null
                    : () async {
                        setLocal(() => uploading = true);
                        final url = await ServiceStorage.pickAndUpload(
                            maxWidth: 1000, maxHeight: 1000);
                        if (url != null) imageUrl = url;
                        setLocal(() => uploading = false);
                      },
                child: Container(
                  height: 120,
                  width: double.infinity,
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: uploading
                      ? const Center(
                          child: CircularProgressIndicator(
                              color: AppColors.primary, strokeWidth: 2))
                      : (imageUrl == null
                          ? Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(Icons.add_photo_alternate_outlined,
                                    color: AppColors.textHint, size: 28),
                                SizedBox(height: 4.h),
                                Text('cat_pick_image'.tr,
                                    style: TextStyle(
                                        fontSize: 12.sp,
                                        color: AppColors.textHint)),
                              ],
                            )
                          : Stack(fit: StackFit.expand, children: [
                              Image.network(imageUrl!, fit: BoxFit.cover),
                              Align(
                                alignment: Alignment.bottomCenter,
                                child: Container(
                                  width: double.infinity,
                                  color: Colors.black54,
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 4),
                                  child: Text('cat_change_image'.tr,
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(
                                          color: Colors.white, fontSize: 11)),
                                ),
                              ),
                            ])),
                ),
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
    if (uz.isEmpty) {
      _toast('cat_err_required'.tr, isError: true);
      return;
    }
    try {
      if (isEdit) {
        final res = await _client
            .from('service_groups')
            .update({'name_uz': uz, 'name_ru': ru, 'image_url': imageUrl})
            .eq('id', existing['id'])
            .select();
        if ((res as List).isEmpty) throw Exception('blocked');
      } else {
        final maxSort = _groups.fold<int>(
            0,
            (m, g) =>
                (g['sort_order'] as int? ?? 0) > m ? (g['sort_order'] as int) : m);
        final res = await _client.from('service_groups').insert({
          'key': _slug(uz),
          'name_uz': uz,
          'name_ru': ru,
          'image_url': imageUrl,
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

  Future<void> _deleteGroup(Map<String, dynamic> g) async {
    // Guard: a group with categories can't be removed (they'd be orphaned).
    if (_catsOf(g['id'] as String).isNotEmpty) {
      _toast('grp_err_in_use'.tr, isError: true);
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.card,
        title: Text('grp_delete_title'.tr,
            style: TextStyle(fontSize: 15.sp, fontWeight: FontWeight.w800)),
        content: Text('grp_delete_body'.tr
            .replaceAll('{name}', (g['name_uz'] ?? '').toString())),
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
      await _client.from('service_groups').delete().eq('id', g['id']);
      _toast('cat_deleted'.tr);
      await _load();
    } catch (e) {
      _toast('grp_err_in_use'.tr, isError: true);
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
                  OutlinedButton.icon(
                    onPressed: () => _addOrEditGroup(),
                    icon: const Icon(Icons.create_new_folder_outlined, size: 18),
                    label: Text('grp_add'.tr),
                    style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.primary,
                        side: const BorderSide(color: AppColors.primary)),
                  ),
                  const SizedBox(width: 8),
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
          padding: const EdgeInsets.fromLTRB(16, 10, 6, 6),
          child: Row(children: [
            if ((g['image_url'] ?? '').toString().isNotEmpty) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.network((g['image_url']).toString(),
                    width: 34, height: 34, fit: BoxFit.cover),
              ),
              const SizedBox(width: 10),
            ],
            Expanded(
              child: Text((g['name_uz'] ?? '').toString(),
                  style: TextStyle(
                      fontSize: 14.sp,
                      fontWeight: FontWeight.w800,
                      color: AppColors.primary)),
            ),
            IconButton(
              icon: const Icon(Icons.edit_outlined,
                  size: 18, color: AppColors.textSecondary),
              onPressed: () => _addOrEditGroup(existing: g),
              tooltip: 'common_edit'.tr,
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline_rounded,
                  size: 18, color: AppColors.error),
              onPressed: () => _deleteGroup(g),
              tooltip: 'common_delete'.tr,
            ),
          ]),
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
        if ((c['image_url'] ?? '').toString().isNotEmpty) ...[
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.network((c['image_url']).toString(),
                width: 40, height: 40, fit: BoxFit.cover),
          ),
          const SizedBox(width: 10),
        ],
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
