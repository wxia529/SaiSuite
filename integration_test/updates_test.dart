import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:saisuite/app/sai_app.dart';
import 'package:saisuite/core/app_state.dart';
import 'package:saisuite/core/updates.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'Android update bridge, preferences, matching APK and live GitHub API',
    (tester) async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.clear();
      final state = AppState(prefs);
      await state.setAutoCheckUpdates(false);
      final installed = await InstalledApp.read();
      expect(installed.version, appVersion);
      expect(
        installed.variant,
        'universal',
      ); // Debug uses the base versionCode without an ABI offset.
      await expectLater(
        updateChannel.invokeMethod('openUrl', {
          'url': 'https://example.com/update.apk',
        }),
        throwsA(
          isA<PlatformException>().having((e) => e.code, 'code', 'INVALID_URL'),
        ),
      );
      var requests = 0;
      final future = GitHubRelease.parse({
        'tag_name': 'v9.0.0',
        'draft': false,
        'prerelease': false,
        'body': '更新检查测试说明',
        'html_url': 'https://github.com/$githubRepository/releases/tag/v9.0.0',
        'assets': [
          {
            'name': 'SaiSuite-9.0.0-universal.apk',
            'state': 'uploaded',
            'size': 100,
            'browser_download_url':
                'https://github.com/$githubRepository/releases/download/v9.0.0/SaiSuite-9.0.0-universal.apk',
          },
        ],
      });
      final updates = UpdateController(
        state,
        GitHubUpdates(
          fetchRelease: () async {
            requests++;
            return future;
          },
        ),
      );
      await tester.pumpWidget(SaiApp(state: state, updates: updates));
      await tester.pumpAndSettle();
      expect(requests, 0);
      await tester.tap(find.text('设置'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('检查更新'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('检查更新'));
      await tester.pumpAndSettle();
      expect(requests, 1);
      expect(updates.available, isTrue);
      expect(
        updates.release!.assetFor(updates.app!)!.name,
        'SaiSuite-9.0.0-universal.apk',
      );
      await tester.ensureVisible(find.text('查看新版本'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('查看新版本'));
      await tester.pumpAndSettle();
      expect(find.text('更新检查测试说明'), findsOneWidget);
      await tester.tap(find.text('稍后'));
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      updates.dispose();
      final restored = AppState(await SharedPreferences.getInstance());
      expect(restored.autoCheckUpdates, isFalse);
      final reloaded = UpdateController(
        restored,
        GitHubUpdates(
          fetchRelease: () async {
            requests++;
            return future;
          },
        ),
      );
      await reloaded.initialize();
      expect(reloaded.available, isTrue);
      expect(requests, 1);
      reloaded.dispose();
      final live = await GitHubUpdates.fetchLatest();
      if (live != null) {
        expect(
          live.url.host,
          'github.com',
        ); // The real repository may acquire its first release later.
      }
      expect(tester.takeException(), isNull);
    },
  );
}
