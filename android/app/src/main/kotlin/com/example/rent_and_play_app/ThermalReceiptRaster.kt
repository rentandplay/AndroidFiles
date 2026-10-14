package com.example.rent_and_play_app

import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Typeface

/** Receipt artwork uses the same 384-dot printhead as the QR labels. */
object ThermalReceiptRaster {
    private data class Line(val text: String, val size: Int, val bold: Boolean, val center: Boolean, val separator: Boolean)
    fun render(input: List<Map<String, Any?>>): Bitmap {
        require(input.size in 1..120) { "The receipt has an invalid number of lines." }
        val lines = ArrayList<Line>()
        for (entry in input) {
            val text = entry["text"] as? String ?: throw IllegalArgumentException("Receipt text is missing.")
            require(text.length <= 1000) { "A receipt field is too long." }
            val size = (entry["size"] as? Number)?.toInt() ?: 20
            require(size in listOf(18, 20, 26)) { "The receipt text size is invalid." }
            val bold = entry["bold"] == true
            val center = entry["center"] == true
            if (entry["separator"] == true) { lines.add(Line("", size, bold, center, true)); continue }
            val paint = textPaint(size, bold)
            for (part in wrap(text.replace(Regex("[\\s\\p{Cntrl}]+"), " ").trim(), paint)) {
                lines.add(Line(part, size, bold, center, false))
            }
        }
        val height = 24 + lines.sumOf { if (it.separator) 16 else it.size + 8 }
        require(height in 1..8192) { "The receipt is too long for one printer job." }
        val bitmap = Bitmap.createBitmap(384, height, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap)
        canvas.drawColor(Color.WHITE)
        val rule = Paint().apply { color = Color.BLACK; strokeWidth = 1f }
        var y = 12f
        for (line in lines) {
            if (line.separator) { canvas.drawLine(12f, y + 6f, 372f, y + 6f, rule); y += 16f; continue }
            val paint = textPaint(line.size, line.bold)
            y += line.size
            paint.textAlign = if (line.center) Paint.Align.CENTER else Paint.Align.LEFT
            canvas.drawText(line.text, if (line.center) 192f else 12f, y, paint)
            y += 8f
        }
        return bitmap
    }
    private fun textPaint(size: Int, bold: Boolean) = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.BLACK; textSize = size.toFloat()
        typeface = Typeface.create(Typeface.MONOSPACE, if (bold) Typeface.BOLD else Typeface.NORMAL)
    }
    private fun wrap(text: String, paint: Paint): List<String> {
        val result = ArrayList<String>(); var current = ""
        for (word in text.split(' ')) {
            val candidate = if (current.isEmpty()) word else "$current $word"
            if (paint.measureText(candidate) <= 360f) { current = candidate; continue }
            if (current.isNotEmpty()) { result.add(current); current = "" }
            for (codePoint in word.codePoints().toArray()) {
                val char = String(Character.toChars(codePoint))
                if (current.isNotEmpty() && paint.measureText(current + char) > 360f) { result.add(current); current = "" }
                current += char
            }
        }
        if (current.isNotEmpty()) result.add(current)
        return result
    }
}
