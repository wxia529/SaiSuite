import 'package:timezone/data/latest.dart' as tzdata;

import 'engine.dart';

String evaluateInBackground(Map<String, dynamic> request) {
  final id = request['id'] as String;
  if (id == 'D04') tzdata.initializeTimeZones();
  return runTool(id, Map<String, String>.from(request['values'] as Map));
}
