import 'dart:async';
import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_ondevice_kyc/flutter_ondevice_kyc.dart';

import 'camera_frame.dart';
import 'gallery_image.dart';
import 'result_panel.dart';
import 'scanner_factory.dart';
import 'theme.dart';
import 'viewfinder.dart';

class ScanPage extends StatefulWidget {
  const ScanPage({required this.opened, super.key});

  final OpenedScanner opened;

  @override
  State<ScanPage> createState() => _ScanPageState();
}

class _ScanPageState extends State<ScanPage> {
  CameraController? _camera;
  var _cameraOn = false;
  var _busy = false;
  var _guideOverlay = false;
  ScanDecision? _decision;
  String? _note;
  Size _viewSize = Size.zero;
  DateTime? _holdLockUntil;
  var _softMisses = 0;
  var _focusing = false;

  @override
  void dispose() {
    unawaited(_stopCamera());
    super.dispose();
  }

  Future<void> _toggleCamera() async {
    if (_cameraOn) {
      await _stopCamera();
      if (mounted) setState(() {});
      return;
    }
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        if (mounted) setState(() => _note = 'Kamera bulunamadı');
        return;
      }
      final description = cameras.firstWhere(
        (camera) => camera.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );
      final controller = await _openCamera(description);
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() {
        _camera = controller;
        _cameraOn = true;
        _note = null;
        _guideOverlay = false;
        _decision = null;
      });
      await WidgetsBinding.instance.endOfFrame;
      try {
        await controller.lockCaptureOrientation(DeviceOrientation.portraitUp);
      } on Object {
        // Preview stays usable when the sensor rejects the lock.
      }
      if (!mounted) return;
      await controller.startImageStream(_onCameraImage);
      unawaited(_focusGuide());
    } on Object {
      if (mounted) setState(() => _note = 'Kamera açılamadı');
    }
  }

  Future<CameraController> _openCamera(CameraDescription description) async {
    final group = defaultTargetPlatform == TargetPlatform.android
        ? ImageFormatGroup.yuv420
        : ImageFormatGroup.bgra8888;
    Object? lastError;
    for (final preset in const [
      ResolutionPreset.veryHigh,
      ResolutionPreset.high,
      ResolutionPreset.medium,
    ]) {
      final controller = CameraController(
        description,
        preset,
        enableAudio: false,
        imageFormatGroup: group,
      );
      try {
        await controller.initialize();
        return controller;
      } on Object catch (error) {
        lastError = error;
        await controller.dispose();
      }
    }
    throw lastError ?? StateError('Kamera açılmadı');
  }

  Future<void> _stopCamera() async {
    final camera = _camera;
    _camera = null;
    _cameraOn = false;
    _busy = false;
    if (camera == null) return;
    if (camera.value.isStreamingImages) {
      await camera.stopImageStream();
    }
    await camera.dispose();
  }

  void _onCameraImage(CameraImage image) {
    if (_busy || !_cameraOn) return;
    final camera = _camera;
    if (camera == null) return;
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
      final decision = await widget.opened.scanner.scanFrame(frame);
      if (decision is ScanSkipped || !mounted || !_cameraOn) return;
      setState(() {
        _decision = _stable(decision);
        _guideOverlay = true;
        _note = null;
      });
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
      if (_softMisses < 3) {
        return _decision ?? decision;
      }
    } else {
      _softMisses = 0;
    }
    return decision;
  }

  Future<void> _focus(Offset local, Size view) async {
    final camera = _camera;
    if (camera == null || !camera.value.isInitialized || view == Size.zero) {
      return;
    }
    final point = Offset(
      (local.dx / view.width).clamp(0.08, 0.92),
      (local.dy / view.height).clamp(0.08, 0.92),
    );
    await _focusAt(point);
  }

  Future<void> _focusGuide() async {
    final view = _viewSize;
    if (view == Size.zero) return;
    await _focusAt(mrzFocusPoint(view));
  }

  /// Focus the MRZ band, then lock exposure and focus so the preview stops hunting.
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
      if (!_cameraOn || _camera != camera) return;
      try {
        await camera.setFocusMode(FocusMode.locked);
        await camera.setExposureMode(ExposureMode.locked);
      } on Object {
        // Some sensors only support continuous autofocus.
      }
    } on Object {
      // Tap-to-focus is optional on this sensor.
    } finally {
      _focusing = false;
      if (mounted) setState(() {});
    }
  }

  Future<void> _gallery() async {
    try {
      final image = await rgbFromGallery();
      if (image == null || !mounted) return;
      final decision = await widget.opened.scanner.scanStill(image);
      if (!mounted) return;
      setState(() {
        _decision = decision;
        _guideOverlay = false;
      });
    } on Object {
      if (mounted) setState(() => _note = 'Görsel okunamadı');
    }
  }

  Future<void> _fixtureLock() async {
    final decision = await widget.opened.scanner.scanStill(
      SyntheticCardSpec.image(),
    );
    if (!mounted) return;
    setState(() {
      _decision = decision;
      _guideOverlay = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final decision = _decision;
    final locked = decision is ScanLocked ? decision : null;
    final rejected = decision is ScanRejected ? decision : null;
    final fixtureCaption = widget.opened.fixture && locked != null
        ? 'Örnek checksum. Belgeden okunmadı.'
        : null;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Header(label: widget.opened.label),
          const SizedBox(height: 12),
          Expanded(child: _stage(locked, rejected)),
          const SizedBox(height: 10),
          Text(
            _status(locked, rejected),
            style: TextStyle(
              color: _statusColor(locked, rejected),
              height: 1.35,
            ),
          ),
          if (_note != null) ...[
            const SizedBox(height: 6),
            Text(_note!, style: const TextStyle(color: holdAmber)),
          ],
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton(
                onPressed: _toggleCamera,
                child: Text(_cameraOn ? 'Kamerayı kapat' : 'Kamera'),
              ),
              OutlinedButton(onPressed: _gallery, child: const Text('Galeri')),
              TextButton(
                key: const Key('fixture-button'),
                onPressed: _fixtureLock,
                child: const Text('Fikstür kilidi'),
              ),
            ],
          ),
          if (locked != null) ...[
            const SizedBox(height: 10),
            Flexible(
              child: SingleChildScrollView(
                child: ResultPanel(
                  locked: true,
                  title: 'Kilit',
                  detail: 'Checksum tuttu. ${locked.elapsedMs} ms',
                  rows: captureRows(locked.capture),
                  caption: fixtureCaption,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _stage(ScanLocked? locked, ScanRejected? rejected) {
    final camera = _camera;
    final live = _cameraOn && camera != null && camera.value.isInitialized;
    return LayoutBuilder(
      builder: (context, constraints) {
        final view = Size(constraints.maxWidth, constraints.maxHeight);
        _viewSize = view;
        final guide = idGuideRect(view);
        return ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: DecoratedBox(
            decoration: const BoxDecoration(color: stage),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapUp: live
                  ? (details) => _focus(details.localPosition, view)
                  : null,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (live) _LivePreview(controller: camera),
                  CustomPaint(
                    painter: _GuidePainter(
                      guide: guide,
                      locked: locked != null,
                      quad: _guideOverlay
                          ? locked?.quad ?? rejected?.quad
                          : null,
                      source: _sourceSize(locked, rejected),
                      dim: live,
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
    if (!_cameraOn && locked == null && rejected == null) {
      return 'Kamerayı aç. Kimliğin arkasını yatay tut, MRZ altta kalsın.';
    }
    if (_focusing && locked == null) {
      return 'MRZ satırlarına kilitleniyor.';
    }
    if (locked != null) return 'Checksum tuttu.';
    if (rejected != null) return rejectLabel(rejected.reason);
    return 'Kartı çerçeveye oturt. Alt üç çizgi MRZ satırları.';
  }

  Color _statusColor(ScanLocked? locked, ScanRejected? rejected) {
    if (locked != null) return lockGreen;
    if (rejected != null) return holdAmber;
    return muted;
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: Container(
            key: const Key('mode-chip'),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              border: Border.all(color: line),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(label),
          ),
        ),
        if (label == 'Fikstür') ...[
          const SizedBox(height: 8),
          const Text(
            'Fikstür — model dosyası yok',
            style: TextStyle(color: muted),
          ),
        ],
        if (label == 'Tespit modeli') ...[
          const SizedBox(height: 8),
          const Text(
            'Okuma modeli yok. Kutu çizilir, kilit basılmaz.',
            style: TextStyle(color: muted),
          ),
        ],
      ],
    );
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
        final width = displayed.width;
        final height = displayed.height;
        return ClipRect(
          child: OverflowBox(
            alignment: Alignment.center,
            minWidth: width,
            maxWidth: width,
            minHeight: height,
            maxHeight: height,
            child: SizedBox(
              width: width,
              height: height,
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
  });

  final Rect guide;
  final bool locked;
  final Quad? quad;
  final Size source;
  final bool dim;

  @override
  void paint(Canvas canvas, Size size) {
    if (dim) {
      final shade = Path()
        ..addRect(Offset.zero & size)
        ..addRRect(RRect.fromRectAndRadius(guide, const Radius.circular(12)))
        ..fillType = PathFillType.evenOdd;
      canvas.drawPath(shade, Paint()..color = const Color(0xB3000000));
    }
    final stroke = Paint()
      ..color = locked ? lockGreen : ink
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;
    _brackets(canvas, guide, stroke);
    _mrzLane(canvas, guide, locked ? lockGreen : ink);
    final found = quad;
    if (found != null &&
        source.width > 0 &&
        source.height > 0 &&
        _tracksCard(found, source)) {
      final paint = Paint()
        ..color = locked ? lockGreen : holdAmber
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5;
      final path = Path()
        ..moveTo(_x(found.tl), _y(found.tl))
        ..lineTo(_x(found.tr), _y(found.tr))
        ..lineTo(_x(found.br), _y(found.br))
        ..lineTo(_x(found.bl), _y(found.bl))
        ..close();
      canvas.drawPath(path, paint);
    }
  }

  bool _tracksCard(Quad quad, Size source) {
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
      ..color = color.withValues(alpha: 0.85)
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
    final radius = const Radius.circular(12);
    final rrect = RRect.fromRectAndRadius(rect, radius);
    canvas.drawRRect(rrect, paint..strokeWidth = 1.2);
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
