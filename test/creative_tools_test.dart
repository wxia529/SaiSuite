import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:image/image.dart' as img;
import 'package:archive/archive.dart';
import 'package:saisuite/core/extra_text.dart';
import 'package:saisuite/core/creative_images.dart';
import 'package:saisuite/core/app_state.dart';
import 'package:saisuite/features/catalog.dart';
import 'package:saisuite/features/extra_daily_page.dart';
import 'package:saisuite/features/extra_text_page.dart';
import 'package:saisuite/features/image_studio_page.dart';
import 'package:saisuite/features/poster_page.dart';
import 'package:saisuite/features/recognition_page.dart';

void main() {
  test('big integers, invalid radix and signed conversions', () {
    final number = '${BigInt.one << 256}';
    expect(convertBase(convertBase(number, 10, 36), 36, 10), number);
    expect(convertBase('-FF', 16, 10), '-255');
    expect(() => convertBase('2', 2, 10), throwsFormatException);
    expect(() => convertBase('1', 1, 10), throwsFormatException);
  });
  test('Chinese number groups, zero bridges and money precision', () {
    expect(chineseNumber('10'), '十');
    expect(chineseNumber('100010001'), '一亿零一万零一');
    expect(chineseNumber('-0.05', money: true), '负零元零伍分');
    expect(chineseNumber('1001.20', money: true), '壹仟零壹元贰角');
    expect(() => chineseNumber('1.005', money: true), throwsFormatException);
  });
  test('Morse roundtrip, unknown input, scripts and pinyin Unicode', () {
    expect(morse(morse('HELLO WORLD 123'), decode: true), 'HELLO WORLD 123');
    expect(() => morse('你好'), throwsFormatException);
    expect(raisedDigits('H2O', sub: true), 'H₂O');
    expect(miniEnglish('Abc 中文'), 'ᴀʙᴄ 中文');
    expect(pinyinText('重庆银行', '无声调', {}), 'chong qing yin hang');
    expect(pinyinText('重庆银行', '首字母', {}), 'cqyh');
    expect(pinyinText('你好😀SaiSuite', '声调符号', {}), contains('😀SaiSuite'));
    expect(pinyinText('重庆', '声调符号', {0: 'zhòng'}), startsWith('zhòng'));
  });
  test('gradient dimensions and known endpoints', () {
    final result = creativeImageJob({
      'action': 'gradient',
      'width': 120,
      'height': 60,
      'colors': [0xff000000, 0xffffffff],
      'angle': 0,
      'noise': 0,
    });
    final image = img.decodePng(result['bytes'] as Uint8List)!;
    expect(image.width, 120);
    expect(image.height, 60);
    expect(image.getPixel(0, 10).r, 0);
    expect(image.getPixel(119, 10).r, greaterThan(250));
  });
  test('nine tiles retain correct order and crop pixels', () {
    final input = img.Image(width: 90, height: 60);
    for (final p in input) {
      p
        ..r = p.x
        ..g = p.y
        ..b = 33;
    }
    final source = img.encodePng(input);
    final result = creativeImageJob({
      'action': 'grid',
      'bytes': source,
      'x': 1.0,
      'y': .5,
    });
    final archive = ZipDecoder().decodeBytes(result['bytes'] as Uint8List);
    expect(archive.length, 9);
    final first = img.decodePng(
      Uint8List.fromList(archive.files.first.content),
    )!;
    final last = img.decodePng(Uint8List.fromList(archive.files.last.content))!;
    expect(first.width, 20);
    expect(first.getPixel(0, 0).r, 30);
    expect(last.getPixel(19, 19).r, 89);
    expect(last.getPixel(19, 19).g, 59);
    expect(img.decodePng(source)!.getPixel(0, 0).r, 0);
  });
  test('GIF roundtrip preserves frame count, timing and visible colors', () {
    final red = img.Image(width: 64, height: 64)
      ..clear(img.ColorRgb8(255, 0, 0));
    final blue = img.Image(width: 64, height: 64)
      ..clear(img.ColorRgb8(0, 0, 255));
    final gif =
        creativeImageJob({
              'action': 'gifMake',
              'images': [img.encodePng(red), img.encodePng(blue)],
              'durations': [100, 350],
              'edge': 64,
              'loop': true,
            })['bytes']
            as Uint8List;
    final decoded = img.decodeGif(gif)!;
    expect(decoded.numFrames, 2);
    expect(decoded.frames[0].frameDuration, 100);
    expect(decoded.frames[1].frameDuration, 350);
    expect(decoded.frames[0].getPixel(10, 10).r, greaterThan(240));
    expect(decoded.frames[1].getPixel(10, 10).b, greaterThan(240));
    final split = creativeImageJob({'action': 'gifSplit', 'bytes': gif});
    expect(split['frames'], 2);
    expect(ZipDecoder().decodeBytes(split['bytes'] as Uint8List).length, 3);
  });
  testWidgets('GIF loop toggle controls actual Flutter playback', (
    tester,
  ) async {
    final one = img.Image(width: 64, height: 64)
      ..clear(img.ColorRgb8(200, 20, 30));
    final two = img.Image(width: 64, height: 64)
      ..clear(img.ColorRgb8(30, 20, 200));
    for (final looping in [true, false]) {
      final result = creativeImageJob({
        'action': 'gifMake',
        'images': [img.encodePng(one), img.encodePng(two)],
        'durations': [100, 100],
        'edge': 64,
        'loop': looping,
      });
      final codec = await ui.instantiateImageCodec(
        result['bytes'] as Uint8List,
      );
      expect(codec.frameCount, 2);
      expect(codec.repetitionCount, looping ? -1 : 0);
      codec.dispose();
    }
  });
  test('count excludes border/noise and finds separate objects', () {
    final image = img.Image(width: 200, height: 160)
      ..clear(img.ColorRgb8(255, 255, 255));
    for (final center in [(40, 40), (100, 80), (150, 120)]) {
      img.fillCircle(
        image,
        x: center.$1,
        y: center.$2,
        radius: 10,
        color: img.ColorRgb8(0, 0, 0),
      );
    }
    img.fillRect(
      image,
      x1: 0,
      y1: 10,
      x2: 15,
      y2: 25,
      color: img.ColorRgb8(0, 0, 0),
    );
    image.setPixelRgb(60, 50, 0, 0, 0);
    final result = creativeImageJob({
      'action': 'count',
      'bytes': img.encodePng(image),
      'dark': true,
      'threshold': 100,
      'minArea': 50,
    });
    expect((result['points'] as List).length, 3);
  });
  testWidgets(
    'all creative workbenches fit a narrow screen and dispose cleanly',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final state = AppState(await SharedPreferences.getInstance());
      await tester.binding.setSurfaceSize(const Size(360, 800));
      for (final tool in tools.where(
        (t) => RegExp(r'^[UXB]\d').hasMatch(t.id),
      )) {
        final page = tool.id.startsWith('U')
            ? ExtraDailyPage(tool: tool, state: state)
            : tool.id.startsWith('X')
            ? ExtraTextPage(tool: tool, state: state)
            : {'B04', 'B05'}.contains(tool.id)
            ? PosterPage(tool: tool, state: state)
            : {'B08', 'B09'}.contains(tool.id)
            ? RecognitionPage(tool: tool, state: state)
            : ImageStudioPage(tool: tool, state: state);
        await tester.pumpWidget(MaterialApp(home: page));
        await tester.pump();
        expect(tester.takeException(), isNull, reason: tool.name);
        await tester.pumpWidget(const SizedBox());
        await tester.pump();
      }
      await tester.binding.setSurfaceSize(null);
      state.dispose();
    },
  );
}
