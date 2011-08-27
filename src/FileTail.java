
import java.io.*;

public class FileTail {
    
    public static void main(String[] args) throws Exception {
        
        File cmdFIFO = new File("/Users/rstyczynski/control");
        BufferedReader cmdFD = null;
        String cmd ="";
        
        System.out.println("start");
        cmdFD = new BufferedReader(new InputStreamReader(new FileInputStream(cmdFIFO)));
        System.out.println("start");
        
        while ( (cmd = cmdFD.readLine()) !=null && ! cmd.equals("exit")) {
            System.out.println(cmd);
        }

        cmdFD.close();
        
    }
}
