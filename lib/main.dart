import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'modules/admin/views/admin_entry_route.dart';
import 'modules/theme/colors.dart';
import 'translations/app_translations.dart';

// ═══════════════════════════════════════════════════════════════════════════════
//  MEDIRO ADMIN — Web-only admin dashboard
//
//  Standalone Flutter web app for managing the Mediro Usta-Market platform.
//  Mirrors the admin panel that was previously embedded inside the mobile
//  app at `Vafokul/android`. Sharing the same Supabase project (read +
//  write same tables: usta_registrations, complaints, chat_messages,
//  telemetry_*, profiles).
//
//  Entry: AdminEntryRoute → AdminLoginPage (cloud-verify profiles.role)
//                        → AdminPanelPage (verifications, complaints, telemetry)
// ═══════════════════════════════════════════════════════════════════════════════

const _supabaseUrl     = 'https://ozwwnnspjincujrtdjwh.supabase.co';
const _supabaseAnonKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im96d3dubnNwamluY3VqcnRkandoIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NTEyMzA0NTcsImV4cCI6MjA2NjgwNjQ1N30.RX06As-UNwTxpgPadN2K9S9_04w4UF7VLf60etw_wiA';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(url: _supabaseUrl, anonKey: _supabaseAnonKey);
  await GetStorage.init();
  runApp(const MediroAdminApp());
}

class MediroAdminApp extends StatelessWidget {
  const MediroAdminApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ScreenUtilInit(
      // Desktop-first admin: a desktop design size keeps .w/.sp/.r at their
      // authored values on a desktop browser (the 360×690 phone size blew
      // horizontal spacing up ~4× on wide screens — oversized / spread out).
      designSize: const Size(1280, 800),
      minTextAdapt: true,
      splitScreenMode: true,
      builder: (context, child) => GetMaterialApp(
        title: 'Mediro Admin',
        translations: AppTranslations(),
        locale: const Locale('uz'),
        fallbackLocale: const Locale('uz'),
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: false,
          primaryColor: AppColors.healixGreen,
          scaffoldBackgroundColor: const Color(0xFFF6F7FB),
          colorScheme: ColorScheme.fromSeed(
            seedColor: AppColors.healixGreen,
            primary: AppColors.healixGreen,
            brightness: Brightness.light,
          ),
        ),
        home: const AdminEntryRoute(),
      ),
    );
  }
}
