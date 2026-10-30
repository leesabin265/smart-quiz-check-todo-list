# 스마트 퀴즈 체크 투두 리스트

학습 메모와 함께 할 일을 완료하면 메모에서 핵심 개념을 뽑아 복습 퀴즈를 만들고, Leitner 방식의 간격 반복으로 매일 아침 8시에 다시 출제하는 Flutter 앱입니다.

- Flutter 3.x (Material 3), Dart null-safety, `provider` ^6, `CustomPainter`, `dart:math`
- 설계 문서의 단일 모듈 원칙에 맞춰 앱 코드는 모두 `lib/main.dart` 한 파일에 있습니다.
- 백엔드가 아직 없어서 `QuizApi`가 서버 API 계약을 앱 안에서 그대로 구현합니다. HTTP 구현으로 바꿀 때 Controller와 UI는 수정하지 않아도 됩니다.

## 실행 / 테스트

```bash
flutter pub get
```

```bash
flutter analyze
```

```bash
flutter test
```

```bash
flutter emulators --launch <emulator_id>
```

```bash
flutter run
```

60 FPS를 확인하려면 profile 모드로 실행한 뒤 DevTools의 Performance 탭과 "Highlight repaints"를 켜고 보세요.

```bash
flutter run --profile
```

프레임 시간을 숫자로 남기려면 기기를 연결하고 아래를 실행하세요. 결과는 `build/quiz_flip_perf.timeline_summary.json`에 저장되고, 90퍼센타일이 16ms를 넘으면 실패합니다.

```bash
flutter drive --profile --driver=test_driver/perf_driver.dart --target=integration_test/perf_test.dart
```

### 에뮬레이터에서 해볼 시나리오

1. 앱을 켜면 데모 데이터가 들어 있습니다. "HTTP 캐시 헤더 정리"는 어제 완료한 것으로 되어 있어서 오늘의 복습 퀴즈 3개가 상단에 표시됩니다.
2. 보기를 탭하면 정답/오답 색이 표시되고 → 카드가 뒤집히고 → 결과 애니메이션과 Leitner 단계 링이 나타납니다.
3. "OAuth 2.0 프로토콜 개념 공부"를 체크하면 곧바로 완료 처리되고 "퀴즈 생성 중"이 표시됩니다. 0.6초 정도 뒤 "퀴즈 3개"로 바뀝니다.
4. 우측 상단 메뉴에서 `[디버그] 하루 뒤로 이동`을 누르면 다음 날 08:00 복습 분이 출제됩니다. 맞히면 Lv.2(2일 뒤)로 올라가고, 틀리면 Lv.1(내일)로 초기화됩니다.
5. `[디버그] LLM 장애`를 켠 상태에서 투두를 완료하면 재시도 후 "생성 실패"가 표시되고 투두 완료 상태는 그대로 유지됩니다. 장애를 끄고 "재시도"를 누르면 복구됩니다.
6. 메뉴에서 `퀴즈 내보내기/가져오기`를 쓰면 명세의 v1.1 JSON 형식으로 내보내고 가져올 수 있습니다.

로그는 `{"ts","level","event",...}` 형식의 JSON 한 줄로 `flutter run` 콘솔에 찍힙니다. 이벤트 종류는 `quiz.generated`, `srs.promoted`, `llm.timeout`, `quiz.parse_failed` 등입니다.

## 모듈 구성 (`lib/main.dart` 안의 섹션)

| 섹션 | 역할 |
|---|---|
| `AppLogger` / `LogSink` | INFO·WARN·ERROR 구조화 로그. Sentry/CloudWatch는 Sink만 추가하면 됩니다. 메모 원문은 로그에 남기지 않습니다. |
| `AppClock` | 시간 주입. 디버그용 "시간 이동"과 테스트에 사용합니다. |
| `LeitnerScheduler` | 맞힐 때마다 간격 2배: 1·2·4·8·16·31일(최대), 매번 08:00에 예약. 오답이면 1일(내일)로 초기화. |
| `PromptGuard` | 메모 1,500자 상한(비용 방어), 제어문자 제거, prompt injection 구문과 구분자 탈출 차단, 토큰 추정. |
| `QuizResponseParser` | LLM 응답 JSON 스키마 검증. 위반 시 `FormatException`과 ERROR 로그가 남고 재시도합니다. |
| `HeuristicQuizGenerator` | 오프라인용 대체 생성기입니다. "개념: 설명", "개념은 설명이다" 형태의 문장에서 객관식·OX·빈칸 문제를 만듭니다. |
| `ChaosQuizGenerator` | LLM 장애와 깨진 JSON을 재현합니다. |
| `SlidingWindowRateLimiter` | 사용자별 분당 3회, 일 30회 생성 한도. |
| `QuizJobQueue` | BullMQ 역할. 동시 2개, 5초 timeout, 지수 백오프 4회 재시도, timeout 이후 늦게 도착한 결과는 버립니다. |
| `QuizApi` | `PATCH /todos/{id}/complete`, `GET /quizzes/today`, `POST /quizzes/submit`, hide/report, export/import. 모든 쿼리는 `userId`로 범위가 제한되고(RLS 흉내), 남의 리소스는 404로 응답합니다. |
| `TodoController` / `ReviewController` | `ChangeNotifier`. 완료 토글은 optimistic으로 처리하고, 답 선택은 로컬에서 즉시 채점하는 동시에 서버에 제출합니다. |
| UI | `SmartReviewWidget`(PageView, `onQuizWidgetSlide`), `QuizFlipCard`(`onAnswerSelect`), `TodoTile`, `Selector`/`context.select`로 행 단위 리빌드. |
| Painters | `LeitnerRingPainter`, `ResultBurstPainter`(`repaint: Animation`으로 build 없이 paint만 반복). 둘 다 입력이 바뀔 때만 `shouldRepaint`가 true입니다. |

### 파일을 나눌 때 권장 구조

```
lib/
  main.dart                 # composition root
  core/        logging.dart, clock.dart, errors.dart
  domain/      models.dart, leitner_scheduler.dart
  ai/          prompt_guard.dart, quiz_response_parser.dart, generators/
  data/        quiz_api.dart (interface), http_quiz_api.dart, local_quiz_api.dart
  jobs/        quiz_job_queue.dart        # 서버 이전 시 BullMQ worker로 이동
  state/       todo_controller.dart, review_controller.dart
  ui/          home_page.dart, widgets/, painters/
server/        # API Gateway + AI Worker (VPC 내부) — 이 저장소 범위 밖
```

## 설계 문서 피드백 (누락 / 상충)

1. **복습 주기가 모호합니다.** 시나리오 3의 "1·3·7일 뒤"와 시나리오 4의 "맞히면 14일 뒤"가 고정 일정인지 Leitner 단계인지 정해져 있지 않습니다. 여기서는 **마지막으로 푼 날짜 기준**으로, 맞힐 때마다 간격이 2배가 되는 `[1,2,4,8,16,31]`일(최대 31일)로 구현했습니다. 틀리면 1일(내일)로 돌아갑니다.
2. **SLO "5초 이내"가 재시도 정책과 충돌합니다.** LLM 평균 응답이 2~4초인데 큐 대기와 재시도까지 하면 5초를 넘을 수밖에 없습니다. "첫 시도 p95 < 5s"로 고쳐 쓰는 것을 제안합니다. M2 시연의 "3초 뒤"와도 수치가 다릅니다. 구현에서는 시도마다 5초 timeout을 걸고, `quiz.generated` 로그에 `slo_5s_met`를 기록합니다.
3. **단일 `main.dart`로는 서버 측 요구사항을 충족할 수 없습니다.** AES-256 메모 암호화, Postgres RLS, VPC 방화벽, BullMQ는 서버에서 해야 합니다. 클라이언트가 키를 갖고 암호화하는 척하는 코드는 오히려 해롭기 때문에 넣지 않았습니다. 대신 API 계약과 소유자 스코핑만 구현했습니다.
4. **푸시 알림 의존성이 명세에 빠져 있습니다.** 5절 라이브러리에 `provider`만 있어서 FCM(`firebase_messaging`, `flutter_local_notifications`)을 쓸 수 없습니다. `ReviewNotifier` 인터페이스와 로그 구현만 두었고, 알림은 사용자·날짜당 1회로 묶었습니다. 사용자 timezone도 서버에 저장해야 합니다.
5. **`POST /v1/quizzes/submit`의 요청·응답 본문이 정의되어 있지 않습니다.** 응답은 `SubmitResult {correct, correctIndex, previousBox, newBox, intervalDays, nextReviewAt}`로 제안합니다.
6. **Export 포맷 v1.1에 문제가 있습니다.** (a) 복습 상태(box, next_review_at)가 없어서 가져오면 진도가 초기화됩니다. (b) `"1. ..."`처럼 번호가 보기 문자열에 섞여 있고, `answer`가 문자열 인덱스라서 깨지기 쉽습니다. v1.2에서는 `options: [str]`, `answer_index: int`, `review_state`를 쓰는 것을 제안합니다. 현재 구현은 v1.1을 그대로 지원하고 번호 접두사를 제거합니다.
7. **정답을 클라이언트에서 채점합니다.** 60 FPS로 즉시 반응하려면 클라이언트가 답을 알아야 합니다. 자기 학습용이라 괜찮지만, 스케줄 변경은 서버 응답을 기준으로 합니다.
8. **신뢰 경계가 하나 더 있습니다.** 메모(대외비 코드가 들어갈 수 있음)는 DB 암호화와 별개로 **외부 LLM 제공자에게 평문으로** 전송됩니다. Zero Data Retention 계약, PII/비밀값 마스킹, 사용자 동의 고지가 필요합니다. Sentry로 가는 로그에도 메모가 들어가면 안 됩니다(구현에서는 길이와 해시만 기록).
9. **API Abuse 대책에 구체적인 수치가 없습니다.** 구현에서는 분당 3회·일 30회 한도, 같은 메모로 다시 완료하면 LLM을 다시 부르지 않는 처리(메모 해시), 입력 1,500자 상한을 두었습니다. Gateway에서도 같은 정책을 다시 적용해야 합니다.
10. **목표 "장기 기억 전환율 4배"를 측정할 수 없습니다.** 예를 들어 "7일·30일 복습 정답률"처럼 지표와 기준선을 정해야 합니다.
11. **로그 영구 보존 범위를 정해야 합니다.** 정·오답 이력은 탈퇴 시까지 보존하되, 탈퇴하면 파기하는 절차와 메모 원문을 로그에서 제외하는 규칙을 문서에 명시해야 합니다.

## 검증

테스트 48개, coverage 96.6%, 프레임 성능 측정, 브라우저 E2E 결과와 검증하지 못한 항목은 [`docs/VERIFICATION.md`](docs/VERIFICATION.md)에 정리했습니다.

## 현재 한계

- LLM은 휴리스틱 생성기로 대신하고 있습니다. 실제 연동은 서버 Worker에서 `QuizGenerator` 인터페이스를 구현하면 됩니다.
- 저장소가 in-memory라서 앱을 재시작하면 데이터가 초기화됩니다(백엔드 연동 전 단계).
- Android 플랫폼만 생성되어 있습니다(`targetSdk`는 Flutter 기본값).
