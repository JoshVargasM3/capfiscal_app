import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'cap_colors.dart';

class CapTheme {
  const CapTheme._();

  static ThemeData get dark {
    const scheme = ColorScheme.dark(
      primary: CapColors.gold,
      secondary: CapColors.goldDark,
      surface: CapColors.surface,
      background: CapColors.bgTop,
      onPrimary: Colors.black,
      onSecondary: Colors.black,
      onSurface: CapColors.text,
      onBackground: CapColors.text,
      error: Colors.redAccent,
      onError: Colors.black,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: scheme,

      // ✅ Evita “blancos” por default (pantallas/transiciones)
      scaffoldBackgroundColor: CapColors.bgTop,
      canvasColor: CapColors.bgTop,

      appBarTheme: const AppBarTheme(
        backgroundColor: CapColors.surface,
        foregroundColor: CapColors.text,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        iconTheme: IconThemeData(color: CapColors.text),
      ),

      dividerColor: Colors.white12,

      // ✅ FIX: en tu Flutter es DialogThemeData, no DialogTheme
      dialogTheme: const DialogThemeData(
        backgroundColor: CapColors.surface,
        surfaceTintColor: Colors.transparent,
      ),

      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: CapColors.surface,
        surfaceTintColor: Colors.transparent,
      ),

      snackBarTheme: const SnackBarThemeData(
        backgroundColor: CapColors.surface,
        contentTextStyle: TextStyle(color: CapColors.text),
      ),

      // ✅ Spinners por default en dorado CAPFISCAL
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: CapColors.gold,
        linearTrackColor: Colors.white12,
      ),

      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: FadeUpwardsPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        },
      ),

      // ✅ Evita “cupertino blanco” en transiciones/barras
      cupertinoOverrideTheme: const CupertinoThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: CapColors.bgTop,
        barBackgroundColor: CapColors.surface,
        primaryColor: CapColors.gold,
      ),
    );
  }
}
