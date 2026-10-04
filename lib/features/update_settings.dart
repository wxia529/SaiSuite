import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/app_state.dart';
import '../core/updates.dart';

Future<void> openUpdateUrl(
  BuildContext context,
  UpdateController updates,
  Uri url,
) async {
  try {
    await updates.service.open(url);
  } catch (e) {
    if (!context.mounted) return;
    final message = e is UpdateFailure
        ? e.message
        : e is PlatformException && e.code == 'NO_BROWSER'
        ? '没有可用的浏览器，请安装浏览器后重试'
        : '无法打开 GitHub，请稍后重试';
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }
}

void showUpdateDetails(BuildContext context, UpdateController updates) {
  final release = updates.release, app = updates.app;
  if (release == null || app == null) return;
  final asset = release.assetFor(app);
  showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text('发现新版本 ${release.version.name}'),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('当前版本 ${app.version}'),
            const SizedBox(height: 12),
            if (asset != null)
              Text(
                '${asset.name}\n${(asset.size / 1048576).toStringAsFixed(2)} MB',
              )
            else
              const Text('此版本暂未提供适配当前安装包的 APK，可前往发布页查看。'),
            const SizedBox(height: 16),
            Text(release.notes.isEmpty ? '此版本没有填写更新说明。' : release.notes),
            const SizedBox(height: 16),
            const Text('下载将在浏览器中打开。下载完成后，通过系统安装界面确认更新。'),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: const Text('稍后'),
        ),
        TextButton(
          onPressed: () => openUpdateUrl(dialogContext, updates, release.url),
          child: const Text('GitHub 发布页'),
        ),
        if (asset != null)
          FilledButton.icon(
            onPressed: () => openUpdateUrl(dialogContext, updates, asset.url),
            icon: const Icon(Icons.download_outlined),
            label: const Text('下载 APK'),
          ),
      ],
    ),
  );
}

class UpdateNotice extends StatelessWidget {
  const UpdateNotice({super.key, required this.updates});
  final UpdateController updates;
  @override
  Widget build(BuildContext context) => Card(
    color: Theme.of(context).colorScheme.secondaryContainer,
    child: ListTile(
      leading: const Icon(Icons.system_update_outlined),
      title: Text('发现新版本 ${updates.release!.version.name}'),
      subtitle: const Text('查看更新内容和安装包'),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => showUpdateDetails(context, updates),
    ),
  );
}

class UpdateSettings extends StatelessWidget {
  const UpdateSettings({super.key, required this.state, required this.updates});
  final AppState state;
  final UpdateController updates;
  @override
  Widget build(BuildContext context) {
    final last = updates.lastAttempt?.toLocal();
    final lastText = last == null
        ? null
        : '${last.year}-${last.month.toString().padLeft(2, '0')}-'
              '${last.day.toString().padLeft(2, '0')} ${last.hour.toString().padLeft(2, '0')}:'
              '${last.minute.toString().padLeft(2, '0')}';
    final status = updates.checking
        ? '正在检查 GitHub 发布版本…'
        : updates.error ??
              (updates.available
                  ? '发现新版本 ${updates.release!.version.name}'
                  : updates.checked
                  ? (updates.release == null ? 'GitHub 暂无正式发布版本' : '当前已是最新版本')
                  : last != null
                  ? '今日已尝试检查，可随时手动重试'
                  : '尚未检查更新');
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ListTile(
              leading: const Icon(Icons.system_update_outlined),
              title: const Text('应用更新'),
              subtitle: Text('当前版本 ${updates.app?.version ?? appVersion}'),
            ),
            SwitchListTile(
              title: const Text('自动检查更新'),
              subtitle: const Text('启动或返回应用时，每天最多检查一次'),
              value: state.autoCheckUpdates,
              onChanged: state.setAutoCheckUpdates,
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (updates.checking)
                    const Padding(
                      padding: EdgeInsets.only(bottom: 12),
                      child: LinearProgressIndicator(),
                    ),
                  Text(status, key: const ValueKey('update-status')),
                  if (lastText != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        '最近尝试：$lastText',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      OutlinedButton.icon(
                        onPressed: updates.checking
                            ? null
                            : () => updates.check(),
                        icon: const Icon(Icons.refresh),
                        label: const Text('检查更新'),
                      ),
                      if (updates.available)
                        FilledButton(
                          onPressed: () => showUpdateDetails(context, updates),
                          child: const Text('查看新版本'),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
