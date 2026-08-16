/// Safe numeric parsing for values coming from PostgREST JSON responses.
///
/// PostgREST normally returns numeric columns as JSON numbers, but can
/// return them as strings in some cases (e.g. `numeric` precision or
/// certain query paths). Never crash on either — coerce defensively.
double? parseDouble(Object? value) {
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value.trim());
  return null;
}

int? parseInt(Object? value) {
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value.trim());
  return null;
}
