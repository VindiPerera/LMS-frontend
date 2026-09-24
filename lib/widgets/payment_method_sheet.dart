import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/auth_service.dart';
import '../services/payment_api_service.dart';
import '../theme/app_colors.dart';

/// Direct Visa/Mastercard payment sheet — slides up from the bottom of the
/// screen (per the design spec), collects card details right here (no
/// redirect to paypal.com, no PayPal account needed), and charges via
/// hello-backend's PaymentController. See PayPalService's class doc
/// (backend) for the full architecture and its PCI-DSS note.
///
/// Card fields live only in this sheet's own controllers for as long as
/// it's open — nothing here persists them, logs them, or hands them to
/// anything except the one POST to the backend.
class PaymentMethodSheet {
  /// Returns true if the payment completed successfully.
  static Future<bool?> show(BuildContext context, {required VipPlan plan}) {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _PaymentMethodSheetContent(plan: plan),
    );
  }
}

class _PaymentMethodSheetContent extends StatefulWidget {
  final VipPlan plan;
  const _PaymentMethodSheetContent({required this.plan});

  @override
  State<_PaymentMethodSheetContent> createState() => _PaymentMethodSheetContentState();
}

class _PaymentMethodSheetContentState extends State<_PaymentMethodSheetContent> {
  final _formKey = GlobalKey<FormState>();
  final _cardNumberController = TextEditingController();
  final _expiryController = TextEditingController();
  final _cvvController = TextEditingController();
  final _nameController = TextEditingController();

  bool _paying = false;
  String? _error;

  @override
  void dispose() {
    _cardNumberController.dispose();
    _expiryController.dispose();
    _cvvController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  String get _cardBrand {
    final digits = _cardNumberController.text.replaceAll(' ', '');
    if (digits.isEmpty) return '';
    if (digits.startsWith('4')) return 'VISA';
    final leadTwo = int.tryParse(digits.length >= 2 ? digits.substring(0, 2) : '');
    final leadFour = int.tryParse(digits.length >= 4 ? digits.substring(0, 4) : '');
    if (leadTwo != null && leadTwo >= 51 && leadTwo <= 55) return 'MASTERCARD';
    if (leadFour != null && leadFour >= 2221 && leadFour <= 2720) return 'MASTERCARD';
    return '';
  }

  /// Standard Luhn checksum — catches typos before they ever leave the
  /// device, rather than making a round trip to find out.
  bool _passesLuhn(String digits) {
    var sum = 0;
    var alternate = false;
    for (var i = digits.length - 1; i >= 0; i--) {
      var n = int.parse(digits[i]);
      if (alternate) {
        n *= 2;
        if (n > 9) n -= 9;
      }
      sum += n;
      alternate = !alternate;
    }
    return sum % 10 == 0;
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final uid = AuthService.instance.currentUser?.id;
    if (uid == null || uid.isEmpty) {
      setState(() => _error = 'You must be signed in to subscribe.');
      return;
    }

    final expiryParts = _expiryController.text.split('/');
    final month = int.parse(expiryParts[0]);
    final year = 2000 + int.parse(expiryParts[1]);

    setState(() {
      _paying = true;
      _error = null;
    });

    try {
      await PaymentApiService.payWithCard(
        uid: uid,
        plan: widget.plan,
        cardNumber: _cardNumberController.text.replaceAll(' ', ''),
        expiryMonth: month,
        expiryYear: year,
        cvv: _cvvController.text,
        cardholderName: _nameController.text.trim(),
      );
      if (!mounted) return;
      HapticFeedback.lightImpact();
      Navigator.of(context).pop(true);
    } on PaymentException catch (e) {
      if (!mounted) return;
      setState(() {
        _paying = false;
        _error = e.message;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _paying = false;
        _error = 'Something went wrong. Please try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
            child: Form(
              key: _formKey,
              autovalidateMode: AutovalidateMode.onUserInteraction,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        color: AppColors.divider,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  Row(
                    children: [
                      const Icon(Icons.credit_card_rounded, color: AppColors.primaryPurple),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          'Pay with Card',
                          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close_rounded),
                        onPressed: _paying ? null : () => Navigator.of(context).pop(false),
                      ),
                    ],
                  ),
                  Container(
                    margin: const EdgeInsets.only(top: 4, bottom: 18),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(
                      color: AppColors.vipCardBg,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            widget.plan.label,
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                              color: AppColors.vipCardText,
                            ),
                          ),
                        ),
                        Text(
                          '\$${widget.plan.amount.toStringAsFixed(2)}',
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 16,
                            color: AppColors.vipCardText,
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Card number
                  TextFormField(
                    controller: _cardNumberController,
                    keyboardType: TextInputType.number,
                    onChanged: (_) => setState(() {}),
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(19),
                      _CardNumberFormatter(),
                    ],
                    decoration: InputDecoration(
                      labelText: 'Card number',
                      hintText: '1234 5678 9012 3456',
                      border: const OutlineInputBorder(),
                      suffixText: _cardBrand,
                      suffixStyle: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 12,
                        color: AppColors.primaryPurple,
                      ),
                    ),
                    validator: (value) {
                      final digits = (value ?? '').replaceAll(' ', '');
                      if (digits.length < 13 || digits.length > 19) return 'Enter a valid card number';
                      if (!_passesLuhn(digits)) return 'This card number looks invalid';
                      return null;
                    },
                  ),
                  const SizedBox(height: 14),

                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _expiryController,
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                            LengthLimitingTextInputFormatter(4),
                            _ExpiryFormatter(),
                          ],
                          decoration: const InputDecoration(
                            labelText: 'MM/YY',
                            hintText: '08/28',
                            border: OutlineInputBorder(),
                          ),
                          validator: (value) {
                            final v = value ?? '';
                            final match = RegExp(r'^(\d{2})/(\d{2})$').firstMatch(v);
                            if (match == null) return 'Invalid';
                            final month = int.parse(match.group(1)!);
                            if (month < 1 || month > 12) return 'Invalid month';
                            final year = 2000 + int.parse(match.group(2)!);
                            final now = DateTime.now();
                            final expiry = DateTime(year, month + 1); // first day after expiry month
                            if (expiry.isBefore(DateTime(now.year, now.month))) return 'Expired';
                            return null;
                          },
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: TextFormField(
                          controller: _cvvController,
                          keyboardType: TextInputType.number,
                          obscureText: true,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                            LengthLimitingTextInputFormatter(4),
                          ],
                          decoration: const InputDecoration(
                            labelText: 'CVV',
                            hintText: '123',
                            border: OutlineInputBorder(),
                          ),
                          validator: (value) {
                            final v = value ?? '';
                            if (v.length < 3 || v.length > 4) return 'Invalid';
                            return null;
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),

                  TextFormField(
                    controller: _nameController,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(
                      labelText: 'Cardholder name',
                      hintText: 'As shown on the card',
                      border: OutlineInputBorder(),
                    ),
                    validator: (value) =>
                        (value == null || value.trim().isEmpty) ? 'Required' : null,
                  ),

                  if (_error != null) ...[
                    const SizedBox(height: 14),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppColors.badgeRed.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.error_outline_rounded, color: AppColors.badgeRed, size: 18),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _error!,
                              style: const TextStyle(color: AppColors.badgeRed, fontSize: 12.5),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],

                  const SizedBox(height: 18),
                  SizedBox(
                    height: 50,
                    child: ElevatedButton(
                      onPressed: _paying ? null : _submit,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primaryPurple,
                        foregroundColor: Colors.white,
                        disabledBackgroundColor: AppColors.divider,
                        elevation: 0,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      child: _paying
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(strokeWidth: 2.2, color: Colors.white),
                            )
                          : Text(
                              'Pay \$${widget.plan.amount.toStringAsFixed(2)}',
                              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15.5),
                            ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.lock_rounded, size: 13, color: AppColors.textTertiary),
                      SizedBox(width: 5),
                      Text(
                        'Processed securely via PayPal',
                        style: TextStyle(fontSize: 11.5, color: AppColors.textTertiary),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Inserts a space every 4 digits as the user types (1234 5678 ...).
class _CardNumberFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    final digits = newValue.text.replaceAll(' ', '');
    final buffer = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i != 0 && i % 4 == 0) buffer.write(' ');
      buffer.write(digits[i]);
    }
    return TextEditingValue(
      text: buffer.toString(),
      selection: TextSelection.collapsed(offset: buffer.length),
    );
  }
}

/// Inserts "/" after the 2nd digit (MM/YY) as the user types.
class _ExpiryFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    final digits = newValue.text.replaceAll('/', '');
    final buffer = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i == 2) buffer.write('/');
      buffer.write(digits[i]);
    }
    return TextEditingValue(
      text: buffer.toString(),
      selection: TextSelection.collapsed(offset: buffer.length),
    );
  }
}
