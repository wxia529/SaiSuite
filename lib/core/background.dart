import 'package:timezone/data/latest.dart' as tzdata;

import 'engine.dart';
import 'electrolyte.dart';

String evaluateInBackground(Map<String, dynamic> request) {
  final id = request['id'] as String;
  if (id == 'D04') tzdata.initializeTimeZones();
  final values = Map<String, String>.from(request['values'] as Map);
  return id.startsWith('N') ? runLabTool(id, values) : runTool(id, values);
}
