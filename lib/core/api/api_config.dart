class ApiConfig {
  const ApiConfig._();

  static const baseUrl = String.fromEnvironment('API_BASE_URL');
  static const pollingSeconds = int.fromEnvironment(
    'API_POLLING_SECONDS',
    defaultValue: 20,
  );

  static bool get enabled => baseUrl.trim().isNotEmpty;
}
