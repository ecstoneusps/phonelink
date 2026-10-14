// PhoneLink addition: BLE advertising for connectionless ("broadcast") toys.
//
// Intiface's Bluetooth stack (btleplug) can only scan and connect, so toys that
// are controlled by listening for advertisements (LoveSpouse, MuSE, ...) need
// the phone itself to broadcast. This channel is deliberately generic: Dart
// decides *what* to send (a list of 16-bit service UUIDs), Kotlin just puts it
// on the air and keeps it there until told otherwise.
package com.nonpolynomial.intiface_central

import android.bluetooth.BluetoothManager
import android.bluetooth.le.AdvertiseData
import android.bluetooth.le.AdvertisingSet
import android.bluetooth.le.AdvertisingSetCallback
import android.bluetooth.le.AdvertisingSetParameters
import android.bluetooth.le.BluetoothLeAdvertiser
import android.content.Context
import android.os.ParcelUuid
import android.util.Log
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.UUID

object PhoneLinkBroadcast {
  private const val TAG = "PhoneLinkBroadcast"
  private const val CHANNEL_NAME = "phonelink/broadcast"

  private var advertiser: BluetoothLeAdvertiser? = null
  private var currentSet: AdvertisingSet? = null
  private var callback: AdvertisingSetCallback? = null
  private var starting = false
  private var pendingData: AdvertiseData? = null

  fun register(context: Context, flutterEngine: FlutterEngine) {
    MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL_NAME)
      .setMethodCallHandler { call, result ->
        when (call.method) {
          "advertiseServiceUuids" -> {
            val uuids = call.argument<List<Int>>("uuid16")
            if (uuids == null) {
              result.error("bad_args", "uuid16 list is required", null)
            } else {
              result.success(advertise(context.applicationContext, uuids))
            }
          }
          "stop" -> {
            stop()
            result.success(true)
          }
          else -> result.notImplemented()
        }
      }
  }

  private fun uuid16(value: Int): ParcelUuid =
    ParcelUuid(UUID.fromString(String.format("%08x-0000-1000-8000-00805f9b34fb", value and 0xFFFF)))

  private fun buildData(uuids: List<Int>): AdvertiseData {
    val builder = AdvertiseData.Builder()
      .setIncludeDeviceName(false)
      .setIncludeTxPowerLevel(false)
    // Order matters: the receiving toy reads these as a raw byte string.
    for (u in uuids) builder.addServiceUuid(uuid16(u))
    return builder.build()
  }

  /** Returns null on success, or a short error description. */
  @Synchronized
  private fun advertise(context: Context, uuids: List<Int>): String? {
    val data = buildData(uuids)
    try {
      val set = currentSet
      if (set != null) {
        set.setAdvertisingData(data)
        return null
      }
      if (starting) {
        pendingData = data
        return null
      }

      val manager = context.getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager
      val adapter = manager?.adapter ?: return "Bluetooth unavailable"
      if (!adapter.isEnabled) return "Bluetooth is off"
      val adv = adapter.bluetoothLeAdvertiser ?: return "This phone cannot broadcast BLE advertisements"
      advertiser = adv

      val params = AdvertisingSetParameters.Builder()
        .setLegacyMode(true)
        .setConnectable(false)
        .setScannable(false)
        .setInterval(AdvertisingSetParameters.INTERVAL_MIN)
        .setTxPowerLevel(AdvertisingSetParameters.TX_POWER_HIGH)
        .build()

      val cb = object : AdvertisingSetCallback() {
        override fun onAdvertisingSetStarted(advertisingSet: AdvertisingSet?, txPower: Int, status: Int) {
          synchronized(this@PhoneLinkBroadcast) {
            starting = false
            if (status == AdvertisingSetCallback.ADVERTISE_SUCCESS && advertisingSet != null) {
              currentSet = advertisingSet
              pendingData?.let { advertisingSet.setAdvertisingData(it) }
            } else {
              Log.e(TAG, "Advertising failed to start, status $status")
              callback = null
            }
            pendingData = null
          }
        }

        override fun onAdvertisingSetStopped(advertisingSet: AdvertisingSet?) {
          synchronized(this@PhoneLinkBroadcast) {
            if (currentSet == advertisingSet) currentSet = null
          }
        }
      }
      callback = cb
      starting = true
      adv.startAdvertisingSet(params, data, null, null, null, cb)
      return null
    } catch (e: SecurityException) {
      starting = false
      Log.e(TAG, "Missing Bluetooth advertise permission", e)
      return "Missing Bluetooth advertise permission"
    } catch (e: RuntimeException) {
      starting = false
      Log.e(TAG, "Advertising error", e)
      return e.message ?: "Advertising error"
    }
  }

  @Synchronized
  fun stop() {
    try {
      callback?.let { advertiser?.stopAdvertisingSet(it) }
    } catch (e: SecurityException) {
      Log.e(TAG, "Missing permission while stopping advertising", e)
    } catch (e: RuntimeException) {
      Log.e(TAG, "Error stopping advertising", e)
    }
    callback = null
    currentSet = null
    starting = false
    pendingData = null
  }
}
