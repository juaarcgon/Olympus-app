// Entidad de dominio AppUser para la feature de autenticación.
//
// El modelo de usuario del dominio es único y compartido entre features para
// garantizar que sea ampliable y coherente (Req 3.5): se define una sola vez
// como `Profile` en la feature `profile`. Aquí se expone el alias `AppUser`,
// que es el nombre con el que la capa de autenticación se refiere al usuario
// autenticado (ver "Servicio_Autenticacion" en el diseño).

import 'package:olympus/features/profile/domain/entities/profile.dart';

/// Usuario autenticado del Sistema.
///
/// Alias del modelo de dominio compartido [Profile]. Mantener un único tipo
/// evita duplicar los campos conocidos y el mapa `metadata` ampliable.
typedef AppUser = Profile;
