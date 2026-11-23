package com.example.intono

import android.Manifest
import android.app.Activity
import android.content.pm.PackageManager
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.view.ViewGroup
import android.widget.Button
import android.widget.LinearLayout
import android.widget.Switch
import android.widget.TextView

/** Phase 2 PR 2 harness: starts and stops capture, shows the stream facts, and exercises the drone policy. The Flutter UI replaces it. */
class MainActivity : Activity() {
    private val audio = NativeAudio()
    private lateinit var monitor: HeadphoneMonitor
    private lateinit var status: TextView
    private lateinit var droneSwitch: Switch
    private var userDrone: Boolean? = null
    private var headphones = false
    private val ui = Handler(Looper.getMainLooper())
    private val tick = object : Runnable {
        override fun run() {
            refresh()
            ui.postDelayed(this, 1000)
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val pad = (16 * resources.displayMetrics.density).toInt()
        val root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(pad, pad, pad, pad)
        }
        status = TextView(this).apply { textSize = 14f }
        val toggle = Button(this).apply {
            text = "Start / stop capture"
            setOnClickListener { if (audio.running) audio.stop() else startCapture() }
        }
        droneSwitch = Switch(this).apply {
            text = "Drone"
            setOnCheckedChangeListener { v, checked -> if (v.isPressed) { userDrone = checked; applyDrone() } }
        }
        root.addView(toggle, ViewGroup.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT))
        root.addView(droneSwitch)
        root.addView(status)
        setContentView(root)
        monitor = HeadphoneMonitor(this) { connected -> headphones = connected; applyDrone(); refresh() }
        headphones = monitor.connected()
    }

    override fun onStart() {
        super.onStart()
        monitor.start()
        ui.post(tick)
    }

    override fun onStop() {
        ui.removeCallbacks(tick)
        monitor.stop()
        audio.stop()   // never record in the background
        super.onStop()
    }

    private fun startCapture() {
        if (checkSelfPermission(Manifest.permission.RECORD_AUDIO) != PackageManager.PERMISSION_GRANTED) {
            requestPermissions(arrayOf(Manifest.permission.RECORD_AUDIO), 1)
            return
        }
        audio.start()
        applyDrone()
        refresh()
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        if (requestCode == 1 && grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED) startCapture() else refresh()
    }

    private fun applyDrone() {
        val d = DronePolicy.decide(userDrone, headphones)
        if (audio.running) audio.setDrone(d.play)
        droneSwitch.isChecked = d.play
    }

    private fun refresh() {
        val d = DronePolicy.decide(userDrone, headphones)
        if (audio.running && !audio.healthy()) { audio.stop(); audio.start(); applyDrone() }   // route change: restart the streams
        val sb = StringBuilder()
        sb.append("headphones: ").append(headphones).append('\n')
        if (d.warnSpeaker) sb.append(DronePolicy.SPEAKER_WARNING).append('\n')
        sb.append(audio.info())
        if (!audio.running && audio.lastError.isNotEmpty()) sb.append("\nerror: ").append(audio.lastError)
        status.text = sb.toString()
    }
}
