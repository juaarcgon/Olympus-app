# Reglas ProGuard/R8 para la build de release ofuscada de Olympus.
#
# Flutter y sus plugins usan reflexión/JNI en varios puntos; estas reglas
# evitan que R8 elimine u ofusque clases necesarias en tiempo de ejecución.

# --- Flutter embedding ---
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }
-dontwarn io.flutter.embedding.**

# --- Play Core (deferred components / split install) ---
# Flutter referencia estas clases aunque la app no use componentes diferidos.
-keep class com.google.android.play.core.** { *; }
-dontwarn com.google.android.play.core.**

# --- Mantener anotaciones y metadatos de Kotlin ---
-keepattributes *Annotation*
-keepattributes Signature
-keepattributes InnerClasses
-keepattributes EnclosingMethod

# --- Modelos serializados vía JSON (si se añaden con reflexión en el futuro) ---
# Supabase/HTTP usan serialización estándar de Dart en el lado Flutter, por lo
# que normalmente no requieren reglas en Java/Kotlin. Se deja este bloque como
# punto de extensión si se integran SDKs nativos que usen Gson/Moshi.
