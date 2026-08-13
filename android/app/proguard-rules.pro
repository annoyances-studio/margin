# JGit (git-read spike) references JVM/desktop-only classes on code paths that
# Android never executes — process handles, JMX monitoring, Kerberos/GSS auth,
# and the slf4j static binder. Silence R8's missing-class errors for those, and
# keep JGit + its LFS add-on from being stripped or renamed (they load pieces
# reflectively and via ServiceLoader, which R8 can't see).
-dontwarn java.lang.ProcessHandle
-dontwarn java.lang.management.**
-dontwarn javax.management.**
-dontwarn org.ietf.jgss.**
-dontwarn org.slf4j.impl.**
-dontwarn org.eclipse.jgit.**

-keep class org.eclipse.jgit.** { *; }
-keep class org.eclipse.jgit.lfs.** { *; }
