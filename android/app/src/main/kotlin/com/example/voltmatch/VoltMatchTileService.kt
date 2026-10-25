
package com.example.voltmatch

import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.os.Build
import android.service.quicksettings.Tile
import android.service.quicksettings.TileService

class VoltMatchTileService : TileService() {

    override fun onStartListening() {
        super.onStartListening()
        updateTileState()
    }

    override fun onClick() {
        super.onClick()
        val isRunning = ProbeService.isRunning
        val serviceIntent = Intent(this, ProbeService::class.java)

        if (isRunning) {
            stopService(serviceIntent)
            setTileUi(false)
        } else {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                startForegroundService(serviceIntent)
            } else {
                startService(serviceIntent)
            }
            setTileUi(true)
        }
    }

    private fun setTileUi(active: Boolean) {
        val tile = qsTile ?: return
        tile.state = if (active) Tile.STATE_ACTIVE else Tile.STATE_INACTIVE
        tile.label = "VoltMatch"
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            tile.subtitle = if (active) "Streaming" else "Off"
        }
        tile.updateTile()
    }

    private fun updateTileState() {
        setTileUi(ProbeService.isRunning)
    }

    companion object {
        fun refreshTile(context: Context) {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                requestListeningState(context, ComponentName(context, VoltMatchTileService::class.java))
            }
        }
    }
}