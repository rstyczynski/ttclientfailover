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
        String connectionString="TTC_SERVER=ozone1;TTC_SERVER_DSN=repdb1_1121;TCP_PORT=53389;TTC_SERVER2=ozone2;TTC_SERVER_DSN2=repdb2_1121;TCP_PORT2=53385;uid=appuser;pwd=appuser";
        String ttSelectSQL = "select * from dual";
        String ttInsertSQL = "insert into customers values (PK,'a','b','c')";
        String ttDeleteSQL = "delete from customers where cust_number=PK";
        String ttUpdateSQL = "update customers set address='VALUE' where cust_number=PK";

        TimesTenConnection connection = null;
        ttClientFailoverNotify notify = new ttClientFailoverNotify();

        //control loop
        File cmdFIFO = new File("/Users/rstyczynski/NetBeansProjects/ttclientfailover/dist/control");
        BufferedReader cmdFD;
        String cmd = "";
        String line;
        String lineTokens[];

        Statement bufferedStmt = null;
        String response = null;
        
        Log log = new Log();
        log.console=System.out;
        log.logExt="msg";
        Log err = new Log();
        err.console=System.err;
        err.logExt="exc";
        
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

                            try {
                                Class clsDriver;
                                clsDriver = Class.forName("com.timesten.jdbc.TimesTenDriver");
                                Driver driver = (Driver) clsDriver.newInstance();
                                DriverManager.registerDriver(driver);
                                
                                connection = (TimesTenConnection) DriverManager.getConnection(ttURL, ttUID, ttPWD);
                                notify.setLog(testId + "-notify", "msg", System.out);
                                connection.addConnectionEventListener(notify);
                            } catch (Exception ex) {
                                log.msg("Error, info:" + ex.getMessage());
                                throw ex;
                            }
                            log.msg("Connected to:" + conStr);

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
                        case PREPARED://quick
                            log.msg("Prepared select");
                            log.msg("Host:" + me.getHost(connection));
                            log.msg("Status:" + me.getRepStatus(connection));
                            
                            ResultSet rs = bufferedStmt.executeQuery(ttSelectSQL);
                            rs.next();
                            response = rs.getString(1);
                            log.msg("Resp:" + response);
                            rs.close();
                            break;
                        case UNKNOWN:
                            log.msg("Unknown command:'" + cmd);
                            break;
                            
                        case UPDATE://step
                            String updateValue;
                            String updatePK;
                            if (lineTokens.length < (tokenPos+2)) {
                                throw new Exception("Update PK and VALUE string not specified");
                            }
                            updatePK=lineTokens[tokenPos];
                            updateValue=lineTokens[tokenPos+1];
                            
                            log.msg("Update");
                            log.msg("Host:" + me.getHost(connection));
                            log.msg("Status:" + me.getRepStatus(connection));
                            
                            Statement oneTimeUpdateStmt = connection.createStatement();
                            oneTimeUpdateStmt.executeQuery(ttUpdateSQL.replaceFirst("PK", updatePK).replaceFirst("VALUE", updateValue));
                            int rowUpdateCount = oneTimeUpdateStmt.getUpdateCount();
                            log.msg("Resp:" + rowUpdateCount);
                            oneTimeUpdateStmt.close();
                            break;
                        
                        case INSERT://step
                            String insertValue;
                            if (lineTokens.length < (tokenPos+1)) {
                                throw new Exception("Insert value string not specified");
                            }
                            insertValue=lineTokens[tokenPos];
                            
                            log.msg("Insert");
                            log.msg("Host:" + me.getHost(connection));
                            log.msg("Status:" + me.getRepStatus(connection));
                            
                            Statement oneTimeStmt = connection.createStatement();
                            oneTimeStmt.executeQuery(ttInsertSQL.replaceFirst("PK", insertValue));
                            int rowCount = oneTimeStmt.getUpdateCount();
                            log.msg("Resp:" + rowCount);
                            oneTimeStmt.close();
                            break;
                        case SELECT://step
                            log.msg("Select");
                            log.msg("Host:" + me.getHost(connection));
                            log.msg("Status:" + me.getRepStatus(connection));
                            
                            Statement oneTimeSelectStmt = connection.createStatement();
                            ResultSet rsSelect = oneTimeSelectStmt.executeQuery(ttSelectSQL);
                            rsSelect.next();
                            response = rsSelect.getString(1);
                            log.msg("Resp:" + response);
                            rsSelect.close();
                            oneTimeSelectStmt.close();
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
                    error = a.getClass() + "\t" + a.getMessage() + "@" + a.getStackTrace()[0];
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
        //cmdDir.put("sql", SQL);
        //mdDir.put("insert", DELETE);
        cmdDir.put("update", UPDATE);
        cmdDir.put("insert", INSERT);
        cmdDir.put("select", SELECT);
        cmdDir.put("quick", PREPARED);
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
    
    static final int CFG = 50;
    static final int CONNECT = 40;
    static final int INIT = 30;
    static final int PREPARED = 20;
    static final int SQL = 5;
    static final int DELETE = 4;
    static final int UPDATE = 3;
    static final int INSERT = 2;
    static final int SELECT = 1;
    static final int UNKNOWN = -1;
}
