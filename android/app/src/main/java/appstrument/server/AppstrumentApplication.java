package appstrument.server;

import android.app.Application;
import android.content.Context;
import android.content.Intent;

public class AppstrumentApplication extends Application {
    @Override
    public void onCreate() {
        super.onCreate();

        startService(new Intent(this, AppstrumentService.class));
    }
}
