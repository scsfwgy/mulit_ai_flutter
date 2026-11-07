# Umeng Flutter adapters

Sources: the official `umeng_common_sdk` 1.3.1 and `umeng_apm_sdk` 2.3.7
packages downloaded by the official Umeng integration workflow. Upstream
LICENSE files are retained in each package. The native SDKs remain package
manager dependencies, not copied binaries.

These small source copies make the official integration's cache repairs
reproducible on a fresh checkout:

- Common: remove duplicate Kotlin/Swift stubs; replace jcenter, raise compileSdk;
  pin Android common 10.0.1 / asms 1.8.7.2; finish initialization method replies
  and expose the native debug logging switch. The app bridge controls Firebase
  and native analytics; native monitor changes require restarting the process.
- APM: retain HTTP 1.x compatibility (the app uses MediaType); gate binding, queues and uploads
  using the persisted collection preference, use the active Flutter render view, and avoid
  replacing an existing binding.
- Both iOS plugins target iOS 15 and allow Apple Silicon simulator builds.
- Flutter exception payloads retain only the error type and package stack
  frames. Exception messages, custom attributes and absolute local paths are
  removed before entering the SDK's queues. API tracing stays disabled.

The rest of the SDK source is retained without a general style refactor.
Recheck these patches against upstream when upgrading.
