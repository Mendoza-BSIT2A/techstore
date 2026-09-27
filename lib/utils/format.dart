/// Small formatting helpers (kept local so the app needs no intl package).
library;

const _months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

/// US dollars with thousands separators: 1999.99 -> `$1,999.99`,
/// 0.5 -> `$0.50`. With [cents] false the amount is rounded to whole dollars.
String formatPrice(double value, {bool cents = true}) {
  final negative = value < 0;
  if (!cents) {
    return '${negative ? '-' : ''}\$${formatNumber(value.abs().round())}';
  }
  final totalCents = (value.abs() * 100).round();
  final dollars = totalCents ~/ 100;
  final remainder = (totalCents % 100).toString().padLeft(2, '0');
  return '${negative ? '-' : ''}\$${formatNumber(dollars)}.$remainder';
}

/// Whole number with thousands separators: 100000 -> `100,000`.
String formatNumber(int value) {
  final digits = value.abs().toString();
  final buffer = StringBuffer(value < 0 ? '-' : '');
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(',');
    buffer.write(digits[i]);
  }
  return buffer.toString();
}

/// `Sep 26, 2026`
String formatDate(DateTime date) =>
    '${_months[date.month - 1]} ${date.day}, ${date.year}';

/// `1 product`, `2 products`
String pluralize(int count, String singular, [String? plural]) =>
    '$count ${count == 1 ? singular : (plural ?? '${singular}s')}';
