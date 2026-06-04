import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// ═══════════════════════════════════════════════════════════════════════════════
//  ADMIN CHATS MODERATION PAGE
//
//  Lists every chat room across the entire platform with stats per room
//  (message count, last message preview, last activity). Admin can:
//    1. Sort / search rooms by usta name, client id, or last activity
//    2. Open a room → see every message in chronological order
//    3. Delete an individual message (spam / fraud / leaked phone)
//    4. Delete an entire room (mass spam, abusive chat)
//
//  Architecture:
//    - Server reads via the existing anon Supabase client (admin session
//      uses Supabase Auth with profiles.role='admin', so RLS-bypassing
//      service-role calls aren't needed for SELECT — the existing
//      admin policies cover it).
//    - Deletes use the same SDK, relying on the admin policy on
//      chat_messages / chat_rooms.
//
//  Required Supabase SQL (apply once if not already):
//    create policy "admin select chats" on public.chat_rooms
//      for select using (
//        exists (select 1 from public.profiles
//                where id = auth.uid() and role = 'admin'));
//    create policy "admin delete chat rooms" on public.chat_rooms
//      for delete using (
//        exists (select 1 from public.profiles
//                where id = auth.uid() and role = 'admin'));
//    create policy "admin select chat msgs" on public.chat_messages
//      for select using (
//        exists (select 1 from public.profiles
//                where id = auth.uid() and role = 'admin'));
//    create policy "admin delete chat msgs" on public.chat_messages
//      for delete using (
//        exists (select 1 from public.profiles
//                where id = auth.uid() and role = 'admin'));
// ═══════════════════════════════════════════════════════════════════════════════

class ChatsModerationPage extends StatefulWidget {
  /// When true, the page is rendered inside the desktop sidebar pane
  /// (no Scaffold/AppBar — just the body).
  final bool embedded;
  const ChatsModerationPage({super.key, this.embedded = false});

  @override
  State<ChatsModerationPage> createState() => _ChatsModerationPageState();
}

class _ChatsModerationPageState extends State<ChatsModerationPage> {
  bool _loading = true;
  List<_RoomSummary> _rooms = const [];
  String _search = '';
  int _sortIdx = 3; // last activity desc by default
  bool _asc = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() => _loading = true);
    try {
      final client = Supabase.instance.client;

      // Pull rooms + per-room aggregates in two cheap queries (rooms,
      // then messages — bucketed client-side). For an admin-facing
      // moderation page this scales fine into the thousands of rooms.
      final roomRows = await client
          .from('chat_rooms')
          .select('id, client_id, usta_id, created_at, order_id');
      final rooms = (roomRows as List)
          .map((r) => Map<String, dynamic>.from(r as Map))
          .toList();

      final msgRows = await client
          .from('chat_messages')
          .select('id, room_id, sender, text, sent_at')
          .order('sent_at', ascending: false);
      final msgs = (msgRows as List)
          .map((r) => Map<String, dynamic>.from(r as Map))
          .toList();

      // Bucket messages by room — track last msg + total count
      final bucket = <String, _RoomAgg>{};
      for (final m in msgs) {
        final rid = (m['room_id'] ?? '').toString();
        final agg = bucket.putIfAbsent(rid, _RoomAgg.new);
        agg.count++;
        agg.last ??= m; // first wins (desc order)
      }

      // Hydrate usta names from usta_registrations so the row shows a
      // human label instead of just the reg-… id.
      final ustaIds = rooms
          .map((r) => (r['usta_id'] ?? '').toString())
          .toSet()
          .toList();
      final ustaRows = ustaIds.isEmpty
          ? <Map<String, dynamic>>[]
          : (await client
                  .from('usta_registrations')
                  .select('id, name, category')
                  .inFilter('id', ustaIds) as List)
              .map((r) => Map<String, dynamic>.from(r as Map))
              .toList();
      final ustaById = {
        for (final r in ustaRows) (r['id'] ?? '').toString(): r,
      };

      final summary = rooms.map((r) {
        final rid = (r['id'] ?? '').toString();
        final agg = bucket[rid];
        final usta = ustaById[(r['usta_id'] ?? '').toString()];
        return _RoomSummary(
          roomId: rid,
          clientId: (r['client_id'] ?? '').toString(),
          ustaId: (r['usta_id'] ?? '').toString(),
          ustaName: (usta?['name'] ?? '').toString(),
          ustaCategory: (usta?['category'] ?? '').toString(),
          orderId: r['order_id']?.toString() ?? '',
          createdAt: DateTime.tryParse((r['created_at'] ?? '').toString()) ??
              DateTime.now(),
          messageCount: agg?.count ?? 0,
          lastMessage: (agg?.last?['text'] ?? '').toString(),
          lastSender: (agg?.last?['sender'] ?? '').toString(),
          lastAt: DateTime.tryParse((agg?.last?['sent_at'] ?? '').toString()) ??
              DateTime.tryParse((r['created_at'] ?? '').toString()) ??
              DateTime.now(),
        );
      }).toList();

      if (!mounted) return;
      setState(() {
        _rooms = summary;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      _toast(
        title: 'Xato',
        body: e.toString(),
        bg: Colors.red.shade700,
      );
    }
  }

  Future<void> _deleteRoom(_RoomSummary room) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Suhbatni o\'chirish'),
        content: Text(
          'Bu suhbatni va undagi ${room.messageCount} ta xabarni butunlay o\'chirmoqchimisiz? Bu amal qaytarib bo\'lmaydi.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Bekor'),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: Colors.red.shade700),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('O\'chirish'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      // FK from chat_messages.room_id REFERENCES chat_rooms(id) ON DELETE CASCADE
      // takes care of the messages — we only need to delete the room.
      // `.select()` so an RLS-blocked delete (0 rows, no exception) is caught.
      final res = await Supabase.instance.client
          .from('chat_rooms')
          .delete()
          .eq('id', room.roomId)
          .select();
      if (!mounted) return;
      if ((res as List).isEmpty) {
        _toast(
            title: 'O\'chirib bo\'lmadi',
            body: 'Ruxsat yo\'q yoki suhbat topilmadi.',
            bg: Colors.red.shade700);
        return;
      }
      _toast(
        title: 'O\'chirildi',
        body: '${room.ustaName.isEmpty ? room.ustaId : room.ustaName} bilan suhbat o\'chirildi.',
        bg: const Color(0xFF198754),
      );
      _load();
    } catch (e) {
      if (mounted) {
        _toast(
            title: 'O\'chirib bo\'lmadi',
            body: e.toString(),
            bg: Colors.red.shade700);
      }
    }
  }

  Future<void> _openRoom(_RoomSummary room) async {
    await showDialog<void>(
      context: context,
      builder: (_) => _RoomMessagesDialog(room: room),
    );
    if (mounted) _load();
  }

  void _toast({required String title, required String body, required Color bg}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: bg,
        content: Text(
          '$title — $body',
          style: const TextStyle(color: Colors.white),
        ),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.embedded) return _buildEmbedded();
    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FA),
      appBar: AppBar(
        title: const Text('Suhbatlar moderatsiyasi'),
        backgroundColor: const Color(0xFF0F172A),
        foregroundColor: Colors.white,
      ),
      body: _buildEmbedded(),
    );
  }

  Widget _buildEmbedded() {
    return Column(children: [
      _Toolbar(
        search: _search,
        onSearch: (v) => setState(() => _search = v),
        totalRooms: _rooms.length,
        onRefresh: _load,
        loading: _loading,
      ),
      Expanded(
        child: _loading
            ? const Center(
                child: CircularProgressIndicator(
                  color: Color(0xFF1976D2),
                  strokeWidth: 2,
                ),
              )
            : _buildTable(),
      ),
    ]);
  }

  Widget _buildTable() {
    var rows = _rooms;
    if (_search.trim().isNotEmpty) {
      final q = _search.trim().toLowerCase();
      rows = rows.where((r) =>
          r.ustaName.toLowerCase().contains(q) ||
          r.clientId.toLowerCase().contains(q) ||
          r.lastMessage.toLowerCase().contains(q)).toList();
    }
    rows = List<_RoomSummary>.from(rows);
    rows.sort((a, b) {
      int cmp;
      switch (_sortIdx) {
        case 0:
          cmp = a.ustaName.toLowerCase().compareTo(b.ustaName.toLowerCase());
          break;
        case 1:
          cmp = a.clientId.compareTo(b.clientId);
          break;
        case 2:
          cmp = a.messageCount.compareTo(b.messageCount);
          break;
        case 3:
        default:
          cmp = a.lastAt.compareTo(b.lastAt);
      }
      return _asc ? cmp : -cmp;
    });

    if (rows.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Text(
            'Suhbat topilmadi',
            style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
          ),
        ),
      );
    }

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
            sortColumnIndex: _sortIdx,
            sortAscending: _asc,
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
              _col('CLIENT', 1),
              _col('MESSAGES', 2, numeric: true),
              _col('LAST ACTIVITY', 3),
              const DataColumn(label: Text('LAST PREVIEW')),
              const DataColumn(label: Text('ACTIONS')),
            ],
            rows: rows.map((r) {
              return DataRow(cells: [
                DataCell(Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      r.ustaName.isEmpty ? 'Usta?' : r.ustaName,
                      style: const TextStyle(
                          fontSize: 12.5, fontWeight: FontWeight.w700),
                    ),
                    if (r.ustaCategory.isNotEmpty)
                      Text(r.ustaCategory,
                          style: TextStyle(
                              fontSize: 10.5, color: Colors.grey.shade600)),
                  ],
                )),
                DataCell(Text(
                  _maskClient(r.clientId),
                  style: const TextStyle(fontSize: 11.5),
                )),
                DataCell(Text(
                  '${r.messageCount}',
                  style: const TextStyle(
                      fontSize: 12.5, fontWeight: FontWeight.w800),
                )),
                DataCell(Text(
                  DateFormat('d MMM, HH:mm').format(r.lastAt),
                  style: TextStyle(
                      fontSize: 11.5, color: Colors.grey.shade600),
                )),
                DataCell(SizedBox(
                  width: 260,
                  child: Text(
                    r.lastMessage.isEmpty
                        ? '—'
                        : '${r.lastSender == 'usta' ? '🔧 ' : '👤 '}${r.lastMessage}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12),
                  ),
                )),
                DataCell(Row(mainAxisSize: MainAxisSize.min, children: [
                  SizedBox(
                    height: 30,
                    child: OutlinedButton.icon(
                      onPressed: () => _openRoom(r),
                      icon: const Icon(Icons.visibility_outlined, size: 12),
                      label: const Text('Ko\'rish',
                          style: TextStyle(fontSize: 11)),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF1976D2),
                        side: const BorderSide(color: Color(0xFF1976D2)),
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(7)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  SizedBox(
                    height: 30,
                    child: OutlinedButton.icon(
                      onPressed: () => _deleteRoom(r),
                      icon: const Icon(Icons.delete_outline_rounded, size: 12),
                      label: const Text("O'chirish",
                          style: TextStyle(fontSize: 11)),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFFD32F2F),
                        side: const BorderSide(color: Color(0xFFD32F2F)),
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(7)),
                      ),
                    ),
                  ),
                ])),
              ]);
            }).toList(),
          ),
        ),
      ),
    );
  }

  DataColumn _col(String label, int idx, {bool numeric = false}) {
    return DataColumn(
      label: Text(label),
      numeric: numeric,
      onSort: (i, a) => setState(() {
        _sortIdx = i;
        _asc = a;
      }),
    );
  }

  String _maskClient(String id) {
    if (id.isEmpty || id == 'guest') return 'Mehmon';
    if (RegExp(r'^\d{9,15}$').hasMatch(id)) {
      final last2 = id.substring(id.length - 2);
      return '+••• •• ••• ** $last2';
    }
    final tail = id.length > 4 ? id.substring(id.length - 4) : id;
    return 'Mehmon #$tail';
  }
}

// ─── Helpers ─────────────────────────────────────────────────────────────

class _RoomSummary {
  final String roomId;
  final String clientId;
  final String ustaId;
  final String ustaName;
  final String ustaCategory;
  final String orderId;
  final DateTime createdAt;
  final int messageCount;
  final String lastMessage;
  final String lastSender;
  final DateTime lastAt;

  _RoomSummary({
    required this.roomId,
    required this.clientId,
    required this.ustaId,
    required this.ustaName,
    required this.ustaCategory,
    required this.orderId,
    required this.createdAt,
    required this.messageCount,
    required this.lastMessage,
    required this.lastSender,
    required this.lastAt,
  });
}

class _RoomAgg {
  int count = 0;
  Map<String, dynamic>? last;
  _RoomAgg();
}

// ─── Toolbar ─────────────────────────────────────────────────────────────

class _Toolbar extends StatelessWidget {
  final String search;
  final ValueChanged<String> onSearch;
  final int totalRooms;
  final VoidCallback onRefresh;
  final bool loading;

  const _Toolbar({
    required this.search,
    required this.onSearch,
    required this.totalRooms,
    required this.onRefresh,
    required this.loading,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Color(0x14000000))),
      ),
      child: Row(children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: const Color(0xFFF1F5F9),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            '$totalRooms rooms',
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
            onTap: loading ? null : onRefresh,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                loading
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
          width: 280,
          height: 36,
          child: TextField(
            onChanged: onSearch,
            decoration: InputDecoration(
              hintText: 'Search usta / client / message…',
              hintStyle: TextStyle(fontSize: 12, color: Colors.grey.shade500),
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
            ),
            style: const TextStyle(fontSize: 12),
          ),
        ),
      ]),
    );
  }
}

// ─── Room messages drill-down dialog ─────────────────────────────────────

class _RoomMessagesDialog extends StatefulWidget {
  final _RoomSummary room;
  const _RoomMessagesDialog({required this.room});

  @override
  State<_RoomMessagesDialog> createState() => _RoomMessagesDialogState();
}

class _RoomMessagesDialogState extends State<_RoomMessagesDialog> {
  bool _loading = true;
  List<Map<String, dynamic>> _messages = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final rows = await Supabase.instance.client
          .from('chat_messages')
          .select('id, sender, text, sent_at, read_at')
          .eq('room_id', widget.room.roomId)
          .order('sent_at', ascending: true);
      if (!mounted) return;
      setState(() {
        _messages = (rows as List)
            .map((r) => Map<String, dynamic>.from(r as Map))
            .toList();
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  void _toast({required String title, required String body, required Color bg}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: bg,
        content: Text('$title — $body',
            style: const TextStyle(color: Colors.white)),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _deleteMessage(int id) async {
    try {
      final res = await Supabase.instance.client
          .from('chat_messages')
          .delete()
          .eq('id', id)
          .select();
      if (!mounted) return;
      if ((res as List).isEmpty) {
        _toast(
            title: 'O\'chirib bo\'lmadi',
            body: 'Ruxsat yo\'q yoki xabar topilmadi.',
            bg: Colors.red.shade700);
        return;
      }
      _load();
    } catch (e) {
      if (mounted) {
        _toast(
            title: 'O\'chirib bo\'lmadi',
            body: e.toString(),
            bg: Colors.red.shade700);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Container(
        width: 600,
        constraints: const BoxConstraints(maxHeight: 600),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header
            Row(children: [
              const Icon(Icons.forum_rounded, color: Color(0xFF1976D2)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  widget.room.ustaName.isEmpty
                      ? widget.room.ustaId
                      : '${widget.room.ustaName} · ${widget.room.ustaCategory}',
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w800),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close, size: 18),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ]),
            const SizedBox(height: 8),
            Divider(color: Colors.grey.shade300, height: 1),
            const SizedBox(height: 12),
            // Messages
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
                  : _messages.isEmpty
                      ? const Center(child: Text('Bo\'sh suhbat'))
                      : ListView.separated(
                          itemCount: _messages.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 8),
                          itemBuilder: (_, i) {
                            final m = _messages[i];
                            final isClient = (m['sender'] ?? '') == 'client';
                            return Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: isClient
                                    ? const Color(0xFFE3F2FD)
                                    : const Color(0xFFE8F5E9),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(children: [
                                    Text(
                                      isClient ? '👤 Mijoz' : '🔧 Usta',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w800,
                                        color: isClient
                                            ? const Color(0xFF1976D2)
                                            : const Color(0xFF2E7D32),
                                      ),
                                    ),
                                    const Spacer(),
                                    Text(
                                      DateFormat('d MMM, HH:mm:ss').format(
                                          DateTime.tryParse(
                                                  (m['sent_at'] ?? '')
                                                      .toString()) ??
                                              DateTime.now()),
                                      style: TextStyle(
                                        fontSize: 10,
                                        color: Colors.grey.shade600,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    InkWell(
                                      onTap: () {
                                        final id = m['id'];
                                        if (id is int) _deleteMessage(id);
                                      },
                                      child: const Icon(
                                        Icons.delete_outline_rounded,
                                        size: 14,
                                        color: Color(0xFFD32F2F),
                                      ),
                                    ),
                                  ]),
                                  const SizedBox(height: 4),
                                  Text(
                                    (m['text'] ?? '').toString(),
                                    style: const TextStyle(fontSize: 13),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }
}
