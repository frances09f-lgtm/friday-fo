import 'package:flutter/material.dart';

/// Orion Store look (Material 3 Expressive): soft green surfaces, pill dock,
/// light and dark themes. UI only.
class Orion {
  static ThemeData light() => _build(const ColorScheme(
      brightness: Brightness.light,
      primary: Color(0xFF00695A),
      onPrimary: Color(0xFFFFFFFF),
      primaryContainer: Color(0xFFB9F0DF),
      onPrimaryContainer: Color(0xFF00201A),
      secondary: Color(0xFF4A635B),
      onSecondary: Color(0xFFFFFFFF),
      secondaryContainer: Color(0xFFD4E8E0),
      onSecondaryContainer: Color(0xFF0E1F1A),
      tertiary: Color(0xFF3D5F82),
      onTertiary: Color(0xFFFFFFFF),
      tertiaryContainer: Color(0xFFD3E4F7),
      onTertiaryContainer: Color(0xFF0A1D30),
      error: Color(0xFFB3261E),
      onError: Color(0xFFFFFFFF),
      surface: Color(0xFFF2F8F5),
      onSurface: Color(0xFF0E1F1A),
      onSurfaceVariant: Color(0xFF475D56),
      outline: Color(0xFF71857D),
      outlineVariant: Color(0xFFC1D1CA),
      surfaceContainerLowest: Color(0xFFFFFFFF),
      surfaceContainerLow: Color(0xFFEEF5F1),
      surfaceContainer: Color(0xFFE8F1ED),
      surfaceContainerHigh: Color(0xFFDBE8E2),
      surfaceContainerHighest: Color(0xFFD2E1DA)));

  static ThemeData dark() => _build(const ColorScheme(
      brightness: Brightness.dark,
      primary: Color(0xFF4FD8B8),
      onPrimary: Color(0xFF00382D),
      primaryContainer: Color(0xFF00503F),
      onPrimaryContainer: Color(0xFFB9F0DF),
      secondary: Color(0xFFB2CCC3),
      onSecondary: Color(0xFF1D352E),
      secondaryContainer: Color(0xFF2B3D36),
      onSecondaryContainer: Color(0xFFD4E8E0),
      tertiary: Color(0xFFA7C8EC),
      onTertiary: Color(0xFF0A2744),
      tertiaryContainer: Color(0xFF2E4057),
      onTertiaryContainer: Color(0xFFD3E4F7),
      error: Color(0xFFFFB4AB),
      onError: Color(0xFF690005),
      surface: Color(0xFF0C1411),
      onSurface: Color(0xFFE2EFE9),
      onSurfaceVariant: Color(0xFFA3B8AF),
      outline: Color(0xFF6E8279),
      outlineVariant: Color(0xFF3A4A43),
      surfaceContainerLowest: Color(0xFF070D0B),
      surfaceContainerLow: Color(0xFF131C18),
      surfaceContainer: Color(0xFF1D2B26),
      surfaceContainerHigh: Color(0xFF26362F),
      surfaceContainerHighest: Color(0xFF304139)));

  static ThemeData _build(ColorScheme s) {
    bool selected(Set<WidgetState> st) => st.contains(WidgetState.selected);
    return ThemeData(
        useMaterial3: true,
        colorScheme: s,
        fontFamily: 'Inter',
        scaffoldBackgroundColor: s.surface,
        dividerTheme: DividerThemeData(color: s.outlineVariant),
        appBarTheme: AppBarTheme(
            backgroundColor: s.surface,
            foregroundColor: s.onSurface,
            elevation: 0,
            scrolledUnderElevation: 0,
            surfaceTintColor: Colors.transparent,
            centerTitle: false),
        cardTheme: CardThemeData(
            color: s.surfaceContainer,
            elevation: 0,
            margin: EdgeInsets.zero,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24))),
        inputDecorationTheme: InputDecorationTheme(
            filled: true,
            fillColor: s.surfaceContainer,
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(28),
                borderSide: BorderSide.none)),
        navigationBarTheme: NavigationBarThemeData(
            height: 68,
            elevation: 0,
            backgroundColor: Colors.transparent,
            surfaceTintColor: Colors.transparent,
            indicatorColor: s.primaryContainer,
            labelTextStyle: WidgetStateProperty.resolveWith((st) => TextStyle(
                fontSize: 11,
                fontWeight: selected(st) ? FontWeight.w700 : FontWeight.w500,
                color: selected(st) ? s.onSurface : s.onSurfaceVariant)),
            iconTheme: WidgetStateProperty.resolveWith((st) => IconThemeData(
                color: selected(st) ? s.onPrimaryContainer : s.onSurfaceVariant))));
  }
}
