package com.example.intono

import android.content.Context
import android.media.AudioDeviceCallback
import android.media.AudioDeviceInfo
import android.media.AudioManager
import android.os.Handler
import android.os.Looper

/** Tells whether the audio output is headphone-like (wired, USB, Bluetooth). Used by [DronePolicy]. */
class HeadphoneMonitor(context: Context, private val onChange: (Boolean) -> Unit) {
    private val audio = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
    private val callback = object : AudioDeviceCallback() {
        override fun onAudioDevicesAdded(addedDevices: Array<out AudioDeviceInfo>) = onChange(connected())
        override fun onAudioDevicesRemoved(removedDevices: Array<out AudioDeviceInfo>) = onChange(connected())
    }

    fun connected(): Boolean = audio.getDevices(AudioManager.GET_DEVICES_OUTPUTS).any { isHeadphoneType(it.type) }

    fun start() = audio.registerAudioDeviceCallback(callback, Handler(Looper.getMainLooper()))
    fun stop() = audio.unregisterAudioDeviceCallback(callback)

    companion object {
        fun isHeadphoneType(type: Int): Boolean = when (type) {
            AudioDeviceInfo.TYPE_WIRED_HEADPHONES,
            AudioDeviceInfo.TYPE_WIRED_HEADSET,
            AudioDeviceInfo.TYPE_USB_HEADSET,
            AudioDeviceInfo.TYPE_BLUETOOTH_A2DP,
            AudioDeviceInfo.TYPE_BLUETOOTH_SCO,
            AudioDeviceInfo.TYPE_BLE_HEADSET,
            AudioDeviceInfo.TYPE_HEARING_AID -> true
            else -> false
        }
    }
}
