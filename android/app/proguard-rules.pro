# Flutter wrapper
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }
-dontwarn io.flutter.embedding.**

# NaviSense native bridge
-keep class com.navisense.app.** { *; }

# Google ML Kit
-keep class com.google.mlkit.** { *; }
-dontwarn com.google.mlkit.**

# Firebase AI Logic & App Check
-keep class com.google.firebase.ai.** { *; }
-keep class com.google.firebase.appcheck.** { *; }
