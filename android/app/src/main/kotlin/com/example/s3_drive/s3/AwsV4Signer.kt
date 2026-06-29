package com.himdek.files3.s3

import java.nio.charset.StandardCharsets
import java.security.MessageDigest
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.TimeZone
import javax.crypto.Mac
import javax.crypto.spec.SecretKeySpec

object AwsV4Signer {

    private const val ALGORITHM = "AWS4-HMAC-SHA256"
    private const val SERVICE = "s3"

    data class SignedRequest(
        val headers: Map<String, String>
    )

    fun sign(
        method: String,
        region: String,
        host: String,
        canonicalUri: String,
        query: List<Pair<String, String>>,
        headers: Map<String, String>,
        payloadHash: String,
        accessKey: String,
        secretKey: String,
    ): SignedRequest {

        val amzDate = SimpleDateFormat(
            "yyyyMMdd'T'HHmmss'Z'",
            Locale.US
        ).apply {
            timeZone = TimeZone.getTimeZone("UTC")
        }.format(Date())

        val dateStamp = amzDate.substring(0, 8)

        val allHeaders = headers.toMutableMap()

        allHeaders["Host"] = host
        allHeaders["x-amz-date"] = amzDate
        allHeaders["x-amz-content-sha256"] = payloadHash

        val canonicalQuery = query
            .sortedWith(
                compareBy<Pair<String, String>>(
                    { awsEncode(it.first) },
                    { awsEncode(it.second) }
                )
            )
            .joinToString("&") {
                "${awsEncode(it.first)}=${awsEncode(it.second)}"
            }

        val canonicalHeaders = allHeaders
            .mapKeys { it.key.lowercase() }
            .toSortedMap()
            .entries
            .joinToString("") {
                "${it.key}:${it.value.trim()}\n"
            }

        val signedHeaders = allHeaders.keys
            .map { it.lowercase() }
            .sorted()
            .joinToString(";")

        val canonicalRequest = listOf(
            method,
            canonicalUri,
            canonicalQuery,
            canonicalHeaders,
            signedHeaders,
            payloadHash
        ).joinToString("\n")

        val credentialScope =
            "$dateStamp/$region/$SERVICE/aws4_request"

        val stringToSign = listOf(
            ALGORITHM,
            amzDate,
            credentialScope,
            sha256Hex(canonicalRequest)
        ).joinToString("\n")

        val signingKey = getSigningKey(
            secretKey,
            dateStamp,
            region,
            SERVICE
        )

        val signature = hmacHex(
            signingKey,
            stringToSign
        )

        val authorization =
            "$ALGORITHM " +
                "Credential=$accessKey/$credentialScope, " +
                "SignedHeaders=$signedHeaders, " +
                "Signature=$signature"

        allHeaders["Authorization"] = authorization

        return SignedRequest(
            headers = allHeaders.toSortedMap(String.CASE_INSENSITIVE_ORDER)
        )
    }

    fun emptyPayloadHash(): String =
        sha256Hex(ByteArray(0))

    fun sha256Hex(text: String): String =
        sha256Hex(text.toByteArray(StandardCharsets.UTF_8))

    fun sha256Hex(bytes: ByteArray): String =
        MessageDigest.getInstance("SHA-256")
            .digest(bytes)
            .joinToString("") {
                "%02x".format(it)
            }

    fun awsEncode(input: String): String {

        val bytes = input.toByteArray(Charsets.UTF_8)
        val sb = StringBuilder(bytes.size * 3)

        for (b in bytes) {

            val c = (b.toInt() and 0xFF).toChar()

            if (
                c in 'A'..'Z' ||
                c in 'a'..'z' ||
                c in '0'..'9' ||
                c == '-' ||
                c == '_' ||
                c == '.' ||
                c == '~'
            ) {
                sb.append(c)
            } else {
                sb.append('%')
                sb.append("%02X".format(b.toInt() and 0xFF))
            }
        }

        return sb.toString()
    }

    private fun getSigningKey(
        secret: String,
        date: String,
        region: String,
        service: String,
    ): ByteArray {

        val kDate = hmac(
            ("AWS4$secret").toByteArray(StandardCharsets.UTF_8),
            date
        )

        val kRegion = hmac(kDate, region)

        val kService = hmac(kRegion, service)

        return hmac(kService, "aws4_request")
    }

    private fun hmac(
        key: ByteArray,
        data: String,
    ): ByteArray {

        val mac = Mac.getInstance("HmacSHA256")

        mac.init(
            SecretKeySpec(
                key,
                "HmacSHA256"
            )
        )

        return mac.doFinal(
            data.toByteArray(StandardCharsets.UTF_8)
        )
    }

    private fun hmacHex(
        key: ByteArray,
        data: String,
    ): String =
        hmac(key, data)
            .joinToString("") {
                "%02x".format(it)
            }
}