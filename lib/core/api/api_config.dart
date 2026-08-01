class ApiConfig {
  const ApiConfig._();

  static const baseUrl = String.fromEnvironment('API_BASE_URL');
  static const notificationBaseUrl = String.fromEnvironment(
    'NOTIFICATION_API_BASE_URL',
  );
  static const fcmWebVapidKey = String.fromEnvironment('FCM_WEB_VAPID_KEY');
  static const pollingSeconds = int.fromEnvironment(
    'API_POLLING_SECONDS',
    defaultValue: 20,
  );

  static bool get enabled => baseUrl.trim().isNotEmpty;
  static bool get notificationsEnabled => notificationBaseUrl.trim().isNotEmpty;
}
