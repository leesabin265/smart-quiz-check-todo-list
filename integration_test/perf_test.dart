import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:smart_quiz_todo/main.dart';

// 실기기 측정:
//   flutter drive --profile --driver=test_driver/perf_driver.dart --target=integration_test/perf_test.dart
// 결과: build/quiz_flip_perf.timeline_summary.json
// 기준(60 FPS): 프레임 build·raster 90퍼센타일 < 16ms. 기준 검사를 끄려면 --dart-define=PERF_ASSERT=false
const _assertBudget = bool.fromEnvironment('PERF_ASSERT', defaultValue: true);

String _bankJson(int n) => jsonEncode({
      'version': '1.1',
      'quiz_bank': [
        for (var i = 0; i < n; i++)
          {
            'source_todo_title': '성능 측정용 묶음',
            'question': '성능 측정용 문제 $i: Access Token을 발급하는 주체는?',
            'options': ['1. Resource Owner', '2. Authorization Server', '3. Client', '4. Resource Server'],
            'answer': '2',
          },
      ],
    });

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('퀴즈 카드 정답 선택 → 뒤집기 → 스와이프 10회 프레임 측정', (tester) async {
    final services = AppServices.create(sinks: [MemoryLogSink()]);
    await services.api.importJson(services.userId, _bankJson(10));
    await tester.pumpWidget(SmartQuizApp(services: services));
    await tester.pumpAndSettle();

    final quizzes = await services.api.todayQuizzes(services.userId);
    expect(quizzes, hasLength(10));

    await binding.watchPerformance(() async {
      for (final item in quizzes) {
        final card = find.byKey(ValueKey(item.quiz.id));
        await tester.tap(find.descendant(of: card, matching: find.text('2. Authorization Server')));
        await tester.pumpAndSettle();
        expect(find.descendant(of: card, matching: find.text('정답!')), findsOneWidget);
        await tester.fling(find.byType(PageView), const Offset(-300, 0), 1500);
        await tester.pumpAndSettle();
      }
    }, reportKey: 'quiz_flip');

    _checkBudget(binding, 'quiz_flip');
  });

  // 비교 기준: 애니메이션 없는 단순 목록 스크롤. 이것도 예산을 넘으면 앱이 아니라 기기·환경의 한계다.
  testWidgets('비교 기준: 할 일 목록 스크롤 프레임 측정', (tester) async {
    final services = AppServices.create(sinks: [MemoryLogSink()]);
    for (var i = 0; i < 40; i++) {
      await services.api.createTodo(services.userId, '할 일 $i', '메모 $i');
    }
    await tester.pumpWidget(SmartQuizApp(services: services));
    await tester.pumpAndSettle();

    await binding.watchPerformance(() async {
      for (var i = 0; i < 5; i++) {
        await tester.fling(find.byType(CustomScrollView), const Offset(0, -600), 2000);
        await tester.pumpAndSettle();
        await tester.fling(find.byType(CustomScrollView), const Offset(0, 600), 2000);
        await tester.pumpAndSettle();
      }
    }, reportKey: 'list_scroll_baseline');

    _checkBudget(binding, 'list_scroll_baseline');
  });
}

void _checkBudget(IntegrationTestWidgetsFlutterBinding binding, String key) {
  final s = (binding.reportData![key] as Map).cast<String, dynamic>();
  debugPrint('PERF_SUMMARY $key ${jsonEncode({
    for (final k in s.keys)
      if (!k.endsWith('_times') && !k.contains('cache')) k: s[k],
  })}');
  if (_assertBudget) {
    expect(s['90th_percentile_frame_build_time_millis'] as num, lessThan(16));
    expect(s['90th_percentile_frame_rasterizer_time_millis'] as num, lessThan(16));
  }
}
