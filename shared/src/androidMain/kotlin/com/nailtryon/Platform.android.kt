package com.nailtryon

actual fun platformName(): String = "Android"

actual fun createUUID(): String {
    return java.util.UUID.randomUUID().toString()
}
