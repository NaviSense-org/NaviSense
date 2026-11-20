import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_image_labeling/google_mlkit_image_labeling.dart';
import 'package:google_mlkit_object_detection/google_mlkit_object_detection.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:navisense/core/errors/navi_failure.dart';
import 'package:navisense/core/utils/clock.dart';
import 'package:navisense/core/utils/navi_log.dart';
import 'package:navisense/features/mlkit_perception/models/spatial_scene_summary.dart';
import 'package:navisense/features/mlkit_perception/spatial_math.dart';

/// Abstracts ML Kit detectors behind a minimal seam for deterministic testing.
abstract interface class PerceptionDetectors {
  /// Runs object detection on [inputImage].
  Future<List<DetectedObject>> detectObjects(InputImage inputImage);

  /// Runs image labeling on [inputImage].
  Future<List<ImageLabel>> labelImage(InputImage inputImage);

  /// Runs Latin text recognition on [inputImage].
  Future<RecognizedText> recognizeText(InputImage inputImage);

  /// Releases all underlying native ML Kit detector resources.
  Future<void> close();
}

/// Production [PerceptionDetectors] holding exactly one instance of each ML Kit
/// detector for the app lifetime (`4-code-standards.md` §4.5.8).
final class MlKitPerceptionDetectors implements PerceptionDetectors {
  /// Creates the three Stage 0 ML Kit detectors once.
  MlKitPerceptionDetectors()
      : _objectDetector = ObjectDetector(
          options: ObjectDetectorOptions(
            mode: DetectionMode.stream,
            classifyObjects: true,
            multipleObjects: true,
          ),
        ),
        _imageLabeler = ImageLabeler(
          options: ImageLabelerOptions(confidenceThreshold: 0.65),
        ),
        _textRecognizer = TextRecognizer(script: TextRecognitionScript.latin);

  final ObjectDetector _objectDetector;
  final ImageLabeler _imageLabeler;
  final TextRecognizer _textRecognizer;

  @override
  Future<List<DetectedObject>> detectObjects(InputImage inputImage) =>
      _objectDetector.processImage(inputImage);

  @override
  Future<List<ImageLabel>> labelImage(InputImage inputImage) =>
      _imageLabeler.processImage(inputImage);

  @override
  Future<RecognizedText> recognizeText(InputImage inputImage) =>
      _textRecognizer.processImage(inputImage);

  @override
  Future<void> close() async {
    await _objectDetector.close();
    await _imageLabeler.close();
    await _textRecognizer.close();
  }
}

/// Stage 0 Google ML Kit perception service.
///
/// Runs object detection, image labeling, and OCR **sequentially** on each
/// frame to prevent native heap spikes on 3 GB RAM Android Go devices.
final class MlKitPerceptionService {
  /// Creates an [MlKitPerceptionService].
  MlKitPerceptionService({
    PerceptionDetectors? detectors,
    Clock? clock,
    Duration timeout = const Duration(milliseconds: 1000),
  })  : _detectors = detectors ?? MlKitPerceptionDetectors(),
        _clock = clock ?? const SystemClock(),
        _timeout = timeout;

  /// Minimum label confidence accepted into [SpatialSceneSummary].
  static const double minConfidence = 0.65;

  /// Minimum normalized OCR block area ratio relative to frame size.
  static const double minTextAreaRatio = 0.005;

  /// Maximum number of entities retained in a summary.
  static const int maxEntities = 5;

  /// Maximum number of OCR text snippets retained in a summary.
  static const int maxTexts = 3;

  /// Maximum character length per OCR snippet.
  static const int maxTextLength = 40;

  static const Set<String> _coarseLabels = <String>{
    'home good',
    'fashion good',
    'food',
    'place',
    'plant',
    'unknown',
    'object',
  };

  static const Map<DeviceOrientation, int> _orientations =
      <DeviceOrientation, int>{
    DeviceOrientation.portraitUp: 0,
    DeviceOrientation.landscapeLeft: 90,
    DeviceOrientation.portraitDown: 180,
    DeviceOrientation.landscapeRight: 270,
  };

  final PerceptionDetectors _detectors;
  final Clock _clock;
  final Duration _timeout;

  /// Builds an [InputImage] and rotation-corrected frame [Size] from an NV21
  /// [CameraImage] without retaining the [CameraImage] buffer.
  static ({InputImage image, Size frameSize}) inputFromNv21CameraImage({
    required CameraImage cameraImage,
    required int sensorOrientation,
    required DeviceOrientation deviceOrientation,
  }) {
    final buffer = WriteBuffer();
    for (final plane in cameraImage.planes) {
      buffer.putUint8List(plane.bytes);
    }
    final bytes = buffer.done().buffer.asUint8List();

    final rotationDegrees = _computeRotationDegrees(
      sensorOrientation: sensorOrientation,
      deviceOrientation: deviceOrientation,
    );
    final rotation = InputImageRotationValue.fromRawValue(rotationDegrees) ??
        InputImageRotation.rotation0deg;

    final rawW = cameraImage.width.toDouble();
    final rawH = cameraImage.height.toDouble();
    final isSwapped = rotationDegrees == 90 || rotationDegrees == 270;
    final frameSize = isSwapped ? Size(rawH, rawW) : Size(rawW, rawH);

    final image = InputImage.fromBytes(
      bytes: bytes,
      metadata: InputImageMetadata(
        size: Size(rawW, rawH),
        rotation: rotation,
        format: InputImageFormat.nv21,
        bytesPerRow: cameraImage.planes.first.bytesPerRow,
      ),
    );
    return (image: image, frameSize: frameSize);
  }

  /// Creates an [InputImage] from a transient snapshot JPEG path on disk.
  static InputImage inputFromFilePath(String path) =>
      InputImage.fromFilePath(path);

  /// Reads JPEG width/height from SOF markers in [jpegBytes] without full
  /// pixel decoding, falling back to [fallback] if unavailable.
  static Size readJpegDimensions(
    Uint8List jpegBytes, {
    Size fallback = const Size(768, 768),
  }) {
    if (jpegBytes.length < 4 || jpegBytes[0] != 0xFF || jpegBytes[1] != 0xD8) {
      return fallback;
    }
    var i = 2;
    while (i + 8 < jpegBytes.length) {
      if (jpegBytes[i] != 0xFF) {
        i++;
        continue;
      }
      final marker = jpegBytes[i + 1];
      if (marker == 0xD9 || marker == 0xDA) break;
      if (marker == 0x00 ||
          marker == 0x01 ||
          (marker >= 0xD0 && marker <= 0xD7)) {
        i += 2;
        continue;
      }
      final length = (jpegBytes[i + 2] << 8) | jpegBytes[i + 3];
      if (length < 2 || i + 2 + length > jpegBytes.length) break;
      final isSof = (marker >= 0xC0 && marker <= 0xC3) ||
          (marker >= 0xC5 && marker <= 0xC7) ||
          (marker >= 0xC9 && marker <= 0xCB) ||
          (marker >= 0xCD && marker <= 0xCF);
      if (isSof && i + 8 < jpegBytes.length) {
        final height = (jpegBytes[i + 5] << 8) | jpegBytes[i + 6];
        final width = (jpegBytes[i + 7] << 8) | jpegBytes[i + 8];
        if (width > 0 && height > 0) {
          return Size(width.toDouble(), height.toDouble());
        }
      }
      i += 2 + length;
    }
    return fallback;
  }

  /// Runs Stage 0 sequential detection + fusion + OCR filtering within [_timeout].
  Future<SpatialSceneSummary> perceive(
    InputImage inputImage, {
    required Size frameSize,
  }) async {
    final startedMs = _clock.nowMs();
    try {
      return await _runSequential(
        inputImage,
        frameSize: frameSize,
        startedMs: startedMs,
      ).timeout(_timeout);
    } on TimeoutException {
      throw TimeoutFailure(
        'ML Kit perception > ${_timeout.inMilliseconds}ms',
      );
    } on PlatformException catch (e) {
      throw PerceptionFailure(e.message ?? 'ML Kit perception platform error');
    } catch (e) {
      if (e is NaviFailure) rethrow;
      throw PerceptionFailure('ML Kit perception failed: $e');
    }
  }

  Future<SpatialSceneSummary> _runSequential(
    InputImage inputImage, {
    required Size frameSize,
    required int startedMs,
  }) async {
    // WHY: Sequential inference avoids parallel native heap spikes on 3 GB RAM.
    final detectedObjects = await _detectors.detectObjects(inputImage);
    final imageLabels = await _detectors.labelImage(inputImage);
    final recognizedText = await _detectors.recognizeText(inputImage);

    final entities = _fuseObjectsAndLabels(
      detectedObjects: detectedObjects,
      imageLabels: imageLabels,
      frameSize: frameSize,
    );
    final texts = _filterTexts(
      blocks: recognizedText.blocks,
      frameSize: frameSize,
    );

    final elapsed = (_clock.nowMs() - startedMs).clamp(0, 60000);
    if (!const bool.fromEnvironment('dart.vm.product')) {
      log(
        'stage0 processingMs=$elapsed entities=${entities.length} '
        'texts=${texts.length}',
        name: 'navisense.mlkit',
      );
    }

    return SpatialSceneSummary(
      entities: entities,
      texts: texts,
      capturedAt: _clock.now(),
      processingMs: elapsed,
    );
  }

  List<SpatialEntity> _fuseObjectsAndLabels({
    required List<DetectedObject> detectedObjects,
    required List<ImageLabel> imageLabels,
    required Size frameSize,
  }) {
    final validImageLabels = imageLabels
        .where(
          (ImageLabel l) =>
              l.confidence >= minConfidence && l.label.trim().isNotEmpty,
        )
        .toList(growable: false)
      ..sort(
        (ImageLabel a, ImageLabel b) => b.confidence.compareTo(a.confidence),
      );

    final usedLabelTexts = <String>{};
    final entities = <SpatialEntity>[];

    for (final obj in detectedObjects) {
      final direction = directionFor(obj.boundingBox, frameSize);
      final distance = distanceFor(obj.boundingBox, frameSize);
      final kind = isObstacle(direction, distance)
          ? EntityKind.obstacle
          : EntityKind.object;

      final resolved = _resolveObjectLabel(
        obj: obj,
        candidateLabels: validImageLabels,
        usedLabels: usedLabelTexts,
      );

      entities.add(
        SpatialEntity(
          kind: kind,
          label: resolved.label,
          direction: direction,
          distance: distance,
          confidence: resolved.confidence,
        ),
      );
    }

    entities.sort((SpatialEntity a, SpatialEntity b) {
      final kindCmp = a.kind.index.compareTo(b.kind.index);
      if (kindCmp != 0) return kindCmp;
      final distCmp = a.distance.index.compareTo(b.distance.index);
      if (distCmp != 0) return distCmp;
      return b.confidence.compareTo(a.confidence);
    });

    return entities.take(maxEntities).toList(growable: false);
  }

  ({String label, double confidence}) _resolveObjectLabel({
    required DetectedObject obj,
    required List<ImageLabel> candidateLabels,
    required Set<String> usedLabels,
  }) {
    final validObjectLabels = obj.labels
        .where(
          (Label l) =>
              l.confidence >= minConfidence && l.text.trim().isNotEmpty,
        )
        .toList(growable: false)
      ..sort((Label a, Label b) => b.confidence.compareTo(a.confidence));

    final bestSpecific = validObjectLabels.cast<Label?>().firstWhere(
          (Label? l) => !_coarseLabels.contains(l!.text.trim().toLowerCase()),
          orElse: () => null,
        );

    if (bestSpecific != null) {
      final clean = bestSpecific.text.trim();
      usedLabels.add(clean.toLowerCase());
      return (label: clean, confidence: bestSpecific.confidence);
    }

    // Fallback to highest-confidence unused ImageLabeler label (>= 0.65).
    for (final imgLabel in candidateLabels) {
      final clean = imgLabel.label.trim();
      final key = clean.toLowerCase();
      if (!_coarseLabels.contains(key) && !usedLabels.contains(key)) {
        usedLabels.add(key);
        return (label: clean, confidence: imgLabel.confidence);
      }
    }

    final fallbackConfidence = validObjectLabels.isNotEmpty
        ? validObjectLabels.first.confidence
        : minConfidence;
    return (label: 'object', confidence: fallbackConfidence);
  }

  List<String> _filterTexts({
    required List<TextBlock> blocks,
    required Size frameSize,
  }) {
    final frameArea = frameSize.width * frameSize.height;
    if (frameArea <= 0) return const <String>[];

    final candidates = <({double area, String text})>[];
    for (final block in blocks) {
      final box = block.boundingBox;
      final area = box.width.clamp(0.0, double.infinity) *
          box.height.clamp(0.0, double.infinity);
      if (area / frameArea < minTextAreaRatio) continue;

      final normalized = block.text.trim().replaceAll(RegExp(r'\s+'), ' ');
      if (normalized.isEmpty) continue;

      final truncated = normalized.length > maxTextLength
          ? normalized.substring(0, maxTextLength).trimRight()
          : normalized;
      candidates.add((area: area, text: truncated));
    }

    candidates.sort((a, b) => b.area.compareTo(a.area));
    return candidates.take(maxTexts).map((c) => c.text).toList(growable: false);
  }

  static int _computeRotationDegrees({
    required int sensorOrientation,
    required DeviceOrientation deviceOrientation,
  }) {
    final deviceDegrees = _orientations[deviceOrientation] ?? 0;
    return (sensorOrientation - deviceDegrees + 360) % 360;
  }

  /// Releases all ML Kit native detectors.
  Future<void> close() => _detectors.close();
}
