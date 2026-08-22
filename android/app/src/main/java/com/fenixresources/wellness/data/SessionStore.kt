package com.fenixresources.wellness.data

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import java.nio.ByteBuffer
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/** Persists session tokens encrypted with a non-exportable Android Keystore key. */
class SessionStore(context: Context) {
    private val preferences = context.getSharedPreferences("fenix-session", Context.MODE_PRIVATE)
    private val keyAlias = "fenix-session-key"

    var accessToken: String?
        get() = read("access_token")
        set(value) = write("access_token", value)

    var refreshToken: String?
        get() = read("refresh_token")
        set(value) = write("refresh_token", value)

    fun clear() = preferences.edit().clear().apply()

    private fun write(name: String, value: String?) {
        val editor = preferences.edit()
        if (value == null) editor.remove(name) else editor.putString(name, encrypt(value))
        editor.apply()
    }

    private fun read(name: String): String? = preferences.getString(name, null)?.let {
        runCatching { decrypt(it) }.getOrElse { clear(); null }
    }

    private fun encrypt(value: String): String {
        val cipher = Cipher.getInstance("AES/GCM/NoPadding").apply { init(Cipher.ENCRYPT_MODE, secretKey()) }
        val encrypted = cipher.doFinal(value.toByteArray(Charsets.UTF_8))
        return Base64.encodeToString(ByteBuffer.allocate(cipher.iv.size + encrypted.size).put(cipher.iv).put(encrypted).array(), Base64.NO_WRAP)
    }

    private fun decrypt(value: String): String {
        val packed = Base64.decode(value, Base64.NO_WRAP)
        require(packed.size > 12)
        val iv = packed.copyOfRange(0, 12)
        val ciphertext = packed.copyOfRange(12, packed.size)
        val cipher = Cipher.getInstance("AES/GCM/NoPadding").apply { init(Cipher.DECRYPT_MODE, secretKey(), GCMParameterSpec(128, iv)) }
        return cipher.doFinal(ciphertext).toString(Charsets.UTF_8)
    }

    private fun secretKey(): SecretKey {
        val store = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        (store.getKey(keyAlias, null) as? SecretKey)?.let { return it }
        return KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore").apply {
            init(KeyGenParameterSpec.Builder(keyAlias, KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .build())
        }.generateKey()
    }
}
