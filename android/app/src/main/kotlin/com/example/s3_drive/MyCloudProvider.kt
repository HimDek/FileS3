package com.himdek.files3

import android.content.res.AssetFileDescriptor
import android.database.Cursor
import android.database.MatrixCursor
import android.graphics.Point
import android.os.Bundle
import android.os.CancellationSignal
import android.os.ParcelFileDescriptor
import android.provider.CloudMediaProvider
import android.provider.CloudMediaProviderContract
import java.io.File

class MyCloudProvider : CloudMediaProvider() {

    override fun onCreate(): Boolean = true

    override fun onGetMediaCollectionInfo(extras: Bundle): Bundle {
        return Bundle().apply {
            putString(
                CloudMediaProviderContract.MediaCollectionInfo.MEDIA_COLLECTION_ID,
                "files3"
            )
            putLong(
                CloudMediaProviderContract.MediaCollectionInfo.LAST_MEDIA_SYNC_GENERATION,
                1L
            )
            putString(
                CloudMediaProviderContract.MediaCollectionInfo.ACCOUNT_NAME,
                "FileS3"
            )
        }
    }

    override fun onQueryDeletedMedia(extras: Bundle): Cursor {
        return MatrixCursor(
            arrayOf(
                CloudMediaProviderContract.MediaColumns.ID
            )
        )
    }

    override fun onQueryMedia(extras: Bundle): Cursor {

        val cursor = MatrixCursor(
            arrayOf(
                CloudMediaProviderContract.MediaColumns.ID,
                CloudMediaProviderContract.MediaColumns.MIME_TYPE,
                CloudMediaProviderContract.MediaColumns.STANDARD_MIME_TYPE_EXTENSION,
                CloudMediaProviderContract.MediaColumns.DATE_TAKEN_MILLIS,
                CloudMediaProviderContract.MediaColumns.SYNC_GENERATION,
                CloudMediaProviderContract.MediaColumns.SIZE_BYTES,
            )
        )

        cursor.addRow(
            arrayOf<Any>(
                "test",
                "image/jpeg",
                CloudMediaProviderContract.MediaColumns.STANDARD_MIME_TYPE_EXTENSION_NONE,
                System.currentTimeMillis(),
                1L,
                0L,
            )
        )

        return cursor
    }

    override fun onOpenMedia(
        mediaId: String,
        extras: Bundle?,
        signal: CancellationSignal?
    ): ParcelFileDescriptor {

        val file = File(
            context!!.cacheDir,
            "test.jpg"
        )

        return ParcelFileDescriptor.open(
            file,
            ParcelFileDescriptor.MODE_READ_ONLY
        )
    }

    override fun onOpenPreview(
        mediaId: String,
        size: Point,
        extras: Bundle?,
        signal: CancellationSignal?
    ): AssetFileDescriptor {

        val file = File(
            context!!.cacheDir,
            "thumb.jpg"
        )

        val pfd = ParcelFileDescriptor.open(
            file,
            ParcelFileDescriptor.MODE_READ_ONLY
        )

        return AssetFileDescriptor(
            pfd,
            0,
            AssetFileDescriptor.UNKNOWN_LENGTH
        )
    }
}