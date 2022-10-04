package appstrument.server;

import android.util.Log;

public class LogUtil {
    private static final String TAG = "Appstrument";

    public static void print(Object value) {
        if (value == null) {
            Log.d(TAG, "null");
        } else {
            Log.d(TAG, value.toString());
        }
    }
}
