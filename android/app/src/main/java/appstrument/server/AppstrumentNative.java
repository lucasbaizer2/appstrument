package appstrument.server;

public class AppstrumentNative {
    private long contextPtr;

    public AppstrumentNative() {
        contextPtr = nativeCreateContext();
    }

    public static void initialize() {
        nativeInitialize();
    }

    private static native void nativeInitialize();

    private native long nativeCreateContext();

    private native byte[] nativeCreateLogcatPacket(long context, String content);

    private native byte[] nativeHandleRequest(long context, byte[] request, int offset);

    private native void nativeDestroyContext(long context);

    public byte[] handleRequest(byte[] request, int offset) {
        return nativeHandleRequest(contextPtr, request, offset);
    }

    public byte[] createLogcatPacket(String log) {
        return nativeCreateLogcatPacket(contextPtr, log);
    }

    public void destroy() {
        nativeDestroyContext(contextPtr);
    }
}
