/// Converts a saved Colombian emergency-contact phone to E.164.
///
/// Accepts a raw number or the app's `name — phone` contact format. Only
/// Colombian mobile numbers (10 digits starting with 3) are accepted.
String? normalizeColombianMobileNumber(String contact) {
  final phone = contact.split('—').last.trim();
  final digits = phone.replaceAll(RegExp(r'\D'), '');

  if (digits.length == 10 && digits.startsWith('3')) {
    return '+57$digits';
  }
  if (digits.length == 12 && digits.startsWith('573')) {
    return '+$digits';
  }
  return null;
}