package com.fenixresources.wellness

import android.app.Application
import com.fenixresources.wellness.data.SessionStore
import com.fenixresources.wellness.data.SupabaseApi

class FenixApplication : Application() {
    val api by lazy { SupabaseApi(this, SessionStore(this)) }
}
