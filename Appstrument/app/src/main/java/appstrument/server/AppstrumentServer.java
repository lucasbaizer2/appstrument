package appstrument.server;

import android.util.Log;

import org.java_websocket.WebSocket;
import org.java_websocket.handshake.ClientHandshake;
import org.java_websocket.server.WebSocketServer;

import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.net.InetSocketAddress;
import java.nio.ByteBuffer;
import java.util.HashMap;
import java.util.zip.GZIPOutputStream;

public class AppstrumentServer extends WebSocketServer {
    public static AppstrumentServer instance;
    public HashMap<WebSocket, AppstrumentNative> natives = new HashMap<>();

    public AppstrumentServer(int port) {
        super(new InetSocketAddress(port));
        instance = this;
    }

    public static byte[] gzipCompress(byte[] uncompressedData) {
        try (ByteArrayOutputStream bos = new ByteArrayOutputStream(uncompressedData.length);
             GZIPOutputStream gzipOS = new GZIPOutputStream(bos)) {
            gzipOS.write(uncompressedData);
            // You need to close it before using bos
            gzipOS.close();
            return bos.toByteArray();
        } catch (IOException e) {
            throw new AppstrumentException(e);
        }
    }

    @Override
    public void onOpen(WebSocket conn, ClientHandshake handshake) {
        this.natives.put(conn, new AppstrumentNative());
    }

    @Override
    public void onClose(WebSocket conn, int code, String reason, boolean remote) {
        this.natives.remove(conn).destroy();
    }

    @Override
    public void onMessage(WebSocket conn, String message) {
    }

    @Override
    public void onMessage(WebSocket conn, ByteBuffer message) {
        AppstrumentNative appstrumentNative = natives.get(conn);
        byte[] req = message.array();

        byte[] res = new byte[0];
        try {
            res = appstrumentNative.handleRequest(req, 0);
        } catch (Throwable t) {
            LogUtil.print(Log.getStackTraceString(t));
        }
        conn.send(gzipCompress(res));
    }

    @Override
    public void onError(WebSocket conn, Exception ex) {
        throw new RuntimeException(ex);
    }

    @Override
    public void onStart() {
        LogUtil.print("Started WebSocket server.");
    }
}
