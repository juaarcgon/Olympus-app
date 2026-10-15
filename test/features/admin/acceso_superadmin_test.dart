// Pruebas unitarias de acceso de superadmin al Servicio_Administracion.
//
// Tarea 10.9: acceso de superadmin a gestión (Req 5.3) y listado de usuarios
// (Req 6.1).
//
// Req 5.3: "WHILE un usuario tiene una Sesion activa como Superadministrador,
//           THE Servicio_Administracion SHALL conceder acceso a las operaciones
//           de gestión de usuarios."
// Req 6.1: "WHILE un Superadministrador tiene una Sesion activa,
//           THE Servicio_Administracion SHALL permitir consultar la lista de
//           Usuarios con su nombre, apellidos, correo electrónico,
//           Estado_Usuario y Saldo_De_Clases."
//
// Son pruebas de cliente con una fuente de datos falsa que sustituye a Supabase
// (sin red), siguiendo el patrón de `reservas_repository_impl_test.dart`:
//   - El acceso de gestión del superadministrador se verifica contra la guarda
//     de dominio `autorizarGestion` (espejo de `es_superadmin()` del backend) y
//     comprobando que cada operación del `AdminRepository` es alcanzable/
//     autorizada para una sesión de superadministrador (no lanza fallo de
//     autorización, delega en la fuente de datos).
//   - El listado de usuarios se verifica mapeando filas crudas de `profiles` a
//     la entidad [Profile] y comprobando que expone los cinco campos exigidos.

import 'package:flutter_test/flutter_test.dart';
import 'package:olympus/core/error/error.dart';
import 'package:olympus/features/admin/data/datasources/admin_remote_datasource.dart';
import 'package:olympus/features/admin/data/repositories/admin_repository_impl.dart';
import 'package:olympus/features/admin/domain/admin_authorization.dart';
import 'package:olympus/features/profile/domain/entities/profile.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Fuente de datos falsa: devuelve lo configurado o lanza la excepción
/// configurada, sin contactar con Supabase. Registra las llamadas recibidas
/// para poder afirmar que cada operación de gestión es alcanzable.
class _FakeAdminDataSource extends AdminRemoteDataSource {
  _FakeAdminDataSource()
    : super(client: SupabaseClient('http://localhost', 'anon'));

  List<Map<String, dynamic>> usuarios = <Map<String, dynamic>>[];
  Object? errorToThrow;

  // Registro de llamadas para aserciones de alcanzabilidad (Req 5.3).
  bool fetchLlamado = false;
  bool suspenderLlamado = false;
  bool reactivarLlamado = false;
  bool eliminarLlamado = false;
  bool restablecerBonoLlamado = false;
  bool ajustarBonoLlamado = false;
  bool concederSuperadminLlamado = false;
  String? ultimoUserId;
  int? ultimoValorAjuste;

  void _maybeThrow() {
    final error = errorToThrow;
    if (error != null) throw error;
  }

  @override
  Future<List<Map<String, dynamic>>> fetchUsers() async {
    fetchLlamado = true;
    _maybeThrow();
    return usuarios;
  }

  @override
  Future<void> suspenderUsuario(String targetUserId) async {
    suspenderLlamado = true;
    ultimoUserId = targetUserId;
    _maybeThrow();
  }

  @override
  Future<void> reactivarUsuario(String targetUserId) async {
    reactivarLlamado = true;
    ultimoUserId = targetUserId;
    _maybeThrow();
  }

  @override
  Future<void> eliminarUsuario(String targetUserId) async {
    eliminarLlamado = true;
    ultimoUserId = targetUserId;
    _maybeThrow();
  }

  @override
  Future<void> restablecerBono(String targetUserId) async {
    restablecerBonoLlamado = true;
    ultimoUserId = targetUserId;
    _maybeThrow();
  }

  @override
  Future<void> ajustarBono(String targetUserId, int valor) async {
    ajustarBonoLlamado = true;
    ultimoUserId = targetUserId;
    ultimoValorAjuste = valor;
    _maybeThrow();
  }

  @override
  Future<void> concederSuperadmin(String targetUserId) async {
    concederSuperadminLlamado = true;
    ultimoUserId = targetUserId;
    _maybeThrow();
  }
}

Map<String, dynamic> _usuarioRow({
  String id = 'u1',
  String nombre = 'Ana',
  String apellidos = 'García',
  String email = 'ana@example.com',
  String estado = 'activo',
  int saldoClases = 8,
  String rol = 'usuario',
}) {
  return <String, dynamic>{
    'id': id,
    'nombre': nombre,
    'apellidos': apellidos,
    'foto_url': null,
    'email': email,
    'saldo_clases': saldoClases,
    'estado': estado,
    'rol': rol,
    'metadata': <String, dynamic>{},
    'created_at': '2025-01-01T00:00:00.000Z',
  };
}

void main() {
  late _FakeAdminDataSource fake;
  late AdminRepositoryImpl repo;

  setUp(() {
    fake = _FakeAdminDataSource();
    repo = AdminRepositoryImpl(dataSource: fake);
  });

  group('Req 5.3 - el superadministrador tiene acceso a las operaciones de '
      'gestión', () {
    test('la guarda de dominio autoriza al superadministrador en TODAS las '
        'operaciones de gestión', () {
      // WHILE sesión de superadministrador -> acceso concedido a toda
      // operación de gestión (autorizar devuelve null = permitido).
      for (final operacion in OperacionGestion.values) {
        expect(
          autorizarGestion(RolUsuario.superadmin, operacion),
          isNull,
          reason:
              'el superadministrador debe tener acceso a la operación '
              '$operacion (Req 5.3)',
        );
      }
    });

    test(
      'cada operación de gestión del AdminRepository es alcanzable para una '
      'sesión de superadministrador y delega en la fuente de datos',
      () async {
        // Sin errores configurados: simula una sesión de superadministrador
        // cuyas RPC `SECURITY DEFINER` superan la validación `es_superadmin()`.
        await repo.suspendUser('u1');
        await repo.reactivateUser('u2');
        await repo.deleteUser('u3');
        await repo.restablecerBono('u4');
        await repo.ajustarBono('u5', 5);
        await repo.grantSuperadmin('u6');

        expect(fake.suspenderLlamado, isTrue);
        expect(fake.reactivarLlamado, isTrue);
        expect(fake.eliminarLlamado, isTrue);
        expect(fake.restablecerBonoLlamado, isTrue);
        expect(fake.ajustarBonoLlamado, isTrue);
        expect(fake.ultimoValorAjuste, 5);
        expect(fake.concederSuperadminLlamado, isTrue);
      },
    );

    test('una operación de gestión completa sin lanzar fallo de autorización '
        'cuando el backend acepta al superadministrador (Req 5.3)', () async {
      // No se configura ninguna excepción: la operación debe completar.
      await expectLater(repo.suspendUser('u1'), completes);
      expect(fake.ultimoUserId, 'u1');
    });
  });

  group('Req 6.1 - listado de usuarios con los campos exigidos', () {
    test(
      'listUsers devuelve los Usuarios con nombre, apellidos, email, estado y '
      'saldo_clases',
      () async {
        fake.usuarios = [
          _usuarioRow(
            id: 'u1',
            nombre: 'Ana',
            apellidos: 'García',
            email: 'ana@example.com',
            estado: 'activo',
            saldoClases: 8,
          ),
          _usuarioRow(
            id: 'u2',
            nombre: 'Luis',
            apellidos: 'Pérez',
            email: 'luis@example.com',
            estado: 'suspendido',
            saldoClases: 0,
          ),
        ];

        final usuarios = await repo.listUsers();

        expect(fake.fetchLlamado, isTrue);
        expect(usuarios, hasLength(2));

        final ana = usuarios.first;
        expect(ana.nombre, 'Ana');
        expect(ana.apellidos, 'García');
        expect(ana.email, 'ana@example.com');
        expect(ana.estado, EstadoUsuario.activo);
        expect(ana.saldoClases, 8);

        final luis = usuarios[1];
        expect(luis.nombre, 'Luis');
        expect(luis.apellidos, 'Pérez');
        expect(luis.email, 'luis@example.com');
        expect(luis.estado, EstadoUsuario.suspendido);
        expect(luis.saldoClases, 0);
      },
    );

    test('listUsers devuelve una lista vacía cuando no hay usuarios', () async {
      fake.usuarios = <Map<String, dynamic>>[];

      final usuarios = await repo.listUsers();

      expect(fake.fetchLlamado, isTrue);
      expect(usuarios, isEmpty);
    });

    test('sin sesión / sin autorización el listado produce '
        'AutorizacionInsuficienteFailure (contraste con Req 5.3/7.3)', () {
      fake.errorToThrow = PostgrestException(
        message: 'jwt expired',
        code: 'PGRST301',
      );

      expect(
        () => repo.listUsers(),
        throwsA(isA<AutorizacionInsuficienteFailure>()),
      );
    });
  });
}
