import 'package:flutter/material.dart';
import '../data/countries.dart';
import '../theme/app_colors.dart';

/// Searchable country picker — a bottom sheet with a live-filtered list,
/// since data/countries.dart's ~195 entries are far too many to scroll
/// through blind. Returns the tapped [Country], or null if dismissed
/// without picking one.
Future<Country?> showCountryPickerSheet(BuildContext context) {
  return showModalBottomSheet<Country>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (_) => const _CountryPickerSheet(),
  );
}

class _CountryPickerSheet extends StatefulWidget {
  const _CountryPickerSheet();

  @override
  State<_CountryPickerSheet> createState() => _CountryPickerSheetState();
}

class _CountryPickerSheetState extends State<_CountryPickerSheet> {
  final _searchController = TextEditingController();
  List<Country> _filtered = countries;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String query) {
    final q = query.trim().toLowerCase();
    setState(() {
      _filtered = q.isEmpty
          ? countries
          : countries.where((c) => c.name.toLowerCase().contains(q)).toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      minChildSize: 0.4,
      maxChildSize: 0.92,
      expand: false,
      builder: (context, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              const SizedBox(height: 10),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.divider,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 14),
              const Text(
                'Select your country',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                child: TextField(
                  controller: _searchController,
                  autofocus: true,
                  onChanged: _onSearchChanged,
                  style: const TextStyle(fontSize: 14.5),
                  decoration: InputDecoration(
                    hintText: 'Search countries…',
                    hintStyle: const TextStyle(
                      color: AppColors.textTertiary,
                      fontSize: 14,
                    ),
                    prefixIcon: const Icon(
                      Icons.search_rounded,
                      size: 20,
                      color: AppColors.textTertiary,
                    ),
                    filled: true,
                    fillColor: AppColors.surfaceLight,
                    contentPadding: const EdgeInsets.symmetric(vertical: 12),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide.none,
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: const BorderSide(
                        color: AppColors.primaryPurple,
                        width: 1.4,
                      ),
                    ),
                  ),
                ),
              ),
              Expanded(
                child: _filtered.isEmpty
                    ? const Center(
                        child: Text(
                          'No countries match your search.',
                          style: TextStyle(color: AppColors.textTertiary),
                        ),
                      )
                    : ListView.builder(
                        controller: scrollController,
                        padding: const EdgeInsets.only(bottom: 12),
                        itemCount: _filtered.length,
                        itemBuilder: (context, i) {
                          final country = _filtered[i];
                          return ListTile(
                            leading: Text(
                              country.flagEmoji,
                              style: const TextStyle(fontSize: 26),
                            ),
                            title: Text(
                              country.name,
                              style: const TextStyle(
                                fontSize: 14.5,
                                fontWeight: FontWeight.w500,
                                color: AppColors.textPrimary,
                              ),
                            ),
                            onTap: () => Navigator.of(context).pop(country),
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}
