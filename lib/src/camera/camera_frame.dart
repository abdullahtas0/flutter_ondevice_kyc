import 'dart:typed_data';

import 'package:camera/camera.dart';

import '../pipeline/frame_convert.dart';
import '../scan/guide.dart';

/// Copies a camera buffer into a [RawCameraFrame] the scanner can rotate and crop.
RawCameraFrame? rawFromCameraImage(
  CameraImage image, {
  required int sensorOrientation,
  GuideCrop? crop,
  bool framed = false,
}) {
  final turns = analysisTurns(
    bufferWidth: image.width,
    bufferHeight: image.height,
    sensorOrientation: sensorOrientation,
  );
  final region = crop ?? (left: 0, top: 0, right: 1, bottom: 1);
  switch (image.format.group) {
    case ImageFormatGroup.yuv420:
      if (image.planes.length < 3) return null;
      return RawCameraFrame(
        width: image.width,
        height: image.height,
        layout: RawFrameLayout.yuv420,
        planes: image.planes.map(_plane).toList(),
        quarterTurns: turns,
        framed: framed,
        cropLeft: region.left,
        cropTop: region.top,
        cropRight: region.right,
        cropBottom: region.bottom,
      );
    case ImageFormatGroup.bgra8888:
      if (image.planes.isEmpty) return null;
      return RawCameraFrame(
        width: image.width,
        height: image.height,
        layout: RawFrameLayout.bgra8888,
        planes: [_plane(image.planes.first)],
        quarterTurns: turns,
        framed: framed,
        cropLeft: region.left,
        cropTop: region.top,
        cropRight: region.right,
        cropBottom: region.bottom,
      );
    case ImageFormatGroup.nv21:
      if (image.planes.length < 2) return null;
      return RawCameraFrame(
        width: image.width,
        height: image.height,
        layout: RawFrameLayout.nv21,
        planes: [_plane(image.planes[0]), _plane(image.planes[1])],
        quarterTurns: turns,
        framed: framed,
        cropLeft: region.left,
        cropTop: region.top,
        cropRight: region.right,
        cropBottom: region.bottom,
      );
    default:
      return null;
  }
}

RawPlane _plane(Plane plane) {
  final pixel = plane.bytesPerPixel ?? 1;
  return RawPlane(
    bytes: Uint8List.fromList(plane.bytes),
    bytesPerRow: plane.bytesPerRow,
    bytesPerPixel: pixel <= 0 ? 1 : pixel,
  );
}
