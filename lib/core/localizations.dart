import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:material_ui/material_ui.dart' as editor_ui;

// Subeditors open routes on the app Navigator, so both Material libraries
// need their delegates above that Navigator, rather than only on the editor.
const saiLocalizationsDelegates = [
  ...GlobalMaterialLocalizations.delegates,
  ...editor_ui.GlobalMaterialLocalizations.delegates,
];
