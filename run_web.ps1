# Arranca la app Flutter en Chrome en un puerto fijo (3000) con las
# variables de entorno de Supabase desde dart_defines.json.
#
# Uso:
#   ./run_web.ps1
#
# Fijar el puerto evita que la app se abra en una dirección distinta en cada
# ejecucion, lo que facilita las pruebas y la configuracion de Supabase
# (redirect URLs, etc.).

flutter run -d chrome --web-port=3000 --dart-define-from-file=dart_defines.json
