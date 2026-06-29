package com.himdek.files3.s3

data class S3Object(
    val key: String,
    val size: Long,
    val lastModified: String,
    val eTag: String,
    val storageClass: String,
)

data class CommonPrefix(
    val prefix: String,
)

data class ListObjectsV2Result(
    val bucket: String,
    val prefix: String?,
    val delimiter: String?,
    val maxKeys: Int,
    val keyCount: Int,
    val isTruncated: Boolean,
    val continuationToken: String?,
    val nextContinuationToken: String?,
    val objects: List<S3Object>,
    val commonPrefixes: List<CommonPrefix>,
)

data class S3Error(
    val code: String,
    val message: String,
    val requestId: String?,
    val hostId: String?,
)

class S3Exception(
    val statusCode: Int,
    val error: S3Error?,
) : Exception(
    error?.let {
        "${it.code}: ${it.message}"
    } ?: "HTTP $statusCode"
)