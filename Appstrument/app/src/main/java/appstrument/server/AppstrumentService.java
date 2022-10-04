package appstrument.server;

import android.app.Service;
import android.content.Intent;
import android.os.IBinder;
import android.util.Log;

import androidx.annotation.Nullable;

public class AppstrumentService extends Service {
    private AppstrumentServer server;

    @Nullable
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
