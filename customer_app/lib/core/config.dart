/// Backend base URL (no trailing /api — [ApiClient] adds `/api`).
///
/// - **Android emulator:** `http://10.0.2.2:4000` reaches your PC’s localhost.
/// - **Physical phone:** `10.0.2.2` does **not** work. Use your PC’s LAN IP, same Wi‑Fi:
///   `flutter run --dart-define=API_BASE_URL=http://192.168.1.50:4000`
const String kApiBaseUrl = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: 'http://10.0.2.2:4000',
);

const double kAccraLat = 5.6037;
const double kAccraLng = -0.1870;
