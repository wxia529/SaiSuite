import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:saisuite/features/pdf_page.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'mixed native image dimensions, alpha and EXIF remain intact in PDF',
    (tester) async {
      final temp = await getTemporaryDirectory();
      final folder = '${temp.path}/pdf-original-size-fixtures';
      final paths = [
        '$folder/wide.png',
        '$folder/portrait.png',
        for (var i = 1; i <= 8; i++) '$folder/orientation-$i.jpg',
      ];
      final hashes = [
        for (final path in paths)
          sha256.convert(await File(path).readAsBytes()).toString(),
      ];
      final output = (await pdfChannel.invokeMethod<String>('images', {
        'images': paths,
        'paper': '按图片尺寸',
        'landscape': true,
        'margin': 500,
      }))!;
      final info = (await pdfChannel.invokeMapMethod<String, dynamic>(
        'inspect',
        {'path': output},
      ))!;
      expect(info['count'], 10);
      final pages = info['pages'] as List;
      expect((pages[0] as Map)['width'], 5000);
      expect((pages[0] as Map)['height'], 200);
      expect((pages[1] as Map)['width'], 240);
      expect((pages[1] as Map)['height'], 480);
      for (var i = 1; i <= 8; i++) {
        expect((pages[i + 1] as Map)['width'], i >= 5 ? 120 : 180);
        expect((pages[i + 1] as Map)['height'], i >= 5 ? 180 : 120);
      }
      final saved = File('${temp.path}/saisuite_pdf_original_size_test.pdf');
      await File(output).copy(saved.path);
      // The driver copies the generated fixture for independent pypdf/Poppler inspection.
      // ignore: avoid_print
      print('PDF_ORIGINAL_SIZE_READY');
      await Future<void>.delayed(const Duration(seconds: 10));
      final standard = (await pdfChannel.invokeMethod<String>('images', {
        'images': paths.take(2).toList(),
        'paper': 'A4',
        'landscape': true,
        'margin': 20,
      }))!;
      final a4 = (await pdfChannel.invokeMapMethod<String, dynamic>('inspect', {
        'path': standard,
      }))!;
      for (final page in a4['pages'] as List) {
        expect((page as Map)['width'], closeTo(841.89, .1));
        expect(page['height'], closeTo(595.28, .1));
      }
      final letter = (await pdfChannel.invokeMethod<String>('images', {
        'images': [paths.first],
        'paper': 'Letter',
        'margin': 20,
      }))!;
      final letterInfo = (await pdfChannel.invokeMapMethod<String, dynamic>(
        'inspect',
        {'path': letter},
      ))!;
      expect((letterInfo['pages'] as List).first['width'], 612);
      expect((letterInfo['pages'] as List).first['height'], 792);
      await expectLater(
        pdfChannel.invokeMethod<String>('images', {
          'images': ['$folder/oversize.png'],
          'paper': '按图片尺寸',
        }),
        throwsA(
          isA<PlatformException>().having(
            (e) => e.message,
            'message',
            contains('1600 万像素'),
          ),
        ),
      );
      for (var i = 0; i < paths.length; i++) {
        expect(
          sha256.convert(await File(paths[i]).readAsBytes()).toString(),
          hashes[i],
        );
      }
      await pdfChannel.invokeMethod<void>('cleanup', {
        'paths': [output, standard, letter, saved.path],
      });
    },
  );
}
