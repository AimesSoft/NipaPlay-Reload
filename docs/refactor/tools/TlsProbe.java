import java.net.URL;
import java.security.cert.Certificate;
import javax.net.ssl.HttpsURLConnection;

public class TlsProbe {
    public static void main(String[] args) throws Exception {
        String host = args.length > 0 ? args[0] : "https://services.gradle.org/distributions/gradle-9.1.0-all.zip";
        HttpsURLConnection c = (HttpsURLConnection) new URL(host).openConnection();
        c.setConnectTimeout(15000);
        c.setReadTimeout(15000);
        c.setRequestMethod("HEAD");
        try {
            c.connect();
            Certificate[] chain = c.getServerCertificates();
            for (Certificate cert : chain) {
                System.out.println("CERT: " + cert);
            }
            System.out.println("RESPONSE: " + c.getResponseCode());
        } catch (Exception e) {
            System.out.println("FAILED: " + e);
            Throwable cause = e;
            while (cause.getCause() != null) cause = cause.getCause();
            System.out.println("ROOT CAUSE: " + cause);
        }
    }
}
