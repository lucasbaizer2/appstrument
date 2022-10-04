package appstrument.server;

import java.util.Arrays;
import java.util.Map;
import java.util.stream.Collectors;

public class ProcessUtil {
    public static JavaThread[] getThreads() {
        Map<Thread, StackTraceElement[]> threads = Thread.getAllStackTraces();
        JavaThread[] javaThreads = new JavaThread[threads.size()];
        int i = 0;
        for (Map.Entry<Thread, StackTraceElement[]> entry : threads.entrySet()) {
            String stackTrace = Arrays.stream(entry.getValue()).map(StackTraceElement::toString).collect(Collectors.joining("\n"));
            javaThreads[i++] = new JavaThread(
                    entry.getKey().getName(),
                    entry.getKey().isDaemon(),
                    stackTrace);
        }
        return javaThreads;
    }
}
