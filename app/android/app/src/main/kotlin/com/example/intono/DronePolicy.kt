package com.example.intono

/**
 * Drone policy (ADR 0009, Kelechi 2026-11-23): the drone is off by default and is on by default only when headphones are connected.
 * The user can override either way. If it plays on the phone speaker the screen warns, because the drone then leaks into the
 * microphone (notch filtering is Phase 3).
 */
object DronePolicy {
    const val SPEAKER_WARNING = "Use headphones for accurate results"

    data class Decision(val play: Boolean, val warnSpeaker: Boolean)

    /** [userChoice]: null while the user has not touched the switch. */
    fun decide(userChoice: Boolean?, headphones: Boolean): Decision {
        val play = userChoice ?: headphones
        return Decision(play = play, warnSpeaker = play && !headphones)
    }
}
