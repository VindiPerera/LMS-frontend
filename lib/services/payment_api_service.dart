import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/api_config.dart';

/// One VIP plan a user can buy — kept in sync with hello-backend's
/// PaymentController::PLANS (the price actually charged always comes from
/// there, never from this client value; this is display-only).
class VipPlan {
  final String id;
  final String label;
  final double amount;
  final String currency;
  final int days;

  const VipPlan({
    required this.id,
    required this.label,
    required this.amount,
    required this.currency,
    required this.days,
  });

  /// Rs. 1,000 is the actual target price for this plan. The card charge
  /// still has to happen in USD (PayPal Advanced Card Payments doesn't
  /// take LKR here), so [thirtyDaysFor] recomputes the USD amount from a
  /// live USD->LKR rate every time it's built — see ExchangeRateService —
  /// keeping the real, LKR-equivalent price pegged to this figure as the
  /// exchange rate moves, instead of the USD price silently drifting.
  static const double lkrTargetPrice = 1000;

  /// Shown until a live rate is available (first launch, or offline with
  /// no cache yet) — roughly what Rs. 1,000 is worth in USD.
  static const double fallbackUsdAmount = 4.99;

  /// Builds the 30-day plan priced from [usdToLkrRate] (from
  /// ExchangeRateService.instance.rate). Pass null to get
  /// [fallbackUsdAmount] while a rate hasn't loaded yet.
  static VipPlan thirtyDaysFor(double? usdToLkrRate) {
    final amount = (usdToLkrRate != null && usdToLkrRate > 0)
        ? double.parse((lkrTargetPrice / usdToLkrRate).toStringAsFixed(2))
        : fallbackUsdAmount;
    return VipPlan(
      id: 'vip_30_days',
      label: 'VIP — 30 days',
      amount: amount,
      currency: 'USD',
      days: 30,
    );
  }
}

/// Thrown when hello-backend rejects or fails a payment, with the
/// server's own explanation (never contains raw card data — see
/// PayPalService's class doc on that guarantee).
class PaymentException implements Exception {
  final String message;
  const PaymentException(this.message);
  @override
  String toString() => message;
}

/// Talks to hello-backend's PaymentController — direct Visa/Mastercard
/// payments via PayPal's Advanced Card Payments, with no PayPal account
/// or redirect involved for the payer. See PayPalService's class doc for
/// the full architecture and its PCI-DSS note.
class PaymentApiService {
  /// Charges [plan] to the given card and, on success, the backend grants
  /// VIP directly in Firestore. Card fields are sent once, over HTTPS in
  /// any release build (see ApiConfig.baseUrl), and never touch anything
  /// else client-side — not logged, not cached, not stored.
  static Future<void> payWithCard({
    required String uid,
    required VipPlan plan,
    required String cardNumber,
    required int expiryMonth,
    required int expiryYear,
    required String cvv,
    required String cardholderName,
  }) async {
    final http.Response response;
    try {
      response = await http
          .post(
            Uri.parse('${ApiConfig.baseUrl}/api/payments/card-pay'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'uid': uid,
              'plan': plan.id,
              'card_number': cardNumber,
              'expiry_month': expiryMonth,
              'expiry_year': expiryYear,
              'cvv': cvv,
              'cardholder_name': cardholderName,
            }),
          )
          .timeout(const Duration(seconds: 30));
    } catch (e) {
      throw const PaymentException(
        "Couldn't reach the payment server. Check your connection and try again.",
      );
    }

    Map<String, dynamic> body;
    try {
      body = jsonDecode(response.body) as Map<String, dynamic>;
    } catch (_) {
      throw const PaymentException('Unexpected response from the payment server.');
    }

    if (response.statusCode == 200 && body['success'] == true) {
      return;
    }

    if (body['errors'] is Map) {
      final errors = (body['errors'] as Map).values.expand((v) => v is List ? v : [v]).map((e) => e.toString());
      throw PaymentException(errors.isNotEmpty ? errors.first : 'Payment details were rejected.');
    }

    throw PaymentException(body['message']?.toString() ?? 'Payment failed. Please try again.');
  }
}
