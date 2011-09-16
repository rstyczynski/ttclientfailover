/*
 * To change this template, choose Tools | Templates
 * and open the template in the editor.
 */
package ttclientfailover;

import java.io.File;
import java.io.FileWriter;
import java.io.PrintStream;
import java.text.SimpleDateFormat;
import java.util.Calendar;

/**
 *
 * @author rstyczynski
 */
public class Log {
long lastLog=0;
long deltaLog=0;
long now=0;
FileWriter fileLog;
String logName; 
String logExt;
String logNameTmp;
PrintStream console;
Timer timer = new Timer();

public void Log(PrintStream _console, String _extension) {
    console = _console;
    logExt = _extension;
}

public void create(String _name) throws Exception {
    create(_name,"");
}
public void create(String _name, String _msg) throws Exception {
    logName = _name;
    logNameTmp = logName + "." + logExt + ".tmp";
    File file = new File(logNameTmp);
    file.createNewFile();
    fileLog = new FileWriter(logNameTmp);
    timer.start();
    msg(_msg,false);
}

public void close() throws Exception {
    close("");
}

public void close(String _msg) throws Exception {
   timer.stop();
   msg(_msg,false);
   
   fileLog.flush();
   fileLog.close();
   fileLog = null;
   
   File filetmp = new File(logNameTmp);
   File file = new File(logName + "." + logExt);
   filetmp.renameTo(file);

}

public void msg (String msg) throws Exception {
    msg(msg, true);
}

public void msg (String msg, boolean write2log) throws Exception {
    final String timeString =
    new SimpleDateFormat("HH:mm:ss:SSS").format(Calendar.getInstance().getTime());
    now=Calendar.getInstance().getTimeInMillis();

    if (lastLog == 0)
        deltaLog=0;
    else {
        deltaLog=now-lastLog;
    }
    lastLog=now;
    
    if ( console != null ) {
        console.println(timeString + "\t" + deltaLog + "\t" + timer.getInStepTime() + "\t" + msg);
    }
    
    if (fileLog != null && write2log) {
        fileLog.write(msg+'\n');
        fileLog.flush();
    }
}
    
}
