import 'dart:io';
import 'dart:typed_data';

import 'package:firebase_ai/firebase_ai.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:navisense/core/config/remote_config_service.dart';
import 'package:navisense/core/errors/navi_failure.dart';
import 'package:navisense/core/utils/clock.dart';
import 'package:navisense/features/ai_orchestrator/cloud_reasoning_service.dart';
import 'package:navisense/features/mlkit_perception/models/spatial_scene_summary.dart';

final class _MockTemplateReasoningClient extends Mock
    implements TemplateReasoningClient {}

final class _FakeClock implements Clock {
  int _nowMs = 1000;

  void advance(int deltaMs) => _nowMs += deltaMs;

  @override
  int nowMs() => _nowMs;

  @override
  DateTime now() => DateTime.fromMillisecondsSinceEpoch(_nowMs);
}

void main() {
  late _MockTemplateReasoningClient mockClient;
  late _FakeClock clock;
  final jpeg = Uint8List.fromList(<int>[0xFF, 0xD8, 0xFF]);
  final summary = SpatialSceneSummary(
    entities: const <SpatialEntity>[
      SpatialEntity(
        kind: EntityKind.obstacle,
        label: 'Chair',
        direction: Direction.center,
        distance: Distance.veryClose,
        confidence: 0.88,
      ),
    ],
    texts: const <String>['EXIT'],
    capturedAt: DateTime.utc(2026, 11, 18),
    processingMs: 32,
  );

  setUp(() {
    mockClient = _MockTemplateReasoningClient();
    clock = _FakeClock();
  });

  CloudReasoningService makeService({
    String Function()? templateReader,
    Duration timeout = const Duration(milliseconds: 1500),
  }) {
    return CloudReasoningService(
      client: mockClient,
      templateIdReader: templateReader ?? () => 'navisense_nav_prompt_v1',
      timeoutReader: () => timeout,
      clock: clock,
    );
  }

  group('CloudReasoningService', () {
    test('returns CloudReasoningResult on valid response', () async {
      when(
        () => mockClient.generateContent(
          'navisense_nav_prompt_v1',
          inputs: any(named: 'inputs'),
        ),
      ).thenAnswer((_) async {
        clock.advance(420);
        return 'Chair very close ahead. Exit sign on left.';
      });

      final result = await makeService().reason(jpeg: jpeg, summary: summary);

      expect(result.text, 'Chair very close ahead. Exit sign on left.');
      expect(result.templateId, 'navisense_nav_prompt_v1');
      expect(result.latencyMs, 420);
    });

    test('throws TimeoutFailure when response exceeds timeout budget',
        () async {
      final service = makeService(timeout: const Duration(milliseconds: 50));
      when(
        () => mockClient.generateContent(
          any(),
          inputs: any(named: 'inputs'),
        ),
      ).thenAnswer((_) async {
        await Future<void>.delayed(const Duration(milliseconds: 120));
        return 'Too late';
      });

      await expectLater(
        service.reason(jpeg: jpeg, summary: summary),
        throwsA(isA<TimeoutFailure>()),
      );
    });

    test('maps SocketException to NetworkFailure', () async {
      when(
        () => mockClient.generateContent(
          any(),
          inputs: any(named: 'inputs'),
        ),
      ).thenThrow(const SocketException('No route to host'));

      await expectLater(
        makeService().reason(jpeg: jpeg, summary: summary),
        throwsA(isA<NetworkFailure>()),
      );
    });

    test('maps FirebaseException(permission-denied) to FirebaseAiFailure',
        () async {
      when(
        () => mockClient.generateContent(
          any(),
          inputs: any(named: 'inputs'),
        ),
      ).thenThrow(
        FirebaseException(
          plugin: 'firebase_ai',
          code: 'permission-denied',
          message: 'App Check token invalid',
        ),
      );

      await expectLater(
        makeService().reason(jpeg: jpeg, summary: summary),
        throwsA(
          isA<FirebaseAiFailure>().having(
            (FirebaseAiFailure f) => f.code,
            'code',
            'permission-denied',
          ),
        ),
      );
    });

    test('maps FirebaseAIException to FirebaseAiFailure', () async {
      when(
        () => mockClient.generateContent(
          any(),
          inputs: any(named: 'inputs'),
        ),
      ).thenThrow(FirebaseAIException('Quota exceeded'));

      await expectLater(
        makeService().reason(jpeg: jpeg, summary: summary),
        throwsA(isA<FirebaseAiFailure>()),
      );
    });

    test('maps empty or null response text to FirebaseAiFailure(code: empty)',
        () async {
      when(
        () => mockClient.generateContent(
          any(),
          inputs: any(named: 'inputs'),
        ),
      ).thenAnswer((_) async => '   ');

      await expectLater(
        makeService().reason(jpeg: jpeg, summary: summary),
        throwsA(
          isA<FirebaseAiFailure>().having(
            (FirebaseAiFailure f) => f.code,
            'code',
            'empty',
          ),
        ),
      );
    });

    test('tracks live promptTemplateProvider switches immediately', () async {
      final rcService = RemoteConfigService();
      final container = ProviderContainer(
        overrides: [
          remoteConfigServiceProvider.overrideWithValue(rcService),
          templateReasoningClientProvider.overrideWithValue(mockClient),
        ],
      );
      addTearDown(container.dispose);

      when(
        () => mockClient.generateContent(
          any(),
          inputs: any(named: 'inputs'),
        ),
      ).thenAnswer((_) async => 'Guidance text.');

      final service = container.read(cloudReasoningServiceProvider);

      final first = await service.reason(jpeg: jpeg, summary: summary);
      expect(first.templateId, 'navisense_nav_prompt_v1');

      container
          .read(promptTemplateProvider.notifier)
          .set('navisense_nav_prompt_v2');

      final second = await service.reason(jpeg: jpeg, summary: summary);
      expect(second.templateId, 'navisense_nav_prompt_v2');
      verifyInOrder(<Future<String?> Function()>[
        () => mockClient.generateContent(
              'navisense_nav_prompt_v1',
              inputs: any(named: 'inputs'),
            ),
        () => mockClient.generateContent(
              'navisense_nav_prompt_v2',
              inputs: any(named: 'inputs'),
            ),
      ]);
    });
  });
}
