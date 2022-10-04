package appstrument.server;

public class AppstrumentException extends RuntimeException {
    public AppstrumentException(String message) {
        super(message);
    }

    public AppstrumentException(Throwable ex) {
        super(ex);
    }

    public AppstrumentException(String message, Throwable ex) {
        super(message, ex);
    }
}
