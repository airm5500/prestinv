package com.dici.prestinv

import android.content.Context
import android.content.pm.PackageManager
import android.media.AudioManager
import android.media.ToneGenerator
import android.os.Build
import android.os.VibrationEffect
import android.os.Vibrator
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Retour sonore et vibration après un scan (canal « prestinv/retour », voir lib/scan/retour_scan.dart).
 * Bip court = succès, double bip = déjà compté, bip long = erreur. Aucune autorisation dangereuse :
 * VIBRATE est une autorisation « normale » (accordée à l'installation).
 */
class MainActivity : FlutterActivity() {
    private var tonalites: ToneGenerator? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "prestinv/retour").setMethodCallHandler { call, result ->
            val type = call.argument<String>("type") ?: "succes"
            try {
                when (call.method) {
                    "bip" -> { bip(type); result.success(null) }
                    "vibrer" -> { vibrer(type); result.success(null) }
                    else -> result.notImplemented()
                }
            } catch (e: Exception) {
                // Le retour n'est qu'une aide : son échec ne doit jamais gêner la saisie.
                result.success(null)
            }
        }
        // 4.14 : présence d'un appareil photo (lib/scan/camera/scan_camera.dart) — sans appareil photo, le
        // bouton de scan par l'appareil photo n'est pas affiché. Aucune autorisation nécessaire.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "prestinv/appareil").setMethodCallHandler { call, result ->
            when (call.method) {
                "cameraPresente" -> result.success(packageManager.hasSystemFeature(PackageManager.FEATURE_CAMERA_ANY))
                else -> result.notImplemented()
            }
        }
    }

    private fun bip(type: String) {
        val t = tonalites ?: ToneGenerator(AudioManager.STREAM_NOTIFICATION, 90).also { tonalites = it }
        when (type) {
            "dejaCompte" -> t.startTone(ToneGenerator.TONE_PROP_BEEP2, 300)
            "erreur" -> t.startTone(ToneGenerator.TONE_SUP_ERROR, 700)
            else -> t.startTone(ToneGenerator.TONE_PROP_BEEP, 120)
        }
    }

    @Suppress("DEPRECATION")
    private fun vibrer(type: String) {
        val v = getSystemService(Context.VIBRATOR_SERVICE) as? Vibrator ?: return
        if (!v.hasVibrator()) return
        val motif = when (type) {
            "dejaCompte" -> longArrayOf(0, 60, 90, 60)
            "erreur" -> longArrayOf(0, 450)
            else -> longArrayOf(0, 40)
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            v.vibrate(VibrationEffect.createWaveform(motif, -1))
        } else {
            v.vibrate(motif, -1)
        }
    }

    override fun onDestroy() {
        tonalites?.release()
        tonalites = null
        super.onDestroy()
    }
}
