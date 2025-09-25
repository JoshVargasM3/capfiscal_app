import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';

enum ConnectivityStatus { online, offline }

class ConnectivityService {
  ConnectivityService._();

  static final ConnectivityService _instance = ConnectivityService._();

  factory ConnectivityService() => _instance;

  final Connectivity _connectivity = Connectivity();

  ConnectivityStatus _mapResult(dynamic result) {
    if (result is ConnectivityResult) {
      return result == ConnectivityResult.none
          ? ConnectivityStatus.offline
          : ConnectivityStatus.online;
    }
    if (result is List<ConnectivityResult>) {
      final hasConnection = result.any((e) => e != ConnectivityResult.none);
      return hasConnection ? ConnectivityStatus.online : ConnectivityStatus.offline;
    }
    return ConnectivityStatus.offline;
  }

  Stream<ConnectivityStatus> watchStatus() async* {
    try {
      final initial = await _connectivity.checkConnectivity();
      yield _mapResult(initial);
    } catch (_) {
      yield ConnectivityStatus.offline;
    }
    yield* _connectivity.onConnectivityChanged
        .map<ConnectivityStatus>(_mapResult)
        .handleError((_) => ConnectivityStatus.offline);
  }

  Future<ConnectivityStatus> currentStatus() async {
    try {
      final result = await _connectivity.checkConnectivity();
      return _mapResult(result);
    } catch (_) {
      return ConnectivityStatus.offline;
    }
  }
}
