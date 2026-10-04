import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:saisuite/app/sai_app.dart';
import 'package:saisuite/core/app_state.dart';
import 'package:saisuite/features/pdf_page.dart';
import 'package:saisuite/features/catalog.dart';
import 'package:crypto/crypto.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'Android PDF operations preserve content and round-trip encryption',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: Text('PDF 验证中'))),
      );
      Future<T> call<T extends Object>(
        String method,
        Map<String, dynamic> args,
      ) async => (await pdfChannel.invokeMethod<T>(method, args))!;
      final original = await call<String>('fixture', {}),
          originalHash = sha256.convert(await File(original).readAsBytes());
      final info = await call<Map>('inspect', {'path': original});
      expect(info['count'], 3);
      expect(info['title'], 'SaiSuite test fixture');
      final extracted = await call<String>('transform', {
        'path': original,
        'pages': [2, 0, 2],
      });
      expect((await call<Map>('inspect', {'path': extracted}))['count'], 3);
      final text = await call<String>('text', {
        'path': extracted,
        'pages': [0, 1, 2],
      });
      expect(text, contains('Page 3'));
      expect(text.indexOf('Page 3'), lessThan(text.indexOf('Page 1')));
      final split = await call<String>('transform', {
        'path': original,
        'pages': [1],
      });
      expect((await call<Map>('inspect', {'path': split}))['count'], 1);
      final merged = await call<String>('merge', {
        'sources': [
          {'path': original},
          {'path': split},
        ],
      });
      expect((await call<Map>('inspect', {'path': merged}))['count'], 4);
      final rotated = await call<String>('transform', {
        'path': original,
        'pages': [0, 1, 2],
        'rotation': 90,
        'rotationPages': [0],
      });
      final rotations =
          (await call<Map>('inspect', {'path': rotated}))['pages'] as List;
      expect(rotations[0]['rotation'], 90);
      expect(rotations[1]['rotation'], 0);
      final png = await call<String>('render', {
        'path': original,
        'page': 0,
        'dpi': 72,
        'format': 'PNG',
      });
      expect((await File(png).readAsBytes()).take(8).toList(), [
        137,
        80,
        78,
        71,
        13,
        10,
        26,
        10,
      ]);
      final jpeg = await call<String>('render', {
        'path': original,
        'page': 1,
        'dpi': 72,
        'format': 'JPEG',
      });
      expect((await File(jpeg).readAsBytes()).take(2).toList(), [255, 216]);
      final images = await call<String>('images', {
        'images': [png, jpeg],
        'paper': 'A4',
        'landscape': true,
        'margin': 10,
      });
      expect((await call<Map>('inspect', {'path': images}))['count'], 2);
      expect(
        (await call<String>('text', {
          'path': images,
        })).replaceAll(RegExp(r'--- 第 \d+ 页 ---'), '').trim(),
        isEmpty,
      );
      final many = await call<String>('fixture', {'count': 500});
      expect((await call<Map>('inspect', {'path': many}))['count'], 500);
      final excess = await call<String>('fixture', {'count': 501});
      await expectLater(
        call<Map>('inspect', {'path': excess}),
        throwsA(isA<PlatformException>()),
      );
      await expectLater(
        call<String>('merge', {
          'sources': [
            {'path': many},
            {'path': original},
          ],
        }),
        throwsA(isA<PlatformException>()),
      );
      final watermarked = await call<String>('watermark', {
        'path': original,
        'pages': [0],
        'text': '赛赛测试',
        'opacity': .3,
        'size': 24,
        'position': 'center',
      });
      expect(
        await call<String>('text', {
          'path': watermarked,
          'pages': [0],
        }),
        contains('Page 1'),
      );
      expect(
        await File(
          await call<String>('render', {
            'path': watermarked,
            'page': 0,
            'dpi': 72,
          }),
        ).length(),
        greaterThan(1000),
      );
      final imageMark = await call<String>('watermark', {
        'path': original,
        'pages': [0],
        'image': png,
        'opacity': .2,
        'size': 24,
        'position': 'bottom',
      });
      expect((await call<Map>('inspect', {'path': imageMark}))['count'], 3);
      final encrypted = await call<String>('encrypt', {
        'path': original,
        'newPassword': 'test-1234',
      });
      await expectLater(
        call<Map>('inspect', {'path': encrypted, 'password': 'wrong'}),
        throwsA(isA<PlatformException>()),
      );
      expect(
        (await call<Map>('inspect', {
          'path': encrypted,
          'password': 'test-1234',
        }))['encrypted'],
        true,
      );
      final decrypted = await call<String>('decrypt', {
        'path': encrypted,
        'password': 'test-1234',
      });
      expect(
        (await call<Map>('inspect', {'path': decrypted}))['encrypted'],
        false,
      );
      expect(
        await call<String>('text', {'path': decrypted}),
        contains('Page 1'),
      );
      await expectLater(
        call<String>('transform', {
          'path': original,
          'pages': [10],
        }),
        throwsA(isA<PlatformException>()),
      );
      final invalid = File(
        '${File(original).parent.path}/saisuite_invalid.pdf',
      );
      await invalid.writeAsString('not a pdf');
      await expectLater(
        call<Map>('inspect', {'path': invalid.path}),
        throwsA(isA<PlatformException>()),
      );
      expect(
        sha256.convert(await File(original).readAsBytes()).toString(),
        originalHash.toString(),
      );
      final prefs = await SharedPreferences.getInstance();
      await prefs.clear();
      final state = AppState(prefs);
      await tester.pumpWidget(
        MaterialApp(
          home: PdfPage(
            tool: tools.firstWhere((t) => t.id == 'P07'),
            state: state,
            initialInput: PdfInput(
              many,
              '500-page test',
              '',
              Map<String, dynamic>.from(
                await call<Map>('inspect', {'path': many}),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      // ListView builds children lazily; small emulator viewports may not have
      // built the action button until we scroll toward it.
      await tester.scrollUntilVisible(
        find.text('处理 / 查看'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('处理 / 查看'));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.scrollUntilVisible(
        find.text('取消当前操作'),
        100,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('取消当前操作'));
      await tester.pumpAndSettle();
      expect(find.textContaining('操作已取消'), findsOneWidget);
      expect(find.textContaining('已生成'), findsNothing);
      await state.star('S01');
      await state.setTheme(ThemeMode.dark);
      await state.visit('P01');
      final reload = AppState(await SharedPreferences.getInstance());
      expect(reload.favorites, ['S01']);
      expect(reload.theme, ThemeMode.dark);
      await tester.pumpWidget(SaiApp(state: reload));
      await tester.pumpAndSettle();
      expect(find.text('赛赛工具箱'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
