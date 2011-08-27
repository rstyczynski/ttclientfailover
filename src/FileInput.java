
import java.io.*;

public class FileInput {
    
    public static void main(String[] args) throws Exception {
        
        File cmdFIFO = new File("/Users/rstyczynski/control");
        BufferedReader cmdFD = null;
        String cmd ="";
        
        
        cmdFD = new BufferedReader(new InputStreamReader(new FileInputStream(cmdFIFO)));
        
        while ( (cmd = cmdFD.readLine()) !=null && ! cmd.equals("exit")) {
            System.out.println(cmd);
        }

        cmdFD.close();
        
    }
}
