import 'dart:typed_data';

import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// ═══════════════════════════════════════════════════════════════════════════
//  SERVICE STORAGE — provider avatar + equipment photo uploads.
//
//  Uploads to the public `service-photos` bucket (RLS: usta_admin write,
//  public read) and returns the public URL. Web-compatible (uses bytes from
//  image_picker's XFile).
// ═══════════════════════════════════════════════════════════════════════════

class ServiceStorage {
  static final _picker = ImagePicker();

  /// Opens the file picker and uploads the chosen image. Returns the public
  /// URL, or null if the user cancelled or the upload failed.
  static Future<String?> pickAndUpload({int counter = 0}) async {
    final XFile? file =
        await _picker.pickImage(source: ImageSource.gallery, imageQuality: 82);
    if (file == null) return null;
    final bytes = await file.readAsBytes();
    return uploadBytes(bytes, file.name, counter: counter);
  }

  /// Uploads raw bytes; returns the public URL or null on failure.
  static Future<String?> uploadBytes(Uint8List bytes, String name,
      {int counter = 0}) async {
    try {
      final bucket = Supabase.instance.client.storage.from('service-photos');
      final ext = _ext(name);
      final ts = DateTime.now().millisecondsSinceEpoch;
      final path = 'p_${ts}_$counter.$ext';
      await bucket.uploadBinary(
        path,
        bytes,
        fileOptions: FileOptions(contentType: _mime(ext), upsert: false),
      );
      return bucket.getPublicUrl(path);
    } catch (_) {
      return null;
    }
  }

  static String _ext(String name) {
    final i = name.lastIndexOf('.');
    final e = (i >= 0 ? name.substring(i + 1) : 'jpg').toLowerCase();
    return e.isEmpty ? 'jpg' : e;
  }

  static String _mime(String ext) {
    switch (ext) {
      case 'png':
        return 'image/png';
      case 'webp':
        return 'image/webp';
      case 'gif':
        return 'image/gif';
      default:
        return 'image/jpeg';
    }
  }
}
