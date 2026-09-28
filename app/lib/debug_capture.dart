import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Debug builds only: registers `ext.lich.capture`, which returns the
/// current frame as a base64 PNG. Lets tooling screenshot the app on
/// platforms where `flutter screenshot` isn't supported (e.g. Linux/Impeller).
void registerDebugCapture() {
  if (!kDebugMode) return;
  developer.registerExtension('ext.lich.capture', (method, params) async {
    final view = WidgetsBinding.instance.renderViews.first;
    final layer = view.debugLayer! as OffsetLayer;
    final ratio = view.flutterView.devicePixelRatio;
    final image = await layer.toImage(Offset.zero & view.size,
        pixelRatio: ratio);
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    return developer.ServiceExtensionResponse.result(jsonEncode({
      'png': base64.encode(png!.buffer.asUint8List()),
    }));
  });
}
