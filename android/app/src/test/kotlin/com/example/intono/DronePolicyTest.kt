package com.example.intono

import android.media.AudioDeviceInfo
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class DronePolicyTest {
    @Test fun offByDefaultWithoutHeadphones() {
        val d = DronePolicy.decide(userChoice = null, headphones = false)
        assertFalse(d.play); assertFalse(d.warnSpeaker)
    }

    @Test fun onByDefaultWithHeadphonesAndNoWarning() {
        val d = DronePolicy.decide(null, true)
        assertTrue(d.play); assertFalse(d.warnSpeaker)
    }

    @Test fun userTurningItOnWithoutHeadphonesPlaysAndWarns() {
        val d = DronePolicy.decide(true, false)
        assertTrue(d.play); assertTrue(d.warnSpeaker)
    }

    @Test fun userTurningItOffWithHeadphonesStaysOff() {
        val d = DronePolicy.decide(false, true)
        assertFalse(d.play); assertFalse(d.warnSpeaker)
    }

    @Test fun unpluggingHeadphonesSwitchesADefaultOnDroneOffButKeepsAUserChoice() {
        assertFalse(DronePolicy.decide(null, false).play)
        assertTrue(DronePolicy.decide(true, false).play)
    }

    @Test fun theWarningTextIsTheOneKelechiAsked() {
        assertEquals("Use headphones for accurate results", DronePolicy.SPEAKER_WARNING)
    }

    @Test fun headphoneLikeOutputsAreRecognisedAndTheSpeakerIsNot() {
        for (t in intArrayOf(
            AudioDeviceInfo.TYPE_WIRED_HEADPHONES, AudioDeviceInfo.TYPE_WIRED_HEADSET, AudioDeviceInfo.TYPE_USB_HEADSET,
            AudioDeviceInfo.TYPE_BLUETOOTH_A2DP, AudioDeviceInfo.TYPE_BLUETOOTH_SCO, AudioDeviceInfo.TYPE_BLE_HEADSET,
            AudioDeviceInfo.TYPE_HEARING_AID,
        )) assertTrue("type $t", HeadphoneMonitor.isHeadphoneType(t))
        for (t in intArrayOf(AudioDeviceInfo.TYPE_BUILTIN_SPEAKER, AudioDeviceInfo.TYPE_BUILTIN_EARPIECE, AudioDeviceInfo.TYPE_HDMI))
            assertFalse("type $t", HeadphoneMonitor.isHeadphoneType(t))
    }
}
