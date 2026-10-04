import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('native images video device and PDF smoke check', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: Text('原生工具验证中'))),
    );
    const media = MethodChannel('saisuite/media'),
        device = MethodChannel('saisuite/device'),
        pdf = MethodChannel('saisuite/pdf');
    final dir = await getTemporaryDirectory();
    final recorder = ui.PictureRecorder(), canvas = Canvas(recorder);
    canvas.drawRect(
      const Rect.fromLTWH(0, 0, 8, 8),
      Paint()..color = const Color(0xffff0000),
    );
    canvas.drawRect(
      const Rect.fromLTWH(8, 0, 8, 8),
      Paint()..color = const Color(0xff00ff00),
    );
    final picture = recorder.endRecording(),
        image = await picture.toImage(16, 8);
    final file = File('${dir.path}/saisuite_test.png');
    await file.writeAsBytes(
      (await image.toByteData(format: ui.ImageByteFormat.png))!.buffer
          .asUint8List(),
    );
    image.dispose();
    picture.dispose();
    final crop = await media.invokeMapMethod('imageProcess', {
      'paths': [file.path],
      'width': 16,
      'crop': [0, 0, 50, 100],
      'rotation': 0,
      'flip': false,
      'layout': '网格',
      'format': 'PNG',
      'quality': 100,
      'watermark': '',
    });
    expect(crop!['width'], 16);
    final imageInfo = await media.invokeMapMethod('imageInfo', {
      'path': file.path,
    });
    expect(imageInfo!['width'], 16);
    expect(imageInfo['height'], 8);
    expect(crop['height'], 16);
    final codec = await ui.instantiateImageCodec(
      await File(crop['path'] as String).readAsBytes(),
    );
    final frame = (await codec.getNextFrame()).image,
        pixels = (await frame.toByteData(format: ui.ImageByteFormat.rawRgba))!
            .buffer
            .asUint8List();
    expect(pixels[(8 * 16 + 8) * 4], 255);
    expect(pixels[(8 * 16 + 8) * 4 + 1], 0);
    frame.dispose();
    codec.dispose();
    final collage = await media.invokeMapMethod('imageProcess', {
      'paths': [file.path, file.path],
      'width': 32,
      'crop': [0, 0, 100, 100],
      'rotation': 0,
      'flip': false,
      'layout': '横向',
      'format': 'JPEG',
      'quality': 80,
      'watermark': '测试',
    });
    expect(collage!['width'], 32);
    expect((collage['bytes'] as num) > 0, true);
    final client = HttpClient();
    final videoFile = File('${dir.path}/saisuite_test.mp4');
    try {
      final request = await client.getUrl(
        Uri.parse(
          'https://raw.githubusercontent.com/androidx/media/release/libraries/test_data/src/test/assets/media/mp4/sample.mp4',
        ),
      );
      final response = await request.close();
      expect(response.statusCode, 200);
      final bytes = <int>[];
      await for (final part in response) {
        bytes.addAll(part);
      }
      await videoFile.writeAsBytes(bytes);
    } finally {
      client.close(force: true);
    }
    final source = await media.invokeMapMethod('videoInfo', {
      'path': videoFile.path,
    });
    expect((source!['duration'] as num) > 0, true);
    final videoFrame = await media.invokeMapMethod('videoFrame', {
      'path': videoFile.path,
      'seconds': 0.0,
    });
    expect(await File(videoFrame!['path'] as String).exists(), true);
    final output = await media.invokeMapMethod('videoProcess', {
      'path': videoFile.path,
      'start': 0.0,
      'end': .5,
      'mute': true,
      'height': 360,
      'bitrate': 500000,
    });
    expect((output!['bytes'] as num) > 0, true);
    final outputInfo = await media.invokeMapMethod('videoInfo', {
      'path': output['path'],
    });
    expect(outputInfo!['duration'] as num, closeTo(.5, .15));
    expect(outputInfo['hasAudio'], false);
    expect((await media.invokeMethod<int>('videoProgress'))!, -1);
    String? cancellation;
    final cancelling = media
        .invokeMapMethod('videoProcess', {
          'path': videoFile.path,
          'start': 0.0,
          'end': .5,
          'mute': false,
          'height': 1080,
          'bitrate': 1000000,
        })
        .catchError((Object e) {
          if (e is PlatformException) {
            cancellation = e.code;
            return <dynamic, dynamic>{};
          }
          throw e;
        });
    await media.invokeMethod('videoCancel');
    await cancelling;
    expect(cancellation, 'CANCELLED');
    final inventory = await device.invokeMethod<List>('sensors');
    expect(inventory, isNotEmpty);
    final metrics = await device.invokeMapMethod('displayMetrics');
    expect((metrics!['xdpi'] as num) > 0, true);
    await device.invokeMethod('timerCancel');
    final original = await pdf.invokeMethod<String>('fixture', {}),
        info = await pdf.invokeMapMethod('inspect', {'path': original});
    expect(info!['count'], 3);
    await media.invokeMethod('mediaCleanup', {
      'paths': [
        crop['path'],
        collage['path'],
        videoFrame['path'],
        output['path'],
      ],
    });
    await file.delete();
    await videoFile.delete();
    // No experimental data is written to preferences by any of these services.
    expect(jsonEncode(inventory), contains('available'));
  });
}
