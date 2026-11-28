package com.example.intono

import android.content.Context
import android.speech.tts.TextToSpeech
import java.util.Locale

/**
 * The spoken summary after a run (ADR 0017): the system text-to-speech engine. Dart asks for speech only after the run's capture has
 * ended, so the microphone is already off whenever this speaks. A voice that needs no network is chosen when the device language has one.
 */
class Speech(context: Context) {
    private var ready = false
    private val tts: TextToSpeech = TextToSpeech(context.applicationContext) { status -> ready = status == TextToSpeech.SUCCESS }

    fun speak(text: String): Boolean {
        if (!ready) return false
        val lang = Locale.getDefault().language
        tts.voices?.firstOrNull { !it.isNetworkConnectionRequired && it.locale.language == lang }?.let { tts.voice = it }
        return tts.speak(text, TextToSpeech.QUEUE_FLUSH, null, "intono-summary") == TextToSpeech.SUCCESS
    }

    fun stop() {
        tts.stop()
    }

    fun shutdown() {
        tts.stop()
        tts.shutdown()
    }
}
