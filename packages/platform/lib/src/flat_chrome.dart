import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The channel `MainActivity` answers device questions on.
const deviceChannel = MethodChannel('app.settlo/device');

/// Whether the glass tab bar should use its flat 92% surface instead of a
/// blur: true on low-RAM Android phones (canvas note n32, ADR 0012). False
/// elsewhere, including where there is no native side.
Future<bool> prefersFlatChrome({MethodChannel channel = deviceChannel}) async {
  try {
    return await channel.invokeMethod<bool>('prefersFlatChrome') ?? false;
  } on MissingPluginException {
    return false;
  }
}

/// [prefersFlatChrome], read once at launch; `main` overrides this.
final flatChromeProvider = Provider<bool>((ref) => false);
