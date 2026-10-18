/// Masks a PAN for logs and secondary UI. The host still receives the full
/// number on the capture so it can fill a form.
String redactPan(String pan) {
  final digits = pan.replaceAll(RegExp(r'\D'), '');
  if (digits.length < 4) return '****';
  final last = digits.substring(digits.length - 4);
  return '**** **** **** $last';
}
