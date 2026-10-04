# Requirements Document

## Introduction

Este documento define los requisitos para una aplicación de gestión de un gimnasio desarrollada con Flutter en el cliente y Supabase como backend (autenticación y base de datos PostgreSQL). La aplicación permite registrar y autenticar usuarios del gimnasio, gestionar su perfil, y administrar su bono de clases (un bono inicial otorga 10 clases). Además, incluye un rol de superadministrador (con un máximo de dos superadministradores) capaz de gestionar usuarios: suspenderlos (dar de baja), reactivarlos, eliminarlos y ajustar su bono de clases. La aplicación también ofrece un sistema de reserva de clases con calendario y control de aforo: los superadministradores crean y mantienen las clases (horario, aforo máximo y monitor asignado) y los usuarios reservan plaza consumiendo clases de su bono, con soporte para lista de espera, cancelaciones con o sin reembolso según la antelación, y promoción automática desde la lista de espera. El modelo de datos de usuario está diseñado para ser ampliable, de forma que puedan añadirse campos adicionales en el futuro sin romper la estructura existente. Asimismo, la aplicación incluye un flujo de recuperación de contraseña basado en Supabase Auth, mediante el cual un usuario puede solicitar un enlace de restablecimiento a su correo electrónico y establecer una nueva contraseña de forma segura.

## Glossary

- **Sistema**: La aplicación de gestión del gimnasio en su conjunto (cliente Flutter más backend Supabase).
- **Servicio_Autenticacion**: El componente responsable del registro, inicio de sesión y verificación de credenciales, apoyado en Supabase Auth.
- **Servicio_Usuarios**: El componente responsable de crear, leer, actualizar y gestionar los registros de usuario en la base de datos.
- **Servicio_Bono**: El componente responsable de gestionar el saldo de clases (bono) de cada usuario.
- **Servicio_Administracion**: El componente responsable de las operaciones de gestión disponibles para los superadministradores.
- **Usuario**: Persona registrada en el Sistema con rol estándar. Posee: nombre, apellidos, foto, correo electrónico, contraseña, saldo de clases y estado.
- **Superadministrador**: Usuario con privilegios elevados que puede gestionar a otros usuarios. El Sistema admite como máximo dos (2) superadministradores.
- **Bono**: Conjunto de clases disponibles asociadas a un Usuario. Un bono completo otorga diez (10) clases.
- **Saldo_De_Clases**: Número entero de clases restantes que un Usuario tiene disponibles, con valor mínimo de cero (0).
- **Estado_Usuario**: Condición del Usuario dentro del Sistema. Valores permitidos: "activo", "suspendido" (dado de baja).
- **Contraseña_Cifrada**: Representación de la contraseña almacenada mediante hash en la base de datos, nunca en texto plano.
- **Sesion**: Periodo autenticado de un Usuario o Superadministrador tras un inicio de sesión correcto.
- **Servicio_Reservas**: El componente responsable de gestionar las clases del calendario, las reservas, la lista de espera y las cancelaciones.
- **Clase**: Sesión programada en el calendario del gimnasio. Posee: horario (fecha y hora de inicio), Aforo máximo y un Monitor asignado.
- **Horario_Clase**: Fecha y hora de inicio de una Clase.
- **Aforo**: Número máximo de plazas disponibles para una Clase. Es un límite superior configurable del Sistema; su valor actual es diez (10) y puede aumentarse en el futuro sin cambiar la estructura.
- **Lista_De_Espera_Maxima**: Número máximo de Usuarios que puede contener la Lista_De_Espera de una Clase. Su valor es veinte (20).
- **Monitor**: Persona asignada para impartir una Clase.
- **Reserva**: Vínculo entre un Usuario y una Clase que representa una plaza confirmada. Un Usuario puede tener como máximo una Reserva por Clase.
- **Lista_De_Espera**: Secuencia ordenada de Usuarios que solicitaron plaza en una Clase cuyo Aforo estaba completo, de la cual se promociona al siguiente Usuario cuando se libera una plaza.
- **Reserva_Confirmada**: Reserva que ocupa una plaza efectiva dentro del Aforo de una Clase.
- **Token_Restablecimiento**: Credencial de un solo uso y con caducidad, enviada mediante enlace al correo electrónico del Usuario, que habilita el establecimiento de una nueva contraseña durante el flujo de recuperación.

## Requirements

### Requirement 1: Registro de usuarios

**User Story:** Como persona interesada en el gimnasio, quiero registrarme en la aplicación proporcionando mis datos, para poder acceder a mis clases y a mi perfil.

#### Acceptance Criteria

1. WHEN una persona envía un formulario de registro con nombre, apellidos, correo electrónico y contraseña, THE Servicio_Autenticacion SHALL crear una cuenta de Usuario con Estado_Usuario igual a "activo".
2. WHEN se crea una cuenta de Usuario, THE Servicio_Bono SHALL inicializar el Saldo_De_Clases del Usuario en diez (10).
3. WHEN se registra una contraseña, THE Servicio_Autenticacion SHALL almacenar una Contraseña_Cifrada mediante hash en la base de datos.
4. IF el correo electrónico proporcionado ya está asociado a un Usuario existente, THEN THE Servicio_Autenticacion SHALL rechazar el registro y devolver un mensaje que indique que el correo electrónico ya está en uso.
5. IF el correo electrónico proporcionado no cumple el formato de una dirección de correo válida, THEN THE Servicio_Autenticacion SHALL rechazar el registro y devolver un mensaje de error de formato de correo.
6. IF la contraseña proporcionada tiene menos de ocho (8) caracteres, THEN THE Servicio_Autenticacion SHALL rechazar el registro y devolver un mensaje de error de longitud de contraseña.
7. WHERE la persona proporciona una foto durante el registro, THE Servicio_Usuarios SHALL asociar la foto al perfil del Usuario.

### Requirement 2: Inicio y cierre de sesión

**User Story:** Como usuario registrado, quiero iniciar sesión con mi correo y contraseña, para acceder de forma segura a mi cuenta.

#### Acceptance Criteria

1. WHEN un Usuario envía un correo electrónico y una contraseña que coinciden con una cuenta existente y activa, THE Servicio_Autenticacion SHALL establecer una Sesion autenticada para ese Usuario.
2. IF las credenciales enviadas no coinciden con ninguna cuenta existente, THEN THE Servicio_Autenticacion SHALL rechazar el inicio de sesión y devolver un mensaje de credenciales inválidas.
3. IF un Usuario con Estado_Usuario igual a "suspendido" intenta iniciar sesión, THEN THE Servicio_Autenticacion SHALL rechazar el inicio de sesión y devolver un mensaje que indique que la cuenta está suspendida.
4. WHEN un Usuario con una Sesion activa solicita cerrar sesión, THE Servicio_Autenticacion SHALL finalizar la Sesion de ese Usuario.
5. WHEN el Servicio_Autenticacion verifica una contraseña, THE Servicio_Autenticacion SHALL comparar la contraseña proporcionada contra la Contraseña_Cifrada sin exponer la contraseña en texto plano.

### Requirement 3: Gestión del perfil de usuario

**User Story:** Como usuario registrado, quiero ver y actualizar los datos de mi perfil, para mantener mi información al día.

#### Acceptance Criteria

1. WHILE un Usuario tiene una Sesion activa, THE Servicio_Usuarios SHALL permitir al Usuario consultar su nombre, apellidos, foto, correo electrónico y Saldo_De_Clases.
2. WHEN un Usuario con Sesion activa envía cambios en su nombre, apellidos o foto, THE Servicio_Usuarios SHALL actualizar los campos correspondientes del perfil del Usuario.
3. THE Servicio_Usuarios SHALL impedir que un Usuario con rol estándar modifique su propio Saldo_De_Clases.
4. THE Servicio_Usuarios SHALL impedir que un Usuario con rol estándar modifique su propio Estado_Usuario.
5. THE Servicio_Usuarios SHALL almacenar el registro de Usuario con una estructura ampliable que permita añadir campos adicionales sin eliminar ni redefinir los campos existentes.

### Requirement 4: Gestión del bono de clases

**User Story:** Como usuario del gimnasio, quiero consultar y consumir las clases de mi bono, para saber cuántas clases me quedan disponibles.

#### Acceptance Criteria

1. WHEN un Usuario con Sesion activa consulta su Bono, THE Servicio_Bono SHALL devolver el Saldo_De_Clases actual del Usuario.
2. WHEN se registra la asistencia de un Usuario a una clase y su Saldo_De_Clases es mayor que cero (0), THE Servicio_Bono SHALL reducir el Saldo_De_Clases en una (1) clase.
3. IF se intenta registrar la asistencia de un Usuario cuyo Saldo_De_Clases es igual a cero (0), THEN THE Servicio_Bono SHALL rechazar el registro de asistencia y devolver un mensaje que indique que no quedan clases disponibles.
4. THE Servicio_Bono SHALL mantener el Saldo_De_Clases dentro del rango de cero (0) a diez (10) ambos inclusive.

### Requirement 5: Administración de superadministradores

**User Story:** Como propietario del gimnasio, quiero que existan como máximo dos superadministradores, para controlar quién tiene privilegios de gestión.

#### Acceptance Criteria

1. THE Sistema SHALL admitir un máximo de dos (2) cuentas con rol de Superadministrador.
2. IF se intenta asignar el rol de Superadministrador cuando ya existen dos (2) Superadministradores, THEN THE Servicio_Administracion SHALL rechazar la asignación y devolver un mensaje que indique que se ha alcanzado el número máximo de superadministradores.
3. WHILE un usuario tiene una Sesion activa como Superadministrador, THE Servicio_Administracion SHALL conceder acceso a las operaciones de gestión de usuarios.
4. IF un Usuario con rol estándar intenta acceder a una operación de gestión de usuarios, THEN THE Servicio_Administracion SHALL denegar el acceso y devolver un mensaje de autorización insuficiente.

### Requirement 6: Gestión de usuarios por superadministradores

**User Story:** Como superadministrador, quiero gestionar las cuentas de los usuarios, para mantener el padrón del gimnasio al día.

#### Acceptance Criteria

1. WHILE un Superadministrador tiene una Sesion activa, THE Servicio_Administracion SHALL permitir consultar la lista de Usuarios con su nombre, apellidos, correo electrónico, Estado_Usuario y Saldo_De_Clases.
2. WHEN un Superadministrador solicita dar de baja a un Usuario activo, THE Servicio_Administracion SHALL establecer el Estado_Usuario de ese Usuario en "suspendido".
3. WHEN un Superadministrador solicita reactivar a un Usuario suspendido, THE Servicio_Administracion SHALL establecer el Estado_Usuario de ese Usuario en "activo".
4. WHEN un Superadministrador solicita eliminar a un Usuario, THE Servicio_Administracion SHALL eliminar el registro de ese Usuario de la base de datos.
5. WHEN un Superadministrador solicita restablecer el Bono de un Usuario, THE Servicio_Bono SHALL establecer el Saldo_De_Clases de ese Usuario en diez (10).
6. WHEN un Superadministrador solicita ajustar el Saldo_De_Clases de un Usuario a un valor entre cero (0) y diez (10), THE Servicio_Bono SHALL establecer el Saldo_De_Clases de ese Usuario en el valor indicado.
7. IF un Superadministrador solicita eliminar su propia cuenta de Superadministrador, THEN THE Servicio_Administracion SHALL rechazar la operación y devolver un mensaje que indique que un superadministrador no puede eliminarse a sí mismo.

### Requirement 7: Seguridad y control de acceso a datos

**User Story:** Como propietario del gimnasio, quiero que los datos de los usuarios estén protegidos, para cumplir con la privacidad y seguridad de la información.

#### Acceptance Criteria

1. THE Servicio_Autenticacion SHALL almacenar las contraseñas únicamente como Contraseña_Cifrada mediante hash.
2. IF una petición de datos de un Usuario proviene de una Sesion que no corresponde al propio Usuario ni a un Superadministrador, THEN THE Servicio_Usuarios SHALL denegar la petición y devolver un mensaje de autorización insuficiente.
3. WHILE un cliente no dispone de una Sesion activa, THE Servicio_Usuarios SHALL denegar el acceso a los datos de cualquier Usuario.

### Requirement 8: Reserva de clases con calendario y aforo

**User Story:** Como usuario del gimnasio, quiero reservar plaza en las clases del calendario, para asegurar mi asistencia consumiendo las clases de mi bono.

#### Acceptance Criteria

1. WHILE un Superadministrador tiene una Sesion activa, THE Servicio_Reservas SHALL permitir crear, editar y eliminar Clases del calendario, cada una con Horario_Clase, Aforo máximo (entero mayor o igual que uno (1) y menor o igual que el límite configurable del Sistema, cuyo valor actual es diez (10)) y Monitor asignado.
2. IF un Usuario con rol estándar intenta crear, editar o eliminar una Clase del calendario, THEN THE Servicio_Reservas SHALL denegar la operación y devolver un mensaje de autorización insuficiente, sin modificar la Clase.
3. WHEN un Usuario con Sesion activa reserva plaza en una Clase cuyo Aforo no está completo y cuyo Saldo_De_Clases es mayor que cero (0), THE Servicio_Reservas SHALL crear una Reserva_Confirmada para ese Usuario en esa Clase y THE Servicio_Bono SHALL reducir el Saldo_De_Clases del Usuario en una (1) clase.
4. IF un Usuario con Sesion activa intenta reservar plaza en una Clase cuando su Saldo_De_Clases es igual a cero (0), THEN THE Servicio_Reservas SHALL rechazar la reserva, no crear ninguna Reserva ni entrada en Lista_De_Espera, y devolver un mensaje que indique que no quedan clases en el bono.
5. WHEN un Usuario con Sesion activa reserva plaza en una Clase cuyo Aforo ya está completo y cuyo Saldo_De_Clases es mayor que cero (0), THE Servicio_Reservas SHALL añadir al Usuario al final de la Lista_De_Espera de esa Clase sin modificar su Saldo_De_Clases.
6. IF un Usuario con Sesion activa intenta reservar plaza en una Clase en la que ya tiene una Reserva o figura en la Lista_De_Espera, THEN THE Servicio_Reservas SHALL rechazar la solicitud, no crear una reserva o entrada duplicada, y devolver un mensaje que indique que ya existe una reserva para esa Clase.
7. WHEN un Usuario con una Reserva_Confirmada cancela su Reserva con dos (2) horas o más de antelación respecto al Horario_Clase, THE Servicio_Reservas SHALL liberar la plaza del Usuario en esa Clase y THE Servicio_Bono SHALL incrementar el Saldo_De_Clases del Usuario en una (1) clase.
8. WHEN un Usuario con una Reserva_Confirmada cancela su Reserva con menos de dos (2) horas de antelación respecto al Horario_Clase, THE Servicio_Reservas SHALL liberar la plaza del Usuario en esa Clase sin modificar su Saldo_De_Clases.
9. WHEN se libera una plaza en una Clase y la Lista_De_Espera de esa Clase contiene al menos un Usuario cuyo Saldo_De_Clases es mayor que cero (0), THE Servicio_Reservas SHALL promocionar al primer Usuario de la Lista_De_Espera a Reserva_Confirmada en esa Clase y THE Servicio_Bono SHALL reducir el Saldo_De_Clases de ese Usuario en una (1) clase.
10. THE Servicio_Bono SHALL mantener el Saldo_De_Clases dentro del rango de cero (0) a diez (10) ambos inclusive tras cualquier reserva, cancelación o reembolso.
11. WHEN un Usuario que figura en la Lista_De_Espera de una Clase cancela su solicitud, THE Servicio_Reservas SHALL eliminar al Usuario de la Lista_De_Espera de esa Clase sin modificar su Saldo_De_Clases.
12. IF un Usuario con Sesion activa intenta reservar plaza en una Clase cuyo Aforo está completo y cuya Lista_De_Espera ya contiene veinte (20) Usuarios, THEN THE Servicio_Reservas SHALL rechazar la solicitud y devolver un mensaje que indique que la Lista_De_Espera está completa.

### Requirement 9: Recuperación de contraseña

**User Story:** Como usuario registrado, quiero recuperar mi contraseña cuando la olvide proporcionando mi correo electrónico, para poder recuperar el acceso a mi cuenta de forma segura.

#### Acceptance Criteria

1. WHEN un Usuario solicita restablecer su contraseña proporcionando un correo electrónico, THE Servicio_Autenticacion SHALL devolver siempre un mensaje genérico que indique que, si el correo electrónico existe, se ha enviado un enlace de restablecimiento, con independencia de si el correo electrónico está asociado a una cuenta.
2. WHEN un Usuario solicita restablecer su contraseña con un correo electrónico asociado a una cuenta existente, THE Servicio_Autenticacion SHALL enviar a ese correo electrónico un enlace que contenga un Token_Restablecimiento.
3. THE Servicio_Autenticacion SHALL asignar a cada Token_Restablecimiento una caducidad de sesenta (60) minutos desde el momento de su emisión.
4. IF se presenta un Token_Restablecimiento cuya caducidad ya ha transcurrido, THEN THE Servicio_Autenticacion SHALL rechazar el restablecimiento y devolver un mensaje que indique que el enlace es inválido o ha caducado.
5. IF se presenta un Token_Restablecimiento que ya fue utilizado en un restablecimiento previo, THEN THE Servicio_Autenticacion SHALL rechazar el restablecimiento y devolver un mensaje que indique que el enlace es inválido o ha caducado.
6. IF un Usuario establece una nueva contraseña con menos de ocho (8) caracteres durante el restablecimiento, THEN THE Servicio_Autenticacion SHALL rechazar el restablecimiento y devolver un mensaje de error de longitud de contraseña.
7. WHEN un Usuario establece una nueva contraseña válida mediante un Token_Restablecimiento vigente y no utilizado, THE Servicio_Autenticacion SHALL almacenar la nueva contraseña como Contraseña_Cifrada mediante hash.
8. WHEN se completa correctamente un restablecimiento de contraseña de un Usuario, THE Servicio_Autenticacion SHALL invalidar toda Sesion previa de ese Usuario.
9. WHEN se completa correctamente un restablecimiento de contraseña de un Usuario, THE Servicio_Autenticacion SHALL marcar el Token_Restablecimiento utilizado como consumido.
10. IF un Usuario con Estado_Usuario igual a "suspendido" presenta un Token_Restablecimiento para establecer una nueva contraseña, THEN THE Servicio_Autenticacion SHALL rechazar el restablecimiento y devolver un mensaje que indique que la cuenta está suspendida.
