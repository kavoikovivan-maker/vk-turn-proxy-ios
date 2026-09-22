package com.wdtt.client

import android.content.Intent
import android.os.Bundle
import androidx.activity.ComponentActivity

/**
 * Lightweight K&C launcher. No bundled video or binary asset is required,
 * which keeps CI/release builds reproducible.
 */
class SplashScreenActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        startActivity(Intent(this, MainActivity::class.java))
        finish()
    }
}
