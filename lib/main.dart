// AI Link 应用入口：runApp、手表后台入口与应用外壳。
// 聊天主页见 lib/chat/chat_home.dart。

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'package:mulit_ai_flutter/chat/chat_home.dart';
import 'package:mulit_ai_flutter/core/app_platform.dart';
import 'package:mulit_ai_flutter/core/app_preferences.dart';
import 'package:mulit_ai_flutter/settings/startup_screen.dart';
import 'package:mulit_ai_flutter/ui/ios_style.dart';
import 'package:mulit_ai_flutter/watch/watch_chat.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  assert(() {
    // Inspector paint diagnostics can persist across hot restarts in debug.
    debugPaintBaselinesEnabled = false;
    debugPaintPointersEnabled = false;
    debugPaintSizeEnabled = false;
    debugRepaintRainbowEnabled = false;
    return true;
  }());
  runApp(const ModelChatApp());
}

@pragma('vm:entry-point')
void watchBackgroundMain() => startWatchWorker();

class ModelChatApp extends StatelessWidget {
  const ModelChatApp({super.key});

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: AppPreferences.instance,
    builder: (context, _) => MaterialApp(
      title: tr('AI Link'),
      debugShowCheckedModeBanner: false,
      locale: AppPreferences.instance.locale,
      supportedLocales: const [Locale('zh'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      builder: (context, child) => AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: AppPreferences.instance.dark
              ? Brightness.light
              : Brightness.dark,
          systemNavigationBarColor: IosColors.background,
          systemNavigationBarIconBrightness: AppPreferences.instance.dark
              ? Brightness.light
              : Brightness.dark,
          systemNavigationBarContrastEnforced: false,
        ),
        child: CupertinoTheme(
          data: CupertinoThemeData(
            primaryColor: IosColors.blue,
            brightness: AppPreferences.instance.dark
                ? Brightness.dark
                : Brightness.light,
          ),
          child: child ?? const SizedBox.shrink(),
        ),
      ),
      theme: ThemeData(
        useMaterial3: false,
        platform: isDesktopApp ? defaultTargetPlatform : TargetPlatform.iOS,
        scaffoldBackgroundColor: IosColors.background,
        primaryColor: IosColors.blue,
        colorScheme: ColorScheme.fromSeed(
          seedColor: IosColors.blue,
          surface: IosColors.surface,
        ),
        pageTransitionsTheme: const PageTransitionsTheme(
          builders: {
            TargetPlatform.android: CupertinoPageTransitionsBuilder(),
            TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          },
        ),
      ),
      darkTheme: ThemeData(
        useMaterial3: false,
        platform: isDesktopApp ? defaultTargetPlatform : TargetPlatform.iOS,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: IosColors.background,
        primaryColor: IosColors.blue,
        colorScheme: ColorScheme.fromSeed(
          seedColor: IosColors.blue,
          brightness: Brightness.dark,
          surface: IosColors.surface,
        ),
        pageTransitionsTheme: const PageTransitionsTheme(
          builders: {
            TargetPlatform.android: CupertinoPageTransitionsBuilder(),
            TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          },
        ),
      ),
      themeMode: AppPreferences.instance.themeMode,
      home: StartupScreen(
        initialize: AppPreferences.instance.load,
        homeBuilder: (onReady) => ChatHome(onReady: onReady),
      ),
    ),
  );
}
