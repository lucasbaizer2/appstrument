package appstrument.server;

public class JavaThread {
    public String name;
    public boolean isDaemon;
    public String stackTrace;

    public JavaThread(String name, boolean isDaemon, String stackTrace) {
        this.name = name;
        this.isDaemon = isDaemon;
        this.stackTrace = stackTrace;
    }
}
