import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import 'catalog_model.dart';

/// Debug builds only: registers `ext.lich.capture`, which returns the
/// current frame as a base64 PNG, and `ext.lich.demo`, which sets up a view
/// (params: query, select, type, sort) for README screenshots. Lets tooling
/// screenshot the app where `flutter screenshot` isn't supported
/// (e.g. Linux/Impeller).
void registerDebugCapture(CatalogModel model) {
  if (!kDebugMode) return;
  developer.registerExtension('ext.lich.demo', (method, params) async {
    T? pick<T extends Enum>(List<T> values, String key) =>
        values.where((v) => v.name == params[key]).firstOrNull;
    if (pick(TypeFilter.values, 'type') case final t?) model.setTypeFilter(t);
    if (pick(SortBy.values, 'sort') case final s?) model.setSortBy(s);
    if (params['query'] case final q?) model.setQuery(q);
    if (params['select'] case final name?) {
      model.select(model.allGroups.where((g) => g.name == name).firstOrNull);
    }
    return developer.ServiceExtensionResponse.result(
      jsonEncode({'visible': model.visible.length}),
    );
  });
  developer.registerExtension('ext.lich.capture', (method, params) async {
    final view = WidgetsBinding.instance.renderViews.first;
    final layer = view.debugLayer! as OffsetLayer;
    final ratio = view.flutterView.devicePixelRatio;
    final image = await layer.toImage(
      Offset.zero & view.size,
      pixelRatio: ratio,
    );
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    return developer.ServiceExtensionResponse.result(
      jsonEncode({'png': base64.encode(png!.buffer.asUint8List())}),
    );
  });
}
