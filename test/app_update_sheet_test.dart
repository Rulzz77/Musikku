import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_5/services/app_update_service.dart';
import 'package:flutter_application_5/widgets/app_update_sheet.dart';

void main() {
  testWidgets('duplicate update prompts show only one bottom sheet', (tester) async {
    const release = AppUpdateRelease(
      version: '99.0.0',
      tagName: 'v99.0.0',
      title: 'MusikKu 99.0.0',
      notes: 'Update prompt regression test',
      releasePageUrl: 'https://github.com/Rulzz77/flutter_application_5/releases/tag/v99.0.0',
      apkUrl: 'https://github.com/Rulzz77/flutter_application_5/releases/download/v99.0.0/app-release.apk',
      apkFileName: 'app-release.apk',
      apkSize: 1024,
      sha256Digest: null,
      publishedAt: null,
    );
    const result = AppUpdateCheckResult(
      status: AppUpdateStatus.available,
      currentVersion: '4.6.5',
      release: release,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                key: const ValueKey('trigger-duplicate-update'),
                onPressed: () {
                  unawaited(AppUpdateSheet.show(
                    context,
                    initialResult: result,
                    automaticPrompt: true,
                  ));
                  unawaited(AppUpdateSheet.show(
                    context,
                    initialResult: result,
                    automaticPrompt: true,
                  ));
                },
                child: const Text('Open update'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('trigger-duplicate-update')));
    await tester.pumpAndSettle();

    expect(find.text('Pembaruan MusikKu'), findsOneWidget);
    expect(find.text('Pembaruan tersedia • v99.0.0'), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();

    // The same automatic release prompt must not reappear after being dismissed.
    await tester.tap(find.byKey(const ValueKey('trigger-duplicate-update')));
    await tester.pumpAndSettle();
    expect(find.text('Pembaruan MusikKu'), findsNothing);
  });
}
