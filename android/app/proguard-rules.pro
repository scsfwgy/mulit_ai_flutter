# 插件及依赖使用各自的 consumer rules；仅为反射/JNI 添加精确保留规则。

# 友盟 SDK 混淆规则
-keep class com.umeng.** {*;}
-keep class com.uc.** {*;}
-keepclassmembers class * {
    public <init> (org.json.JSONObject);
}
-keepclassmembers enum * {
    public static **[] values();
    public static ** valueOf(java.lang.String);
}

# U-APM network monitoring is disabled; its optional OkHttp adapter is unused.
-dontwarn okhttp3.Call
-dontwarn okhttp3.Callback
-dontwarn okhttp3.Connection
-dontwarn okhttp3.EventListener$Factory
-dontwarn okhttp3.EventListener
-dontwarn okhttp3.Handshake
-dontwarn okhttp3.Headers
-dontwarn okhttp3.HttpUrl
-dontwarn okhttp3.Interceptor$Chain
-dontwarn okhttp3.Interceptor
-dontwarn okhttp3.MediaType
-dontwarn okhttp3.OkHttpClient$Builder
-dontwarn okhttp3.OkHttpClient
-dontwarn okhttp3.Protocol
-dontwarn okhttp3.Request$Builder
-dontwarn okhttp3.Request
-dontwarn okhttp3.RequestBody
-dontwarn okhttp3.Response$Builder
-dontwarn okhttp3.Response
-dontwarn okhttp3.ResponseBody
