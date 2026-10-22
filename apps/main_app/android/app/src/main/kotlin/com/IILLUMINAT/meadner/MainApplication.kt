package com.IILLUMINAT.meadner

import android.app.Application
import android.util.Log
import io.flutter.FlutterInjector

class MainApplication : Application() {
    override fun onCreate() {
        super.onCreate()

        Log.i("MainApplication", "onCreate() called - starting Flutter initialization")
        Log.i("MainApplication", "packageName=$packageName")

        try {
            val loader = FlutterInjector.instance().flutterLoader()
            Log.i("MainApplication", "FlutterLoader obtained, initialized=${loader.initialized()}")
            
            if (!loader.initialized()) {
                Log.i("MainApplication", "Starting Flutter initialization...")
                loader.startInitialization(this)
                Log.i("MainApplication", "Ensuring initialization complete...")
                loader.ensureInitializationComplete(this, null)
                Log.i("MainApplication", "Flutter initialization completed successfully")
            } else {
                Log.i("MainApplication", "Flutter already initialized")
            }
        } catch (e: Exception) {
            Log.e("MainApplication", "FlutterLoader init failed", e)
            throw e
        }
    }
}
