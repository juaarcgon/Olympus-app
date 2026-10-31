# Icono de la app (logo de Olympus)

Coloca aquí tu logo como un único archivo PNG cuadrado:

```
assets/icon/app_icon.png
```

Requisitos del PNG:

- Cuadrado, **1024 x 1024 px**.
- Formato PNG.
- Para Android, el icono adaptativo recorta las esquinas y aplica un margen
  interior (`safe zone`): deja el motivo del logo dentro del ~66% central para
  que no se recorte en iconos circulares.

## Generar los iconos

Una vez colocado `app_icon.png`, ejecuta desde la raíz del proyecto:

```powershell
flutter pub get
dart run flutter_launcher_icons
```

Esto regenera automáticamente todos los tamaños:

- Android: `android/app/src/main/res/mipmap-*/`
- iOS: `ios/Runner/Assets.xcassets/AppIcon.appiconset/`

La configuración vive en `pubspec.yaml`, bajo la clave `flutter_launcher_icons`.
