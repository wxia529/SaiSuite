import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Only retired tool shortcuts are migrated, never exported files.
const retiredToolIds = {'N02', 'N06', 'N07', 'EC21', 'B06'};

List<String> migrateShortcutIds(List<String> ids) => {
  for (final id in ids)
    if (!retiredToolIds.contains(id)) id == 'B05' ? 'B04' : id,
}.toList();

class AppState extends ChangeNotifier {
  AppState(this.prefs) {
    favorites = migrateShortcutIds(prefs.getStringList('favorites') ?? []);
    recent = migrateShortcutIds(prefs.getStringList('recent') ?? []);
    final mode = prefs.getInt('theme') ?? 0;
    theme = ThemeMode.values[mode.clamp(0, ThemeMode.values.length - 1)];
    calculatorHistory = prefs.getStringList('calculatorHistory') ?? [];
    autoCheckUpdates = prefs.getBool('autoCheckUpdates') ?? true;
  }
  final SharedPreferences prefs;
  late List<String> favorites, recent, calculatorHistory;
  late ThemeMode theme;
  late bool autoCheckUpdates;
  Future<void> setAutoCheckUpdates(bool enabled) async {
    autoCheckUpdates = enabled;
    notifyListeners();
    await prefs.setBool('autoCheckUpdates', enabled);
  }

  Future<void> migrateRetiredTools() async {
    for (final key in ['favorites', 'recent']) {
      final saved = prefs.getStringList(key);
      if (saved != null && !listEquals(saved, migrateShortcutIds(saved))) {
        await prefs.setStringList(key, migrateShortcutIds(saved));
      }
    }
  }

  Future<void> star(String id) async {
    favorites.contains(id) ? favorites.remove(id) : favorites.add(id);
    notifyListeners();
    await prefs.setStringList('favorites', favorites);
  }

  Future<void> reorder(int old, int next) async {
    final id = favorites.removeAt(old);
    favorites.insert(next, id);
    notifyListeners();
    await prefs.setStringList('favorites', favorites);
  }

  Future<void> visit(String id) async {
    recent.remove(id);
    recent.insert(0, id);
    recent = recent.take(20).toList();
    notifyListeners();
    await prefs.setStringList('recent', recent);
  }

  Future<void> setTheme(ThemeMode mode) async {
    theme = mode;
    notifyListeners();
    await prefs.setInt('theme', mode.index);
  }

  Future<void> rememberCalculation(String expression, String result) async {
    calculatorHistory.insert(
      0,
      jsonEncode({'expression': expression, 'result': result}),
    );
    calculatorHistory = calculatorHistory.take(30).toList();
    await prefs.setStringList('calculatorHistory', calculatorHistory);
    notifyListeners();
  }

  Future<void> clearHistory() async {
    recent = [];
    calculatorHistory = [];
    notifyListeners();
    await prefs.remove('recent');
    await prefs.remove('calculatorHistory');
  }
}
