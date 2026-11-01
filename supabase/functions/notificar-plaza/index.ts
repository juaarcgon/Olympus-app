// Edge Function: notificar-plaza
//
// La llama el trigger `reservas_notificar_plaza` (migración 0015) cuando una
// reserva pasa de la lista de espera a plaza confirmada. Envía una
// notificación push por Firebase Cloud Messaging (API HTTP v1) a todos los
// móviles registrados del Usuario.
//
// Seguridad:
//   - Se despliega con --no-verify-jwt porque la llama la base de datos, no un
//     Usuario. En su lugar exige la cabecera `x-olympus-secret`, que debe
//     coincidir con el secreto OLYMPUS_PUSH_SECRET (comparación en tiempo
//     constante).
//   - La cuenta de servicio de Firebase llega como secreto
//     FIREBASE_SERVICE_ACCOUNT (el JSON completo). Nunca está en el repo ni en
//     la app.
//
// Secretos necesarios (Supabase → Edge Functions → Secrets):
//   OLYMPUS_PUSH_SECRET, FIREBASE_SERVICE_ACCOUNT
// SUPABASE_URL y SUPABASE_SERVICE_ROLE_KEY los inyecta Supabase.

import { createClient } from "npm:@supabase/supabase-js@2.118.0";
import { obtenerAccessToken } from "./google_oauth.js";

type CuentaServicio = {
  project_id: string;
  client_email: string;
  private_key: string;
};

const SECRETO = Deno.env.get("OLYMPUS_PUSH_SECRET") ?? "";

function leerCuentaServicio(): CuentaServicio | null {
  try {
    const cuenta = JSON.parse(Deno.env.get("FIREBASE_SERVICE_ACCOUNT") ?? "");
    if (cuenta?.project_id && cuenta?.client_email && cuenta?.private_key) {
      return cuenta as CuentaServicio;
    }
  } catch {
    // Se informa más abajo.
  }
  return null;
}

const CUENTA = leerCuentaServicio();

const supabase = createClient(
  Deno.env.get("SUPABASE_URL") ?? "",
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
  { auth: { persistSession: false } },
);

/** Comparación de cadenas en tiempo constante (evita ataques de temporización). */
function igualesSeguro(a: string, b: string): boolean {
  const ea = new TextEncoder().encode(a);
  const eb = new TextEncoder().encode(b);
  let diferencia = ea.length ^ eb.length;
  for (let i = 0; i < Math.max(ea.length, eb.length); i++) {
    diferencia |= (ea[i] ?? 0) ^ (eb[i] ?? 0);
  }
  return diferencia === 0;
}

/** "viernes 31 de octubre a las 18:00", en hora de Madrid. */
function describirClase(horarioIso: string): string {
  const fecha = new Date(horarioIso);
  const dia = new Intl.DateTimeFormat("es-ES", {
    timeZone: "Europe/Madrid",
    weekday: "long",
    day: "numeric",
    month: "long",
  }).format(fecha).replace(",", "");
  const hora = new Intl.DateTimeFormat("es-ES", {
    timeZone: "Europe/Madrid",
    hour: "2-digit",
    minute: "2-digit",
    hour12: false,
  }).format(fecha);
  return `${dia} a las ${hora}`;
}

function json(cuerpo: unknown, status = 200): Response {
  return new Response(JSON.stringify(cuerpo), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

Deno.serve(async (req) => {
  if (req.method !== "POST") return json({ error: "Método no permitido" }, 405);

  if (!SECRETO || !igualesSeguro(req.headers.get("x-olympus-secret") ?? "", SECRETO)) {
    return json({ error: "No autorizado" }, 401);
  }
  if (!CUENTA) {
    console.error("FIREBASE_SERVICE_ACCOUNT no está configurado o no es válido");
    return json({ error: "Configuración incompleta" }, 500);
  }

  let userId: unknown;
  let claseId: unknown;
  try {
    ({ user_id: userId, clase_id: claseId } = await req.json());
  } catch {
    return json({ error: "Cuerpo no válido" }, 400);
  }
  if (typeof userId !== "string" || typeof claseId !== "string") {
    return json({ error: "Faltan user_id o clase_id" }, 400);
  }

  const { data: dispositivos, error: errorDispositivos } = await supabase
    .from("dispositivos_push")
    .select("token")
    .eq("user_id", userId);
  if (errorDispositivos) {
    console.error("Error leyendo dispositivos:", errorDispositivos.message);
    return json({ error: "Error leyendo dispositivos" }, 500);
  }
  if (!dispositivos || dispositivos.length === 0) return json({ enviados: 0 });

  const { data: clase } = await supabase
    .from("clases")
    .select("horario")
    .eq("id", claseId)
    .maybeSingle();

  const titulo = "¡Ya tienes plaza!";
  const cuerpo = clase?.horario
    ? `Has salido de la lista de espera: tienes plaza en la clase del ${describirClase(clase.horario)}.`
    : "Has salido de la lista de espera y ya tienes plaza en tu clase.";

  let accessToken: string;
  try {
    accessToken = await obtenerAccessToken(CUENTA);
  } catch (e) {
    console.error(String(e));
    return json({ error: "No se pudo autenticar con Firebase" }, 502);
  }

  const url = `https://fcm.googleapis.com/v1/projects/${CUENTA.project_id}/messages:send`;
  let enviados = 0;

  for (const { token } of dispositivos) {
    const respuesta = await fetch(url, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${accessToken}`,
      },
      body: JSON.stringify({
        message: {
          // Destino: token de registro de FCM (migración 0016).
          token,
          notification: { title: titulo, body: cuerpo },
          data: { tipo: "plaza_conseguida", clase_id: claseId },
          android: {
            priority: "HIGH",
            notification: { channel_id: "reservas", icon: "ic_stat_olympus" },
          },
          apns: {
            headers: { "apns-priority": "10" },
            payload: { aps: { sound: "default" } },
          },
        },
      }),
    });

    if (respuesta.ok) {
      enviados++;
      continue;
    }

    const detalle = await respuesta.text();
    // Registro caducado o de una app desinstalada: se elimina para no reintentar.
    if (respuesta.status === 404 || detalle.includes("UNREGISTERED")) {
      await supabase.from("dispositivos_push").delete().eq("token", token);
    } else {
      console.error(`FCM ${respuesta.status}: ${detalle}`);
    }
  }

  return json({ enviados });
});
