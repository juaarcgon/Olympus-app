// Obtención de un access token de Google OAuth 2.0 a partir de la cuenta de
// servicio de Firebase, para llamar a la API HTTP v1 de Firebase Cloud
// Messaging. Implementado solo con Web Crypto (sin dependencias externas).
//
// Flujo "JWT bearer" (RFC 7523): se firma con RS256 un JWT con la clave privada
// de la cuenta de servicio y se intercambia en oauth2.googleapis.com por un
// access token de 1 hora, que se cachea en memoria.

const FCM_SCOPE = "https://www.googleapis.com/auth/firebase.messaging";
const TOKEN_URL = "https://oauth2.googleapis.com/token";

/**
 * Codifica en base64url (sin relleno) un texto o unos bytes.
 * @param {string | Uint8Array} data
 * @returns {string}
 */
export function base64url(data) {
  const bytes = typeof data === "string" ? new TextEncoder().encode(data) : data;
  let binario = "";
  for (const b of bytes) binario += String.fromCharCode(b);
  return btoa(binario).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

/**
 * Importa la clave privada PEM (PKCS#8) de la cuenta de servicio.
 * @param {string} pem
 * @returns {Promise<CryptoKey>}
 */
async function importarClavePrivada(pem) {
  const cuerpo = pem
    .replace(/-----BEGIN PRIVATE KEY-----/, "")
    .replace(/-----END PRIVATE KEY-----/, "")
    .replace(/\\n/g, "")
    .replace(/\s+/g, "");
  const der = Uint8Array.from(atob(cuerpo), (c) => c.charCodeAt(0));
  return await crypto.subtle.importKey(
    "pkcs8",
    der,
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"],
  );
}

/**
 * Crea y firma (RS256) el JWT de la cuenta de servicio.
 * @param {{ client_email: string, private_key: string }} cuenta
 * @param {number} ahora Segundos desde epoch.
 * @returns {Promise<string>}
 */
export async function crearJwtFirmado(cuenta, ahora) {
  const cabecera = base64url(JSON.stringify({ alg: "RS256", typ: "JWT" }));
  const claims = base64url(
    JSON.stringify({
      iss: cuenta.client_email,
      scope: FCM_SCOPE,
      aud: TOKEN_URL,
      iat: ahora,
      exp: ahora + 3600,
    }),
  );
  const clave = await importarClavePrivada(cuenta.private_key);
  const firma = await crypto.subtle.sign(
    "RSASSA-PKCS1-v1_5",
    clave,
    new TextEncoder().encode(`${cabecera}.${claims}`),
  );
  return `${cabecera}.${claims}.${base64url(new Uint8Array(firma))}`;
}

/** @type {{ valor: string, expira: number } | null} */
let cache = null;

/**
 * Devuelve un access token válido para FCM, reutilizando el cacheado mientras
 * le quede más de un minuto de vida.
 * @param {{ client_email: string, private_key: string }} cuenta
 * @returns {Promise<string>}
 */
export async function obtenerAccessToken(cuenta) {
  const ahora = Math.floor(Date.now() / 1000);
  if (cache && cache.expira - 60 > ahora) return cache.valor;

  const jwt = await crearJwtFirmado(cuenta, ahora);
  const respuesta = await fetch(TOKEN_URL, {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion: jwt,
    }),
  });
  if (!respuesta.ok) {
    throw new Error(`OAuth de Google ${respuesta.status}: ${await respuesta.text()}`);
  }
  const json = await respuesta.json();
  cache = { valor: json.access_token, expira: ahora + (json.expires_in ?? 3600) };
  return cache.valor;
}
