import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// Live USD -> LKR rate, used to keep VIP subscription pricing pegged to a
/// fixed Rs. 1,000 target (see PaymentApiService's VipPlan.thirtyDaysFor)
/// even though the actual card charge has to be in USD. Backed by a free,
/// no-key API (open.er-api.com) and cached in SharedPreferences so the
/// price stays stable across app restarts and still works offline.
class ExchangeRateService {
  ExchangeRateService._();
  static final ExchangeRateService instance = ExchangeRateService._();

  static const _rateKey = 'usd_lkr_rate';
  static const _fetchedAtKey = 'usd_lkr_rate_fetched_at';
  static const _refreshInterval = Duration(hours: 6);

  /// Last known LKR-per-USD rate. Null until the first cache read or fetch
  /// completes — VipPlan.thirtyDaysFor falls back to a fixed USD price
  /// while this is null, so pricing UI never has to wait on it.
  final ValueNotifier<double?> rate = ValueNotifier<double?>(null);

  bool _loadedFromCache = false;
  Future<void>? _inFlight;

  /// Loads the cached rate (if any) and refreshes it in the background when
  /// stale. Safe to call from multiple widgets — concurrent calls share one
  /// underlying fetch. Call early (e.g. MeScreen.initState) and read [rate]
  /// via ValueListenableBuilder wherever the price is shown.
  Future<void> ensureLoaded() {
    return _inFlight ??= _load().whenComplete(() => _inFlight = null);
  }

  Future<void> _load() async {
    SharedPreferences? prefs;
    try {
      prefs = await SharedPreferences.getInstance();
    } catch (_) {
      // No persistence available (e.g. some web/test contexts) — still
      // worth trying a live fetch below.
    }

    if (!_loadedFromCache && prefs != null) {
      final cached = prefs.getDouble(_rateKey);
      if (cached != null && cached > 0) rate.value = cached;
      _loadedFromCache = true;
    }

    final fetchedAtMs = prefs?.getInt(_fetchedAtKey);
    final isStale = fetchedAtMs == null ||
        DateTime.now().difference(DateTime.fromMillisecondsSinceEpoch(fetchedAtMs)) > _refreshInterval;
    if (!isStale) return;

    try {
      final response = await http
          .get(Uri.parse('https://open.er-api.com/v6/latest/USD'))
          .timeout(const Duration(seconds: 8));
      if (response.statusCode != 200) return;

      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final lkr = (body['rates'] as Map<String, dynamic>?)?['LKR'];
      final freshRate = lkr is num ? lkr.toDouble() : null;
      if (freshRate == null || freshRate <= 0) return;

      rate.value = freshRate;
      await prefs?.setDouble(_rateKey, freshRate);
      await prefs?.setInt(_fetchedAtKey, DateTime.now().millisecondsSinceEpoch);
    } catch (e) {
      // Never let a flaky network block VIP pricing — the cached/fallback
      // value (handled by callers) covers this.
      debugPrint('ExchangeRateService: rate refresh failed (non-fatal): $e');
    }
  }
}
