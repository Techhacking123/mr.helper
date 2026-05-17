import 'package:url_launcher/url_launcher.dart';

class CallLauncher {
  /// Launches the phone dialer with the given number.
  static Future<void> makeCall(String phoneNumber) async {
    final Uri launchUri = Uri(scheme: 'tel', path: phoneNumber);
    if (await canLaunchUrl(launchUri)) {
      await launchUrl(launchUri);
    } else {
      throw 'Could not launch $phoneNumber';
    }
  }
}
