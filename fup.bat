@echo off
REM fup - Levanta la app Flutter en Chrome en el puerto fijo 3000
REM usando las variables de Supabase de dart_defines.json.
REM
REM Uso (desde la raiz del proyecto):
REM   fup
REM
REM Nota: el puerto fijo evita que la app se abra en una direccion distinta
REM en cada ejecucion.

flutter run -d chrome --web-port=3000 --dart-define-from-file=dart_defines.json %*
