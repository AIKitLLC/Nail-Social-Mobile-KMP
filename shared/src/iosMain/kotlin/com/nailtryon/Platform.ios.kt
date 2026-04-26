package com.nailtryon

actual fun platformName(): String = "iOS"

actual fun createUUID(): String {
    return platform.Foundation.NSUUID().UUIDString()
}
