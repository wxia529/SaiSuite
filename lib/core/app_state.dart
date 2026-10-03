import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppState extends ChangeNotifier {
  AppState(this.prefs) {
    favorites = prefs.getStringList('favorites') ?? [];
    recent = prefs.getStringList('recent') ?? [];
    final mode = prefs.getInt('theme') ?? 0;
    theme = ThemeMode.values[mode.clamp(0, ThemeMode.values.length - 1)];
    calculatorHistory = prefs.getStringList('calculatorHistory') ?? [];
  }
  final SharedPreferences prefs;
  late List<String> favorites, recent, calculatorHistory;
  late ThemeMode theme;
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
