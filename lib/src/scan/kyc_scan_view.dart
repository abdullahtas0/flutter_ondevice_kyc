import 'dart:async';
import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../camera/camera_frame.dart';
import '../pipeline/frame_convert.dart';
import '../pipeline/quad.dart';
import '../pipeline/scanner.dart';
import '../result/kyc_capture.dart';
import '../result/scan_decision.dart';
import 'guide.dart';

/// Live back-camera scan. The host supplies a configured [KycScanner].
///
/// Model files stay in the host app. This widget opens the camera, locks
/// focus on the MRZ band, and calls [onLocked] when a checksum passes.
class KycScanView extends StatefulWidget {
  const KycScanView({
    required this.scanner,
    this.onLocked,
    this.onDecision,
    this.rejectText = rejectLabel,
    this.idleHint = 'Fit the card in the frame. The three lines mark the MRZ.',
    this.focusingHint = 'Focusing on the MRZ lines.',
    this.lockedHint = 'Checksum matched.',
    this.cameraMissingHint = 'Camera is unavailable.',
    super.key,
  });

  final KycScanner scanner;
  final ValueChanged<KycCapture>? onLocked;
  final ValueChanged<ScanDecision>? onDecision;
  final String Function(RejectReason reason) rejectText;
  final String idleHint;
  final String focusingHint;
  final String lockedHint;
  final String cameraMissingHint;

  @override
  State<KycScanView> createState() => _KycScanViewState();
}

class _KycScanViewState extends State<KycScanView> {
  CameraController? _camera;
  var _busy = false;
  var _focusing = false;
  var _started = false;
  ScanDecision? _decision;
  String? _note;
  Size _viewSize = Size.zero;
  DateTime? _holdLockUntil;
  var _softMisses = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_start());
  }

  @override
  void dispose() {
    final camera = _camera;
    _camera = null;
    if (camera != null) {
      unawaited(_disposeCamera(camera));
    }
    super.dispose();
  }

  Future<void> _start() async {
    try {
      final cameras = await availableCameras();
      if (!mounted) return;
      if (cameras.isEmpty) {
        setState(() => _note = widget.cameraMissingHint);
        return;
      }
      final description = cameras.firstWhere(
        (camera) => camera.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );
      final controller = CameraController(
        description,
        ResolutionPreset.high,
        enableAudio: false,
        imageFormatGroup: defaultTargetPlatform == TargetPlatform.android
            ? ImageFormatGroup.yuv420
            : ImageFormatGroup.bgra8888,
      );
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      try {
        await controller.lockCaptureOrientation(DeviceOrientation.portraitUp);
      } on Object {
        // The preview still works when the sensor rejects the lock.
      }
      await controller.startImageStream(_onCameraImage);
      if (!mounted) {
        await _disposeCamera(controller);
        return;
      }
      setState(() {
        _camera = controller;
        _started = true;
        _note = null;
      });
      unawaited(_focusGuide());
    } on Object {
      if (mounted) setState(() => _note = widget.cameraMissingHint);
    }
  }

  Future<void> _disposeCamera(CameraController camera) async {
    if (camera.value.isStreamingImages) {
      await camera.stopImageStream();
    }
    await camera.dispose();
  }

  void _onCameraImage(CameraImage image) {
    if (_busy || _camera == null) return;
    final camera = _camera!;
    final turns = analysisTurns(
      bufferWidth: image.width,
      bufferHeight: image.height,
      sensorOrientation: camera.description.sensorOrientation,
    );
    final oriented = turns.isOdd
        ? Size(image.height.toDouble(), image.width.toDouble())
        : Size(image.width.toDouble(), image.height.toDouble());
    final crop = _viewSize == Size.zero ? null : guideCrop(_viewSize, oriented);
    final frame = rawFromCameraImage(
      image,
      sensorOrientation: camera.description.sensorOrientation,
      crop: crop,
      framed: crop != null,
    );
    if (frame == null) return;
    _busy = true;
    unawaited(_consume(frame));
  }

  Future<void> _consume(RawCameraFrame frame) async {
    try {
      final decision = await widget.scanner.scanFrame(frame);
      if (decision is ScanSkipped || !mounted || _camera == null) return;
      final shown = _stable(decision);
      setState(() => _decision = shown);
      widget.onDecision?.call(shown);
      if (shown is ScanLocked) widget.onLocked?.call(shown.capture);
    } finally {
      _busy = false;
    }
  }

  ScanDecision _stable(ScanDecision decision) {
    final now = DateTime.now();
    if (decision is ScanLocked) {
      _holdLockUntil = now.add(const Duration(milliseconds: 1400));
      _softMisses = 0;
      return decision;
    }
    final held = _holdLockUntil;
    if (held != null && now.isBefore(held) && _decision is ScanLocked) {
      return _decision!;
    }
    if (decision is ScanRejected &&
        decision.reason == RejectReason.unreadable) {
      _softMisses += 1;
      if (_softMisses < 3) return _decision ?? decision;
    } else {
      _softMisses = 0;
    }
    return decision;
  }

  Future<void> _focusGuide() async {
    if (_viewSize == Size.zero) return;
    await _focusAt(mrzFocusPoint(_viewSize));
  }

  Future<void> _focusAt(Offset point) async {
    final camera = _camera;
    if (camera == null || !camera.value.isInitialized || _focusing) return;
    _focusing = true;
    if (mounted) setState(() {});
    try {
      await camera.setFocusMode(FocusMode.auto);
      await camera.setExposureMode(ExposureMode.auto);
      await camera.setFocusPoint(point);
      await camera.setExposurePoint(point);
      await Future<void>.delayed(const Duration(milliseconds: 650));
      if (!mounted || _camera != camera) return;
      try {
        await camera.setFocusMode(FocusMode.locked);
        await camera.setExposureMode(ExposureMode.locked);
      } on Object {
        // Some sensors only support continuous autofocus.
      }
    } on Object {
      // Focus is optional when the sensor rejects the point.
    } finally {
      _focusing = false;
      if (mounted) setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final decision = _decision;
    final locked = decision is ScanLocked ? decision : null;
    final rejected = decision is ScanRejected ? decision : null;
    final status = _status(locked, rejected);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(child: _stage(locked, rejected)),
        const SizedBox(height: 8),
        Text(status, style: Theme.of(context).textTheme.bodyMedium),
      ],
    );
  }

  Widget _stage(ScanLocked? locked, ScanRejected? rejected) {
    final camera = _camera;
    final live = _started && camera != null && camera.value.isInitialized;
    return LayoutBuilder(
      builder: (context, constraints) {
        final view = Size(constraints.maxWidth, constraints.maxHeight);
        if (_viewSize != view) {
          _viewSize = view;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) unawaited(_focusGuide());
          });
        }
        final guide = idGuideRect(view);
        final scheme = Theme.of(context).colorScheme;
        return ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: ColoredBox(
            color: Colors.black,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapUp: live
                  ? (details) {
                      final box = context.findRenderObject() as RenderBox?;
                      if (box == null) return;
                      final local = box.globalToLocal(details.globalPosition);
                      unawaited(
                        _focusAt(
                          Offset(
                            (local.dx / view.width).clamp(0.08, 0.92),
                            (local.dy / view.height).clamp(0.08, 0.92),
                          ),
                        ),
                      );
                    }
                  : null,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (live)
                    _LivePreview(controller: camera),
                  CustomPaint(
                    painter: _GuidePainter(
                      guide: guide,
                      locked: locked != null,
                      quad: locked?.quad ?? rejected?.quad,
                      source: _sourceSize(locked, rejected),
                      dim: live,
                      ink: scheme.onSurface,
                      accent: scheme.primary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Size _sourceSize(ScanLocked? locked, ScanRejected? rejected) {
    final width = locked?.sourceWidth ?? rejected?.sourceWidth ?? 0;
    final height = locked?.sourceHeight ?? rejected?.sourceHeight ?? 0;
    if (width <= 0 || height <= 0) return Size.zero;
    return Size(width.toDouble(), height.toDouble());
  }

  String _status(ScanLocked? locked, ScanRejected? rejected) {
    if (_focusing && locked == null) return widget.focusingHint;
    if (locked != null) return widget.lockedHint;
    if (rejected != null) return widget.rejectText(rejected.reason);
    if (_note != null) return _note!;
    return widget.idleHint;
  }
}

class _LivePreview extends StatelessWidget {
  const _LivePreview({required this.controller});

  final CameraController controller;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final displayed = previewCoverSize(
          viewWidth: constraints.maxWidth,
          viewHeight: constraints.maxHeight,
          cameraAspectRatio: controller.value.aspectRatio,
        );
        return ClipRect(
          child: OverflowBox(
            alignment: Alignment.center,
            minWidth: displayed.width,
            maxWidth: displayed.width,
            minHeight: displayed.height,
            maxHeight: displayed.height,
            child: SizedBox(
              width: displayed.width,
              height: displayed.height,
              child: CameraPreview(controller),
            ),
          ),
        );
      },
    );
  }
}

class _GuidePainter extends CustomPainter {
  _GuidePainter({
    required this.guide,
    required this.locked,
    required this.quad,
    required this.source,
    required this.dim,
    required this.ink,
    required this.accent,
  });

  final Rect guide;
  final bool locked;
  final Quad? quad;
  final Size source;
  final bool dim;
  final Color ink;
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    if (dim) {
      final shade = Path()
        ..addRect(Offset.zero & size)
        ..addRRect(RRect.fromRectAndRadius(guide, const Radius.circular(12)))
        ..fillType = PathFillType.evenOdd;
      canvas.drawPath(shade, Paint()..color = const Color(0xB3000000));
    }
    final color = locked ? accent : ink;
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;
    _brackets(canvas, guide, stroke);
    _mrzLane(canvas, guide, color);
    final found = quad;
    if (found != null &&
        source.width > 0 &&
        source.height > 0 &&
        _tracksCard(found)) {
      final paint = Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5;
      canvas.drawPath(
        Path()
          ..moveTo(_x(found.tl), _y(found.tl))
          ..lineTo(_x(found.tr), _y(found.tr))
          ..lineTo(_x(found.br), _y(found.br))
          ..lineTo(_x(found.bl), _y(found.bl))
          ..close(),
        paint,
      );
    }
  }

  bool _tracksCard(Quad quad) {
    const edge = 8.0;
    return quad.tl.x > edge ||
        quad.tl.y > edge ||
        quad.br.x < source.width - edge ||
        quad.br.y < source.height - edge;
  }

  void _mrzLane(Canvas canvas, Rect guide, Color color) {
    final top = guide.top + guide.height * 0.64;
    final lane = Rect.fromLTRB(
      guide.left + 10,
      top,
      guide.right - 10,
      guide.bottom - 8,
    );
    final paint = Paint()
      ..color = color.withValues(alpha: 0.9)
      ..strokeWidth = 1.2
      ..style = PaintingStyle.stroke;
    canvas.drawRRect(
      RRect.fromRectAndRadius(lane, const Radius.circular(6)),
      paint,
    );
    for (final fraction in const [0.33, 0.66]) {
      final y = lane.top + lane.height * fraction;
      canvas.drawLine(
        Offset(lane.left + 8, y),
        Offset(lane.right - 8, y),
        paint,
      );
    }
  }

  double _x(Point2 point) => guide.left + point.x / source.width * guide.width;

  double _y(Point2 point) => guide.top + point.y / source.height * guide.height;

  void _brackets(Canvas canvas, Rect rect, Paint paint) {
    final length = math.min(22.0, rect.shortestSide * 0.12);
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(12)),
      paint..strokeWidth = 1.2,
    );
    paint.strokeWidth = 3;
    void corner(Offset start, Offset via, Offset end) {
      canvas.drawLine(start, via, paint);
      canvas.drawLine(via, end, paint);
    }

    corner(
      Offset(rect.left, rect.top + length),
      rect.topLeft,
      Offset(rect.left + length, rect.top),
    );
    corner(
      Offset(rect.right - length, rect.top),
      rect.topRight,
      Offset(rect.right, rect.top + length),
    );
    corner(
      Offset(rect.right, rect.bottom - length),
      rect.bottomRight,
      Offset(rect.right - length, rect.bottom),
    );
    corner(
      Offset(rect.left + length, rect.bottom),
      rect.bottomLeft,
      Offset(rect.left, rect.bottom - length),
    );
  }

  @override
  bool shouldRepaint(covariant _GuidePainter oldDelegate) {
    return oldDelegate.guide != guide ||
        oldDelegate.locked != locked ||
        oldDelegate.quad != quad ||
        oldDelegate.source != source ||
        oldDelegate.dim != dim;
  }
}
