/// An error returned by (or while reaching) one of the APIs.
class ApiException implements Exception {
  const ApiException(
    this.message, {
    this.statusCode,
    this.fieldErrors = const {},
  });

  final String message;

  /// HTTP status code, or null when the server could not be reached.
  final int? statusCode;

  /// Per-field validation messages from a 422 response, keyed by JSON field name.
  final Map<String, String> fieldErrors;

  bool get isNotFound => statusCode == 404;
  bool get isValidation => statusCode == 422;
  bool get isConnectionError => statusCode == null;

  @override
  String toString() => message;
}
