package com.himdek.files3.s3

import android.util.Xml
import org.xmlpull.v1.XmlPullParser
import java.io.StringReader

object XmlParser {

    fun parseListObjectsV2(xml: String): ListObjectsV2Result {

        val parser = Xml.newPullParser()
        parser.setInput(StringReader(xml))

        var bucket = ""
        var prefix: String? = null
        var delimiter: String? = null
        var maxKeys = 0
        var keyCount = 0
        var isTruncated = false
        var continuationToken: String? = null
        var nextContinuationToken: String? = null

        val objects = mutableListOf<S3Object>()
        val prefixes = mutableListOf<CommonPrefix>()

        var currentKey = ""
        var currentETag = ""
        var currentLastModified = ""
        var currentStorageClass = ""
        var currentSize = 0L

        var insideContents = false
        var insideCommonPrefix = false

        while (parser.eventType != XmlPullParser.END_DOCUMENT) {

            when (parser.eventType) {

                XmlPullParser.START_TAG -> {

                    when (parser.name) {

                        "Contents" -> {
                            insideContents = true
                            currentKey = ""
                            currentETag = ""
                            currentLastModified = ""
                            currentStorageClass = ""
                            currentSize = 0
                        }

                        "CommonPrefixes" -> {
                            insideCommonPrefix = true
                        }

                        "Name" -> bucket = parser.nextText()

                        "Prefix" -> {
                            val value = parser.nextText()

                            if (insideCommonPrefix)
                                prefixes.add(CommonPrefix(value))
                            else
                                prefix = value
                        }

                        "Delimiter" ->
                            delimiter = parser.nextText()

                        "MaxKeys" ->
                            maxKeys = parser.nextText().toInt()

                        "KeyCount" ->
                            keyCount = parser.nextText().toInt()

                        "IsTruncated" ->
                            isTruncated = parser.nextText().toBoolean()

                        "ContinuationToken" ->
                            continuationToken = parser.nextText()

                        "NextContinuationToken" ->
                            nextContinuationToken = parser.nextText()

                        "Key" ->
                            if (insideContents)
                                currentKey = parser.nextText()

                        "ETag" ->
                            if (insideContents)
                                currentETag = parser.nextText().trim('\"')

                        "LastModified" ->
                            if (insideContents)
                                currentLastModified = parser.nextText()

                        "StorageClass" ->
                            if (insideContents)
                                currentStorageClass = parser.nextText()

                        "Size" ->
                            if (insideContents)
                                currentSize = parser.nextText().toLong()
                    }
                }

                XmlPullParser.END_TAG -> {

                    when (parser.name) {

                        "Contents" -> {
                            insideContents = false

                            objects += S3Object(
                                key = currentKey,
                                size = currentSize,
                                lastModified = currentLastModified,
                                eTag = currentETag,
                                storageClass = currentStorageClass
                            )
                        }

                        "CommonPrefixes" ->
                            insideCommonPrefix = false
                    }
                }
            }

            parser.next()
        }

        return ListObjectsV2Result(
            bucket = bucket,
            prefix = prefix,
            delimiter = delimiter,
            maxKeys = maxKeys,
            keyCount = keyCount,
            isTruncated = isTruncated,
            continuationToken = continuationToken,
            nextContinuationToken = nextContinuationToken,
            objects = objects,
            commonPrefixes = prefixes
        )
    }

    fun parseError(xml: String): S3Error {

        val parser = Xml.newPullParser()
        parser.setInput(StringReader(xml))

        var code = ""
        var message = ""
        var requestId: String? = null
        var hostId: String? = null

        while (parser.eventType != XmlPullParser.END_DOCUMENT) {

            if (parser.eventType == XmlPullParser.START_TAG) {

                when (parser.name) {

                    "Code" ->
                        code = parser.nextText()

                    "Message" ->
                        message = parser.nextText()

                    "RequestId" ->
                        requestId = parser.nextText()

                    "HostId" ->
                        hostId = parser.nextText()
                }
            }

            parser.next()
        }

        return S3Error(
            code = code,
            message = message,
            requestId = requestId,
            hostId = hostId
        )
    }
}