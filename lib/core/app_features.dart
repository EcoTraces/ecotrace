abstract final class AppFeatures {
  const AppFeatures._();

  /// Firebase Storage requires a Blaze billing plan. Keep uploads disabled for
  /// Spark builds so operational forms can still be submitted without files.
  static const firebaseStorageUploadsEnabled = bool.fromEnvironment(
    'ENABLE_FIREBASE_STORAGE',
    defaultValue: false,
  );
}
