package com.maxhall.ailink

import android.app.Application
import android.os.Bundle
import com.umeng.commonsdk.UMConfigure
import com.umeng.umcrash.UMCrash

class MyApplication : Application() {
    override fun onCreate() {
        super.onCreate()
        UMCrash.setDebug(BuildConfig.DEBUG)

        // 配置 Native 采集开关（必须在 preInit 之前调用）
        val bundle = Bundle().apply {
            putBoolean(UMCrash.KEY_ENABLE_CRASH_JAVA, true)
            putBoolean(UMCrash.KEY_ENABLE_CRASH_NATIVE, true)
            putBoolean(UMCrash.KEY_ENABLE_CRASH_UNEXP, true)
            putBoolean(UMCrash.KEY_ENABLE_ANR, false)
            putBoolean(UMCrash.KEY_ENABLE_PA, false)
            putBoolean(UMCrash.KEY_ENABLE_LAUNCH, false)
            putBoolean(UMCrash.KEY_ENABLE_MEM, false)
            putBoolean(UMCrash.KEY_ENABLE_NET, false)
            putBoolean(UMCrash.KEY_ENABLE_CODE_LOG, false)
            putBoolean(UMCrash.KEY_ENABLE_H5PAGE, false)
            putBoolean(UMCrash.KEY_ENABLE_POWER, false)
        }
        UMCrash.initConfig(bundle)

        // 预初始化
        UMConfigure.enableImeiCollection(false)
        UMConfigure.enableImsiCollection(false)
        UMConfigure.enableIccidCollection(false)
        UMConfigure.enableWiFiMacCollection(false)
        UMConfigure.enableAplCollection(false)
        UMConfigure.enableInstallReferrerCollection(false)
        UMConfigure.preInit(this, "6aef1438863270068cba2f0c", BuildConfig.UMENG_CHANNEL)
    }
}
