/*
 * To change this template, choose Tools | Templates
 * and open the template in the editor.
 */
package ttclientfailover;

/**
 *
 * @author TimesTen Tptbm
 */
public class Timer {

    private long startTime = -1;
    private long endTime = -1;
    
    public void start() {
	startTime = System.currentTimeMillis();
    }
    public void stop() {
	endTime = System.currentTimeMillis();
    }
    
    public long getInStepTime() {
        return System.currentTimeMillis() - startTime;
}
    public long getTimeInMs() {
	if((startTime == -1) || (endTime == -1)) {
	    System.err.println("call start() and stop() before this method");
	    return -1;
	}
	else
	    return (endTime - startTime);
	
    }
}