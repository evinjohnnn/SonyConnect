package dev.connect.sony_companion

import android.Manifest
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothSocket
import android.content.pm.PackageManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.UUID

/**
 * Host side of the Flutter transport.
 *
 * The Rust engine owns framing and protocol state; this class only moves bytes
 * over the headphone's RFCOMM service. Sony exposes the control channel under
 * two SDP UUIDs; V2 is tried first, then the V1 fallback.
 */
class MainActivity : FlutterActivity() {
    private var channel: MethodChannel? = null
    private var socket: BluetoothSocket? = null
    private var reader: Thread? = null

    private val main = Handler(Looper.getMainLooper())
    private val serviceV2: UUID = UUID.fromString("956C7B26-D49A-4BA8-B03F-B17D393CB6E2")
    private val serviceV1: UUID = UUID.fromString("96CC203E-5068-46AD-B32D-E316F5E069BA")

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "dev.connect.sony/transport").also {
            it.setMethodCallHandler { call, result ->
                when (call.method) {
                    "listDevices" -> result.success(listDevices())
                    "open" -> open(call.argument<String>("device"), result)
                    "write" -> write(call.argument<ByteArray>("bytes"), result)
                    "close" -> close(result)
                    else -> result.notImplemented()
                }
            }
        }
    }

    private fun hasPermission(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) return true
        return checkSelfPermission(Manifest.permission.BLUETOOTH_CONNECT) ==
            PackageManager.PERMISSION_GRANTED
    }

    private fun requestPermission() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            requestPermissions(arrayOf(Manifest.permission.BLUETOOTH_CONNECT), 41)
        }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == 41 &&
            grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED
        ) {
            channel?.invokeMethod("permission", true)
        }
    }

    private fun adapter(): BluetoothAdapter? = BluetoothAdapter.getDefaultAdapter()

    private fun listDevices(): List<String> {
        if (!hasPermission()) {
            requestPermission()
            return emptyList()
        }
        val a = adapter() ?: return emptyList()
        if (!a.isEnabled) return emptyList()
        return a.bondedDevices
            .mapNotNull { it.name }
            .filter { it.isNotBlank() }
            .sorted()
    }

    private fun open(name: String?, result: MethodChannel.Result) {
        if (name == null) {
            result.error("bad_argument", "missing device name", null)
            return
        }
        if (!hasPermission()) {
            requestPermission()
            result.error("permission", "Bluetooth permission required", null)
            return
        }
        val a = adapter()
        if (a == null || !a.isEnabled) {
            result.error("bluetooth", "Bluetooth is unavailable", null)
            return
        }
        val device = a.bondedDevices.firstOrNull { it.name == name }
        if (device == null) {
            result.error("not_found", "no paired device named $name", null)
            return
        }

        closeQuietly()
        Thread {
            var lastError: Exception? = null
            for (uuid in listOf(serviceV2, serviceV1)) {
                try {
                    val s = device.createRfcommSocketToServiceRecord(uuid)
                    a.cancelDiscovery()
                    s.connect()
                    socket = s
                    startReader(s)
                    main.post { result.success(null) }
                    return@Thread
                } catch (e: Exception) {
                    lastError = e
                    try { socket?.close() } catch (_: Exception) {}
                    socket = null
                }
            }
            main.post {
                result.error("open_failed", lastError?.message ?: "could not open RFCOMM", null)
            }
        }.start()
    }

    private fun startReader(s: BluetoothSocket) {
        reader = Thread {
            val buffer = ByteArray(4096)
            try {
                val input = s.inputStream
                while (socket === s) {
                    val count = input.read(buffer)
                    if (count <= 0) break
                    val bytes = buffer.copyOf(count)
                    main.post { channel?.invokeMethod("bytes", bytes) }
                }
            } catch (_: Exception) {
                // A closed socket ends the reader; the UI reconnects.
            }
        }.also { it.start() }
    }

    private fun write(bytes: ByteArray?, result: MethodChannel.Result) {
        val s = socket
        if (bytes == null || s == null) {
            result.error("not_open", "control channel is not open", null)
            return
        }
        Thread {
            try {
                s.outputStream.write(bytes)
                s.outputStream.flush()
                main.post { result.success(null) }
            } catch (e: Exception) {
                main.post { result.error("write_failed", e.message, null) }
            }
        }.start()
    }

    private fun close(result: MethodChannel.Result) {
        closeQuietly()
        result.success(null)
    }

    private fun closeQuietly() {
        reader?.interrupt()
        reader = null
        try { socket?.close() } catch (_: Exception) {}
        socket = null
    }
}
