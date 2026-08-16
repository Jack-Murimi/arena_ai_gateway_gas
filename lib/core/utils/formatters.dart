import 'package:intl/intl.dart';

/// Shared formatting helpers (Kenyan Shillings, dates).
class AppFormatters {
  AppFormatters._();

  static final NumberFormat _kes = NumberFormat.currency(
    locale: 'en_KE',
    symbol: 'KSh ',
    decimalDigits: 2,
  );

  static final NumberFormat _number = NumberFormat('#,##0');
  static final DateFormat _date = DateFormat('dd MMM yyyy');
  static final DateFormat _dateTime = DateFormat('dd MMM yyyy, HH:mm');

  static String kes(num amount) => _kes.format(amount);
  static String number(num value) => _number.format(value);
  static String date(DateTime d) => _date.format(d);
  static String dateTime(DateTime d) => _dateTime.format(d);
}
