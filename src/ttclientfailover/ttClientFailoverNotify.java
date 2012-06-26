/*
 * To change this template, choose Tools | Templates
 * and open the template in the editor.
 */
package ttclientfailover;

import com.timesten.jdbc.ClientFailoverEvent;
import com.timesten.jdbc.ClientFailoverEventListener;
import java.io.PrintStream;
import java.util.Calendar;

/**
 *
 * @author rstyczynski
 */
public class ttClientFailoverNotify implements ClientFailoverEventListener {

    public static Timer timer = new Timer();
    public static int counter;
    Log log = new Log();
    long now;

    String logName, logExtension;
    
    public void setLog (String _name, String _extension, PrintStream _console) {
        log.console=_console;
        log.logExt = _extension;
        logName = _name;
        logExtension = _extension;
    }
            
    public void notify(ClientFailoverEvent event) {
        ClientFailoverEvent.FailoverEvent theEvent = event.getTheFailoverEvent();
        try {
            now=System.currentTimeMillis();
            switch (theEvent) {
                case BEGIN:
                    timer.start();
                    counter++;
                    log.create(logName + "-" + counter);
                    timer.stop();
                    log.msg(now+ "\t" + "Failover " + counter + ":" + event + "\t" + timer.getTimeInMs());
                    break;
                case END:
                    timer.stop();
                    log.msg(now+ "\t" + "Failover " + counter + ":" + event + "\t" + timer.getTimeInMs());
                    log.close();
                    break;
                case ABORT:
                    timer.stop();
                    log.msg(now+ "\t" + "Failover " + counter + ":" + event + "\t" + timer.getTimeInMs());
                    log.close();
                    break;
                case REAUTH:
                    timer.stop();
                    log.msg(now+ "\t" + "Failover " + counter + ":" + event + "\t" + timer.getTimeInMs());
                    break;
                case ERROR:
                    timer.stop();
                    log.msg(now+ "\t" + "Failover " + counter + ":" + event + "\t" + timer.getTimeInMs());
                    break;
            }
        } catch (Exception ex) {
            System.err.println("Exception:" + ex.getClass() + ": " + ex.getMessage() + "\t" + now+ "\t" + "Failover " + counter + ":" + event + "\t" + timer.getTimeInMs());
        }
    }       
}
