package appstrument.server;

import android.util.Log;

import org.java_websocket.WebSocket;

import java.io.BufferedReader;
import java.io.InputStreamReader;
import java.util.HashMap;
import java.util.Map;

public class LogcatUtil {
    public static boolean consumeLogcat = true;
    private static Thread readThread;

    public static void startReadThread() {
        readThread = new Thread(() -> {
            LogUtil.print("Started Logcat thread!");
            try {
                Runtime.getRuntime().exec("logcat -c").waitFor();
                Process process = Runtime.getRuntime().exec("logcat");
                BufferedReader bufferedReader = new BufferedReader(
                        new InputStreamReader(process.getInputStream()));

                String line;
                while ((line = bufferedReader.readLine()) != null) {
                    if (consumeLogcat) {
                        Map<WebSocket, AppstrumentNative> copy = new HashMap<>(AppstrumentServer.instance.natives);
                        for (Map.Entry<WebSocket, AppstrumentNative> entry : copy.entrySet()) {
                            byte[] packet = entry.getValue().createLogcatPacket(line);
                            entry.getKey().send(AppstrumentServer.gzipCompress(packet));
                        }
                    }
                }
            } catch (Exception e) {
                LogUtil.print(Log.getStackTraceString(e));
            }
            LogUtil.print("Exiting LogCat thread!");
        });
        readThread.setName("Appstrument Logcat Thread");
        readThread.start();
    }
}
