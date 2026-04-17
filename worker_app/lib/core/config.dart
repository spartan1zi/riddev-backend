/// Backend base URL (no trailing /api — [ApiClient] adds `/api`).
///
/// **Physical phone:** default `10.0.2.2` does not work — use your PC LAN IP:
/// `flutter run --dart-define=API_BASE_URL=http://192.168.x.x:4000`
const String kApiBaseUrl = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: 'http://10.0.2.2:4000',
);

const double kAccraLat = 5.6037;
const double kAccraLng = -0.1870;
