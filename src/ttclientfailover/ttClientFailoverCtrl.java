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
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.sql.SQLException;
import java.sql.Statement;
import java.sql.Timestamp;
import java.text.DateFormat;
import java.text.ParseException;
import java.text.SimpleDateFormat;
import java.util.ArrayList;
import java.util.Date;
import java.util.Enumeration;
import java.util.HashMap;
import jline.*;
import java.io.*;
import java.util.LinkedList;
import java.util.List;

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

        String ttSelectPrepSQL = "select * from dual";
        String ttInsertPrepSQL = "insert into customers values (?,'a','b','c')";
        String ttDeletePrepSQL = "delete from customers where cust_number=?";
        String ttUpdatePrepSQL = "update customers set address=? where cust_number=?";
        PreparedStatement ttSelectPrepStmt = null;
        PreparedStatement ttInsertPrepStmt = null;
        PreparedStatement ttDeletePrepStmt = null;
        PreparedStatement ttUpdatePrepStmt = null;
        
        String ttSessionSQL = "select * from NLS_SESSION_PARAMETERS where PARAMETER='NLS_TIMESTAMP_FORMAT'";
                    
        // which query will be executed? SELECT,INSERT,DELETE,UPDATE 
        String doTimestampMask = "";
        int doTimestampPK = 0;
        String doTimestampDate = "";
        String doTimestampTime = "";
        Timestamp doTimestampValue = null;
        String doTimestampString = null;
        
        String ttInsertTimestampPrepSQL = "insert into timestampTest values (?,?)";
        
        String ttSelectTimestampPrepSQL = "select id, timefield from timestampTest where id=? and timefield=?";

        String ttDeleteTimestampPrepSQL = "delete from timestampTest where id<(?+1)";
        String ttDelete2TimestampPrepSQL = "delete from timestampTest where id=? and timefield=?";
        
        String ttUpdateTimestampPrepSQL = "update timestampTest set timefield=? where id=?";
        String ttUpdate2TimestampPrepSQL = "update timestampTest set timefield=? where id=? and timefield<=?";

                
        String ttSelectTimestampTODATE_PrepSQL = "select id, timefield from timestampTest where id=? and timefield=to_date(?,'DD-MON-RR HH.MI.SSXFF AM')";
        String ttDeleteTimestampTODATE_PrepSQL = "delete from timestampTest where id=? and timefield=to_date(?,'DD-MON-RR HH.MI.SSXFF AM')";
        String ttUpdateTimestampTODATE_PrepSQL = "update timestampTest set timefield=to_date(?,'DD-MON-RR HH.MI.SSXFF AM') where id=? and timefield<=to_date(?,'DD-MON-RR HH.MI.SSXFF AM')";
        
        
        PreparedStatement ttSelectTimestampPrepStmt = null;
        PreparedStatement ttInsertTimestampPrepStmt = null;
        PreparedStatement ttUpdateTimestampPrepStmt = null;
        PreparedStatement ttUpdate2TimestampPrepStmt = null;
        PreparedStatement ttDeleteTimestampPrepStmt = null;
        PreparedStatement ttDelete2TimestampPrepStmt = null;
        
        PreparedStatement ttSelectTimestampTODATE_PrepStmt = null;
        PreparedStatement ttDeleteTimestampTODATE_PrepStmt = null;
        PreparedStatement ttUpdateTimestampTODATE_PrepStmt = null;
        
        PreparedStatement[] prepStatements = new PreparedStatement[20];
        int preparedStmtSlot;
        PreparedStatement preparedStmt;
        Boolean[] prepStatementsResult = new Boolean[20];
        
        class varValue {
            String type;
            Object value;
            
            public varValue (String _type, Object _value ){
                this.type=_type;
                this.value=_value;
            }
        };
        HashMap vars = new HashMap<String, varValue>();
        
        TimesTenConnection connection = null;
        ttClientFailoverNotify notify = new ttClientFailoverNotify();

        //control loop
        //File cmdFIFO = new File("/Users/rstyczynski/NetBeansProjects/ttclientfailover/dist/control");
        BufferedReader cmdFD;
        String cmd = "";
        String line;
        String lineTokens[];

        
        String response = null;
        
        Log log = new Log();
        log.console=System.out;
        log.logExt="msg";
        Log err = new Log();
        err.console=System.err;
        err.logExt="exc";
        
        //cmdFD = new BufferedReader(new InputStreamReader(new FileInputStream(cmdFIFO)));
        //cmdFD = new BufferedReader(new InputStreamReader(System.in));
        ConsoleReader reader = new ConsoleReader();
        
        if (args.length != 1) {
            throw new Exception("Test id not specified!");
        }
        String testId = args[0];
        
        log.msg("Available commands:" + me.cmdDir.keySet());
        
        List completors = new LinkedList();
        completors.add(new SimpleCompletor((String[])me.cmdDir.keySet().toArray(new String[0])));
        reader.addCompletor(new ArgumentCompletor(completors));
            
        log.msg("Ready to go.");

        
        int step = 0;
        int tokenPos;
        String error = "";
        while (!"exit".equals(cmd)) {
            

            line = reader.readLine(">");
            
            
            //line = cmdFD.readLine();
                    
            if (line == null || "".equals(line)) {
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
                //log.msg("#command:" + line);
                err.create(testId + "." + step, "Step " + step + " - BEGIN");
                //err.msg("#command:" + line);
                //log.msg("Step " + step + " - BEGIN", false);
                try {
                    switch (me.cmdInt(cmd)) {
                        case PREPARE:
                            if (lineTokens.length <= (tokenPos)) {
                                throw new Exception("Parameters not specified! Usage: prepare <slot> <SQL>");
                            }

                            preparedStmtSlot = (new Integer(lineTokens[tokenPos])).intValue();
                            StringBuffer preparedSQL = new StringBuffer();

                            for (int i = tokenPos+1; i < lineTokens.length; i++) {
                                preparedSQL.append(" ").append(lineTokens[i]);

                            }
                            prepStatements[preparedStmtSlot] = connection.prepareStatement(preparedSQL.toString());
                            log.msg("Prepared statment registered. Slot:" + preparedStmtSlot + 
                                    ", SQL:" + preparedSQL.toString());
                            break;
                        case DEFINE:
                            String varName=lineTokens[tokenPos++];                   
                            String varType=lineTokens[tokenPos++];
                            
                            StringBuffer value = new StringBuffer();
                            for (int i = tokenPos; i < lineTokens.length; i++) {
                                value.append(lineTokens[i]);
                                
                                if(i < lineTokens.length-1) 
                                       value.append(" ");
                            }
                            
                            String varValueString=value.toString();
                            Object varValue = null;      
                            if ("TIMESTAMP".equalsIgnoreCase(varType)) {
                                DateFormat formatter;
                                formatter = new SimpleDateFormat("d-MMM-yy HH.mm.ss");
                                Date varDateValue = (Date) formatter.parse(varValueString);
                                varValue = new Timestamp(varDateValue.getTime());
                            } else if ("INTEGER".equalsIgnoreCase(varType)) {
                                varValue = new Integer(varValueString);
                            } else if ("STRING".equalsIgnoreCase(varType)) {
                                varValue = varValueString;
                            }
                            vars.put(varName, new varValue(varType, varValue));
                            log.msg("Registered variable " + varName + " as " + varType + " := " + varValue );
                            break;
                        case EXEC:
                            if (lineTokens.length <= (tokenPos)) {
                                throw new Exception("Parameters not specified! Usage: exec <slot>");
                            }
                            preparedStmtSlot = (new Integer(lineTokens[tokenPos++])).intValue();
                            
                            
                            //TODO execute prep stmt
                            preparedStmt = prepStatements[preparedStmtSlot];
                            
                            //read variables
                            int varPos = 1;
                            for (int i = tokenPos; i < lineTokens.length; i++) {
                                varName = lineTokens[i];
                                varType = ((varValue)vars.get(varName)).type;
                                varValue = ((varValue)vars.get(varName)).value;
                                
                                if ("string".equalsIgnoreCase(varType)) {
                                    preparedStmt.setString(varPos, (String)varValue);
                                } else if ("integer".equalsIgnoreCase(varType)) {
                                    preparedStmt.setInt(varPos, ((Integer)varValue).intValue());
                                } else if ("timestamp".equalsIgnoreCase(varType)) {
                                    preparedStmt.setTimestamp(varPos, (Timestamp)varValue);
                                  
                                }
                                log.msg("DEBUG: var:" + varPos + "name:" + varName + ", type:" + varType + ", value " + varValue);        
                                varPos++;
                            }
                            prepStatementsResult[preparedStmtSlot] = preparedStmt.execute();
                            break;
                        case FETCH:
                            if (lineTokens.length <= (tokenPos)) {
                                throw new Exception("Parameters not specified! Usage: fetchall <slot>");
                            }
                            preparedStmtSlot = (new Integer(lineTokens[tokenPos++])).intValue();
                            
                            
                            //TODO execute prep stmt
                            if(prepStatementsResult[preparedStmtSlot].booleanValue()) {
                                //returned resultSet
                                ResultSet rs = prepStatements[preparedStmtSlot].getResultSet();
                                rs.next();
                                
                                //log.msg("Column count:" + rs.getMetaData().getColumnCount());
                                response="";
                                for (int i=1;i<=rs.getMetaData().getColumnCount();i++){
                                    response = response + " " + rs.getString(i);
                                }
                                log.msg("Response:" + response);
                            } else {
                                //returned update count of nothing
                                int updateCount = prepStatements[preparedStmtSlot].getUpdateCount();
                                log.msg("Response:" + updateCount);
                            }                          
                            
                            break;
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
//                            if (lineTokens.length < (tokenPos+1)) {
//                                throw new Exception("Connection string not specified");
//                            }
                            String conStr;
                            if (lineTokens.length >= (tokenPos+1)) {
                                conStr = lineTokens[tokenPos];
                            } else {
                                log.msg("Warning: Connection string not specified. Trying environment...");
                                //tturl must be exported in OS before starting program
                                conStr=System.getenv("ttURL");
                                
                                //err.msg(System.getenv().toString());
                                if (conStr == null || "".equals(conStr)) {
                                throw new Exception("Error: Connection string not specified");
                                } else {
                                    log.msg("OK. Connection string taken from environment:" + conStr);
                                }
                            }

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
                        case DISCONNECT://disconect
                            if (connection != null) {
                                //**
//                                if (bufferedStmt != null) {
//                                    try {
//                                        bufferedStmt.close();
//                                    } catch (SQLException sQLException) {
//                                        err.msg("Warning: Prepares statement close error");
//                                    }
//                                 
//                                }

                                                            
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
                            log.msg("Connection closed");
                            break;
                        case INIT://init
                            if (lineTokens.length > (tokenPos)) {
                                String subCommand=lineTokens[tokenPos];
                                if ("TIME".equals(subCommand)) {
                                    if (lineTokens.length > (tokenPos+1)) {
                                        doTimestampMask=lineTokens[tokenPos+2];
                                    } else {
                                        err.msg("Warning: operation mask not specified. Using defaults.");
                                        doTimestampMask="INSERT,SELECT,UPDATE,DELETE";
                                    }
                                    
                                    //ArrayList initializedSQL = new ArrayList();
                                    String[] sqlcommands=doTimestampMask.split(",");
                                    for(int cmdId=0;cmdId<sqlcommands.length;cmdId++){
                                        String sqlCommand=sqlcommands[cmdId];
                                        if("INSERT".equals(sqlCommand)){ 
                                            if(ttInsertTimestampPrepStmt!=null) 
                                                ttInsertTimestampPrepStmt.close();
                                            ttInsertTimestampPrepStmt=connection.prepareStatement(ttInsertTimestampPrepSQL);
                                            log.msg("Initialized " + sqlCommand + ": " + ttInsertTimestampPrepSQL);
                                        }
                                        
                                        if("SELECT".equals(sqlCommand)) {
                                            if(ttSelectTimestampPrepStmt!=null) 
                                                ttSelectTimestampPrepStmt.close();
                                            ttSelectTimestampPrepStmt=connection.prepareStatement(ttSelectTimestampPrepSQL);
                                            log.msg("Initialized " + sqlCommand + ": " + ttSelectTimestampPrepSQL);
                                        
                                            if(ttSelectTimestampTODATE_PrepStmt!=null) 
                                                ttSelectTimestampTODATE_PrepStmt.close();
                                            ttSelectTimestampTODATE_PrepStmt=
                                                    connection.prepareStatement(ttSelectTimestampTODATE_PrepSQL);
                                            log.msg("Initialized " + sqlCommand + "_TODATE: " + ttSelectTimestampTODATE_PrepSQL);

                                        }
                                        
                                        if("UPDATE".equals(sqlCommand)) {
                                            if(ttUpdateTimestampPrepStmt!=null) 
                                                ttUpdateTimestampPrepStmt.close();                                            
                                            ttUpdateTimestampPrepStmt=connection.prepareStatement(ttUpdateTimestampPrepSQL);
                                            log.msg("Initialized " + sqlCommand + ": " + ttUpdateTimestampPrepSQL);
                                            
                                            if(ttUpdate2TimestampPrepStmt!=null) 
                                                ttUpdate2TimestampPrepStmt.close();                                            
                                            ttUpdate2TimestampPrepStmt=connection.prepareStatement(ttUpdate2TimestampPrepSQL);
                                            log.msg("Initialized " + sqlCommand + "2: " + ttUpdate2TimestampPrepSQL);
                                            
                                            if(ttUpdateTimestampTODATE_PrepStmt!=null) 
                                                ttUpdateTimestampTODATE_PrepStmt.close();                                            
                                            ttUpdateTimestampTODATE_PrepStmt=
                                                    connection.prepareStatement(ttUpdateTimestampTODATE_PrepSQL);
                                            log.msg("Initialized " + sqlCommand + "_TODATE: " + ttUpdateTimestampTODATE_PrepSQL);                                            
                                            
                                        }
                                        
                                        if("DELETE".equals(sqlCommand)) {
                                            if(ttDeleteTimestampPrepStmt!=null) 
                                                ttDeleteTimestampPrepStmt.close();                                            
                                            ttDeleteTimestampPrepStmt=connection.prepareStatement(ttDeleteTimestampPrepSQL);
                                            log.msg("Initialized " + sqlCommand + ": " + ttDeleteTimestampPrepSQL);
                                            
                                            if(ttDelete2TimestampPrepStmt!=null) 
                                                ttDelete2TimestampPrepStmt.close();                                            
                                            ttDelete2TimestampPrepStmt=connection.prepareStatement(ttDelete2TimestampPrepSQL);
                                            log.msg("Initialized " + sqlCommand + "2: " + ttDelete2TimestampPrepSQL);

                                                                                        
                                            if(ttDeleteTimestampTODATE_PrepStmt!=null) 
                                                ttDeleteTimestampTODATE_PrepStmt.close();                                            
                                            ttDeleteTimestampTODATE_PrepStmt=
                                                    connection.prepareStatement(ttDeleteTimestampTODATE_PrepSQL);
                                            log.msg("Initialized " + sqlCommand + 
                                                    "_TODATE: " + ttDeleteTimestampTODATE_PrepSQL);

                                        }
                                    }
                                } else {
                                    err.msg("Error: sub command not recognized, info: "+subCommand);
                                }
                            } else {                            
                                if (ttSelectPrepStmt != null) {
                                    ttSelectPrepStmt.close();
                                }
                                ttSelectPrepStmt = connection.prepareStatement(ttSelectPrepSQL);
                            }
                            log.msg("Statement(s) initialized");
                            break;
                        case QUICK://quick
                            if (lineTokens.length > (tokenPos)) {
                                
                                String subCommand=lineTokens[tokenPos];
                                
                                if ("TIME".equals(subCommand)) {
                                    if (lineTokens.length > (tokenPos+2)) {
                                        doTimestampMask=lineTokens[tokenPos+1];
                                        doTimestampPK=new Integer(lineTokens[tokenPos+2]).intValue();
                                        
                                        if (lineTokens.length > (tokenPos+4)) {
                                            doTimestampDate=lineTokens[tokenPos+3];
                                            doTimestampTime=lineTokens[tokenPos+4];

                                            //log.msg("TIMESTAMP statements will be executed with:" + doTimestampMask + ", " +
                                            //        "pk: " + doTimestampPK + ", " +
                                            //        "date: " + doTimestampDate + ", " +
                                            //        "time: " + doTimestampTime);

                                            try {
                                              DateFormat formatter;
                                              formatter = new SimpleDateFormat("d-MMM-yy HH.mm.ss");
                                              doTimestampString = doTimestampDate + " " + doTimestampTime;
                                              Date date = (Date) formatter.parse(doTimestampString);
                                              doTimestampValue = new Timestamp(date.getTime());
                                            } catch (ParseException e) {
                                                throw new Exception("Timestamp conversion error. Use this format: d-MMM-yy HH.mm.ss");
                                            }
                                        }
                                    } else {
                                        throw new Exception("TIME requires MASK and pk; DATE and TIME are optional paramters");
                                    }
                                    
                               //     String[] sqlcommands=doTimestampMask.split(",");
                               //     for(int cmdId=0;cmdId<sqlcommands.length;cmdId++){
                                        //String sqlCommand=sqlcommands[cmdId];
                                        String sqlCommand=doTimestampMask;
                                        
                                        if("INSERT".equals(sqlCommand)){ 
                                            ttInsertTimestampPrepStmt.setInt(1, doTimestampPK);
                                            ttInsertTimestampPrepStmt.setTimestamp(2, doTimestampValue);
                                            ttInsertTimestampPrepStmt.execute();
                                            log.msg("INSERT done with pk=" + doTimestampPK + ", timestamp=" + doTimestampValue);
                                        }
                                        
                                        if("SELECT".equals(sqlCommand)) {
                                            ttSelectTimestampPrepStmt.setInt(1, doTimestampPK);
                                            ttSelectTimestampPrepStmt.setTimestamp(2, doTimestampValue);
                                          
                                            ResultSet rs = ttSelectTimestampPrepStmt.executeQuery();
                                            rs.next();
                                            response = rs.getString(1);
                                            log.msg("Resp:" + response);
                                            rs.close();
                                           log.msg("SELECT done with pk=" + doTimestampPK + ", timestamp=" + doTimestampValue);
                                        }
                                        
                                        if("SELECT_TODATE".equals(sqlCommand)) {
                                            ttSelectTimestampTODATE_PrepStmt.setInt(1, doTimestampPK);
                                            ttSelectTimestampTODATE_PrepStmt.setString(2, doTimestampString);
                                          
                                            ResultSet rs = ttSelectTimestampTODATE_PrepStmt.executeQuery();
                                            rs.next();
                                            response = rs.getString(1);
                                            log.msg("Resp:" + response);
                                            rs.close();
                                           log.msg("SELECT_TODATE done with pk=" + doTimestampPK + ", timestamp=" + doTimestampValue);
                                        }
                                        
                                        if("UPDATE".equals(sqlCommand)) {
                                            ttUpdateTimestampPrepStmt.setTimestamp(1, doTimestampValue);
                                            ttUpdateTimestampPrepStmt.setInt(2, doTimestampPK);
                                            
                                            ttUpdateTimestampPrepStmt.execute();
                                            log.msg("UPDATE done with pk=" + doTimestampPK + ", timestamp=" + doTimestampValue);
                                        }
                                        
                                        if("UPDATE2".equals(sqlCommand)) {
                                            ttUpdate2TimestampPrepStmt.setTimestamp(1, doTimestampValue);
                                            ttUpdate2TimestampPrepStmt.setInt(2, doTimestampPK);
                                            ttUpdate2TimestampPrepStmt.setTimestamp(3, doTimestampValue);
                                            
                                            ttUpdate2TimestampPrepStmt.execute();
                                            log.msg("UPDATE2 done with pk=" + doTimestampPK + ", timestamp=" + doTimestampValue);
                                        }
                                        
                                        if("UPDATE_TODATE".equals(sqlCommand)) {
                                            ttUpdateTimestampTODATE_PrepStmt.setString(1, doTimestampString);
                                            ttUpdateTimestampTODATE_PrepStmt.setInt(2, doTimestampPK);
                                            ttUpdateTimestampTODATE_PrepStmt.setString(3, doTimestampString);
                                            
                                            ttUpdateTimestampTODATE_PrepStmt.execute();
                                            log.msg("UPDATE_TODATE done with pk=" + doTimestampPK + ", timestamp=" + doTimestampValue);
                                        }

                                        
                                        if("DELETE".equals(sqlCommand)) {
                                            ttDeleteTimestampPrepStmt.setInt(1, doTimestampPK);
                                          
                                            ttDeleteTimestampPrepStmt.execute();
                                            log.msg("DELETE done with pk=" + doTimestampPK);
                                        }
                                        
                                        if("DELETE2".equals(sqlCommand)) {
                                            ttDelete2TimestampPrepStmt.setInt(1, doTimestampPK);
                                            ttDelete2TimestampPrepStmt.setTimestamp(2, doTimestampValue);
                                          
                                            ttDelete2TimestampPrepStmt.execute();
                                            log.msg("DELETE2 done with pk=" + doTimestampPK + ", timestamp=" + doTimestampValue);
                                        }
                                        
                                        if("DELETE_TODATE".equals(sqlCommand)) {
                                            ttDeleteTimestampTODATE_PrepStmt.setInt(1, doTimestampPK);
                                            ttDeleteTimestampTODATE_PrepStmt.setString(2, doTimestampValue.toString());
                                          
                                            ttDeleteTimestampTODATE_PrepStmt.execute();
                                            log.msg("DELETE_TODATE done with pk=" + doTimestampPK + ", timestamp=" + doTimestampValue);
                                        }
                                        //}
                                } else {
                                    err.msg("Error: sub command not recognized.");
                                }
                            } else {                            
                                log.msg("Prepared select");
                                log.msg("Host:" + me.getHost(connection));
                                log.msg("Status:" + me.getRepStatus(connection));

                                ResultSet rs = ttSelectPrepStmt.executeQuery();
                                rs.next();
                                response = rs.getString(1);
                                log.msg("Resp:" + response);
                                rs.close();
                            }
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
                        case ONESELECT://step
                            log.msg("OneSelect");
                            //log.msg("Host:" + me.getHost(connection));
                            log.msg("Status:" + me.getRepStatus(connection));
                            
                            break;
                            
                        case SESSION://step
                            log.msg("Session");
                            
                            Statement oneSessionStmt = connection.createStatement();
                            ResultSet rsSession = oneSessionStmt.executeQuery(ttSessionSQL);
                            rsSession.next();
                            response = rsSession.getString(1);
                            log.msg("Resp:" + response);
                            rsSession.close();
                            oneSessionStmt.close();
                            break;
                            
                        case HELP://help
                            log.msg("Available commands:" + me.cmdDir.keySet());
                            break;
                        case COMMIT://help
                            log.msg("Commit");
                            connection.commit();
                            break;
                        
                        case EXIT://exit
//                            if (bufferedStmt != null) {
//                                bufferedStmt.close();
//                            }
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
        
        //cmdFD.close();
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
        cmdDir.put("session", SESSION);
        cmdDir.put("commit", COMMIT);
        cmdDir.put("update", UPDATE);
        cmdDir.put("insert", INSERT);
        cmdDir.put("oneselect", ONESELECT);
        cmdDir.put("select", SELECT);
        cmdDir.put("quick", QUICK);
        cmdDir.put("init", INIT);
        cmdDir.put("?", HELP);
        cmdDir.put("help", HELP);
        cmdDir.put("exit", EXIT);
        cmdDir.put("connect", CONNECT);
        cmdDir.put("disconnect", DISCONNECT);
        cmdDir.put("cfg", CFG);
        cmdDir.put("comment", COMMENT);
        cmdDir.put("prepare", PREPARE);
        cmdDir.put("define", DEFINE);
        cmdDir.put("exec", EXEC);
        cmdDir.put("fetch", FETCH);
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
    static final int COMMIT = 97;
    
    static final int SESSION = 75;
    static final int DEFINE = 70;
    static final int FETCH = 62;
    static final int EXEC = 61;
    static final int PREPARE = 60;
    static final int CFG = 50;
    static final int CONNECT = 40;
    static final int DISCONNECT = 41;
    static final int INIT = 30;
    static final int QUICK = 20;
    static final int ONESELECT = 6;
    static final int SQL = 5;
    static final int DELETE = 4;
    static final int UPDATE = 3;
    static final int INSERT = 2;
    static final int SELECT = 1;
    static final int UNKNOWN = -1;
}
