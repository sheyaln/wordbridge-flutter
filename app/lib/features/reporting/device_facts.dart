import 'dart:io';
import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/services.dart';

import 'report.dart';

/// Which hardware this is, for the two questions that cannot be answered
/// without it.
///
/// "Slow" on an iPad mini 5 and "slow" on this year's iPad are different
/// findings, and a crash that only happens on one chip is a crash nobody can
/// reproduce without knowing which. So the model class travels with a report.
///
/// **A model class is not an identifier.** `iPad11,1` names a product line that
/// millions of people own. Nothing here reads a serial, an advertising id, a
/// name, or the §4.49 device id — that last one exists to group usage rows on
/// one tablet, and sending it would let two reports be tied to one person.
class DeviceModel {
  DeviceModel({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(_name);

  static const _name = 'org.wordbridge/device_facts';

  final MethodChannel _channel;

  /// The hardware identifier, or null where the platform did not answer.
  ///
  /// Null is a fine answer. A report without a model is still a report, and an
  /// unimplemented channel on a platform nobody has built for yet must not be
  /// the reason somebody cannot tell us their app crashed.
  Future<String?> model() async {
    try {
      return await _channel.invokeMethod<String>('model');
    } catch (_) {
      return null;
    }
  }
}

/// Everything about the tablet that goes in a report.
Future<DeviceFacts> deviceFacts({DeviceModel? models}) async => (
  platform: Platform.operatingSystem,
  osVersion: Platform.operatingSystemVersion,
  model: await (models ?? DeviceModel()).model(),
  locale: PlatformDispatcher.instance.locale.toString(),
);
