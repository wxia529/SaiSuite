import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tzdata;

import 'core/app_state.dart';
import 'core/files.dart';
import 'app/sai_app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  tzdata.initializeTimeZones();
  await Files.cleanOldCache();
  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks([
      'AndroidX Media3',
    ], await rootBundle.loadString('assets/licenses/media3-LICENSE.txt'));
    yield LicenseEntryWithLineBreaks(
      ['PdfBox-Android / Apache PDFBox'],
      '${await rootBundle.loadString('assets/licenses/pdfbox-LICENSE.txt')}\n${await rootBundle.loadString('assets/licenses/pdfbox-NOTICE.txt')}',
    );
  });
  final state = AppState(await SharedPreferences.getInstance());
  await state.migrateRetiredTools();
  runApp(SaiApp(state: state));
}
