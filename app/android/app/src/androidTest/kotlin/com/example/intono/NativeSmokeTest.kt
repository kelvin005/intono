package com.example.intono

import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

/** Runs on the CI emulator, which has no audio device (-no-audio): library load, JNI and the engine only (ADR 0009). */
@RunWith(AndroidJUnit4::class)
class NativeSmokeTest {
    @Test fun theLibraryLoadsAndTheEngineRunsThroughJni() {
        assertTrue(NativeAudio().smokeTest())
    }

    @Test fun stoppedMeansStopped() {
        val a = NativeAudio()
        assertEquals("stopped", a.info())
        assertEquals(0L, a.enginePointer())
        a.stop()   // harmless
    }
}
