import 'package:connectivity_plus/connectivity_plus.dart';

/// Thin wrapper around connectivity_plus so widgets never import it
/// directly — matches the rest of the app's service-layer convention.
class ConnectivityService {
  ConnectivityService._();
  static final instance = ConnectivityService._();

  final Connectivity _connectivity = Connectivity();

  bool _isOnline(List<ConnectivityResult> results) =>
      results.isNotEmpty && !results.contains(ConnectivityResult.none);

  /// True/false online stream — collapses connectivity_plus's list-of-active
  /// interfaces API down to the single boolean every Moments widget needs
  /// (offline banner, disabling the Post button, etc.).
  Stream<bool> get onlineStatus =>
      _connectivity.onConnectivityChanged.map(_isOnline);

  Future<bool> get isOnlineNow async =>
      _isOnline(await _connectivity.checkConnectivity());
}
