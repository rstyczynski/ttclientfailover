/*
 * To change this template, choose Tools | Templates
 * and open the template in the editor.
 */
package ttclientfailover;

import java.sql.Connection;
import java.sql.Driver;
import java.sql.DriverManager;
import java.sql.ResultSet;
import java.sql.SQLWarning;
import java.sql.Statement;
import java.util.HashMap;

/**
 *
 * @author rstyczynski
 */
public class ttClientFailover {

    /**
     * @param args the command line arguments
     */
    public static void main(String[] args) throws Exception {

        String ttURL;
//        ttURL = "jdbc:timesten:client:dsn=cachedb10_at_ozone1";
        ttURL = "jdbc:timesten:client:"
                + "TTC_SERVER=ozone1_tt1121v8;"
                + "TTC_SERVER_DSN=cachedb10_1121;"
                + "TCP_PORT=53389;"
                + "TTC_SERVER2=ozone2_tt1121v8;"
                + "TTC_SERVER_DSN2=cachedb10_1121;"
                + "TCP_PORT2=53385;";
//        ttURL = "jdbc:timesten:client:dsn=cachedb10_at_ozone1ozone2";
        String ttUID = "cug";
        String ttPWD = "welcome";
        String ttSQL = "select * from dual";

        Class clsDriver;
        clsDriver = Class.forName("com.timesten.jdbc.TimesTenDriver");
        Driver driver = (Driver) clsDriver.newInstance();
        DriverManager.registerDriver(driver);


        Connection connection = DriverManager.getConnection(ttURL, ttUID, ttPWD);
        Statement stmt = connection.createStatement();

        ResultSet rs = stmt.executeQuery(ttSQL); 
        rs.next();
        String response = rs.getString(1);
        System.out.println("Response:" + response);
        rs.close();

        ttSQL = "select value from nodeinfo where key='host'";
        rs = stmt.executeQuery(ttSQL); 
        rs.next();
        response = rs.getString(1);
        System.out.println("Response:" + response);
        rs.close();
        
        HashMap ttCfg = new HashMap();
        ttSQL = "{call ttconfiguration()}";
        rs = stmt.executeQuery(ttSQL);
        while (rs.next()) {
            ttCfg.put(rs.getString(1), rs.getString(2));
        }
        System.out.println("Response:" + ttCfg);
        rs.close();
        
        
        
    }
}
