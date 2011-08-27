package ttclientfailover;

import com.timesten.jdbc.ClientFailoverEventListener;
import com.timesten.jdbc.TimesTenConnection;
import java.io.BufferedReader;
import java.io.File;
import java.io.FileInputStream;
import java.io.InputStreamReader;
import java.sql.Connection;
import java.sql.Driver;
import java.sql.DriverManager;
import java.sql.ResultSet;
import java.sql.SQLException;
import java.sql.Statement;
import java.util.HashMap;

/**
 *
 * @author rstyczynski
 */
public class ttClientFailoverCtrl {

    /**
     * @param args the command line arguments
     */
    public static void main(String[] args) throws Exception {

        ttClientFailoverCtrl me = new ttClientFailoverCtrl();
        String ttURL;
        String ttUID = null;
        String ttPWD = null;
        HashMap ttCfg = null;
        String ttSQL = "select * from dual";

        TimesTenConnection connection = null;
        ttClientFailoverNotify notify = new ttClientFailoverNotify();

        //control loop
        File cmdFIFO = new File("/Users/rstyczynski/NetBeansProjects/ttclientfailover/dist/control");
        BufferedReader cmdFD;
        String cmd = "";
        String line;
        String lineTokens[];

        Statement bufferedStmt = null;
        ResultSet rs = null;
        String response = null;
        
        Log log = new Log();
        log.console=System.out;
        log.logExt="msg";
        Log err = new Log();
        err.console=System.err;
        err.logExt="err";
        
        //cmdFD = new BufferedReader(new InputStreamReader(new FileInputStream(cmdFIFO)));
        cmdFD = new BufferedReader(new InputStreamReader(System.in));
        
        if (args.length != 1) {
            throw new Exception("Test id not specified!");
        }
        String testId = args[0];
        
        log.msg("Available commands:" + me.cmdDir.keySet());
        log.msg("Ready to go.");
      
        int step = 0;
        int tokenPos;
        String error = "";
        while (!"exit".equals(cmd)) {
            line = cmdFD.readLine();
            if (line == null) {
                Thread.sleep(100);
            } else {    
                lineTokens = line.split(" ");
                tokenPos=0;
                try {
                    step = new Integer(lineTokens[tokenPos]).intValue();
                    tokenPos++;
                } catch (NumberFormatException e) {
                    step++;
                }
                
                try {
                    cmd = lineTokens[tokenPos];
                    tokenPos++;
                } catch (ArrayIndexOutOfBoundsException e) {
                    cmd="";
                }

                log.create(testId + "." + step, "Step " + step + " - BEGIN");
                err.create(testId + "." + step, "Step " + step + " - BEGIN");
                //log.msg("Step " + step + " - BEGIN", false);
                try {
                    switch (me.cmdInt(cmd)) {
                        case COMMENT:
                            StringBuffer comment = new StringBuffer();
                            for (int i = tokenPos; i < lineTokens.length; i++) {
                                comment.append(" ").append(lineTokens[i]);
                            }                            
                            log.msg("Comment:" + comment.toString());
                            break;
                        case CFG:
                            ttCfg = me.getConfiguration(connection);
                            log.msg(ttCfg.toString());

                            for (int i = tokenPos; i < lineTokens.length; i++) {
                                log.msg(lineTokens[i] + "=" + ttCfg.get(lineTokens[i]));
                            }
                            break;
                        case CONNECT:
                            if (lineTokens.length < (tokenPos+1)) {
                                throw new Exception("Connection string not specified");
                            }
                            String conStr = lineTokens[tokenPos];
                            log.msg("Connection string:" + conStr);

                            HashMap conAttr = new HashMap();
                            String connElements[] = conStr.split(";");
                            for (int i = 0; i < connElements.length; i++) {
                                String conKeyVal[] = connElements[i].split("=");
                                if (conKeyVal.length != 2) {
                                    throw new Exception("Attribute specified with no value, info:" + conKeyVal[0].toLowerCase());
                                }
                                conAttr.put(conKeyVal[0].toLowerCase(), conKeyVal[1]);
                            }

                            //theoretically uid, pwd may be specified in *.odbc.ini, but this does not work
                            //User authentication failed is returned after >120s
                            ttUID = (String) conAttr.get("uid");
                            ttPWD = (String) conAttr.get("pwd");

                            if (ttUID == null) {
                                throw new Exception("UID not specified");
                            }
                            if (ttPWD == null) {
                                throw new Exception("PWD not specified");
                            }
                            ttURL = "jdbc:timesten:client:" + conStr;
                            if (connection != null) {
                                try {
                                    connection.removeConnectionEventListener(notify);
                                } catch (SQLException sQLException) {
                                    err.msg("Warning: Not possible to remove event listener from previous connection");
                                }
                                
                                try {
                                    connection.close();
                                } catch (SQLException sQLException) {
                                    err.msg("Warning: Not possible to close previous connection");
                                }
                            }

                            Class clsDriver;
                            clsDriver = Class.forName("com.timesten.jdbc.TimesTenDriver");
                            Driver driver = (Driver) clsDriver.newInstance();
                            DriverManager.registerDriver(driver);

                            connection = (TimesTenConnection) DriverManager.getConnection(ttURL, ttUID, ttPWD);
                            notify.setLog(testId + "-notify", "msg", System.out);
                            connection.addConnectionEventListener(notify);

                            //TODO: this is not returned by ttConfiguration
                            //check if client failover is configured
//                        ttCfg = me.getConfiguration(connection);
//                        if (!ttCfg.containsKey("ttc_server2")) {
//                            throw new Exception("Failover server not specified");
//                        }
//                        if (!ttCfg.containsKey("ttc_server_dsn2")) {
//                            log.msg("Warning: Failover DSN not specified. TTC_Server_DSN2 is set to the TTC_Server_DSN value ");
//                        }
//                        if (!ttCfg.containsKey("tcp_port2")) {
//                            log.msg("Warning: Failover port not specified. TCP_Port2 is set to the TCP_Port value");
//                        }

                            break;
                        case INIT://init
                            if (bufferedStmt != null) {
                                bufferedStmt.close();
                            }
                            bufferedStmt = connection.createStatement();
                            log.msg("Statement initialized");
                            break;
                        case QUICK://quick
                            log.msg("Quick step");
                            log.msg("Host:" + me.getHost(connection));
                            log.msg("Status:" + me.getRepStatus(connection));
                            
                            rs = bufferedStmt.executeQuery(ttSQL);
                            rs.next();
                            response = rs.getString(1);
                            log.msg("Resp:" + response);
                            rs.close();
                            break;
                        case UNKNOWN:
                            log.msg("Unknown command:'" + cmd + "'. Executing step.");
                            //break;
                        case STEP://step
                            log.msg("Step");
                            log.msg("Host:" + me.getHost(connection));
                            log.msg("Status:" + me.getRepStatus(connection));
                            
                            Statement oneTimeStmt = connection.createStatement();
                            rs = oneTimeStmt.executeQuery(ttSQL);
                            rs.next();
                            response = rs.getString(1);
                            log.msg("Resp:" + response);
                            rs.close();
                            oneTimeStmt.close();
                            break;
                        case HELP://help
                            log.msg("Available commands:" + me.cmdDir.keySet());
                            break;
                        case EXIT://exit
                            if (bufferedStmt != null) {
                                bufferedStmt.close();
                            }
                            log.msg("Done.");
                            break;
                    }
                } catch (SQLException a) {
                    error = a.getClass() + "\t"+ a.getSQLState()+ "\t" + a.getErrorCode() + "\t" + a.getMessage();
                    err.msg(error);
                    log.msg(error, false);               
                } catch (Exception a) {
                    error = a.getClass() + "\t" + a.getMessage();
                    err.msg(error);
                    log.msg(error, false);
                }
                //log.msg("Step " + step + " - END", false);
                log.close("Step " + step + " - END");
                err.close("Step " + step + " - END");
            }//line null
        }//while
        cmdFD.close();
        //file.close();
    }

    public HashMap getConfiguration(Connection connection) throws Exception {
        HashMap ttCfg = new HashMap();
        Statement stmt = connection.createStatement();
        ResultSet rs = stmt.executeQuery("{call ttconfiguration()}");
        while (rs.next()) {
            ttCfg.put(rs.getString(1).toLowerCase(), rs.getString(2));
        }
        rs.close();
        stmt.close();
        return ttCfg;
    }

    public String getHost(Connection connection) throws Exception {
        Statement stmt = connection.createStatement();
        ResultSet rs = stmt.executeQuery("select value from nodeinfo where key='dsn@host:serverport'");
        rs.next();
        String response = rs.getString(1);
        rs.close();
        stmt.close();

        return response;
    }
    
    public String getRepStatus(Connection connection) throws Exception {
        Statement stmt = connection.createStatement();
        ResultSet rs = stmt.executeQuery("{call ttRepStateGet()}");
        rs.next();
        String response = rs.getString(1);
        rs.close();
        stmt.close();

        return response;
    }
        
    HashMap cmdDir = new HashMap();

    public ttClientFailoverCtrl() {
        cmdDir.put("step", STEP);
        cmdDir.put("quick", QUICK);
        cmdDir.put("init", INIT);
        cmdDir.put("?", HELP);
        cmdDir.put("help", HELP);
        cmdDir.put("exit", EXIT);
        cmdDir.put("connect", CONNECT);
        cmdDir.put("cfg", CFG);
        cmdDir.put("comment", COMMENT);
    }

    private int cmdInt(String cmd) {
        if (cmdDir.containsKey(cmd)) {
            return ((Integer) cmdDir.get(cmd)).intValue();
        } else {
            return UNKNOWN;
        }
    }
    static final int EXIT = 100;
    static final int HELP = 99;
    static final int COMMENT = 98;
    
    static final int CFG = 5;
    static final int CONNECT = 4;
    static final int INIT = 3;
    static final int QUICK = 2;
    static final int STEP = 1;
    static final int UNKNOWN = -1;
}
