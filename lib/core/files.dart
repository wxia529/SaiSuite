import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:flutter/material.dart';

class Files {
  static Future<void> cleanOldCache() async {
    final dir = await getTemporaryDirectory();
    await for (final entry in dir.list(followLinks: false)) {
      if (entry is File &&
          entry.uri.pathSegments.last.startsWith('saisuite_')) {
        final info = await entry.stat();
        if (DateTime.now().difference(info.modified) >
            const Duration(days: 1)) {
          await entry.delete();
        }
      }
    }
  }

  static Future<String?> saveBytes(Uint8List bytes, String name) async =>
      (await FilePicker.saveFile(
        dialogTitle: '另存为新文件',
        fileName: name,
        bytes: bytes,
        mimeType: name.endsWith('.pdf')
            ? 'application/pdf'
            : name.endsWith('.png')
            ? 'image/png'
            : name.endsWith('.zip')
            ? 'application/zip'
            : 'application/octet-stream',
      ))?.toString();
  static Future<String> localCopy(
    PlatformFile picked, {
    int maxBytes = 104857600,
  }) async {
    final size = await picked.length();
    if (size != null && size > maxBytes) {
      throw FormatException('文件超过 ${maxBytes ~/ 1048576} MB 上限');
    }
    if (picked.path != null) return picked.path!;
    if (picked.uri.scheme != 'content') {
      throw const FormatException('只支持本地文件或系统文件提供器');
    }
    final dir = await getTemporaryDirectory();
    final ext = (picked.extension ?? 'bin').replaceAll(
      RegExp(r'[^a-zA-Z0-9]'),
      '',
    );
    final file = File(
      '${dir.path}/saisuite_import_${DateTime.now().microsecondsSinceEpoch}.$ext',
    );
    final sink = file.openWrite();
    var total = 0;
    try {
      await for (final chunk in picked.readAsByteStream()) {
        total += chunk.length;
        if (total > maxBytes) throw const FormatException('文件超过大小限制');
        sink.add(chunk);
      }
      await sink.close();
      return file.path;
    } catch (_) {
      await sink.close();
      if (await file.exists()) await file.delete();
      rethrow;
    }
  }

  static Future<String?> saveText(String content, String name) =>
      saveBytes(Uint8List.fromList(utf8.encode(content)), name);
  static Future<void> shareBytes(
    BuildContext context,
    Uint8List bytes,
    String name,
  ) async {
    final dir = await getTemporaryDirectory(),
        file = File('${dir.path}/saisuite_share_$name');
    await file.writeAsBytes(bytes, flush: true);
    if (!context.mounted) return;
    final box = context.findRenderObject() as RenderBox?;
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path)],
        sharePositionOrigin: box == null
            ? null
            : box.localToGlobal(Offset.zero) & box.size,
      ),
    );
  }

  static Future<void> shareText(BuildContext context, String text) async {
    final box = context.findRenderObject() as RenderBox?;
    await SharePlus.instance.share(
      ShareParams(
        text: text,
        sharePositionOrigin: box == null
            ? null
            : box.localToGlobal(Offset.zero) & box.size,
      ),
    );
  }
}
