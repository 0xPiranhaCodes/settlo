import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

/// Opens a link, such as WhatsApp's, in another app. False when nothing
/// on the phone can open it. Tests override this.
final openUrlProvider = Provider<Future<bool> Function(Uri)>(
  (ref) =>
      (uri) => launchUrl(uri, mode: LaunchMode.externalApplication),
);

/// Opens a WhatsApp chat with `phone` (digits, with country code) holding
/// `text`. False when WhatsApp is not installed: a `wa.me` link would open
/// the browser instead, which counts as opened. Tests override this.
final openWhatsAppProvider =
    Provider<Future<bool> Function(String phone, String text)>(
      (ref) => (phone, text) async {
        final uri = Uri.parse(
          'whatsapp://send?phone=$phone&text=${Uri.encodeComponent(text)}',
        );
        return await canLaunchUrl(uri) && await launchUrl(uri);
      },
    );
