package com.example.rent_and_play_app

import android.Manifest
import android.annotation.SuppressLint
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothGatt
import android.bluetooth.BluetoothGattCallback
import android.bluetooth.BluetoothGattCharacteristic
import android.bluetooth.BluetoothGattDescriptor
import android.bluetooth.BluetoothManager
import android.bluetooth.BluetoothProfile
import android.bluetooth.BluetoothStatusCodes
import android.bluetooth.le.ScanCallback
import android.bluetooth.le.ScanResult
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Typeface
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.UUID
import java.util.concurrent.Executors
import kotlin.math.ceil
import kotlin.math.floor
import kotlin.math.min

class MainActivity : FlutterActivity() {
    companion object {
        private const val CHANNEL = "rent_and_play/mx10_printer"
        private const val BLUETOOTH_PERMISSION_REQUEST = 7301
        private const val SCAN_DURATION_MS = 7000L
        private const val WRITE_CHUNK_SIZE = 20
        private const val FLOW_CONTROL_TIMEOUT_MS = 15000L
        private const val FALLBACK_PACKET_DELAY_MS = 7L
        private const val PRINTER_WIDTH = 384
        private const val PRINTER_HEIGHT = 240
        private const val DOTS_PER_MM = 8
        private val SERVICE_UUIDS = listOf(
            UUID.fromString("0000ae30-0000-1000-8000-00805f9b34fb"),
            UUID.fromString("0000af30-0000-1000-8000-00805f9b34fb"),
        )
        private val TX_UUID = UUID.fromString("0000ae01-0000-1000-8000-00805f9b34fb")
        private val RX_UUID = UUID.fromString("0000ae02-0000-1000-8000-00805f9b34fb")
        private val CCCD_UUID = UUID.fromString("00002902-0000-1000-8000-00805f9b34fb")
    }

    private val mainHandler = Handler(Looper.getMainLooper())
    private val printExecutor = Executors.newSingleThreadExecutor()
    private var permissionAction: (() -> Unit)? = null
    private var permissionResult: MethodChannel.Result? = null

    private var scanCallback: ScanCallback? = null
    private var scanResult: MethodChannel.Result? = null
    private val discoveredPrinters = linkedMapOf<String, Map<String, String>>()

    private var activeGatt: BluetoothGatt? = null
    private var isPrinterConnected = false
    private var txCharacteristic: BluetoothGattCharacteristic? = null
    private var rxCharacteristic: BluetoothGattCharacteristic? = null
    private var printerName = "MX10"
    private var connectResult: MethodChannel.Result? = null
    private var connectTimeout: Runnable? = null
    private var flowPaused = false
    private var printBytes: ByteArray? = null
    private var printOffset = 0
    private var pendingWriteLength = 0
    private var writePending = false
    private var printResult: MethodChannel.Result? = null
    private var writeTimeout: Runnable? = null
    private var flowTimeout: Runnable? = null
    private val notificationLock = Any()
    private var notificationBuffer = byteArrayOf()

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = android.app.NotificationChannel(
                "rental_updates",
                "Rental updates",
                android.app.NotificationManager.IMPORTANCE_HIGH,
            )
            channel.description = "Booking approvals, requests and return updates"
            getSystemService(android.app.NotificationManager::class.java)
                .createNotificationChannel(channel)
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "discoverPrinters" -> withBluetoothPermissions(result) {
                        discoverPrinters(result)
                    }
                    "connectPrinter" -> {
                        val id = call.argument<String>("id")
                        if (id.isNullOrBlank()) {
                            result.error("invalid_device", "Choose an MX10 printer first.", null)
                        } else {
                            withBluetoothPermissions(result) { connectPrinter(id, result) }
                        }
                    }
                    "printEquipmentLabel" -> {
                        val code = call.argument<String>("code") ?: "EQUIPMENT"
                        val name = call.argument<String>("name") ?: "Equipment"
                        val matrix = call.argument<Map<String, Any?>>("matrix")
                        if (matrix == null) {
                            result.error("invalid_qr", "The equipment QR data is missing.", null)
                        } else {
                            withBluetoothPermissions(result) {
                                printEquipmentLabel(code, name, matrix, result)
                            }
                        }
                    }
                    "disconnectPrinter" -> {
                        disconnectPrinter()
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun requiredBluetoothPermissions(): Array<String> = when {
        Build.VERSION.SDK_INT >= Build.VERSION_CODES.S -> arrayOf(
            Manifest.permission.BLUETOOTH_SCAN,
            Manifest.permission.BLUETOOTH_CONNECT,
        )
        Build.VERSION.SDK_INT >= Build.VERSION_CODES.M -> arrayOf(
            Manifest.permission.ACCESS_FINE_LOCATION,
        )
        else -> emptyArray()
    }

    private fun withBluetoothPermissions(
        result: MethodChannel.Result,
        action: () -> Unit,
    ) {
        val missing = requiredBluetoothPermissions().filter {
            ContextCompat.checkSelfPermission(this, it) != PackageManager.PERMISSION_GRANTED
        }
        if (missing.isEmpty()) {
            action()
            return
        }
        if (permissionResult != null) {
            result.error("permission_busy", "Bluetooth permission request is already open.", null)
            return
        }
        permissionResult = result
        permissionAction = action
        requestPermissions(missing.toTypedArray(), BLUETOOTH_PERMISSION_REQUEST)
    }

    @Deprecated("Permission callback retained for Android Bluetooth runtime access")
    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != BLUETOOTH_PERMISSION_REQUEST) return
        val result = permissionResult
        val action = permissionAction
        permissionResult = null
        permissionAction = null
        if (grantResults.isNotEmpty() && grantResults.all { it == PackageManager.PERMISSION_GRANTED }) {
            action?.invoke()
        } else {
            result?.error(
                "bluetooth_permission_denied",
                "Allow Bluetooth access to find and print to the MX10 label printer.",
                null,
            )
        }
    }

    @SuppressLint("MissingPermission")
    private fun bluetoothAdapter(): BluetoothAdapter? =
        (getSystemService(BLUETOOTH_SERVICE) as? BluetoothManager)?.adapter

    @SuppressLint("MissingPermission")
    private fun discoverPrinters(result: MethodChannel.Result) {
        val adapter = bluetoothAdapter()
        if (adapter == null) {
            result.error("bluetooth_unavailable", "This phone does not support Bluetooth LE.", null)
            return
        }
        if (!adapter.isEnabled) {
            result.error("bluetooth_off", "Turn on Bluetooth, then search for the MX10 printer again.", null)
            return
        }
        val scanner = adapter.bluetoothLeScanner
        if (scanner == null) {
            result.error("scan_unavailable", "Bluetooth scanning is unavailable on this phone.", null)
            return
        }
        scanResult?.error("scan_cancelled", "The previous printer search was replaced.", null)
        scanResult = null
        stopPrinterScan()
        discoveredPrinters.clear()
        scanResult = result
        val callback = object : ScanCallback() {
            override fun onScanResult(callbackType: Int, scan: ScanResult) {
                val device = scan.device
                val name = device.name ?: scan.scanRecord?.deviceName ?: "Bluetooth printer"
                val serviceMatch = scan.scanRecord?.serviceUuids
                    ?.any { parcel -> SERVICE_UUIDS.contains(parcel.uuid) } == true
                if (!name.startsWith("MX10", ignoreCase = true) && !serviceMatch) return
                synchronized(discoveredPrinters) {
                    discoveredPrinters[device.address] = mapOf(
                        "id" to device.address,
                        "name" to name,
                    )
                }
            }

            override fun onScanFailed(errorCode: Int) {
                mainHandler.post {
                    if (scanResult == result) {
                        scanResult = null
                        stopPrinterScan()
                        result.error("scan_failed", "Could not scan for Bluetooth printers (code $errorCode).", null)
                    }
                }
            }
        }
        scanCallback = callback
        try {
            scanner.startScan(callback)
            mainHandler.postDelayed({
                if (scanResult != result) return@postDelayed
                stopPrinterScan()
                val found = synchronized(discoveredPrinters) {
                    discoveredPrinters.values.toList()
                }
                scanResult = null
                result.success(found)
            }, SCAN_DURATION_MS)
        } catch (error: SecurityException) {
            scanResult = null
            result.error("scan_denied", "Bluetooth scan permission was not granted.", error.message)
        } catch (error: Exception) {
            scanResult = null
            result.error("scan_failed", error.message ?: "Bluetooth scan failed.", null)
        }
    }

    @SuppressLint("MissingPermission")
    private fun stopPrinterScan() {
        val callback = scanCallback ?: return
        try {
            bluetoothAdapter()?.bluetoothLeScanner?.stopScan(callback)
        } catch (_: Exception) {
            // The adapter can be turned off while a scan is running.
        }
        scanCallback = null
    }

    @SuppressLint("MissingPermission")
    private fun connectPrinter(address: String, result: MethodChannel.Result) {
        val adapter = bluetoothAdapter()
        if (adapter == null || !adapter.isEnabled) {
            result.error("bluetooth_off", "Turn on Bluetooth before connecting to the MX10.", null)
            return
        }
        if (activeGatt?.device?.address == address && isPrinterConnected) {
            result.success(mapOf("name" to printerName))
            return
        }
        disconnectPrinter()
        val device = try {
            adapter.getRemoteDevice(address)
        } catch (error: IllegalArgumentException) {
            result.error("invalid_device", "The selected printer is no longer available. Scan again.", null)
            return
        }
        printerName = device.name ?: "MX10"
        connectResult = result
        connectTimeout = Runnable {
            if (connectResult === result) {
                connectResult = null
                activeGatt?.disconnect()
                activeGatt?.close()
                activeGatt = null
                result.error("connect_timeout", "The MX10 did not connect. Check that it is on and not connected to another device.", null)
            }
        }.also { mainHandler.postDelayed(it, 20000L) }
        try {
            activeGatt = device.connectGatt(this, false, gattCallback, BluetoothDevice.TRANSPORT_LE)
            if (activeGatt == null) {
                failConnection("Could not start the MX10 Bluetooth connection.")
            }
        } catch (error: SecurityException) {
            failConnection("Bluetooth permission was not granted.")
        } catch (error: Exception) {
            failConnection(error.message ?: "Could not connect to the MX10.")
        }
    }

    private val gattCallback = object : BluetoothGattCallback() {
        override fun onConnectionStateChange(gatt: BluetoothGatt, status: Int, newState: Int) {
            if (gatt !== activeGatt) return
            if (status != BluetoothGatt.GATT_SUCCESS) {
                mainHandler.post { failConnection("MX10 Bluetooth connection failed (code $status).") }
                return
            }
            if (newState == BluetoothProfile.STATE_CONNECTED) {
                mainHandler.post {
                    try {
                        if (!gatt.discoverServices()) failConnection("Could not read the MX10 printer services.")
                    } catch (error: Exception) {
                        failConnection(error.message ?: "Could not read the MX10 printer services.")
                    }
                }
            } else if (newState == BluetoothProfile.STATE_DISCONNECTED) {
                mainHandler.post {
                    failPrint("Bluetooth disconnected while communicating with the MX10.")
                    if (connectResult != null) failConnection("The MX10 disconnected before it was ready.")
                    if (activeGatt === gatt) {
                        isPrinterConnected = false
                        txCharacteristic = null
                        rxCharacteristic = null
                        flowPaused = false
                        synchronized(notificationLock) { notificationBuffer = byteArrayOf() }
                    }
                }
            }
        }

        override fun onServicesDiscovered(gatt: BluetoothGatt, status: Int) {
            if (gatt !== activeGatt) return
            mainHandler.post {
                if (status != BluetoothGatt.GATT_SUCCESS) {
                    failConnection("Could not inspect the MX10 printer services.")
                    return@post
                }
                val service = SERVICE_UUIDS.firstNotNullOfOrNull { gatt.getService(it) }
                val output = service?.getCharacteristic(TX_UUID)
                if (service == null || output == null) {
                    failConnection("This device does not expose the MX10 label-print service.")
                    return@post
                }
                txCharacteristic = output
                val input = service.getCharacteristic(RX_UUID)
                rxCharacteristic = input
                flowPaused = false
                if (input == null ||
                    (input.properties and (BluetoothGattCharacteristic.PROPERTY_NOTIFY or BluetoothGattCharacteristic.PROPERTY_INDICATE)) == 0
                ) {
                    rxCharacteristic = null
                    finishConnection()
                    return@post
                }
                try {
                    val notificationsEnabled = gatt.setCharacteristicNotification(input, true)
                    val descriptor = input.getDescriptor(CCCD_UUID)
                    if (!notificationsEnabled || descriptor == null) {
                        rxCharacteristic = null
                        finishConnection()
                    } else {
                        val descriptorValue = if (input.properties and BluetoothGattCharacteristic.PROPERTY_NOTIFY != 0) {
                            BluetoothGattDescriptor.ENABLE_NOTIFICATION_VALUE
                        } else {
                            BluetoothGattDescriptor.ENABLE_INDICATION_VALUE
                        }
                        val started = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                            gatt.writeDescriptor(descriptor, descriptorValue) == BluetoothStatusCodes.SUCCESS
                        } else {
                            @Suppress("DEPRECATION")
                            run {
                                descriptor.value = descriptorValue
                                gatt.writeDescriptor(descriptor)
                            }
                        }
                        if (!started) {
                            rxCharacteristic = null
                            finishConnection()
                        }
                    }
                } catch (_: Exception) {
                    rxCharacteristic = null
                    finishConnection()
                }
            }
        }

        override fun onDescriptorWrite(
            gatt: BluetoothGatt,
            descriptor: BluetoothGattDescriptor,
            status: Int,
        ) {
            if (gatt !== activeGatt || descriptor.uuid != CCCD_UUID) return
            mainHandler.post {
                if (status == BluetoothGatt.GATT_SUCCESS) {
                    finishConnection()
                } else {
                    rxCharacteristic = null
                    finishConnection()
                }
            }
        }

        override fun onCharacteristicChanged(
            gatt: BluetoothGatt,
            characteristic: BluetoothGattCharacteristic,
        ) {
            @Suppress("DEPRECATION")
            val value = characteristic.value?.clone() ?: return
            handlePrinterNotification(gatt, characteristic, value)
        }

        override fun onCharacteristicChanged(
            gatt: BluetoothGatt,
            characteristic: BluetoothGattCharacteristic,
            value: ByteArray,
        ) {
            handlePrinterNotification(gatt, characteristic, value.clone())
        }

        override fun onCharacteristicWrite(
            gatt: BluetoothGatt,
            characteristic: BluetoothGattCharacteristic,
            status: Int,
        ) {
            if (gatt !== activeGatt || characteristic.uuid != TX_UUID) return
            mainHandler.post { onPrinterChunkWritten(status) }
        }
    }

    private fun handlePrinterNotification(
        gatt: BluetoothGatt,
        characteristic: BluetoothGattCharacteristic,
        value: ByteArray,
    ) {
        if (gatt !== activeGatt || characteristic.uuid != RX_UUID) return
        val flowStates = mutableListOf<Int>()
        synchronized(notificationLock) {
            notificationBuffer += value
            while (notificationBuffer.size >= 2) {
                var start = -1
                for (position in 0 until notificationBuffer.size - 1) {
                    if ((notificationBuffer[position].toInt() and 0xff) == 0x51 &&
                        (notificationBuffer[position + 1].toInt() and 0xff) == 0x78
                    ) {
                        start = position
                        break
                    }
                }
                if (start < 0) {
                    notificationBuffer = notificationBuffer.takeLast(1).toByteArray()
                    break
                }
                if (start > 0) notificationBuffer = notificationBuffer.copyOfRange(start, notificationBuffer.size)
                if (notificationBuffer.size < 5) break
                val frameLength = 8 + (notificationBuffer[4].toInt() and 0xff)
                if (frameLength < 9 || frameLength > 263) {
                    notificationBuffer = notificationBuffer.copyOfRange(1, notificationBuffer.size)
                    continue
                }
                if (notificationBuffer.size < frameLength) break
                if ((notificationBuffer[frameLength - 1].toInt() and 0xff) != 0xff) {
                    notificationBuffer = notificationBuffer.copyOfRange(1, notificationBuffer.size)
                    continue
                }
                val opcode = notificationBuffer[2].toInt() and 0xff
                if (opcode == 0xae) flowStates.add(notificationBuffer[6].toInt() and 0xff)
                notificationBuffer = notificationBuffer.copyOfRange(frameLength, notificationBuffer.size)
            }
        }
        flowStates.forEach { state ->
            mainHandler.post {
                flowPaused = state == 0x10
                if (!flowPaused) {
                    flowTimeout?.let(mainHandler::removeCallbacks)
                    flowTimeout = null
                    writeNextPrinterChunk()
                } else {
                    armFlowTimeout()
                }
            }
        }
    }

    private fun finishConnection() {
        val result = connectResult ?: return
        connectResult = null
        isPrinterConnected = true
        connectTimeout?.let(mainHandler::removeCallbacks)
        connectTimeout = null
        result.success(mapOf("name" to printerName))
    }

    private fun failConnection(message: String) {
        val result = connectResult ?: return
        connectResult = null
        connectTimeout?.let(mainHandler::removeCallbacks)
        connectTimeout = null
        result.error("connect_failed", message, null)
        activeGatt?.disconnect()
        activeGatt?.close()
        activeGatt = null
        isPrinterConnected = false
        txCharacteristic = null
        rxCharacteristic = null
        flowPaused = false
        synchronized(notificationLock) { notificationBuffer = byteArrayOf() }
    }

    @SuppressLint("MissingPermission")
    private fun disconnectPrinter() {
        connectTimeout?.let(mainHandler::removeCallbacks)
        connectTimeout = null
        connectResult?.error("connection_cancelled", "The printer connection was replaced.", null)
        connectResult = null
        failPrint("The printer connection was closed.")
        activeGatt?.disconnect()
        activeGatt?.close()
        activeGatt = null
        isPrinterConnected = false
        txCharacteristic = null
        rxCharacteristic = null
        flowPaused = false
        synchronized(notificationLock) { notificationBuffer = byteArrayOf() }
    }

    private fun printEquipmentLabel(
        code: String,
        name: String,
        matrix: Map<String, Any?>,
        result: MethodChannel.Result,
    ) {
        val gatt = activeGatt
        if (gatt == null || !isPrinterConnected || txCharacteristic == null) {
            result.error("printer_disconnected", "Connect the MX10 printer before printing.", null)
            return
        }
        if (printResult != null) {
            result.error("printer_busy", "Wait for the current label to finish printing.", null)
            return
        }
        printResult = result
        printExecutor.execute {
            try {
                val job = createMx10PrintJob(code, name, matrix)
                mainHandler.post {
                    if (printResult === result) {
                        printBytes = job
                        printOffset = 0
                        pendingWriteLength = 0
                        writePending = false
                        writeNextPrinterChunk()
                    }
                }
            } catch (error: Exception) {
                mainHandler.post {
                    if (printResult === result) {
                        failPrint(error.message ?: "Could not prepare the MX10 print job.")
                    }
                }
            }
        }
    }

    @SuppressLint("MissingPermission")
    private fun writeNextPrinterChunk() {
        val job = printBytes ?: return
        if (printResult == null || writePending || flowPaused) return
        val gatt = activeGatt ?: run {
            failPrint("Bluetooth disconnected before printing finished.")
            return
        }
        val characteristic = txCharacteristic ?: run {
            failPrint("The MX10 print channel is no longer available.")
            return
        }
        if (printOffset >= job.size) {
            finishPrint()
            return
        }

        val end = min(printOffset + WRITE_CHUNK_SIZE, job.size)
        val packet = job.copyOfRange(printOffset, end)
        pendingWriteLength = packet.size
        writePending = true
        val noResponse = characteristic.properties and BluetoothGattCharacteristic.PROPERTY_WRITE_NO_RESPONSE != 0
        val writeType = if (noResponse) {
            BluetoothGattCharacteristic.WRITE_TYPE_NO_RESPONSE
        } else {
            BluetoothGattCharacteristic.WRITE_TYPE_DEFAULT
        }
        val started = try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                gatt.writeCharacteristic(characteristic, packet, writeType) == BluetoothStatusCodes.SUCCESS
            } else {
                @Suppress("DEPRECATION")
                run {
                    characteristic.writeType = writeType
                    characteristic.value = packet
                    gatt.writeCharacteristic(characteristic)
                }
            }
        } catch (error: Exception) {
            failPrint(error.message ?: "Could not send data to the MX10.")
            return
        }
        if (!started) {
            failPrint("The MX10 rejected a print packet. Reconnect and try again.")
            return
        }
        val expectedResult = printResult
        val timeout = Runnable {
            if (printResult === expectedResult && writePending) {
                failPrint("The MX10 did not acknowledge a Bluetooth print packet. Check its paper and connection.")
            }
        }
        writeTimeout?.let(mainHandler::removeCallbacks)
        writeTimeout = timeout
        mainHandler.postDelayed(timeout, FLOW_CONTROL_TIMEOUT_MS)
    }

    private fun onPrinterChunkWritten(status: Int) {
        if (printResult == null || !writePending) return
        writeTimeout?.let(mainHandler::removeCallbacks)
        writeTimeout = null
        if (status != BluetoothGatt.GATT_SUCCESS) {
            failPrint("The MX10 could not receive a print packet (code $status).")
            return
        }
        printOffset += pendingWriteLength
        pendingWriteLength = 0
        writePending = false
        if (flowPaused) return
        if (rxCharacteristic == null) {
            mainHandler.postDelayed({ writeNextPrinterChunk() }, FALLBACK_PACKET_DELAY_MS)
        } else {
            writeNextPrinterChunk()
        }
    }

    private fun armFlowTimeout() {
        flowTimeout?.let(mainHandler::removeCallbacks)
        val expectedResult = printResult
        val timeout = Runnable {
            if (printResult === expectedResult && flowPaused) {
                failPrint("The MX10 stayed busy for too long. Check the paper roll and try again.")
            }
        }
        flowTimeout = timeout
        mainHandler.postDelayed(timeout, FLOW_CONTROL_TIMEOUT_MS)
    }

    private fun finishPrint() {
        val result = printResult ?: return
        clearPrintState()
        result.success(null)
    }

    private fun failPrint(message: String) {
        val result = printResult ?: return
        clearPrintState()
        result.error("print_failed", message, null)
    }

    private fun clearPrintState() {
        writeTimeout?.let(mainHandler::removeCallbacks)
        flowTimeout?.let(mainHandler::removeCallbacks)
        writeTimeout = null
        flowTimeout = null
        printResult = null
        printBytes = null
        printOffset = 0
        pendingWriteLength = 0
        writePending = false
        flowPaused = false
    }

    private fun createMx10PrintJob(
        code: String,
        itemName: String,
        qrMatrix: Map<String, Any?>,
    ): ByteArray {
        val size = (qrMatrix["size"] as? Number)?.toInt()
            ?: throw IllegalArgumentException("The QR matrix size is missing.")
        val data = (qrMatrix["data"] as? List<*>)
            ?: throw IllegalArgumentException("The QR matrix data is missing.")
        val margin = (qrMatrix["margin"] as? Number)?.toInt() ?: 4
        if (size < 1 || data.size != size * size || margin < 4) {
            throw IllegalArgumentException("The QR matrix is incomplete.")
        }

        val bitmap = Bitmap.createBitmap(PRINTER_WIDTH, PRINTER_HEIGHT, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap)
        canvas.drawColor(Color.WHITE)
        val qrGeometryX = 12.0
        val qrGeometryY = 0.0
        val qrGeometrySize = 272.0
        val left = floor(qrGeometryX * PRINTER_WIDTH / 500.0).toInt()
        val top = floor(qrGeometryY * PRINTER_HEIGHT / 300.0).toInt()
        val boxWidth = ceil((qrGeometryX + qrGeometrySize) * PRINTER_WIDTH / 500.0).toInt() - left
        val boxHeight = ceil((qrGeometryY + qrGeometrySize) * PRINTER_HEIGHT / 300.0).toInt() - top
        val moduleCount = size + margin * 2
        val moduleSize = floor(min(boxWidth, boxHeight).toDouble() / moduleCount).toInt()
        if (moduleSize < 1) {
            bitmap.recycle()
            throw IllegalArgumentException("This equipment QR is too detailed for a 50 × 30 mm label.")
        }
        val qrLeft = left + (boxWidth - moduleCount * moduleSize) / 2
        val qrTop = top
        val qrPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = Color.BLACK }
        for (row in 0 until size) {
            for (column in 0 until size) {
                val index = row * size + column
                val dark = (data[index] as? Number)?.toInt() == 1
                if (!dark) continue
                val x = qrLeft + (column + margin) * moduleSize
                val y = qrTop + (row + margin) * moduleSize
                canvas.drawRect(
                    x.toFloat(),
                    y.toFloat(),
                    (x + moduleSize).toFloat(),
                    (y + moduleSize).toFloat(),
                    qrPaint,
                )
            }
        }

        val codePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = Color.BLACK
            textSize = 15f
            typeface = Typeface.create("sans-serif", Typeface.BOLD)
        }
        val namePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = Color.BLACK
            textSize = 14f
            typeface = Typeface.create("sans-serif", Typeface.NORMAL)
        }
        val brandPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = Color.BLACK
            textSize = 12f
            typeface = Typeface.create("sans-serif", Typeface.BOLD)
        }
        val shortName = if (itemName.length > 20) itemName.take(17) + "…" else itemName
        canvas.drawText(code.take(15), 230f, 29f, codePaint)
        canvas.drawText(shortName, 230f, 61f, namePaint)
        canvas.drawText("RENT & PLAY", 230f, 93f, brandPaint)

        val pixels = IntArray(PRINTER_WIDTH * PRINTER_HEIGHT)
        bitmap.getPixels(pixels, 0, PRINTER_WIDTH, 0, 0, PRINTER_WIDTH, PRINTER_HEIGHT)
        val rows = ArrayList<ByteArray>(PRINTER_HEIGHT)
        for (y in 0 until PRINTER_HEIGHT) {
            val packed = ByteArray(PRINTER_WIDTH / 8)
            for (x in 0 until PRINTER_WIDTH) {
                val color = pixels[y * PRINTER_WIDTH + x]
                val luminance = Color.red(color) * 0.2126 +
                    Color.green(color) * 0.7152 +
                    Color.blue(color) * 0.0722
                if (Color.alpha(color) > 100 && luminance < 175) {
                    val slot = x shr 3
                    packed[slot] = (packed[slot].toInt() or (1 shl (x and 7))).toByte()
                }
            }
            rows.add(packed)
        }
        bitmap.recycle()
        return encodePrintJob(rows)
    }

    private fun encodePrintJob(rows: List<ByteArray>): ByteArray {
        val parts = ArrayList<ByteArray>()
        parts.add(printerCommand(0xf2, byteArrayOf(0x01, 0xc8.toByte())))
        parts.add(printerCommand(0xa3, byteArrayOf(0x00)))
        parts.add(printerCommand(0xa4, byteArrayOf(0x34)))
        parts.add(printerCommand(0xa6, byteArrayOf(0xaa.toByte(), 0x55, 0x17, 0x38, 0x44, 0x5f, 0x5f, 0x5f, 0x44, 0x38, 0x2c)))
        parts.add(printerCommand(0xaf, byteArrayOf(0x98.toByte(), 0x3a)))
        parts.add(printerCommand(0xbe, byteArrayOf(0x00)))
        parts.add(printerCommand(0xbd, byteArrayOf(0x0a)))
        parts.add(printerCommand(0xa1, byteArrayOf(0x10, 0x00)))
        rows.forEach { row ->
            if (row.size != PRINTER_WIDTH / 8) {
                throw IllegalArgumentException("The MX10 print bitmap has an invalid row width.")
            }
            parts.add(printerCommand(0xa2, row))
        }
        parts.add(printerCommand(0xbd, byteArrayOf(0x19)))
        parts.add(printerCommand(0xa1, byteArrayOf(0x18, 0x00)))
        parts.add(printerCommand(0xa6, byteArrayOf(0xaa.toByte(), 0x55, 0x17, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x17)))
        parts.add(printerCommand(0xa3, byteArrayOf(0x00)))
        val totalBytes = parts.sumOf { it.size }
        val output = ByteArray(totalBytes)
        var offset = 0
        parts.forEach { part ->
            part.copyInto(output, offset)
            offset += part.size
        }
        return output
    }

    private fun printerCommand(opcode: Int, payload: ByteArray = byteArrayOf()): ByteArray {
        require(payload.size <= 255) { "A printer command was too large." }
        val output = ByteArray(payload.size + 8)
        output[0] = 0x51
        output[1] = 0x78
        output[2] = opcode.toByte()
        output[3] = 0x00
        output[4] = payload.size.toByte()
        output[5] = 0x00
        payload.copyInto(output, 6)
        output[6 + payload.size] = crc8(payload).toByte()
        output[7 + payload.size] = 0xff.toByte()
        return output
    }

    private fun crc8(bytes: ByteArray): Int {
        var crc = 0
        bytes.forEach { value ->
            crc = crc xor (value.toInt() and 0xff)
            repeat(8) {
                crc = if (crc and 0x80 != 0) ((crc shl 1) xor 0x07) and 0xff
                else (crc shl 1) and 0xff
            }
        }
        return crc
    }

    override fun onDestroy() {
        stopPrinterScan()
        disconnectPrinter()
        printExecutor.shutdownNow()
        super.onDestroy()
    }
}
