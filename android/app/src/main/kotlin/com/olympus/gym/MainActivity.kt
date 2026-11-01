package com.olympus.gym

import android.app.NotificationChannel
import android.app.NotificationManager
import android.os.Build
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        crearCanalReservas()
    }

    /**
     * Crea el canal de notificaciones "Reservas" (Android 8+).
     *
     * Las notificaciones push de FCM indican `channel_id = "reservas"` y el
     * manifest lo declara como canal por defecto. Importancia alta para que el
     * aviso de "ya tienes plaza" aparezca como notificación emergente. Crear un
     * canal que ya existe no tiene efecto, así que es seguro llamarlo siempre.
     */
    private fun crearCanalReservas() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val canal = NotificationChannel(
            CANAL_RESERVAS,
            "Reservas",
            NotificationManager.IMPORTANCE_HIGH,
        ).apply {
            description = "Avisos sobre tus reservas, como conseguir plaza " +
                "desde la lista de espera."
        }
        getSystemService(NotificationManager::class.java)
            ?.createNotificationChannel(canal)
    }

    private companion object {
        const val CANAL_RESERVAS = "reservas"
    }
}
