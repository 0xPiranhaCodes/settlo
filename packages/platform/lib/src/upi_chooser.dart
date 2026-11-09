import 'package:flutter/services.dart';

/// The channel `MainActivity` answers on Android.
const upiChooserChannel = MethodChannel('app.settlo/upi');

/// Opens [uri] (a `upi://pay` intent) through Android's app chooser
/// (`Intent.createChooser`), so the payer picks the UPI app every time,
/// even with a default set. False when no installed app handles `upi:`.
///
/// Android only: iOS has no chooser API, so callers open `upi://`
/// directly there and the system picks the registered app (ADR 0011).
Future<bool> openUpiChooser(
  Uri uri, {
  String title = 'Pay with',
  MethodChannel channel = upiChooserChannel,
}) async =>
    await channel.invokeMethod<bool>('openWithChooser', {
      'uri': '$uri',
      'title': title,
    }) ??
    false;
