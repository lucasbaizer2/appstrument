package appstrument.server;

import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;

public class AppstrumentReceiver extends BroadcastReceiver  {
    @Override
    public void onReceive(Context context, Intent arg1) {
        Intent intent = new Intent(context, AppstrumentService.class);
        context.startService(intent);
    }
}
