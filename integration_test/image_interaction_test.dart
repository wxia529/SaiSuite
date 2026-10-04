import 'package:integration_test/integration_test.dart';

import '../test/image_interaction_test.dart' show registerImageGestureTests;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  registerImageGestureTests(onDevice: true);
}
