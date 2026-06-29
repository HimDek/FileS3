package com.himdek.files3.s3

import okhttp3.HttpUrl.Companion.toHttpUrl
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.Response
import java.io.File
import java.io.IOException


class S3Client(
    private val accessKey: String,
    private val secretKey: String,
    private val region: String,
) {

    private val client = OkHttpClient()

    private fun host(bucket: String): String =
        "$bucket.s3.$region.amazonaws.com"

    private fun endpoint(bucket: String): String =
        "https://${host(bucket)}"

    private fun canonicalUri(key: String): String =
        if (key.isEmpty()) {
            "/"
        } else {
            "/" + key.split('/')
                .joinToString("/") {
                    AwsV4Signer.awsEncode(it)
                }
        }

    @Throws(IOException::class, S3Exception::class)
    private fun execute(
        method: String,
        bucket: String,
        key: String = "",
        query: List<Pair<String, String>> = emptyList(),
        headers: Map<String, String> = emptyMap(),
    ): Response {

        val uri = canonicalUri(key)

        val signed = AwsV4Signer.sign(
            method = method,
            region = region,
            host = host(bucket),
            canonicalUri = uri,
            query = query,
            headers = headers,
            payloadHash = AwsV4Signer.emptyPayloadHash(),
            accessKey = accessKey,
            secretKey = secretKey
        )

        val urlBuilder = endpoint(bucket)
            .toHttpUrl()
            .newBuilder()

        urlBuilder.encodedPath(uri)

        query.forEach {
            urlBuilder.addQueryParameter(
                it.first,
                it.second
            )
        }

        val builder = Request.Builder()
            .url(urlBuilder.build())

        signed.headers.forEach {
            builder.header(
                it.key,
                it.value
            )
        }

        when (method) {
            "GET" -> builder.get()
            "HEAD" -> builder.head()
            else -> error("Unsupported method $method")
        }

        val response =
            client.newCall(builder.build()).execute()

        if (!response.isSuccessful) {

            val body =
                response.body?.string()

            response.close()

            throw S3Exception(
                response.code,
                body?.let(XmlParser::parseError)
            )
        }

        return response
    }

    fun listObjectsV2(
        bucket: String,
        prefix: String? = null,
        delimiter: String? = null,
        continuationToken: String? = null,
        maxKeys: Int? = null,
    ): ListObjectsV2Result {

        val query = mutableListOf<Pair<String, String>>()

        query += "list-type" to "2"

        prefix?.let {
            query += "prefix" to it
        }

        delimiter?.let {
            query += "delimiter" to it
        }

        continuationToken?.let {
            query += "continuation-token" to it
        }

        maxKeys?.let {
            query += "max-keys" to it.toString()
        }

        execute(
            method = "GET",
            bucket = bucket,
            query = query
        ).use { response ->

            val xml =
                response.body!!.string()

            return XmlParser.parseListObjectsV2(xml)
        }
    }

    fun getObject(
        bucket: String,
        key: String,
        destination: File,
    ) {

        destination.parentFile?.mkdirs()

        execute(
            method = "GET",
            bucket = bucket,
            key = key
        ).use { response ->

            val body =
                response.body
                    ?: throw IOException(
                        "Empty response body"
                    )

            destination.outputStream().use {
                body.byteStream().copyTo(it)
            }
        }
    }
}