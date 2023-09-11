package appstrument.server;

import android.app.Service;
import android.content.Intent;
import android.os.IBinder;
import android.util.Log;
import java.net.Inet4Address;
import java.net.InetAddress;
import java.net.NetworkInterface;
import java.net.SocketException;
import java.util.Enumeration;

public class AppstrumentService extends Service {
    private AppstrumentServer server;

    static {
        System.loadLibrary("appstrument");
        AppstrumentNative.initialize();
    }

    public static String getLocalIpAddress() {
        try {
            for (Enumeration<NetworkInterface> en = NetworkInterface.getNetworkInterfaces(); en.hasMoreElements(); ) {
                NetworkInterface intf = en.nextElement();
                for (Enumeration<InetAddress> enumIpAddr = intf.getInetAddresses(); enumIpAddr.hasMoreElements(); ) {
                    InetAddress inetAddress = enumIpAddr.nextElement();
                    if (!inetAddress.isLoopbackAddress() && inetAddress instanceof Inet4Address) {
                        return inetAddress.getHostAddress();
                    }
                }
            }
        } catch (SocketException ex) {
            ex.printStackTrace();
        }
        return null;
    }

    @Override
    public IBinder onBind(Intent intent) {
        return null;
    }

    @Override
    public int onStartCommand(Intent intent, int flags, int startId) {
        if (this.server != null) {
            LogUtil.print("Restarting Appstrument service.");
            try {
                this.server.stop();
            } catch (InterruptedException e) {
                e.printStackTrace();
            }
        } else {
            LogUtil.print("Starting Appstrument service.");
            LogUtil.print("IP Address: " + getLocalIpAddress());
        }
        this.server = new AppstrumentServer(32900);
        LogcatUtil.startReadThread();
        this.server.start();

        return START_NOT_STICKY;
    }

    @Override
    public void onDestroy() {
        super.onDestroy();

        LogUtil.print("Stopping Appstrument service.");
        try {
            this.server.stop();
        } catch (InterruptedException e) {
            throw new RuntimeException(e);
        }

        this.server = null;
    }
}
